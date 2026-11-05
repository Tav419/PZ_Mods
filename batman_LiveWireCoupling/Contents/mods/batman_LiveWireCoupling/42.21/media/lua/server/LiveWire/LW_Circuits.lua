-- Live Wire: authoritative, persistent isolation of native appliance services.
if isClient() then return end
require "LiveWire/LW_Appliances"
require "LiveWire/LW_Anchor"
LiveWire = LiveWire or {}
local Circuits = {}
LiveWire.Circuits = Circuits
-- Two FIFO queues. Network jobs (breaker commands, a rebuilt appliance list) are
-- always served before chunk discovery: coming back to a base loads hundreds of
-- chunks at once, and a command must not wait behind their scans.
local function newQueue() return { jobs = {}, head = 1, tail = 0 } end
local grids, chunks, byKey = newQueue(), newQueue(), {}
local isolated, positions, isolatedCursor = {}, {}, 1
local nextBatchAt, nextSweepAt, sweepLeft, lastClock, preferSaved = 0, 0, 0, nil, false
function Circuits.reset()
    grids, chunks, byKey = newQueue(), newQueue(), {}
    isolated, positions, isolatedCursor = {}, {}, 1
    nextBatchAt, nextSweepAt, sweepLeft, lastClock, preferSaved = 0, 0, 0, nil, false
end
local function track(o, keep)
    local i = positions[o]
    if keep and not i then
        isolated[#isolated + 1] = o; positions[o] = #isolated
    elseif not keep and i then
        local last = isolated[#isolated]
        isolated[i], positions[last] = last, i
        isolated[#isolated], positions[o] = nil, nil
        if isolatedCursor > #isolated then isolatedCursor = 1 end
    end
end
local function loaded(o)
    local sq = o:getSquare()
    return sq and o:getObjectIndex() ~= -1
        and getCell():getGridSquare(sq:getX(), sq:getY(), sq:getZ()) == sq
end
local function key(o)
    local sq, spr = o:getSquare(), o:getSprite()
    return LiveWire.posKey(sq:getX(), sq:getY(), sq:getZ()) .. ":" .. (spr and spr:getName() or "light")
end
-- Stable physical panel assignment, independent of temporary power availability.
-- Billing still belongs to the closest LIVE anchor (Demand), never to an off one.
function Circuits.owner(o)
    local sq = o:getSquare()
    if not sq then return nil end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    -- Native wall switches control a WHOLE room. Use one reference point for
    -- that room so two panels never alternately switch the same light group.
    if instanceof(o, "IsoLightSwitch") and not o:getCanBeModified() and sq:getRoom() then
        local def = sq:getRoom():getRoomDef()
        x, y, z = def:getX() + def:getW() / 2, def:getY() + def:getH() / 2, def:getZ()
    end
    local R, best, distance = LiveWire.Registry
    local radius, floors = LiveWire.Config.tileRange(), LiveWire.Config.verticalRange()
    for _, inv in ipairs(R.invertersNear(x, y, radius)) do
        local d = (x - inv.x)^2 + (y - inv.y)^2
        if math.abs(z - inv.z) <= floors
            and (not best or d < distance or (d == distance and inv.id < best.id)) then
            best, distance = inv, d
        end
    end
    return best and R.grid(best.grid) or nil
end
local function blocked(g, kind)
    if not kind then return false end
    return g and (kind == "light" and g.lightsOff == true or kind ~= "light" and g.equipmentOff == true) or false
end
function Circuits.blocked(o)
    local kind = LiveWire.Appliances.kind(o)
    return kind and blocked(Circuits.owner(o), kind) or false
end
local function captureFor(o, g)
    local A = LiveWire.Appliances
    -- A native room switch changes its siblings too. Find their saved choice
    -- before capturing a later sibling, even when work spans several frames.
    local roomOn
    if not A.saved(o) and instanceof(o, "IsoLightSwitch") and not o:getCanBeModified() then
        local room = o:getSquare():getRoom()
        local switches = room and room:getLightSwitches()
        for i = 0, switches and switches:size() - 1 or -1 do
            local saved = A.saved(switches:get(i))
            if saved and saved.kind == "light" then roomOn = saved.on; break end
        end
    end
    local s = LiveWire.Appliances.capture(o, g)
    if s and roomOn ~= nil then s.on = roomOn end
    local old = g.lightChoices and g.lightChoices[key(o)]
    if s and s.kind == "light" and old ~= nil then s.on = old; g.lightChoices[key(o)] = nil end
end
function Circuits.applyObject(o)
    if not loaded(o) then track(o, false); return end
    local A = LiveWire.Appliances
    if not A.kind(o) and not A.saved(o) then track(o, false); return end
    local g = Circuits.owner(o)
    local old = g and g.lightChoices and g.lightChoices[key(o)]
    if old ~= nil and not A.saved(o) and instanceof(o, "IsoLightSwitch") then
        local s = A.capture(o, g)
        if s then s.on = old; g.lightChoices[key(o)] = nil end
    end
    if blocked(g, A.kind(o)) then
        captureFor(o, g)
        local s = A.saved(o)
        if s then A.apply(o, s, true) end
    else A.restore(o) end
    -- This service owns pending restorations, independently of Demand's cache
    -- and of the lifetime of the inverter that originally isolated the object.
    track(o, A.saved(o) ~= nil)
end
local function push(q, key, job)
    job.key, job.index = key, 1
    q.tail = q.tail + 1; q.jobs[q.tail], byKey[key] = job, job
end
-- Oldest network job first, then the oldest chunk scan.
local function front()
    local job = grids.jobs[grids.head]
    if job then return grids, job end
    job = chunks.jobs[chunks.head]
    if job then return chunks, job end
end
local function pop(q)
    local job = q.jobs[q.head]
    q.jobs[q.head], byKey[job.key] = nil, nil; q.head = q.head + 1
    if q.head > q.tail then q.jobs, q.head, q.tail = {}, 1, 0 end
end
-- Queue (or restart) the circuit job of one inverter's appliance list.
local function queueEntry(id, e)
    e.circuitBusy = true
    local jobKey = "grid:" .. id
    local previous = byKey[jobKey]
    if previous then
        -- A new command must revisit the already processed prefix as well.
        previous.objects, previous.entry, previous.index = e.objects, e, 1
        return
    end
    push(grids, jobKey, { objects = e.objects, entry = e, inverter = id })
end
function Circuits.apply(grid)
    local e = LiveWire.Demand.inventories[grid.inverter]
    if e then queueEntry(grid.inverter, e) end
    -- Coupled inverters keep their own zones: apply the same circuits to their lists.
    local slaves = LiveWire.Registry.slaves(grid)
    for i = 1, #slaves do
        local se = LiveWire.Demand.inventories[slaves[i].id]
        if se then queueEntry(slaves[i].id, se) end
    end
end
-- Chunk jobs are keyed by world position, never by the IsoChunk reference: the
-- engine recycles unloaded chunks (WorldReuserThread) and hands the same Java
-- object to a later load, possibly elsewhere. A new load restarts the scan.
function Circuits.onLoadChunk(chunk)
    local wx, wy = LiveWire.Anchor.chunkCoords(chunk)
    if not wx then return end
    local job = { chunk = chunk, wx = wx, wy = wy, z = chunk:getMinLevel(), zmax = chunk:getMaxLevel(),
        square = 0, object = 0 }
    local jobKey = "chunk:" .. wx .. "," .. wy
    local previous = byKey[jobKey]
    if previous then
        for k, v in pairs(job) do previous[k] = v end
        return
    end
    push(chunks, jobKey, job)
end
-- The map slot is cleared on the main thread when a chunk unloads, before the
-- save and the reuse thread may empty its squares. While the active map still
-- returns this chunk at its position, no other thread can touch its squares.
local function current(job)
    return getCell():getChunkForGridSquare(job.wx * 8, job.wy * 8, job.z) == job.chunk
end
function Circuits.topologyChanged()
    local R = LiveWire.Registry
    if not R or not R.ready or R.readOnly then return end
    local done = {}
    for id in pairs(LiveWire.Demand.inventories) do
        local inv = R.device(id)
        local grid = inv and inv.grid and R.grid(inv.grid)
        if grid and not done[grid.id] then
            done[grid.id] = true
            Circuits.apply(grid)
        end
    end
    nextSweepAt = 0
end
function Circuits.release(grid, defer)
    grid.lightsOff, grid.equipmentOff, grid.mainOff = false, false, false
    local inv = LiveWire.Registry.device(grid.inverter)
    if inv then LiveWire.PowerHistory.equipment(LiveWire.Registry.data, inv, false, getGameTime():getWorldAgeHours()) end
    -- Queue while the old inventory still exists; the job retains its list if
    -- removeDevice/forget deletes the measurement cache immediately afterwards.
    Circuits.apply(grid)
    nextSweepAt = 0
end
function Circuits.set(player, args)
    local R = LiveWire.Registry
    if not R or not R.ready or R.readOnly or not player or player:isDead() then return end
    local dev = LiveWire.Commands.checkDevice(player, args.device)
    if not dev or dev.model ~= "Breaker" or not LiveWire.Protocol.isBool(args.off) then return end
    local grid = dev.grid and R.grid(dev.grid)
    local fields = { main = "mainOff", lights = "lightsOff", equipment = "equipmentOff" }
    local field = fields[args.circuit]
    if not grid or not field or (grid[field] == true) == args.off then return end
    local inv = R.device(grid.inverter)
    grid[field] = args.off
    grid.forecastAt = nil
    if args.circuit == "equipment" then
        LiveWire.PowerHistory.equipment(R.data, inv, args.off, getGameTime():getWorldAgeHours())
    end
    Circuits.apply(grid)
    local demand, breakdown = LiveWire.Demand.measureGrid(grid, inv, true)
    if demand then grid.demand, grid.appliances = demand, breakdown end
    local names = { main = "Main", lights = "Lights", equipment = "Equipment" }
    LiveWire.Journal.add(grid, "IGUI_LW_Event_" .. names[args.circuit] .. (args.off and "Off" or "On"))
    LiveWire.Sim.refresh(grid)
end
local function stepJob(job)
    if job.chunk then
        -- Skip at most 32 empty squares per work unit; stop at the first object.
        -- Unloaded (or recycled) since queued: drop the stale work. A later
        -- LoadChunk queues a fresh scan of whatever is loaded there. One check
        -- per step is enough: unloading never interleaves with this Lua call.
        if not current(job) then return true end
        for _ = 1, 32 do
            if job.z > job.zmax then return true end
            local sq = job.chunk:getGridSquare(job.square % 8, math.floor(job.square / 8), job.z)
            local objects = sq and sq:getObjects()
            local o = objects and job.object < objects:size() and objects:get(job.object)
            if o then
                job.object = job.object + 1
                Circuits.applyObject(o)
                break
            else
                job.object, job.square = 0, job.square + 1
                if job.square == 64 then job.square, job.z = 0, job.z + 1 end
            end
        end
        return false
    end
    local o = job.objects[job.index]
    if o then job.index = job.index + 1; Circuits.applyObject(o); return false end
    return true
end
function Circuits.tick()
    local R = LiveWire.Registry
    if not R or not R.ready or R.readOnly then return end
    local now = getTimestampMs()
    if lastClock and now < lastClock then
        nextBatchAt, nextSweepAt = now, now
    end
    lastClock = now
    -- OnTick only checks the clock between batches. Appliance work depends on
    -- real time, never FPS or time acceleration. No catch-up burst after a stall.
    if now < nextBatchAt then return end
    nextBatchAt = now + (front() and 20 or 100)
    if sweepLeft == 0 and now >= nextSweepAt then
        sweepLeft, nextSweepAt = #isolated, now + 1000
    end
    -- Commands, discovery and independent restorations share one budget. Alternate
    -- queued work and saved objects so a stream of chunk loads cannot starve either.
    local budget = 16
    while budget > 0 do
        local q, job = front()
        if job and (not preferSaved or sweepLeft == 0) then
            if stepJob(job) then
                pop(q)
                if job.entry then
                    job.entry.circuitBusy = false
                    local inv = R.device(job.inverter)
                    local grid = inv and inv.grid and R.grid(inv.grid)
                    if grid and LiveWire.Sim then LiveWire.Sim.refresh(grid) end
                end
            end
            preferSaved = true
        elseif sweepLeft > 0 and #isolated > 0 then
            local o = isolated[isolatedCursor]
            Circuits.applyObject(o)
            if positions[o] then isolatedCursor = isolatedCursor % #isolated + 1 end
            sweepLeft = sweepLeft - 1
            preferSaved = false
        else sweepLeft = 0; break end
        budget = budget - 1
        if getTimestampMs() - now >= 1 then break end
    end
end
Events.OnTick.Add(Circuits.tick)
