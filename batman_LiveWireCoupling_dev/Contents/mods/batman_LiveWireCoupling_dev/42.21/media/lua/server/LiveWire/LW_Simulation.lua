-- Live Wire: simulation step of every network (authority only), every 10 game
-- minutes, whether players are near or not (docs/architecture.md section 4).
if isClient() then return end
require "LiveWire/LW_Events"
require "LiveWire/LW_Forecast"

LiveWire = LiveWire or {}

local Sim = {}
LiveWire.Sim = Sim

local Defs = LiveWire.Defs
local Physics = LiveWire.Physics

Sim.MAX_CATCHUP_HOURS = 720
Sim.SUBSTEP_HOURS = 1.0
Sim.SUBSCRIBE_RANGE = 30
Sim.SUBSCRIBE_MS = 10 * 60 * 1000

-- subscribers[gridId][username] = { player = IsoPlayer, expires = ms }
Sim.subscribers = {}

local function weather()
    local cm = getClimateManager()
    local season = cm:getSeason()
    return {
        clouds = cm:getCloudIntensity(),
        windKph = cm:getWindspeedKph(),
        snowing = cm:isSnowing(),
        snowIntensity = cm:getSnowIntensity(),
        temperature = cm:getTemperature(),
        storm = cm:getIsThunderStorming(),
        rain = cm:getRainIntensity(),
        month = getGameTime():getMonth(),
        dawn = season:getDawn(),
        dusk = season:getDusk(),
    }
end

Sim.weather = weather

-- Mean of the solar curve over the time-of-day interval [t0, t0 + h], with wrap.
local function solarMean(t0, h, w)
    local t1 = t0 + h
    if t1 <= 24 then return Physics.solarCurveMean(t0, t1, w.dawn, w.dusk) end
    local a = Physics.solarCurveMean(t0, 24, w.dawn, w.dusk) * (24 - t0)
    local b = Physics.solarCurveMean(0, t1 - 24, w.dawn, w.dusk) * (t1 - 24)
    return (a + b) / h
end

local function chance(probability)
    return ZombRandFloat(0, 1) < probability
end

local function sourceRaw(src, def, w, t0, h)
    if (src.cond or 0) <= 0 then return 0 end
    if def.kind == "wind" and src.brake then return 0 end
    local factor = 0
    if def.kind == "solar" then
        local facing, shift = Physics.solarFacing(src.facing, LiveWire.Config.get("SolarOrientation"))
        local sw = { dawn = w.dawn + shift, dusk = w.dusk + shift }
        factor = Physics.solarFactor(solarMean(t0, h, sw), w.clouds, src.snow or 0)
            * LiveWire.Config.get("SolarMultiplier") * facing
            * (1 - (LiveWire.Config.get("SolarDirt") and (src.dirt or 0) or 0))
    elseif def.kind == "wind" then
        factor = Physics.windFactor(Physics.windAtHeight(w.windKph, src.z))
            * LiveWire.Config.get("WindMultiplier")
    elseif def.kind == "hydro" then
        factor = Physics.hydroFactor(w.month) * LiveWire.Config.get("HydroMultiplier")
    end
    return def.nominalW * factor * Physics.conditionFactor(src.cond) * (src.eff or 0.85)
end
Sim.sourceRaw = sourceRaw

local function wearDevice(dev, def, h, extra)
    local mult = LiveWire.Config.get("DeviceWearMultiplier")
    if mult <= 0 or not def.wearDays then return end
    local loss = h / (def.wearDays * 24) * mult * (extra or 1)
        * Defs.deviceWearSkillFactor(dev.level or 0)
    dev.cond = math.max(0, (dev.cond or 100) - loss)
end

local function weatherOnSource(src, def, w, h)
    if def.kind == "solar" then
        local snow = src.snow or 0
        if w.snowing then snow = snow + 0.1 * w.snowIntensity * h end
        if w.temperature > 0 then snow = snow - 0.05 * h end
        src.snow = LiveWire.clamp(snow, 0, 1)
        if LiveWire.Config.get("SolarDirt") then
            local autumn = w.month >= 8 and w.month <= 10
            src.dirt = LiveWire.clamp((src.dirt or 0) + h * (autumn and 0.001 or 0.0005)
                - (w.rain or 0) * h * 0.02, 0, 0.5)
        end
    end
    if not LiveWire.Config.get("StormDamage") then return end
    if def.kind == "solar" and w.storm and chance(h / 20) then
        src.cond = math.max(0, (src.cond or 100) - 5)
    elseif def.kind == "wind" and Physics.windAtHeight(w.windKph, src.z) > Physics.WIND_CUT_OUT
        and not src.brake and chance(h / 6) then
        src.cond = math.max(0, (src.cond or 100) - ZombRand(5, 16))
    end
end

local function batteryWear(entry, drawn, h, exhausted)
    local def = LiveWire.Batteries.def(entry.model)
    if not def then return end
    if drawn > 0 then
        local deep = exhausted or (entry.capacity > 0
            and entry.charge / entry.capacity < Defs.DEEP_DISCHARGE_THRESHOLD)
        local wear = Physics.batteryWear(drawn, def.capacityKWh, def.lifeCycles, deep,
            LiveWire.Config.get("BatteryWearMultiplier") * (entry.wearFactor or 1))
        entry.cond = math.max(0, entry.cond - wear)
        entry.cycles = (entry.cycles or 0) + drawn / def.capacityKWh
    end
    local decay = 1 - Defs.SELF_DISCHARGE_PER_DAY * h / 24
    entry.charge = entry.charge * decay
    entry.reserve = (entry.reserve or 0) * decay
    entry.warmCapacity = LiveWire.Batteries.capacity(entry.model, entry.cond)
    entry.capacity = entry.warmCapacity * (entry.coldFactor or 1)
    entry.reserve = math.min(entry.reserve, math.max(0, entry.warmCapacity - entry.capacity))
    if entry.charge > entry.capacity then entry.charge = entry.capacity end
end

-- Battery stock as a fraction of the capacity, nil without any capacity.
local function stockFraction(entries)
    local stock, capacity = 0, 0
    for e = 1, #entries do
        stock = stock + entries[e].charge
        capacity = capacity + entries[e].capacity
    end
    if capacity <= 0 then return nil end
    return stock / capacity
end
Sim.stockFraction = stockFraction

-- Inverters of a grid that are in service (switched on and not broken): the master
-- when its state is "on" or "tripped" (it is the one that trips), plus every slave whose
-- state is "on" and cond > 0. Returns count, list of slave devices in service.
function Sim.inService(grid)
    local R = LiveWire.Registry
    local inv = R.device(grid.inverter)
    local n, list = 0, {}
    if inv and (inv.state == "on" or inv.state == "tripped") then n = 1 end
    local slaves = R.slaves(grid)
    for i = 1, #slaves do
        local sl = slaves[i]
        if sl.state == "on" and (sl.cond or 0) > 0 then
            n = n + 1
            list[#list + 1] = sl
        end
    end
    return n, list
end

-- Capacity of a grid in W: maxW of the model x number of inverters in service
-- (at least the master's maxW, so that a lone inverter behaves exactly as before).
function Sim.capacityW(grid)
    local R = LiveWire.Registry
    local inv = R.device(grid.inverter)
    local def = inv and Defs.devices[inv.model] or {}
    local n = Sim.inService(grid)
    if n < 1 then n = 1 end
    return (def.maxW or 0) * n
end

-- Idle consumption: idleW x number of switched-on inverters (master counts when on).
function Sim.idleW(grid)
    local R = LiveWire.Registry
    local inv = R.device(grid.inverter)
    local def = inv and Defs.devices[inv.model] or {}
    local n = 0
    if inv and inv.state == "on" then n = 1 end
    local slaves = R.slaves(grid)
    for i = 1, #slaves do
        if slaves[i].state == "on" then n = n + 1 end
    end
    return (def.idleW or 0) * n
end

-- Public snapshot of a grid (primitive values only).
function Sim.snapshot(grid)
    local R = LiveWire.Registry
    local inv = R.device(grid.inverter)
    if not inv then return nil end
    local sources, batteries, options, backups, computers, pumps = R.members(grid)
    local snap = {
        grid = grid.id, rev = grid.rev or 0, name = grid.name or "",
        inverter = { id = inv.id, model = inv.model, state = inv.state,
                     cond = math.floor((inv.cond or 0) + 0.5), maxW = Sim.capacityW(grid),
                     eff = inv.eff or 0, powered = grid.powered == true, muffled = inv.muffled == true },
        demand = math.floor((grid.demand or 0) + 0.5),
        demandReady = LiveWire.Demand.ready(inv),
        production = math.floor((grid.production or 0) + 0.5),
        stock = grid.stock or 0, capacity = grid.capacity or 0,
        lost = grid.lost or 0,
        sources = {}, batteries = {}, options = {}, appliances = {},
        coverage = { radius = LiveWire.Config.tileRange(), floors = LiveWire.Config.verticalRange() },
    }
    snap.events = {}
    for _, e in ipairs(grid.events or {}) do
        local args = {}
        for i, v in ipairs(e.args) do args[i] = v end
        snap.events[#snap.events + 1] = { t = e.t, tod = e.tod, key = e.key, args = args }
    end
    snap.consumers = LiveWire.Demand.consumers and LiveWire.Demand.consumers(inv) or {}
    snap.links = {}
    for id in pairs(grid.members) do
        local d = R.device(id)
        if d then snap.links[#snap.links + 1] = { id = id, model = d.model, role = d.role, x = d.x, y = d.y, z = d.z } end
    end
    snap.origin = { x = inv.x, y = inv.y, z = inv.z }
    for cat, b in pairs(grid.appliances or {}) do
        snap.appliances[#snap.appliances + 1] = { cat = cat, n = b.n, w = math.floor(b.w + 0.5) }
    end
    table.sort(snap.appliances, function(a, b) return a.w > b.w end)
    for i = 1, #sources do
        local s = sources[i]
        local sdef = Defs.devices[s.model] or {}
        snap.sources[i] = { id = s.id, model = s.model, kind = sdef.kind or "other",
                            nominal = sdef.nominalW or 0, cond = math.floor((s.cond or 0) + 0.5),
                            w = math.floor((s.pOut or 0) + 0.5),
                            raw = math.floor((s.raw or 0) + 0.5), snow = s.snow or 0,
                            dirt = s.dirt or 0, facing = s.facing or 0 }
    end
    snap.extra = 0
    for i = 1, #batteries do
        local bank = batteries[i]
        snap.extra = snap.extra + (bank.extra or 0)
        for _, sl in ipairs(bank.slots or {}) do
            local e = LiveWire.Batteries.entry(bank, sl.model, sl.id, sl.cond or 0, sl.charge or 0, sl.cycles)
            snap.batteries[#snap.batteries + 1] = { model = sl.model,
                charge = e.capacity > 0 and e.charge / e.capacity or 0,
                capacity = e.capacity, reserve = e.reserve,
                cond = math.floor((sl.cond or 0) + 0.5), cycles = sl.cycles or 0 }
        end
    end
    snap.banks = #batteries
    for i = 1, #options do
        local o = options[i]
        snap.options[i] = { id = o.id, model = o.model, cond = math.floor((o.cond or 0) + 0.5),
                            state = o.state or "ok" }
    end
    local slaves = R.slaves(grid)
    if #slaves > 0 then
        local inService = Sim.inService(grid)
        snap.coupled = { n = inService, total = 1 + #slaves }
    end
    local need = (grid.demand or 0) + Sim.idleW(grid) - (grid.production or 0) * (inv.eff or 0.85)
    if need > 0 and snap.stock > 0 then
        snap.autonomyH = snap.stock * 1000 * (inv.eff or 0.85) / need
    end
    local b = backups[1]
    if b then
        local start, stop = LiveWire.Backup.thresholds()
        snap.backup = { id = b.id, state = b.state or "standby", fuel = b.fuel or 0, maxFuel = 10,
                        w = math.floor((grid.backupW or 0) + 0.5),
                        start = start * 100, stop = stop * 100 }
    end
    local c = computers[1]
    if c then
        local on = grid.computerOn == true
        snap.computer = { id = c.id, powered = on,
                          shed = (c.level or 0) >= LiveWire.Config.requiredLevel(Defs.SHED_LEVEL) }
        if on then
            snap.history = {}
            for i, hs in ipairs(grid.history or {}) do snap.history[i] = { p = hs.p, d = hs.d, s = hs.s } end
            snap.dawnH = LiveWire.Computer.hoursToDawn()
            snap.forecast = {}
            for i, row in ipairs(grid.forecast or {}) do
                local r = {}
                for key, value in pairs(row) do r[key] = value end
                snap.forecast[i] = r
            end
        end
    end
    if R.hasOption(grid, "alarm") then
        snap.alarm = { on = grid.alarmOn == true, ack = grid.alarmAck == true }
    end
    local brk = R.hasOption(grid, "breaker")
    if brk then snap.breaker = { id = brk.id, state = brk.state or "ok",
        lightsOff = grid.lightsOff == true, equipmentOff = grid.equipmentOff == true,
        mainOff = grid.mainOff == true, equipmentControl = true } end
    if #pumps > 0 then
        -- Pumps in service and their flow (the only pump figures the software shows).
        local n, flow, watts = 0, 0, 0
        for i = 1, #pumps do
            if pumps[i].state == "running" or pumps[i].state == "idle" then n = n + 1 end
            flow = flow + (pumps[i].flowLph or 0)
            -- Reuse the last measured duty; never call demandW here (it consumes
            -- the pump's litres counter). No scan, water transfer or new state.
            local def = Defs.devices[pumps[i].model]
            local duty = LiveWire.clamp((pumps[i].flowLph or 0) / (Defs.PUMP_LITRES_PER_MINUTE * 60), 0, 1)
            watts = watts + (def and def.pumpW or 0) * duty
        end
        snap.pumps = { n = n, flow = math.floor(flow + 0.5), w = math.floor(watts + 0.5) }
    end
    return snap
end

function Sim.subscribe(player, gridId)
    local list = Sim.subscribers[gridId] or {}
    Sim.subscribers[gridId] = list
    list[player:getUsername()] = { player = player, expires = getTimestampMs() + Sim.SUBSCRIBE_MS }
end

function Sim.unsubscribe(player, gridId)
    local list = Sim.subscribers[gridId]
    if list then
        list[player:getUsername()] = nil
        for _ in pairs(list) do return end
        Sim.subscribers[gridId] = nil
    end
end

function Sim.purgeSubscribers()
    local R = LiveWire.Registry
    if not R or not R.ready then return end
    local now, online = getTimestampMs(), nil
    local players = isServer() and getOnlinePlayers()
    if players then
        online = {}
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            online[p:getUsername()] = p
        end
    end
    for id, list in pairs(Sim.subscribers) do
        if not R.grid(id) then Sim.subscribers[id] = nil
        else
            local any = false
            for name, sub in pairs(list) do
                if sub.expires <= now or not sub.player or sub.player:isDead()
                    or (online and online[name] ~= sub.player) then list[name] = nil
                else any = true end
            end
            if not any then Sim.subscribers[id] = nil end
        end
    end
end

function Sim.publish(grid)
    if not isServer() then return end
    local list = Sim.subscribers[grid.id]
    if not list then return end
    local inv = LiveWire.Registry.device(grid.inverter)
    local snap = nil
    local nowMs = getTimestampMs()
    for name, sub in pairs(list) do
        local p = sub.player
        local ok = p and not p:isDead() and sub.expires > nowMs and inv
        if ok then
            local dx, dy = p:getX() - inv.x, p:getY() - inv.y
            ok = dx * dx + dy * dy <= Sim.SUBSCRIBE_RANGE * Sim.SUBSCRIBE_RANGE
        end
        if ok then
            snap = snap or Sim.snapshot(grid)
            if snap then
                sendServerCommand(p, LiveWire.MODULE, LiveWire.Protocol.S_SNAPSHOT, snap)
            end
        else
            list[name] = nil
        end
    end
end

-- Apply the desired anchor state on this side and publish it to clients.
function Sim.updateAnchor(inv, on)
    local R = LiveWire.Registry
    local changed = R.setAnchor(inv, on)
    local a = R.anchors[inv.id]
    if a and (changed or LiveWire.Anchor.appliedState[inv.id] == nil) then
        LiveWire.Anchor.set(inv.id, a, on)
    end
    -- A master's coupled inverters follow its power state, each with its own zone.
    if inv.role == "inverter" and not inv.coupled and inv.grid then
        local grid = R.grid(inv.grid)
        if grid then
            local slaves = R.slaves(grid)
            for i = 1, #slaves do
                local sl = slaves[i]
                local slOn = (on == true) and sl.state == "on" and (sl.cond or 0) > 0
                Sim.updateAnchor(sl, slOn)
            end
        end
    end
end

-- A slave with no condition left breaks like the master (see the step below).
local function breakSlave(sl)
    sl.state = "broken"
    LiveWire.notifyNear(sl.x, sl.y, sl.z, Sim.SUBSCRIBE_RANGE, "IGUI_LW_Broken", {}, true)
end

function Sim.stepGrid(grid, now, w)
    local R = LiveWire.Registry
    local inv = R.device(grid.inverter)
    if not inv then
        R.grids()[grid.id] = nil
        return
    end
    local def = Defs.devices[inv.model]
    if not def then return end

    local dt = now - (grid.lastTick or now)
    grid.lastTick = now
    if dt <= 0 then return end
    if dt > Sim.MAX_CATCHUP_HOURS then dt = Sim.MAX_CATCHUP_HOURS end

    local invSq = getCell():getGridSquare(inv.x, inv.y, inv.z)
    local invObj = invSq and LiveWire.Devices.find(inv)
    if invSq and not invObj then
        inv.missing = (inv.missing or 0) + 1
        if inv.missing >= 2 then
            LiveWire.log("inverter " .. inv.id .. " is gone from its square, removing it")
            Sim.updateAnchor(inv, false)
            R.removeDevice(inv.id)
        end
        return
    end
    inv.missing = nil
    local loaded = invObj ~= nil
    if not loaded and not LiveWire.Config.get("SimulateUnloaded") then return end

    if loaded then
        local d, breakdown = LiveWire.Demand.measureGrid(grid, inv)
        if d then
            grid.demand = d
            grid.appliances = breakdown
        end
    end
    local demandW = grid.demand or 0

    -- Sources and equipment removed by another path (admin, other mod): drop them after
    -- two consecutive checks of a loaded square.
    do
        local s0, b0, o0, _, _, p0 = R.members(grid)
        local all = {}
        for i = 1, #s0 do all[#all + 1] = s0[i] end
        for i = 1, #b0 do all[#all + 1] = b0[i] end
        for i = 1, #o0 do all[#all + 1] = o0[i] end
        for i = 1, #p0 do all[#all + 1] = p0[i] end
        local sl0 = R.slaves(grid)
        for i = 1, #sl0 do all[#all + 1] = sl0[i] end
        for i = 1, #all do
            local dev = all[i]
            local sq = getCell():getGridSquare(dev.x, dev.y, dev.z)
            if sq and not LiveWire.Devices.find(dev) then
                dev.missing = (dev.missing or 0) + 1
                if dev.missing >= 2 then
                    LiveWire.log("device " .. dev.id .. " is gone from its square, removing it")
                    R.removeDevice(dev.id)
                end
            elseif sq then
                dev.missing = nil
            end
        end
        -- Linked vanilla objects (generator, computer) are found by their own ModData.
        local _, _, _, bk0, pc0 = R.members(grid)
        local vanilla = {}
        for i = 1, #bk0 do vanilla[#vanilla + 1] = { dev = bk0[i], mod = LiveWire.Backup } end
        for i = 1, #pc0 do vanilla[#vanilla + 1] = { dev = pc0[i], mod = LiveWire.Computer } end
        for i = 1, #vanilla do
            local dev = vanilla[i].dev
            local obj, here = vanilla[i].mod.find(dev)
            if here and not obj then
                dev.missing = (dev.missing or 0) + 1
                if dev.missing >= 2 then
                    LiveWire.log("linked object " .. dev.id .. " is gone from its square, removing it")
                    R.forgetVanilla(dev)
                end
            elseif here then
                dev.missing = nil
            end
        end
    end

    local sources, banks, options, backups, computers, pumps = R.members(grid)
    if w.storm and not grid.stormWarned then
        for _, src in ipairs(sources) do
            local sd = Defs.devices[src.model]
            if sd and sd.kind == "wind" and not src.brake and (src.cond or 0) > 0 then
                grid.stormWarned = true
                LiveWire.notifyNear(inv.x, inv.y, inv.z, Sim.SUBSCRIBE_RANGE, "IGUI_LW_StormBrake",
                    { grid.name ~= "" and grid.name or "IGUI_LW_Network" }, true)
                LiveWire.Journal.add(grid, "IGUI_LW_Event_Storm")
                break
            end
        end
    elseif not w.storm then grid.stormWarned = nil end
    local slaves = R.slaves(grid)
    local entries = {}
    local bankEntries = {}
    for i = 1, #banks do
        local list = LiveWire.Batteries.read(banks[i])
        bankEntries[i] = list
        for j = 1, #list do entries[#entries + 1] = list[j] end
    end
    -- Water pumps draw power while they move water (LW_Pump.lua); the breaker and
    -- the heavy-load test count them with the house demand.
    local pumpW = LiveWire.Pump and LiveWire.Pump.demandW(pumps, dt) or 0
    demandW = demandW + pumpW

    local breaker = R.hasOption(grid, "breaker")
    local tod = getGameTime():getTimeOfDay()
    local n = math.max(1, math.ceil(dt / Sim.SUBSTEP_HOURS - 1e-9))
    local h = dt / n
    local totalLost = 0
    local prodW = 0
    local backupW = 0

    for i = 1, n do
        local t0 = (tod - dt + (i - 1) * h) % 24
        if t0 < 0 then t0 = t0 + 24 end
        prodW = 0
        for s = 1, #sources do
            local src = sources[s]
            local sdef = Defs.devices[src.model]
            if sdef then
                weatherOnSource(src, sdef, w, h)
                src.raw = sourceRaw(src, sdef, w, t0, h)
                src.pOut = Physics.smooth(src.pOut, src.raw, h, Defs.SMOOTHING_TAU_HOURS)
                if sdef.kind == "wind" and src.brake then src.pOut = 0 end
                prodW = prodW + src.pOut
                wearDevice(src, sdef, h)
            end
        end

        -- Backup generator: started under BackupStartPercent, stopped at
        -- BackupStopPercent; only through a working inverter.
        backupW = 0
        local frac = nil
        if inv.state == "on" and (inv.cond or 0) > 0 then frac = stockFraction(entries) end
        for b = 1, #backups do backupW = backupW + LiveWire.Backup.step(backups[b], frac, h) end

        local before = {}
        local beforeStock = 0
        for e = 1, #entries do
            before[e] = entries[e].charge
            beforeStock = beforeStock + before[e]
        end

        if inv.state == "on" and (inv.cond or 0) <= 0 then inv.state = "broken" end
        -- Capacity and idle use are taken again at each sub-step: slaves can break.
        for s = 1, #slaves do
            if slaves[s].state == "on" and (slaves[s].cond or 0) <= 0 then breakSlave(slaves[s]) end
        end
        local capW, idleNow = Sim.capacityW(grid), Sim.idleW(grid)
        -- A tripped breaker cuts the house: the inverter stays on (it still charges).
        local physState = inv.state
        -- Isolating a failed unit changes its switch, never repairs its converter.
        if (inv.cond or 0) <= 0 then physState = "broken" end
        if physState == "on" and (grid.mainOff or (breaker and breaker.state == "tripped")) then physState = "tripped" end
        local r = Physics.stepGrid({
            productionW = prodW + backupW, demandW = demandW, idleW = idleNow, maxW = capW,
            eff = inv.eff, dt = h, wasOn = grid.powered == true, state = physState,
            batteries = entries,
        })
        totalLost = totalLost + r.lostKWh

        if r.tripped then
            local args = { tostring(math.floor(demandW + 0.5)), tostring(capW) }
            if breaker then
                -- The breaker trips before the inverter, which is not damaged.
                breaker.state = "tripped"
                LiveWire.notifyNear(inv.x, inv.y, inv.z, Sim.SUBSCRIBE_RANGE, "IGUI_LW_BreakerTripped", args, true)
            else
                inv.state = "tripped"
                inv.cond = math.max(0, (inv.cond or 100) - Defs.TRIP_CONDITION_LOSS)
                LiveWire.notifyNear(inv.x, inv.y, inv.z, Sim.SUBSCRIBE_RANGE, "IGUI_LW_Tripped", args, true)
            end
        end
        local wasPowered = grid.powered == true
        grid.powered = r.on
        -- Intermediate catch-up transitions are private. Publish only the final
        -- state below, avoiding a burst of global anchor packets after an absence.
        local startHour = now - dt + (i - 1) * h
        if r.onHours > 0 and not wasPowered then
            LiveWire.Journal.add(grid, "IGUI_LW_Event_PowerOn", {}, startHour)
        end
        if not r.on and (wasPowered or r.onHours > 0) then
            LiveWire.Journal.add(grid, "IGUI_LW_Event_PowerOff", {}, startHour + r.onHours)
        end
        LiveWire.PowerHistory.record(R.data, inv, r.onHours > 0, startHour)
        if not r.on then
            LiveWire.PowerHistory.record(R.data, inv, false, startHour + r.onHours)
        end

        for e = 1, #entries do
            -- A partial step may discharge, then recharge from the unused
            -- production. Wear counts the actual proportional discharge, not net
            -- stock loss after that recharge.
            local drawn = beforeStock > 0 and r.drawnKWh * before[e] / beforeStock or 0
            batteryWear(entries[e], drawn, h, not r.on and r.onHours > 0)
        end

        if r.onHours > 0 then
            local heavy = 1
            if demandW > capW * Defs.HEAVY_LOAD_RATIO then heavy = 2 end
            if inv.muffled then heavy = heavy * Defs.MUFFLED_WEAR end
            wearDevice(inv, def, r.onHours, heavy)
            -- Slaves in service wear with the same load, their own muffler included.
            for s = 1, #slaves do
                local sl = slaves[s]
                if sl.state == "on" and (sl.cond or 0) > 0 then
                    local sh = 1
                    if demandW > capW * Defs.HEAVY_LOAD_RATIO then sh = 2 end
                    if sl.muffled then sh = sh * Defs.MUFFLED_WEAR end
                    wearDevice(sl, def, r.onHours, sh)
                    if (sl.cond or 0) <= 0 then breakSlave(sl) end
                end
            end
            if (inv.cond or 0) <= 0 then
                inv.state = "broken"
                grid.powered = false
                LiveWire.notifyNear(inv.x, inv.y, inv.z, Sim.SUBSCRIBE_RANGE, "IGUI_LW_Broken", {}, true)
            end
        end
        if inv.state ~= "on" then
            LiveWire.PowerHistory.record(R.data, inv, false, startHour + h)
        end
        for o = 1, #options do
            local odef = Defs.devices[options[o].model]
            if odef then wearDevice(options[o], odef, h) end
        end
        -- Pump wear is applied per step to the running pumps only (approximation:
        -- the duty of this step is not known here).
        for p = 1, #pumps do
            local pdef = Defs.devices[pumps[p].model]
            if pdef and pumps[p].state == "running" then wearDevice(pumps[p], pdef, h) end
        end
    end

    local stock, capacity = 0, 0
    for i = 1, #banks do LiveWire.Batteries.write(banks[i], bankEntries[i]) end
    for e = 1, #entries do
        stock = stock + entries[e].charge
        capacity = capacity + entries[e].capacity
    end
    grid.production = prodW + backupW
    grid.backupW = backupW
    grid.stock = stock
    grid.capacity = capacity
    grid.lost = totalLost
    grid.rev = (grid.rev or 0) + 1

    local on = grid.powered == true and inv.state == "on"
    Sim.updateAnchor(inv, on)

    -- Management computer (history, forecast, load shedding) and low battery alarm.
    local frac = stockFraction(entries)
    local pc = nil
    for c = 1, #computers do
        if LiveWire.Computer.powered(computers[c], grid) then pc = computers[c] break end
    end
    grid.computerOn = pc ~= nil
    if pc then
        LiveWire.Computer.record(grid, now, grid.production, demandW, frac)
        LiveWire.Forecast.build(grid, sources, now)
        if loaded then LiveWire.Computer.shed(grid, inv, pc, frac) end
    end
    LiveWire.Alarm.check(grid, R.hasOption(grid, "alarm"), frac, now)

    local radius = LiveWire.Config.get("InverterNoiseRadius")
    if on and loaded and radius > 0 and not inv.muffled then
        addSound(nil, inv.x, inv.y, inv.z, radius, 1)
    end
    -- Each slave in service hums at its own position (loaded squares only).
    if on and radius > 0 then
        for s = 1, #slaves do
            local sl = slaves[s]
            if sl.state == "on" and (sl.cond or 0) > 0 and not sl.muffled
                and getCell():getGridSquare(sl.x, sl.y, sl.z) then
                addSound(nil, sl.x, sl.y, sl.z, radius, 1)
            end
        end
    end
    -- Relays of the pumps follow the linked barrels and fixtures (loaded squares only).
    if LiveWire.Pump then
        for p = 1, #pumps do
            local ok, err = pcall(LiveWire.Pump.maintain, pumps[p])
            if not ok then
                LiveWire.warn("pump maintenance failed for " .. tostring(pumps[p].id) .. ": " .. tostring(err))
            end
        end
    end
    -- State shown by the client (lights, menus): rewrite the marks that changed.
    LiveWire.Devices.refreshStates(grid)
    LiveWire.Journal.capture(grid)
    Sim.publish(grid)
end

function Sim.tick()
    local R = LiveWire.Registry
    if not R or not R.ready or R.readOnly then return end
    local now = getGameTime():getWorldAgeHours()
    local w = weather()
    -- Devices destroyed without being picked up (zombies, sledgehammer).
    local devIds = {}
    for id, dev in pairs(R.devices()) do
        if LiveWire.Defs.devices[dev.model] then devIds[#devIds + 1] = id end
    end
    for i = 1, #devIds do
        local dev = R.device(devIds[i])
        if dev then LiveWire.Devices.validate(dev) end
    end
    local ids = {}
    for id in pairs(R.grids()) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do
        local grid = R.grid(ids[i])
        if grid then
            local ok, err = pcall(Sim.stepGrid, grid, now, w)
            if not ok then LiveWire.warn("step failed for " .. ids[i] .. ": " .. tostring(err)) end
        end
    end
end

-- Run one step right now for one grid (after an action changed it).
function Sim.refresh(grid)
    if not grid then return end
    local now = getGameTime():getWorldAgeHours()
    -- A one-minute step re-evaluates the state without skipping the next tick.
    if not grid.lastTick or grid.lastTick > now - 1 / 60 then grid.lastTick = now - 1 / 60 end
    local ok, err = pcall(Sim.stepGrid, grid, now, weather())
    if not ok then LiveWire.warn("refresh failed for " .. grid.id .. ": " .. tostring(err)) end
end

Events.EveryTenMinutes.Add(Sim.tick)
Events.EveryOneMinute.Add(Sim.purgeSubscribers)
