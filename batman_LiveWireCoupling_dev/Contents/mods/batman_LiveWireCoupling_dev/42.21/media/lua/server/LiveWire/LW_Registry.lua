-- Live Wire: authoritative registry of devices and networks (authority only).
-- Stored in the global ModData "LiveWire" (saved in global_mod_data.bin). Never
-- transmitted: clients receive snapshots and the public anchor table only.
if isClient() then return end
require "LiveWire/LW_PowerHistory"

LiveWire = LiveWire or {}

local Registry = {}
LiveWire.Registry = Registry

Registry.ready = false
Registry.readOnly = false

local function data()
    return Registry.data
end

function Registry.init()
    if LiveWire.Circuits then LiveWire.Circuits.reset() end
    if LiveWire.Demand then LiveWire.Demand.reset() end
    if LiveWire.Sim then LiveWire.Sim.subscribers = {} end
    local d = ModData.getOrCreate(LiveWire.DATA_KEY)
    d.devices = d.devices or {}
    d.grids = d.grids or {}
    d.byPos = d.byPos or {}
    d.nextId = d.nextId or 1
    Registry.readOnly = not LiveWire.Migration.run(d)
    Registry.data = d
    Registry.rebuildIndexes()
    local a = ModData.getOrCreate(LiveWire.ANCHOR_KEY)
    Registry.anchors = a
    if not Registry.readOnly then
        LiveWire.PowerHistory.init(d, a, getGameTime():getWorldAgeHours())
    end
    Registry.ready = true
    local n = 0
    for _ in pairs(d.devices) do n = n + 1 end
    LiveWire.log("version " .. tostring(LiveWire.VERSION) .. ", registry ready: " .. tostring(n) .. " device(s)")
end

function Registry.newId(prefix)
    local d = data()
    local id = prefix .. tostring(d.nextId)
    d.nextId = d.nextId + 1
    return id
end

function Registry.device(id)
    return data().devices[id]
end

function Registry.grid(id)
    return data().grids[id]
end

function Registry.devices()
    return data().devices
end

function Registry.grids()
    return data().grids
end

local function indexAdd(dev)
    local k = LiveWire.posKey(dev.x, dev.y, dev.z)
    local list = data().byPos[k] or {}
    list[#list + 1] = dev.id
    data().byPos[k] = list
    local ck = math.floor(dev.x / 8) .. "," .. math.floor(dev.y / 8)
    Registry.byChunk[ck] = Registry.byChunk[ck] or {}
    Registry.byChunk[ck][dev.id] = true
    if dev.role == "inverter" then
        Registry.inverters[dev.id] = true
        Registry.invertersByChunk[ck] = Registry.invertersByChunk[ck] or {}
        Registry.invertersByChunk[ck][dev.id] = true
    end
end

local function indexRemove(dev)
    local ck = math.floor(dev.x / 8) .. "," .. math.floor(dev.y / 8)
    local bucket = Registry.byChunk[ck]
    if bucket then
        bucket[dev.id] = nil
        local any = false
        for _ in pairs(bucket) do any = true; break end
        if not any then Registry.byChunk[ck] = nil end
    end
    Registry.inverters[dev.id] = nil
    local inverters = Registry.invertersByChunk[ck]
    if inverters then
        inverters[dev.id] = nil
        local any = false
        for _ in pairs(inverters) do any = true; break end
        if not any then Registry.invertersByChunk[ck] = nil end
    end
    local k = LiveWire.posKey(dev.x, dev.y, dev.z)
    local list = data().byPos[k]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == dev.id then table.remove(list, i) end
    end
    if #list == 0 then data().byPos[k] = nil end
end

-- Derived session indexes, rebuilt for existing saves without a schema change.
function Registry.rebuildIndexes()
    Registry.byChunk, Registry.inverters, Registry.invertersByChunk = {}, {}, {}
    if Registry.readOnly then return end
    data().byPos = {}
    for _, dev in pairs(data().devices) do indexAdd(dev) end
end

-- A detached list: callers may validate/remove a device while iterating.
function Registry.devicesInChunk(cx, cy)
    local out = {}
    for id in pairs(Registry.byChunk[cx .. "," .. cy] or {}) do
        local dev = Registry.device(id)
        if dev then out[#out + 1] = dev end
    end
    return out
end

-- Session index lookup only: never visit map squares or distant devices.
-- Coupled inverters are included: each keeps its own zone, and its grid is its master's grid.
function Registry.invertersNear(x, y, radius)
    local out, r2 = {}, radius * radius
    for cy = math.floor((y - radius) / 8), math.floor((y + radius) / 8) do
        for cx = math.floor((x - radius) / 8), math.floor((x + radius) / 8) do
            for id in pairs(Registry.invertersByChunk[cx .. "," .. cy] or {}) do
                local d = Registry.device(id)
                if d and d.role == "inverter"
                    and (d.x - x)^2 + (d.y - y)^2 <= r2 then out[#out + 1] = d end
            end
        end
    end
    return out
end

function Registry.devicesAt(x, y, z)
    local list = data().byPos[LiveWire.posKey(x, y, z)]
    local out = {}
    if list then
        for i = 1, #list do
            local dev = data().devices[list[i]]
            if dev then out[#out + 1] = dev end
        end
    end
    return out
end

-- Adds a device table (must have role, model, x, y, z). Returns it with an id.
function Registry.addDevice(dev)
    dev.id = dev.id or Registry.newId("d")
    local previous = data().devices[dev.id]
    if previous then indexRemove(previous) end
    data().devices[dev.id] = dev
    indexAdd(dev)
    return dev
end

function Registry.moveDevice(dev, x, y, z)
    indexRemove(dev)
    dev.x, dev.y, dev.z = x, y, z
    indexAdd(dev)
end

-- Creates the network owned by a new inverter.
function Registry.createGrid(inverter)
    local g = {
        id = Registry.newId("g"), name = "", inverter = inverter.id,
        members = {}, demand = 0, powered = false,
        lastTick = getGameTime():getWorldAgeHours(), rev = 0,
    }
    data().grids[g.id] = g
    inverter.grid = g.id
    return g
end

-- Slave inverters of a grid (sorted by id), dropping ids whose device is gone.
function Registry.slaves(grid)
    local out = {}
    if not grid.slaves then return out end
    local ids = {}
    for id in pairs(grid.slaves) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do
        local dev = data().devices[ids[i]]
        if dev then out[#out + 1] = dev else grid.slaves[ids[i]] = nil end
    end
    return out
end

-- Couple `slave` (an inverter with its own empty grid) to `masterGrid`: its own grid
-- is removed, it joins the master's grid as a slave and keeps its anchor (its own zone).
function Registry.couple(slave, masterGrid)
    local own = slave.grid and data().grids[slave.grid]
    if own and own.id ~= masterGrid.id then data().grids[own.id] = nil end
    slave.grid = masterGrid.id
    slave.coupled = masterGrid.inverter
    masterGrid.slaves = masterGrid.slaves or {}
    masterGrid.slaves[slave.id] = true
    if LiveWire.Circuits then LiveWire.Circuits.topologyChanged() end
    if LiveWire.Journal then LiveWire.Journal.add(masterGrid, "IGUI_LW_Coupled") end
end

-- Make a slave independent again: it leaves the master's grid and gets a new empty grid.
function Registry.uncouple(slave)
    local g = slave.grid and data().grids[slave.grid]
    if g and g.slaves then g.slaves[slave.id] = nil end
    if LiveWire.Journal and g then LiveWire.Journal.add(g, "IGUI_LW_Uncoupled") end
    slave.coupled = nil
    slave.grid = nil
    Registry.createGrid(slave)
    if LiveWire.Circuits then LiveWire.Circuits.topologyChanged() end
end

function Registry.link(dev, grid)
    local already = dev.grid == grid.id and grid.members[dev.id]
    if dev.grid and dev.grid ~= grid.id then Registry.unlink(dev) end
    dev.grid = grid.id
    grid.members[dev.id] = true
    if not already and LiveWire.Journal then
        LiveWire.Journal.add(grid, "IGUI_LW_Event_State", { "IGUI_LW_Model_" .. dev.model, "IGUI_LW_Event_Connected" })
    end
end

function Registry.unlink(dev)
    if dev.role == "inverter" then return end
    local g = dev.grid and data().grids[dev.grid]
    if g and dev.model == "Breaker" and LiveWire.Circuits then
        LiveWire.Circuits.release(g)
    end
    if g then g.members[dev.id] = nil end
    if g and LiveWire.Journal then
        LiveWire.Journal.add(g, "IGUI_LW_Event_State", { "IGUI_LW_Model_" .. dev.model, "IGUI_LW_Event_Disconnected" })
    end
    dev.grid = nil
end

-- Members of a grid by role: sources, power banks, options, backup generators,
-- management computers, water pumps (each a list, sorted by id for a stable order).
function Registry.members(grid)
    local sources, batteries, options, backups, computers, pumps = {}, {}, {}, {}, {}, {}
    local ids = {}
    for id in pairs(grid.members) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do
        local id = ids[i]
        local dev = data().devices[id]
        if not dev then
            grid.members[id] = nil
        elseif dev.role == "source" then sources[#sources + 1] = dev
        elseif dev.role == "storage" then batteries[#batteries + 1] = dev
        elseif dev.role == "option" then options[#options + 1] = dev
        elseif dev.role == "backup" then backups[#backups + 1] = dev
        elseif dev.role == "computer" then computers[#computers + 1] = dev
        elseif dev.role == "pump" then pumps[#pumps + 1] = dev
        end
    end
    return sources, batteries, options, backups, computers, pumps
end

-- Vanilla objects (generator, computer) only exist in the registry through their
-- link: dropping the link removes them and clears the ModData left on the object.
function Registry.forgetVanilla(dev)
    if dev.role == "backup" and LiveWire.Backup then
        LiveWire.Backup.forget(dev)
    elseif dev.role == "computer" and LiveWire.Computer then
        LiveWire.Computer.forget(dev)
    else
        return false
    end
    return true
end

function Registry.hasOption(grid, kind)
    local _, _, options = Registry.members(grid)
    for i = 1, #options do
        local def = LiveWire.Defs.devices[options[i].model]
        if def and def.kind == kind and (options[i].cond or 0) > 0 then return options[i] end
    end
    return nil
end

-- Delete a master's grid: its slaves become independent, its members are left
-- unlinked and its linked vanilla objects are forgotten. Also used for a grid whose
-- inverter vanished from the registry, whose public anchor is then removed too.
function Registry.dropGrid(g)
    if LiveWire.Circuits then LiveWire.Circuits.release(g, true) end
    -- The slaves lose their master: each becomes an independent inverter.
    local slaves = Registry.slaves(g)
    for i = 1, #slaves do Registry.uncouple(slaves[i]) end
    local vanilla = {}
    for mid in pairs(g.members) do
        local m = data().devices[mid]
        if m then
            m.grid = nil
            if m.role == "backup" or m.role == "computer" then vanilla[#vanilla + 1] = m end
        end
    end
    data().grids[g.id] = nil
    for i = 1, #vanilla do Registry.forgetVanilla(vanilla[i]) end
    local a = g.inverter and not data().devices[g.inverter] and Registry.anchors[g.inverter]
    if a then Registry.setAnchor({ id = g.inverter, x = a.x, y = a.y, z = a.z }, nil) end
end

function Registry.removeDevice(id)
    local dev = data().devices[id]
    if not dev then return end
    if dev.role == "inverter" and dev.coupled then
        -- A slave owns no grid: it leaves its master's grid and drops its own anchor.
        local g = dev.grid and data().grids[dev.grid]
        if g and g.slaves then g.slaves[id] = nil end
        Registry.setAnchor(dev, nil)
        indexRemove(dev)
        data().devices[id] = nil
        if LiveWire.Demand then LiveWire.Demand.forget(id) end
        return
    end
    if dev.role == "inverter" then
        local g = dev.grid and data().grids[dev.grid]
        if g then Registry.dropGrid(g) end
        Registry.setAnchor(dev, nil)
    else
        Registry.unlink(dev)
    end
    indexRemove(dev)
    data().devices[id] = nil
    if dev.role == "inverter" and LiveWire.Circuits then LiveWire.Circuits.topologyChanged() end
    if dev.role == "inverter" and LiveWire.Demand then LiveWire.Demand.forget(id) end
end

-- Public anchor table: anchors[inverterId] = { x, y, z, on, log, log0 } (nil removes it).
-- log: state changes { t = world age hours, on = bool }, oldest first, at most
-- ANCHOR_LOG_MAX; log0: state before log[1]. Kept for compatibility; authoritative
-- food catch-up now reads the private 60-day PowerHistory instead.
-- Returns true when the published state changed.
Registry.ANCHOR_LOG_MAX = 16

function Registry.setAnchor(inverter, on)
    local a = Registry.anchors
    local cur = a[inverter.id]
    if on ~= nil or cur then
        LiveWire.PowerHistory.record(data(), inverter, on, getGameTime():getWorldAgeHours())
    end
    if on == nil then
        if cur == nil then return false end
        a[inverter.id] = nil
    else
        if cur and cur.on == on and cur.x == inverter.x and cur.y == inverter.y
            and cur.z == inverter.z then
            return false
        end
        local log, log0 = {}, false
        if cur then
            if type(cur.log) == "table" then
                log = cur.log
                log0 = cur.log0 == true
            else
                log0 = cur.on == true  -- anchor saved before the log existed
            end
        end
        if not cur or cur.on ~= on then
            log[#log + 1] = { t = getGameTime():getWorldAgeHours(), on = on }
            while #log > Registry.ANCHOR_LOG_MAX do
                log0 = log[1].on == true
                table.remove(log, 1)
            end
            LiveWire.log("anchor " .. tostring(inverter.id) .. " " .. (on and "on" or "off"))
        end
        a[inverter.id] = { x = inverter.x, y = inverter.y, z = inverter.z, on = on,
                           log = log, log0 = log0 }
    end
    if isServer() then ModData.transmit(LiveWire.ANCHOR_KEY) end
    return true
end

Events.OnInitGlobalModData.Add(function(isNewGame)
    Registry.init()
end)
