-- Live Wire: management computer (authority only).
-- A real vanilla desktop computer of the map (Mov_DesktopComputer, sprite
-- appliances_com_01_72, media/scripts/generated/items/moveable.txt), wired to an
-- inverter. While it is powered it adds to the network: a 48-hour history, a
-- forecast until sunrise and load shedding (lights are switched
-- off first when the stock gets low, to keep the fridge running).
-- The link is kept in the computer ModData under its own key, so the vanilla
-- object stays untouched otherwise.
if isClient() then return end

LiveWire = LiveWire or {}

local Computer = {}
LiveWire.Computer = Computer

Computer.KEY = LiveWire.Defs.COMPUTER_KEY
Computer.SHED_BELOW = 0.15
Computer.SHED_RESET = 0.30
Computer.HISTORY_HOURS = 48

function Computer.isComputer(obj)
    return LiveWire.Install.isComputer(obj)
end

function Computer.markOf(obj)
    local m = obj and obj:getModData()[Computer.KEY]
    if type(m) == "table" and type(m.id) == "string" then return m end
    return nil
end

function Computer.find(dev)
    local sq = getCell():getGridSquare(dev.x, dev.y, dev.z)
    if not sq then return nil, false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local m = Computer.markOf(o)
        if m and m.id == dev.id then return o, true end
    end
    return nil, true
end

function Computer.register(obj, grid, level)
    local sq = obj:getSquare()
    local dev = LiveWire.Registry.addDevice({
        role = "computer", model = "ManagementComputer", x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        level = level, state = "ok",
    })
    -- The inverter id lets the client open the network interface from the computer.
    obj:getModData()[Computer.KEY] = { id = dev.id, inverter = grid.inverter }
    if isServer() then obj:transmitModData() end
    LiveWire.Registry.link(dev, grid)
    return dev
end

function Computer.forget(dev)
    local obj = Computer.find(dev)
    if obj then
        obj:getModData()[Computer.KEY] = nil
        if isServer() then obj:transmitModData() end
    end
    LiveWire.Registry.removeDevice(dev.id)
end

-- Is the computer running? It needs power on its square (from our anchor or any
-- other source). When not loaded, it runs if the network is powered.
function Computer.powered(dev, grid)
    local obj, loaded = Computer.find(dev)
    if loaded and not obj then return false end  -- gone: Sim drops it after two checks
    if not obj then return grid.powered == true end
    local sq = obj:getSquare()
    return sq:haveElectricity() or (sq:hasGridPower() and sq:getRoom() ~= nil)
end

-- Hourly sample { p = production W, d = demand W, s = stock 0..1 or -1 } (48 kept).
function Computer.record(grid, now, prodW, demandW, stockFrac)
    grid.history = grid.history or {}
    if grid.historyAt and now - grid.historyAt < 1 then return end
    grid.historyAt = now
    local h = grid.history
    h[#h + 1] = { p = math.floor(prodW + 0.5), d = math.floor(demandW + 0.5), s = stockFrac or -1 }
    while #h > Computer.HISTORY_HOURS do table.remove(h, 1) end
end

-- Hours until the next dawn, from the season dawn (decimal hours).
function Computer.hoursToDawn()
    local tod = getGameTime():getTimeOfDay()
    local dawn = getClimateManager():getSeason():getDawn()
    local h = dawn - tod
    if h < 0 then h = h + 24 end
    return h
end

-- Switch the lights of the powered area off once, when the stock gets low.
function Computer.shed(grid, inv, dev, stockFrac)
    if not stockFrac then return end
    if stockFrac >= Computer.SHED_RESET then grid.shed = nil return end
    if grid.shed or stockFrac >= Computer.SHED_BELOW then return end
    local entry = LiveWire.Demand.inventories[inv.id]
    if not entry then return end
    -- The master's zone first, then the zone of every in-service coupled inverter.
    local entries = { entry }
    local _, list = LiveWire.Sim.inService(grid)
    for k = 1, #list do
        local se = LiveWire.Demand.inventories[list[k].id]
        if se then entries[#entries + 1] = se end
    end
    local n = 0
    for k = 1, #entries do
        local objs = entries[k].objects
        for i = 1, #objs do
            local o = objs[i]
            if instanceof(o, "IsoLightSwitch") and o:getObjectIndex() ~= -1 and o:isActivated() then
                o:setActive(false)  -- switches the whole room and syncs (IsoLightSwitch.java:457-476)
                n = n + 1
            end
        end
    end
    grid.shed = true
    if n > 0 then
        LiveWire.notifyNear(inv.x, inv.y, inv.z, 30, "IGUI_LW_Shed", {}, true)
    end
end
