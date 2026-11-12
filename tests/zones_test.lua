-- Offline test of the 2.0 build's right-click menu: "Show all powered areas" and
-- the coupling range in the menu. Runs Live Wire's own LW_ContextMenu.lua and its
-- coupling extension point (LW_Extension.lua, LW_Coupling.lua) with the add-on
-- registered, and stubs for the game's globals. Run by run_tests.py with Lua 5.1
-- (the game's Kahlua is 5.1). Globals set by the runner: MOD_LUA (the add-on's
-- media/lua folder), LIVEWIRE_LUA (Live Wire's media/lua folder, with LW_Coupling.lua).

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
if not LIVEWIRE_LUA then
    print("FAIL: zones_test.lua needs --livewire <Live Wire media/lua folder> (see the README)")
    return 1
end

---------------------------------------------------------------- game stubs
function isServer() return false end
local ticks, fillWorld = {}, nil
Events = {
    OnTick = {
        Add = function(f) ticks[#ticks + 1] = f end,
        Remove = function(f)
            for i = #ticks, 1, -1 do if ticks[i] == f then table.remove(ticks, i) end end
        end,
    },
    OnFillWorldObjectContextMenu = { Add = function(f) fillWorld = f end },
    OnFillInventoryObjectContextMenu = { Add = function() end },
    OnInitGlobalModData = { Add = function() end },
}
local loaded = {}
function require(name)
    local files = {
        ["LiveWireCoupling/LWC_ZonesView"] = MOD_LUA .. "/client/LiveWireCoupling/LWC_ZonesView.lua",
        ["LiveWireCoupling/LWC_CouplingRange"] = MOD_LUA .. "/shared/LiveWireCoupling/LWC_CouplingRange.lua",
        ["LiveWire/LW_Extension"] = LIVEWIRE_LUA .. "/shared/LiveWire/LW_Extension.lua",
        ["LiveWire/LW_Coupling"] = LIVEWIRE_LUA .. "/shared/LiveWire/LW_Coupling.lua",
        ["LiveWire/LW_API"] = LIVEWIRE_LUA .. "/shared/LiveWire/LW_API.lua",
        ["LiveWire/LW_RangeView"] = LIVEWIRE_LUA .. "/client/LiveWire/LW_RangeView.lua",
    }
    if files[name] and not loaded[name] then
        loaded[name] = true
        dofile(files[name])
    end
end

local couplingRange = 0   -- sandbox option LiveWireCoupling.CouplingRange
function getSandboxOptions()
    return { getOptionByName = function(_, name)
        if name == "LiveWireCoupling.CouplingRange" then
            return { getValue = function() return couplingRange end }
        end
    end }
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
function getTimestampMs() return 0 end  -- LiveWire 2.0.0's range view times its "inverter gone" check
function getSpecificPlayer() return player end
function isoToScreenX(i, x, y, z) return x - y end
function isoToScreenY(i, x, y, z) return x + y - z * 3 end

local texts = {}   -- arguments of the last getText call for each key
function getText(key, ...) texts[key] = { ... }; return key end
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
local squares, unloaded, anchors = {}, {}, {}
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
    anchors[id] = { x = x, y = y, z = z, on = true }   -- every inverter has an anchor
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
local disc = true   -- false: a coverage provider replaces the disc (LiveWire Extended)
LiveWire.Coverage = { hasDisc = function() return disc end, extraPositions = function() return {} end }
LiveWire.PumpView = { hide = function() end, isShown = function() return false end }
LiveWire.Marks = { get = function(o) return o and o.mark end }
LiveWire.Anchor = { table = function() return anchors end }
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
        local s = o:getSquare()
        local d, dz = dist(sq, s)
        if d <= 30 and dz <= 3 and not unloaded[key(s.x, s.y, s.z)] then
            out[#out + 1] = { obj = o, dist = d, kind = "device" }
        end
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
-- Like Live Wire's: the distance check reads the coupling range (the cable range
-- unless an add-on sets one).
function LiveWire.Install.checkCouple(character, slave, master)
    local d = dist(slave:getSquare(), master:getSquare())
    local range = LiveWire.Coupling.range()
    if d > range then return false, "Tooltip_LW_TooFarForCable", tostring(math.ceil(d)), tostring(range) end
    return true, nil, math.max(1, math.ceil(d / 4))
end
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

---------------------------------------------------------------- load, in the game's order
-- Shared files (Live Wire's, then the add-on's), then client files (Live Wire's, then
-- the add-on's).
require("LiveWire/LW_Extension")
require("LiveWire/LW_Coupling")
require("LiveWire/LW_API")
dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_Register.lua")
check(LiveWire.CouplingAddon.ok == true, "the add-on registered: " .. tostring(LiveWire.CouplingAddon.why))
check(LiveWire.Coupling.slaveKeepsZone() == true, "coupled inverters keep their zone")
require("LiveWire/LW_RangeView")
local RV = LiveWire.RangeView
dofile(LIVEWIRE_LUA .. "/client/LiveWire/LW_ContextMenu.lua")
local baseShowRange = LiveWire.Menu.onShowRange
require("LiveWireCoupling/LWC_ZonesView")
local ZV = LiveWire.ZonesView
check(ZV ~= nil and ZV.addMenu ~= nil, "LWC_ZonesView loaded")
check(fillWorld ~= nil, "menu registered its world context menu handler")
check(LiveWire.Menu.onShowRange == baseShowRange, "Live Wire's Show range is not wrapped")
check(#LiveWire.API.rangeViewListeners() == 1, "one range view listener registered")
local ticksBefore = #ticks
loaded["LiveWireCoupling/LWC_ZonesView"] = nil
require("LiveWireCoupling/LWC_ZonesView")
check(#LiveWire.API.rangeViewListeners() == 1, "reloading keeps one range view listener")
ticks[#ticks] = nil   -- the reload added its OnTick handler again
check(#ticks == ticksBefore, "tick handlers back to the first load's")

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
unloaded[key(100, 100, 0)] = true
net, c = ZV.collect(S2)
check(net == "M" and ids(c) == "100,125,1 120,100,0", "slave with master unloaded shows itself and S1, got " .. ids(c))
unloaded[key(100, 100, 0)] = nil

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
local ok = pcall(ZV.toggle, player, ghost)
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
RV.show("P", 102, 102, 0, { radius = 10 })   -- near the player: Live Wire hides far views
runTicks(ZV.CHECK_TICKS or 30)
check(RV.inverterId == "P", "a pump's circle is not touched")
RV.hide()

---------------------------------------------------------------- LiveWire Extended: no radius
-- Extended's coverage provider replaces the disc: no circles to show, so no option.
ZV.hide()
disc = false
local xm = openMenu(M)
check(xm ~= nil and find(xm, "Show all powered areas") == nil and find(xm, "Hide all powered areas") == nil,
    "no radius (Extended): 'Show all powered areas' is not offered")
check(find(openMenu(S1), "Show all powered areas") == nil, "no radius: not offered on a coupled inverter either")
ZV.toggle(player, M)
check(ZV.networkId == nil and ZV.element == nil, "no radius: toggling shows nothing")
disc = true
check(find(openMenu(M), "Show all powered areas") ~= nil, "with a radius again: offered")

---------------------------------------------------------------- coupling range
local F = inverter("F", 145, 100, 0)          -- 36 tiles from X: past the cable range
local G = inverter("G", 185, 100, 0, "F")     -- slave of F, 40 tiles from it
-- Masters offered in Live Wire > X > Couple to an inverter, and the submenu.
local function coupleTargets(obj)
    local co = find(openMenu(obj), "ContextMenu_LW_CoupleTo")
    local out = {}
    for _, o in ipairs(co and co.sub and co.sub.options or {}) do
        if o.fn then out[#out + 1] = o.args[2].mark.id .. (o.notAvailable and "!" or "") end
    end
    return table.concat(out, " "), co and co.sub
end
couplingRange = 0
local got = coupleTargets(X)
check(got == "M", "range 0: only masters within the cable range, got '" .. got .. "'")
couplingRange = 50
got = coupleTargets(X)
check(got == "M F", "range 50: the far master is offered and allowed, got '" .. got .. "'")
couplingRange = 40
got = coupleTargets(X)
check(got == "M F", "range 40: 36 tiles offered, got '" .. got .. "'")
couplingRange = 10
local sub
got, sub = coupleTargets(X)
check(got == "" and sub and find(sub, "ContextMenu_LW_NoInverter") ~= nil
    and texts["ContextMenu_LW_NoInverter"][1] == "10", "range 10: 'No inverter within 10 tiles'")
couplingRange = 50
unloaded[key(145, 100, 0)] = true
got = coupleTargets(X)
check(got == "M", "a master on an unloaded square is not offered, got '" .. got .. "'")
-- A slave coupled past the cable range sees its master's distance.
unloaded[key(145, 100, 0)] = nil
local gm = openMenu(G)
check(find(gm, "ContextMenu_LW_CoupledTo") ~= nil and texts["ContextMenu_LW_CoupledTo"][1] == "40",
    "slave 40 tiles away: 'Coupled to the inverter 40 tiles away'")
unloaded[key(145, 100, 0)] = true
gm = openMenu(G)
check(find(gm, "ContextMenu_LW_CoupledFar") ~= nil, "master not loaded: 'Coupled to an inverter out of sight'")
unloaded[key(145, 100, 0)] = nil
-- Show all powered areas finds the whole network past the cable range.
net, c = ZV.collect(G)
check(net == "F" and ids(c) == "145,100,0 185,100,0", "far slave collects its master, got " .. ids(c))
net, c = ZV.collect(F)
check(net == "F" and ids(c) == "145,100,0 185,100,0", "master collects its far slave, got " .. ids(c))
check(LiveWire.Config.get("LinkRange") == 30, "the cable range is unchanged after the menus")
-- Lowered after coupling: G is 40 tiles from F, past a 30-tile range. Live Wire finds
-- the master through its anchor at any distance (API revision 3).
couplingRange = 30
gm = openMenu(G)
check(find(gm, "ContextMenu_LW_CoupledTo") ~= nil and texts["ContextMenu_LW_CoupledTo"][1] == "40",
    "range lowered to 30: the slave's menu still shows its master 40 tiles away")
check(find(gm, "ContextMenu_LW_ShowRange") ~= nil and find(gm, "Show all powered areas") ~= nil,
    "the far slave still has Show range and Show all powered areas")
couplingRange = 0

print(string.format("%d passed, %d failed", passes, fails))
return fails
