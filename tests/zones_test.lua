-- Offline test of the dev build's "Show all powered areas", with stubs for the
-- game's globals. Run by run_tests.py with Lua 5.1 (the game's Kahlua is 5.1).
-- Globals set by the runner: MOD_LUA (path to the dev mod's media/lua folder).

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end

---------------------------------------------------------------- game stubs
function isServer() return false end
local ticks, fillWorld = {}, nil
Events = {
    OnTick = { Add = function(f) ticks[#ticks + 1] = f end },
    OnFillWorldObjectContextMenu = { Add = function(f) fillWorld = f end },
    OnFillInventoryObjectContextMenu = { Add = function() end },
}
local loaded = {}
function require(name)
    if name == "LiveWireCoupling/LWC_ZonesView" and not loaded[name] then
        loaded[name] = true
        dofile(MOD_LUA .. "/client/LiveWireCoupling/LWC_ZonesView.lua")
    end
end

local drawn = {}
local uiCount = 0
ISUIElement = {}
ISUIElement.__index = ISUIElement
function ISUIElement:derive(name)
    local c = {}
    setmetatable(c, self)
    c.__index = c
    c.Type = name
    return c
end
function ISUIElement:new(x, y, w, h)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end
function ISUIElement:initialise() end
function ISUIElement:addToUIManager() uiCount = uiCount + 1; self.inUI = true end
function ISUIElement:removeFromUIManager() uiCount = uiCount - 1; self.inUI = false end
function ISUIElement:backMost() end
function ISUIElement:setVisible(v) end
function ISUIElement:drawLine(tex, x1, y1, x2, y2, th, a, r, g, b)
    drawn[#drawn + 1] = { a = a }
end

local player = { x = 100, y = 100, z = 0 }
function player:getPlayerNum() return 0 end
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:getVehicle() return nil end
function player:getInventory() return { getCountTypeRecurse = function() return 0 end } end
function getPlayer() return player end
function getSpecificPlayer() return player end
function isoToScreenX(i, x, y, z) return x - y end
function isoToScreenY(i, x, y, z) return x + y - z * 3 end

local texts = {}
function getText(key, ...) texts[key] = true; return key end
function getTextOrNull(key) return nil end

-- World: squares and inverters.
local function square(x, y, z)
    local sq = { x = x, y = y, z = z, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getObjects()
        local list = self.objs
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    return sq
end
local world = {}
local squares, unloaded = {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
function getCell()
    return { getGridSquare = function(_, x, y, z)
        local k = key(x, y, z)
        if unloaded[k] then return nil end
        squares[k] = squares[k] or square(x, y, z)
        return squares[k]
    end }
end
local function inverter(id, x, y, z, cpl)
    local sq = square(x, y, z)
    squares[key(x, y, z)] = sq
    local o = { mark = { id = id, model = "Inverter", st = "on", cpl = cpl }, sq = sq }
    function o:getSquare() return self.sq end
    sq.objs[1] = o
    world[#world + 1] = o
    return o
end
local M  = inverter("M", 100, 100, 0)
local S1 = inverter("S1", 120, 100, 0, "M")   -- 20 tiles east: circles overlap
local S2 = inverter("S2", 100, 125, 1, "M")   -- 25 tiles south, one floor up
local X  = inverter("X", 110, 110, 0)         -- independent inverter
local Y  = inverter("Y", 105, 105, 0, "N")    -- slave of another network

LiveWire = {}
LiveWire.Config = {
    tileRange = function() return 20 end,
    verticalRange = function() return 3 end,
    get = function(k) return ({ LinkRange = 30, LinkVerticalRange = 3, WirePerTiles = 4 })[k] end,
}
-- Same public fields as LW_RangeView.lua.
local RV = { COLOR = { r = 0.25, g = 0.9, b = 1.0, a = 0.9 } }
LiveWire.RangeView = RV
function RV.isShown(id) return RV.inverterId ~= nil and RV.inverterId == id end
function RV.hide() RV.inverterId, RV.center, RV.opts = nil, nil, nil end
function RV.show(id, x, y, z, opts) RV.inverterId, RV.center, RV.opts = id, { x = x, y = y, z = z }, opts end
LiveWire.PumpView = { hide = function() end, isShown = function() return false end }
LiveWire.Marks = { get = function(o) return o and o.mark end }
function LiveWire.Marks.findOnSquare(sq, id)
    for _, o in ipairs(sq.objs) do if o.mark and o.mark.id == id then return o end end
end
local function dist(a, b)
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy), math.abs(a:getZ() - b:getZ())
end
LiveWire.Install = {}
function LiveWire.Install.invertersInRange(sq)
    local out = {}
    for _, o in ipairs(world) do
        local d, dz = dist(sq, o:getSquare())
        if d <= 30 and dz <= 3 then out[#out + 1] = { obj = o, dist = d, kind = "device" } end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end
function LiveWire.Install.inverterById(sq, id)
    for _, e in ipairs(LiveWire.Install.invertersInRange(sq)) do
        if e.obj.mark.id == id then return e.obj end
    end
end
function LiveWire.Install.objectsInRange() return {} end
function LiveWire.Install.linkKind(o) return o and o.mark and "device" or nil end
function LiveWire.Install.distance(x1, y1, z1, x2, y2, z2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy), math.abs(z1 - z2)
end
function LiveWire.Install.wiresFor(d) return math.max(1, math.ceil(d / 4)) end
function LiveWire.Install.checkCouple() return true end
function LiveWire.Install.vanillaMark() return nil end
function LiveWire.Install.isBarrelObject() return false end
LiveWire.Defs = { devices = { Inverter = { role = "inverter" } } }
LiveWire.Debug = { allowed = function() return false end }
LWMuffleAction = { canDo = function() return true end }
LWRepairAction = { canRepair = function() return true end }

-- Context menus: record option labels and submenus.
local Menu_ = {}
Menu_.__index = Menu_
local function newMenu() return setmetatable({ options = {} }, Menu_) end
function Menu_:addOption(name, target, fn, a1, a2, a3)
    local o = { name = name, target = target, fn = fn, args = { a1, a2, a3 } }
    self.options[#self.options + 1] = o
    return o
end
function Menu_:addSubMenu(opt, sub) opt.sub = sub end
ISContextMenu = { getNew = function() return newMenu() end }
ISWorldObjectContextMenu = { fetchVars = {}, addToolTip = function() return {} end }

local function find(menu, name)
    for _, o in ipairs(menu.options) do if o.name == name then return o end end
end
local function click(opt) opt.fn(opt.target, opt.args[1], opt.args[2], opt.args[3]) end

---------------------------------------------------------------- load the mod
dofile(MOD_LUA .. "/client/LiveWire/LW_ContextMenu.lua")
local ZV = LiveWire.ZonesView
check(ZV ~= nil, "LWC_ZonesView loaded through the menu's require")
check(fillWorld ~= nil, "menu registered its world context menu handler")

---------------------------------------------------------------- collect()
local function ids(centers)
    local s = {}
    for _, c in ipairs(centers) do s[#s + 1] = c.x .. "," .. c.y .. "," .. c.z end
    table.sort(s)
    return table.concat(s, " ")
end
local want = "100,100,0 100,125,1 120,100,0"
local net, c = ZV.collect(M)
check(net == "M" and ids(c) == want, "master collects itself + 2 slaves, got " .. tostring(net) .. " " .. ids(c))
net, c = ZV.collect(S1)
check(net == "M" and ids(c) == want, "slave collects the whole network, got " .. ids(c))
net, c = ZV.collect(X)
check(net == "X" and ids(c) == "110,110,0", "independent inverter collects only itself, got " .. ids(c))
-- Master not loaded: the slave still shows itself and what it can see.
local savedM = table.remove(world, 1)
net, c = ZV.collect(S2)
check(net == "M" and ids(c):find("100,125,1", 1, true) ~= nil, "slave with master unloaded still shows itself")
table.insert(world, 1, savedM)

---------------------------------------------------------------- render()
local function render()
    drawn = {}
    ZV.element:render()
    local faint, bright = 0, 0
    for _, d in ipairs(drawn) do
        if d.a < 0.5 then faint = faint + 1 else bright = bright + 1 end
    end
    return #drawn, faint, bright
end
ZV.show(ZV.collect(M))
local n, faint, bright = render()
check(n == 3 * 96 + 3 * 2, "3 circles of 96 segments + 3 crosses, got " .. n)
check(faint > 0, "overlapping arcs drawn faint (" .. faint .. ")")
check(bright > 3 * 2, "outer edge drawn bright (" .. bright .. ")")
-- Player on floor 0: S2 (floor 1) is within the vertical range, so all three circles
-- are drawn on floor 0 and S2's circle overlaps M's.
ZV.show("X", { { x = 110, y = 110, z = 0 } })
n, faint = render()
check(n == 96 + 2 and faint == 0, "a lone inverter's circle has no faint arcs")
-- Far apart circles (no overlap): nothing faint.
ZV.show("Q", { { x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 } })
n, faint = render()
check(faint == 0, "separate circles have no faint arcs, got " .. faint)
-- Player 5 floors up: S2's circle stays on its own floor (1), the others on 0.
player.z = 5
ZV.show(ZV.collect(M))
n, faint = render()
check(n == 3 * 96 + 3 * 2, "circles still drawn when the player is out of vertical range")
player.z = 0

---------------------------------------------------------------- hide on distance
ZV.show(ZV.collect(M))
player.x, player.y = 160, 100   -- 40 tiles from S1, 60+ from the others
for _, f in ipairs(ticks) do f() end
check(ZV.isShown("M"), "stays shown while within 60 tiles of one inverter")
player.x, player.y = 300, 300
for _, f in ipairs(ticks) do f() end
check(not ZV.isShown("M") and ZV.element == nil, "hidden when far from every inverter")
player.x, player.y = 100, 100

---------------------------------------------------------------- the right-click menu
local function openMenu(obj)
    ISWorldObjectContextMenu.fetchVars.clickedSquare = obj:getSquare()
    local context = newMenu()
    fillWorld(0, context, { obj }, false)
    local root = find(context, "ContextMenu_LW_Root")
    return root and root.sub and root.sub.options[1] and root.sub.options[1].sub
end
for _, case in ipairs({ { M, "master" }, { S1, "slave" }, { X, "independent" } }) do
    local obj, label = case[1], case[2]
    ZV.hide()
    local menu = openMenu(obj)
    check(menu ~= nil, label .. ": Live Wire > inverter submenu built")
    local show = menu and find(menu, "Show all powered areas")
    check(show ~= nil, label .. ": 'Show all powered areas' is in the inverter submenu")
    -- It sits right after Show range.
    if menu and show then
        local iRange, iAll
        for i, o in ipairs(menu.options) do
            if o.name == "ContextMenu_LW_ShowRange" then iRange = i end
            if o == show then iAll = i end
        end
        check(iRange and iAll == iRange + 1, label .. ": option follows 'Show range'")
        click(show)
        check(ZV.isShown(obj.mark.cpl or obj.mark.id), label .. ": clicking shows the network's areas")
        local menu2 = openMenu(obj)
        local hide = find(menu2, "Hide all powered areas")
        check(hide ~= nil, label .. ": menu then offers 'Hide all powered areas'")
        click(hide)
        check(ZV.networkId == nil and uiCount == 0, label .. ": clicking hides it and removes the overlay")
    end
end

-- Show range and Show all replace each other.
ZV.hide()
local menu = openMenu(M)
click(find(menu, "Show all powered areas"))
click(find(openMenu(M), "ContextMenu_LW_ShowRange"))
check(not ZV.isShown("M") and RV.inverterId == "M", "Show range replaces the network view")
click(find(openMenu(M), "Show all powered areas"))
check(ZV.isShown("M") and RV.inverterId == nil, "Show all replaces the single circle")
-- Picked up between menu and click: no error, nothing shown.
ZV.hide()
local ghost = { getSquare = function() return nil end }
local ok = pcall(LiveWire.Menu.onShowAllZones, player, ghost)
check(ok and ZV.networkId == nil, "clicking for a removed inverter does nothing")
check(uiCount <= 1, "overlays are not leaked (" .. uiCount .. " in UI)")

---------------------------------------------------------------- removed inverters
local function runTicks(n) for _ = 1, n do for _, f in ipairs(ticks) do f() end end end
local function pickUp(o)
    o.sq.objs = {}
    for i, w in ipairs(world) do if w == o then table.remove(world, i) break end end
end
local function putBack(o)
    o.sq.objs = { o }
    world[#world + 1] = o
end
ZV.show(ZV.collect(M))
pickUp(S1)
runTicks(ZV.CHECK_TICKS or 30)
check(ZV.isShown("M") and #ZV.centers == 2, "a picked-up slave's circle goes away, the rest stay")
n = render()
check(n == 2 * 96 + 2 * 2, "only the two remaining circles are drawn, got " .. n)
pickUp(M); pickUp(S2)
runTicks(ZV.CHECK_TICKS or 30)
check(ZV.networkId == nil and ZV.element == nil, "the view hides once every inverter is gone")
putBack(M); putBack(S1); putBack(S2)
-- An unloaded square proves nothing: the circle stays.
ZV.show(ZV.collect(M))
unloaded[key(120, 100, 0)] = true
runTicks(ZV.CHECK_TICKS or 30)
check(ZV.isShown("M") and #ZV.centers == 3, "a circle on an unloaded square is kept")
unloaded[key(120, 100, 0)] = nil
ZV.hide()
-- Live Wire's own Show range circle.
click(find(openMenu(X), "ContextMenu_LW_ShowRange"))
check(RV.inverterId == "X", "Show range shown for X")
runTicks(ZV.CHECK_TICKS or 30)
check(RV.inverterId == "X", "Show range stays while its inverter is there")
pickUp(X)
runTicks(ZV.CHECK_TICKS or 30)
check(RV.inverterId == nil, "Show range hides after its inverter is picked up")
putBack(X)
-- A pump's circle (RangeView with options) is left to LW_PumpView.
RV.show("P", 300, 300, 0, { radius = 10 })
runTicks(ZV.CHECK_TICKS or 30)
check(RV.inverterId == "P", "a pump's circle is not touched")
RV.hide()

print(string.format("%d passed, %d failed", passes, fails))
return fails
