-- Live Wire: Coupled Inverter Zones add-on. Show the powered areas of every
-- inverter of a coupled network at once (client only, local display).
-- Same drawing as LW_RangeView.lua (a circle of GeneratorTileRange around each
-- inverter, projected on the player's floor when within the vertical range, else
-- on the inverter's floor), with one circle per inverter. Where circles overlap,
-- the arcs inside another inverter's circle are drawn faint, so the outer edge
-- of the whole network's area stands out. Hidden when the player walks far from
-- every inverter of the network.
-- A circle goes away when its inverter is removed (picked up, salvaged, destroyed).
-- The same check hides Live Wire's own "Show range" circle (LW_RangeView.lua),
-- which otherwise stays on screen after its inverter is gone.
if isServer() then return end

require "ISUI/ISUIElement"
require "LiveWireCoupling/LWC_CouplingRange"

LiveWire = LiveWire or {}

local ZV = {}
LiveWire.ZonesView = ZV

ZV.HIDE_DISTANCE = 60
ZV.SEGMENTS = 96
ZV.INNER_ALPHA = 0.3
ZV.CHECK_TICKS = 30   -- how often removed inverters are looked for

ZV.networkId = nil    -- master inverter id of the network shown
ZV.centers = nil      -- list of { x, y, z, id }, one per inverter
ZV.element = nil

local Overlay = ISUIElement:derive("LiveWireZonesOverlay")

function Overlay:new()
    local o = ISUIElement:new(0, 0, 1, 1)
    setmetatable(o, self)
    self.__index = self
    return o
end

function Overlay:onMouseDown() return false end
function Overlay:onRightMouseDown() return false end

function Overlay:render()
    local list = ZV.centers
    local player = getPlayer()
    if not list or not player then return end
    local idx = player:getPlayerNum()
    local R = LiveWire.Config.tileRange()
    local floors = LiveWire.Config.verticalRange()
    local pz = math.floor(player:getZ())
    local col = LiveWire.RangeView.COLOR
    -- Floor each circle is drawn on.
    local zs = {}
    for i = 1, #list do
        zs[i] = list[i].z
        if math.abs(pz - list[i].z) <= floors then zs[i] = pz end
    end
    -- True when (x, y) is inside the circle of another inverter drawn on the same floor.
    local function covered(i, x, y)
        for j = 1, #list do
            if j ~= i and zs[j] == zs[i] then
                local dx, dy = x - (list[j].x + 0.5), y - (list[j].y + 0.5)
                if dx * dx + dy * dy < R * R then return true end
            end
        end
        return false
    end
    for i = 1, #list do
        local c = list[i]
        local cx, cy, z = c.x + 0.5, c.y + 0.5, zs[i]
        local px, py = nil, nil
        for s = 0, ZV.SEGMENTS do
            local ang = 2 * math.pi * s / ZV.SEGMENTS
            local wx, wy = cx + R * math.cos(ang), cy + R * math.sin(ang)
            local x, y = isoToScreenX(idx, wx, wy, z), isoToScreenY(idx, wx, wy, z)
            if px then
                local mid = 2 * math.pi * (s - 0.5) / ZV.SEGMENTS
                local a = col.a
                if covered(i, cx + R * math.cos(mid), cy + R * math.sin(mid)) then a = ZV.INNER_ALPHA end
                self:drawLine(nil, px, py, x, y, 3, a, col.r, col.g, col.b)
            end
            px, py = x, y
        end
        -- The inverter itself: a small cross on its square.
        local ix, iy = isoToScreenX(idx, cx, cy, c.z), isoToScreenY(idx, cx, cy, c.z)
        self:drawLine(nil, ix - 8, iy, ix + 8, iy, 3, col.a, col.r, col.g, col.b)
        self:drawLine(nil, ix, iy - 8, ix, iy + 8, 3, col.a, col.r, col.g, col.b)
    end
end

-- Network id of an inverter: its master's id when coupled, else its own.
function ZV.networkOf(mark)
    return mark.cpl or mark.id
end

function ZV.isShown(networkId)
    return ZV.networkId ~= nil and ZV.networkId == networkId
end

function ZV.hide()
    if ZV.element then
        ZV.element:setVisible(false)
        ZV.element:removeFromUIManager()
        ZV.element = nil
    end
    ZV.networkId, ZV.centers = nil, nil
end

-- Squares of the inverters of `obj`'s network: the master and its slaves, on loaded
-- squares at any distance (a slave can be coupled past the cable range,
-- LWC_CouplingRange.lua). They are looked for from the master (from `obj` itself
-- when the master is not loaded). `obj` is always included.
function ZV.collect(obj)
    local CR = LiveWire.CouplingRange
    local mark = LiveWire.Marks.get(obj)
    local netId = ZV.networkOf(mark)
    local base = obj
    if mark.cpl then base = CR.inverterById(obj:getSquare(), mark.cpl) or obj end
    local centers, seen = {}, {}
    local function add(o, id)
        if seen[id] then return end
        seen[id] = true
        local sq = o:getSquare()
        centers[#centers + 1] = { x = sq:getX(), y = sq:getY(), z = sq:getZ(), id = id }
    end
    add(obj, mark.id)
    local list = CR.inverters(base:getSquare(), nil)
    for i = 1, #list do
        local m = LiveWire.Marks.get(list[i].obj)
        if m and (m.id == netId or m.cpl == netId) then add(list[i].obj, m.id) end
    end
    return netId, centers
end

function ZV.show(networkId, centers)
    ZV.hide()
    ZV.networkId = networkId
    ZV.centers = centers
    local el = Overlay:new()
    el:initialise()
    el:addToUIManager()
    el:backMost()
    ZV.element = el
end

-- True when inverter `id` is known to be gone from the square at `c`: the square is
-- loaded and holds no device with that id. An unloaded square proves nothing.
local function gone(c, id)
    local cell = getCell()
    local sq = cell and cell:getGridSquare(c.x, c.y, c.z)
    return sq ~= nil and LiveWire.Marks.findOnSquare(sq, id) == nil
end

local function dropRemoved()
    if ZV.centers then
        local kept = {}
        for i = 1, #ZV.centers do
            local c = ZV.centers[i]
            if not gone(c, c.id) then kept[#kept + 1] = c end
        end
        if #kept == 0 then ZV.hide() else ZV.centers = kept end
    end
    -- Live Wire's "Show range": only an inverter's circle (a pump's circle has options
    -- and is managed by LW_PumpView.lua).
    local RV = LiveWire.RangeView
    if RV and RV.inverterId and RV.center and not RV.opts and gone(RV.center, RV.inverterId) then
        RV.hide()
    end
end

local checkCounter = 0
local function onTick()
    checkCounter = checkCounter + 1
    if checkCounter >= ZV.CHECK_TICKS then
        checkCounter = 0
        dropRemoved()
    end
    if not ZV.centers then return end
    local player = getPlayer()
    if not player then return end
    local far = ZV.HIDE_DISTANCE * ZV.HIDE_DISTANCE
    for i = 1, #ZV.centers do
        local dx, dy = player:getX() - ZV.centers[i].x, player:getY() - ZV.centers[i].y
        if dx * dx + dy * dy <= far then return end
    end
    ZV.hide()
end

Events.OnTick.Add(onTick)
