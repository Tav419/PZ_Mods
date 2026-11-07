-- Live Wire: placed devices enter and leave the registry (authority only).
-- Called by the vanilla furniture wrappers of LW_Placement.lua: a device is
-- registered when its tile is placed and removed when it is picked up. A rotation
-- (pick up then place on the same square) keeps the same device and its links.
-- Devices destroyed by other means (zombies, sledgehammer) are dropped when their
-- square is loaded and the object is gone (Devices.validate).
if isClient() then return end

LiveWire = LiveWire or {}

local Devices = {}
LiveWire.Devices = Devices

local function R() return LiveWire.Registry end

Devices.rotating = false
Devices.pending = {}   -- ids picked up during a rotation, waiting for the new tile

local function ready()
    local Rg = R()
    return Rg and Rg.ready and not Rg.readOnly
end

-- Our object of sprite `spriteName` on `sq` that is not bound to a live device.
local function unboundObject(sq, spriteName)
    local objs = sq:getObjects()
    for i = objs:size() - 1, 0, -1 do
        local o = objs:get(i)
        local spr = o:getSprite()
        if spr and spr:getName() == spriteName then
            local m = LiveWire.Marks.get(o)
            local dev = m and R().device(m.id)
            if not dev or Devices.pending[m.id] or dev.x ~= sq:getX() or dev.y ~= sq:getY()
                or dev.z ~= sq:getZ() then
                return o, m
            end
        end
    end
    return nil
end

-- Inverter id of the network a device is linked to (an inverter: its own id, a slave:
-- the master's id).
local function inverterOf(dev)
    if dev.role == "inverter" then return dev.coupled or dev.id end
    local g = dev.grid and R().grid(dev.grid)
    return g and g.inverter or nil
end

-- State shown by the client: st (inverter: on/off/tripped/broken; breaker:
-- ok/tripped; alarm: ok/ringing), pw (inverter: the house is powered).
local function stateOf(dev)
    local g = dev.grid and R().grid(dev.grid)
    if dev.role == "inverter" then
        return dev.state or "off", (g and g.powered == true and dev.state == "on") or false
    end
    if dev.role == "pump" then
        local inv = g and R().device(g.inverter)
        local powered = g and g.powered == true and not g.mainOff and not g.equipmentOff
            and (dev.cond or 0) > 0 and inv and inv.state == "on" and (inv.cond or 0) > 0
            and not (LiveWire.Pump and LiveWire.Pump.disabled())
        return dev.state or "idle", powered == true
    end
    local def = LiveWire.Defs.devices[dev.model]
    if def and def.kind == "breaker" then
        local inv = g and R().device(g.inverter)
        local powered = g and g.powered == true and not g.mainOff
            and dev.state ~= "tripped" and (dev.cond or 0) > 0
            and inv and inv.state == "on" and (inv.cond or 0) > 0
        return dev.state or "ok", powered == true
    end
    if def and def.kind == "alarm" then
        if g and g.alarmOn and (dev.cond or 0) > 0 then return "ringing", false end
        return "ok", false
    end
    return dev.state or "ok", false
end

local function placementFacts(obj, dev)
    local def = LiveWire.Defs.devices[dev.model]
    if def and def.kind == "solar" then
        local name = obj:getSprite():getName()
        dev.facing = (tonumber(string.match(name, "_(%d+)$")) - def.tile) % 4
    end
    if dev.role == "storage" then dev.outside = obj:getSquare():isOutside() end
end

-- An inverter is in service once a first device was linked to it (or, in older
-- saves, while it has equipment or slaves). Linking to an inverter that is not in
-- service needs the inverter's own Electrical level (Install.checkLink).
local function inService(dev)
    if dev.role ~= "inverter" then return nil end
    if dev.svc or dev.coupled then return true end
    local g = dev.grid and R().grid(dev.grid)
    if not g then return nil end
    for _ in pairs(g.members) do return true end
    for _ in pairs(g.slaves or {}) do return true end
    return nil
end

local function markFromDevice(obj, dev)
    placementFacts(obj, dev)
    local st, pw = stateOf(dev)
    local g = dev.grid and R().grid(dev.grid)
    -- Pumps: number of linked barrels (connect menu limit) and of relay tanks (shown
    -- as "nr" by the tap view).
    local nb, nr = nil, nil
    if dev.role == "pump" then
        nb, nr = 0, 0
        for _ in pairs(dev.barrels or {}) do nb = nb + 1 end
        for _ in pairs(dev.relays or {}) do nr = nr + 1 end
    end
    LiveWire.Marks.set(obj, { id = dev.id, model = dev.model, cond = dev.cond, eff = dev.eff,
                              level = dev.level, inv = inverterOf(dev), st = st, pw = pw,
                              muf = dev.muffled == true or nil, x = dev.x, y = dev.y, z = dev.z,
                              nb = nb, nr = nr, cpl = dev.coupled, br = dev.brake == true,
                              nm = g and g.name or nil, dirt = dev.dirt, snow = dev.snow,
                              facing = dev.facing, svc = inService(dev),
                              xpd = dev.xpd == true or nil })
    dev.shownSt, dev.shownPw, dev.shownInv = st, pw, inverterOf(dev)
    if isServer() then obj:transmitModData() end
end

-- Registry identity and the physical tile win over a missing/altered object mark.
-- Do not attach a registry device to an unrelated vanilla object carrying its id.
function Devices.find(dev)
    local sq = getCell():getGridSquare(dev.x, dev.y, dev.z)
    if not sq then return nil end
    local obj = LiveWire.Marks.findOnSquare(sq, dev.id)
    if obj and LiveWire.Defs.modelOfObject(obj) ~= dev.model then obj = nil end
    if not obj then
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local candidate = objects:get(i)
            if LiveWire.Defs.modelOfObject(candidate) == dev.model then
                local mark = LiveWire.Marks.get(candidate)
                local bound = mark and R().device(mark.id)
                if not bound or bound.x ~= dev.x or bound.y ~= dev.y or bound.z ~= dev.z
                    or bound.model ~= dev.model then obj = candidate; break end
            end
        end
    end
    if obj then
        -- Old saves have no facing field. Read the physical tile even when wear
        -- is disabled and no other mark field changes; never assume south.
        placementFacts(obj, dev)
        local m = LiveWire.Marks.get(obj)
        local st, pw = stateOf(dev)
        if not m or m.id ~= dev.id or m.model ~= dev.model or m.cond ~= dev.cond
            or m.eff ~= dev.eff or m.level ~= dev.level or m.inv ~= inverterOf(dev)
            or m.st ~= st or m.pw ~= pw or m.x ~= dev.x or m.y ~= dev.y or m.z ~= dev.z
            or m.facing ~= dev.facing or (m.br == true) ~= (dev.brake == true)
            or m.svc ~= inService(dev) then
            markFromDevice(obj, dev)
        end
    end
    return obj
end

-- Rewrite the mark of a loaded device (link state shown by the client menus).
function Devices.syncMark(dev)
    if not dev then return end
    local obj = Devices.find(dev)
    if obj then markFromDevice(obj, dev) end
end

-- Rewrite the marks of the inverter and the equipment of a grid whose shown state
-- changed (called after each simulation step).
function Devices.refreshStates(grid)
    local list = { R().device(grid.inverter) }
    local slaves = R().slaves(grid)
    for i = 1, #slaves do list[#list + 1] = slaves[i] end
    local _, _, options, _, _, pumps = R().members(grid)
    for i = 1, #options do list[#list + 1] = options[i] end
    for i = 1, #pumps do list[#list + 1] = pumps[i] end
    for i = 1, #list do
        local dev = list[i]
        if dev then
            local st, pw = stateOf(dev)
            if st ~= dev.shownSt or pw ~= dev.shownPw or inverterOf(dev) ~= dev.shownInv then
                Devices.syncMark(dev)
            end
        end
    end
end

-- Register the unbound object of sprite `spriteName` on `sq` (or keep the same
-- device after a rotation). `adopted`: reported later by a client (C_ADOPT) instead
-- of the placement wrapper, e.g. another mod replaced placeMoveableInternal: no
-- experience, its own message. Returns the device or nil.
local function register(character, sq, spriteName, adopted)
    local where = LiveWire.posKey(sq:getX(), sq:getY(), sq:getZ())
    if not ready() then
        LiveWire.warn("cannot register " .. tostring(spriteName) .. " at " .. where
            .. ": the registry is not ready or read-only")
        if character and not adopted then LiveWire.notify(character, "IGUI_LW_NotRegistered", {}, true) end
        return nil
    end
    local model = LiveWire.Defs.spriteToModel[spriteName]
    local def = model and LiveWire.Defs.devices[model]
    if not def then return nil end
    -- Repair before looking for an unbound tile, otherwise a client report could
    -- create a second registry entry for an existing device whose mark was lost.
    local existing = R().devicesAt(sq:getX(), sq:getY(), sq:getZ())
    for i = 1, #existing do
        if existing[i].model == model and not Devices.pending[existing[i].id] then
            Devices.find(existing[i])
        end
    end
    local obj, mark = unboundObject(sq, spriteName)
    if not obj then
        if not adopted then
            LiveWire.warn("placed " .. tostring(spriteName) .. " at " .. where
                .. " but no unregistered object of that tile is on the square")
        end
        return nil
    end

    -- Rotation: same device, same square, new object.
    if mark and Devices.pending[mark.id] then
        local dev = R().device(mark.id)
        Devices.pending[mark.id] = nil
        if dev then
            markFromDevice(obj, dev)
            return dev
        end
    end

    -- Placing is free: efficiency, installer level and experience come with the
    -- first link (Devices.wired). `xpd = false` marks a device whose link
    -- experience is still due; the mark keeps `xpd = true` once given, so a moved
    -- device does not give it again. Registry devices of older saves have no xpd
    -- field: their experience was given at placement.
    local raw = LiveWire.Marks.raw(obj) or {}
    local level = 0
    local dev = R().addDevice({
        role = def.role, model = model, x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        cond = tonumber(raw.cond) or 100,
        eff = LiveWire.Defs.installEfficiency(level), level = level,
        state = (def.role == "inverter") and "on" or "ok",
        xpd = raw.xpd == true,
    })
    if def.role == "inverter" and raw.muf == true then dev.muffled = true end
    if def.kind == "wind" and raw.br == true then dev.brake = true end
    if def.kind == "solar" then dev.dirt, dev.snow = raw.dirt or 0, raw.snow or 0 end
    if def.role == "storage" then
        dev.wearFactor = LiveWire.Defs.batteryWearSkillFactor(level)
        dev.slots = {}
    end
    if def.role == "pump" then
        dev.barrels = {}
        dev.relays = {}
        dev.state = "idle"
    end
    markFromDevice(obj, dev)
    if def.role == "inverter" then
        local grid = R().createGrid(dev)
        LiveWire.Sim.updateAnchor(dev, false)
        LiveWire.Sim.refresh(grid)
    end
    if character then
        if adopted then
            LiveWire.notify(character, "IGUI_LW_Adopted", { "IGUI_LW_Model_" .. model })
        else
            LiveWire.notify(character, "IGUI_LW_Installed", { "IGUI_LW_Model_" .. model })
        end
    end
    LiveWire.log((adopted and "adopted " or "placed ") .. model .. " " .. dev.id .. " at " .. where)
    return dev
end

-- `character` linked `dev` (nil for a vanilla generator or computer) to the
-- inverter `inv`: both keep the best installer level seen (efficiency, wear) and
-- the inverter is in service. Returns the experience due, given once per device.
function Devices.wired(character, dev, inv)
    local level = LiveWire.Install.level(character)
    local xp = 0
    for _, d in ipairs({ dev or false, inv or false }) do
        if d then
            if level > (d.level or 0) then
                d.level = level
                d.eff = math.max(d.eff or 0, LiveWire.Defs.installEfficiency(level))
                if d.role == "storage" then
                    d.wearFactor = math.min(d.wearFactor or 1, LiveWire.Defs.batteryWearSkillFactor(level))
                end
            end
            if d.xpd == false then
                d.xpd = true
                local def = LiveWire.Defs.devices[d.model]
                xp = xp + (def and def.xp or 0)
            end
        end
    end
    if inv then inv.svc = true end
    return xp
end

function Devices.onPlaced(character, sq, spriteName)
    return register(character, sq, spriteName, false)
end

-- Register every unbound Live Wire tile of a loaded square (client report).
function Devices.adoptSquare(character, sq)
    local names = {}
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local spr = objs:get(i):getSprite()
        local name = spr and spr:getName()
        if name and LiveWire.Defs.spriteToModel[name] then names[#names + 1] = name end
    end
    local n = 0
    for i = 1, #names do
        if register(character, sq, names[i], true) then n = n + 1 end
    end
    return n
end

-- Write the live state into the object's mark so that the picked-up item keeps it.
function Devices.beforePickUp(obj)
    if not ready() then return nil end
    local m = LiveWire.Marks.get(obj)
    local dev = m and R().device(m.id)
    if not dev then return nil end
    markFromDevice(obj, dev)
    return dev.id
end

-- Remove a device from the registry (picked up or destroyed).
function Devices.remove(id)
    local dev = R().device(id)
    if not dev then return end
    -- Every inverter has its own anchor (coupled ones too): switch it off.
    if dev.role == "inverter" then
        LiveWire.Sim.updateAnchor(dev, false)
        LiveWire.Anchor.set(dev.id, R().anchors[dev.id] or dev, false)
    end
    local grid = dev.grid and R().grid(dev.grid)
    local members = {}
    local slaves = {}
    if dev.role == "inverter" and grid then
        for mid in pairs(grid.members) do members[#members + 1] = mid end
        -- Only a master uncouples its slaves (a removed slave owns no grid).
        if not dev.coupled then slaves = R().slaves(grid) end
    end
    if dev.role == "pump" and LiveWire.Pump then LiveWire.Pump.forget(dev) end
    R().removeDevice(dev.id)
    LiveWire.Demand.invalidate(dev.id)
    for i = 1, #members do Devices.syncMark(R().device(members[i])) end
    -- A removed master uncouples its slaves: each one gets its own empty grid.
    for i = 1, #slaves do
        Devices.syncMark(slaves[i])
        local g = slaves[i].grid and R().grid(slaves[i].grid)
        if g then LiveWire.Sim.refresh(g) end
    end
    if grid and R().grid(grid.id) then LiveWire.Sim.refresh(grid) end
    LiveWire.log("removed " .. tostring(dev.model) .. " " .. id)
end

function Devices.onPickedUp(id)
    if not ready() then return end
    if Devices.rotating then
        Devices.pending[id] = true
        return
    end
    Devices.remove(id)
end

function Devices.beginRotation()
    Devices.rotating = true
    Devices.pending = {}
end

function Devices.endRotation()
    Devices.rotating = false
    local left = Devices.pending
    Devices.pending = {}
    if not ready() then return end
    for id in pairs(left) do Devices.remove(id) end
end

-- Drop the devices of a loaded square whose object is gone, after MISSING_CHECKS
-- consecutive checks (chunk load, then each simulation tick): one transient miss
-- never deletes a device and its links. Every removal goes through Devices.remove.
-- Returns true when the object is present or its square is not loaded.
Devices.MISSING_CHECKS = 2
function Devices.validate(dev)
    local sq = getCell():getGridSquare(dev.x, dev.y, dev.z)
    if not sq then return true end
    if Devices.find(dev) then
        dev.missing = nil
        return true
    end
    dev.missing = (dev.missing or 0) + 1
    if dev.missing < Devices.MISSING_CHECKS then return false end
    LiveWire.warn("device " .. dev.id .. " (" .. tostring(dev.model) .. ") is gone, removing it")
    Devices.remove(dev.id)
    return false
end
