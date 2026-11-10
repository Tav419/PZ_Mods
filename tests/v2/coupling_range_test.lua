-- Offline test of the 2.0 build's coupling range (LWC_CouplingRange.lua), with stubs
-- for the game's globals. Since 2.0 Live Wire reads the range through its coupling
-- extension point (register_test.lua), so nothing is wrapped here. Run by run_tests.py with Lua 5.1 (the game's Kahlua is 5.1).
-- Globals set by the runner: MOD_LUA (path to the dev mod's media/lua folder).

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end

---------------------------------------------------------------- game stubs
function require() end

local optionValue = nil          -- LiveWireCoupling.CouplingRange, nil = no option
local useSandboxVars = false
function getSandboxOptions()
    return { getOptionByName = function(_, name)
        if name == "LiveWireCoupling.CouplingRange" and optionValue ~= nil and not useSandboxVars then
            return { getValue = function() return optionValue end }
        end
        return nil
    end }
end

local function square(x, y, z)
    local sq = { x = x, y = y, z = z, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    return sq
end
local squares, unloaded, world, anchors = {}, {}, {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
function getCell()
    return { getGridSquare = function(_, x, y, z)
        local k = key(x, y, z)
        if unloaded[k] then return nil end
        squares[k] = squares[k] or square(x, y, z)
        return squares[k]
    end }
end
-- An inverter, with its anchor unless `noAnchor`.
local function inverter(id, x, y, z, cpl, noAnchor)
    local sq = square(x, y, z)
    squares[key(x, y, z)] = sq
    local o = { mark = { id = id, model = "Inverter", cpl = cpl }, sq = sq }
    function o:getSquare() return self.sq end
    sq.objs[1] = o
    world[#world + 1] = o
    if not noAnchor then anchors[id] = { x = x, y = y, z = z, on = true } end
    return o
end

LiveWire = {}
local baseGet = function(k) return ({ LinkRange = 30, LinkVerticalRange = 3, WirePerTiles = 4 })[k] end
LiveWire.Config = { get = baseGet }
LiveWire.Marks = { get = function(o) return o and o.mark end }
function LiveWire.Marks.findOnSquare(sq, id)
    for _, o in ipairs(sq.objs) do if o.mark and o.mark.id == id then return o end end
end
LiveWire.Anchor = { table = function() return anchors end }

local Install = {}
LiveWire.Install = Install
function Install.distance(x1, y1, z1, x2, y2, z2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy), math.abs(z1 - z2)
end
-- Live Wire's search: loaded inverters within LinkRange and LinkVerticalRange.
function Install.invertersInRange(sq)
    local out = {}
    local range, floors = LiveWire.Config.get("LinkRange"), LiveWire.Config.get("LinkVerticalRange")
    for _, o in ipairs(world) do
        local s = o:getSquare()
        if not unloaded[key(s.x, s.y, s.z)] then
            local d, dz = Install.distance(sq.x, sq.y, sq.z, s.x, s.y, s.z)
            if d <= range and dz <= floors then out[#out + 1] = { obj = o, dist = d, kind = "device" } end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end
function Install.inverterById(sq, id)
    for _, e in ipairs(Install.invertersInRange(sq)) do
        if e.obj.mark.id == id then return e.obj end
    end
end
---------------------------------------------------------------- load
local installBefore = {}
for k, v in pairs(Install) do installBefore[k] = v end
dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_CouplingRange.lua")
local CR = LiveWire.CouplingRange
check(CR ~= nil, "LiveWire.CouplingRange defined")
local same = true
for k, v in pairs(Install) do if installBefore[k] ~= v then same = false end end
check(same and Install.checkCouple == nil, "Live Wire's Install is not wrapped or changed")
check(LiveWire.Config.get == baseGet, "Config.get untouched at load")

---------------------------------------------------------------- CR.get
optionValue = nil
check(CR.get() == 30, "no option: the cable range")
optionValue = 0
check(CR.get() == 30, "0: the cable range")
optionValue = 50
check(CR.get() == 50, "50: 50 tiles")
useSandboxVars = true
SandboxVars = { LiveWireCoupling = { CouplingRange = 45 } }
check(CR.get() == 45, "falls back to SandboxVars, got " .. tostring(CR.get()))
useSandboxVars = false
SandboxVars = nil

local A = inverter("A", 0, 0, 0)       -- the slave being coupled
local B = inverter("B", 45, 0, 0)      -- master 45 tiles away
local BOOM = inverter("BOOM", 5, 0, 0)

---------------------------------------------------------------- CR.inverters
local C = inverter("C", 20, 0, 0)                  -- within the cable range
local D = inverter("D", 60, 0, 0)                  -- past 50
local E = inverter("E", 10, 0, 5)                  -- 5 floors up (vertical range 3)
local F = inverter("F", 0, 40, 0)                  -- 40 tiles, square not loaded
unloaded[key(0, 40, 0)] = true
local G = inverter("G", 0, 25, 0, nil, true)       -- within cable range, no anchor
local function names(list)
    local s = {}
    for _, e in ipairs(list) do s[#s + 1] = e.obj.mark.id end
    return table.concat(s, " ")
end
local list = CR.inverters(A:getSquare(), 50)
check(names(list) == "A BOOM C G B", "range 50: nearest first, scan + anchors, got " .. names(list))
check(list[5].dist == 45 and list[5].kind == "device", "entries carry dist and kind like Live Wire's")
list = CR.inverters(A:getSquare(), 10)
check(names(list) == "A BOOM", "range 10: nothing past 10 tiles, got " .. names(list))
list = CR.inverters(A:getSquare(), nil)
check(names(list) == "A BOOM E C G B D", "no range: any distance, any floor, loaded only, got " .. names(list))
-- Picked up: the anchor is still there (until the server removes it), the object is not.
C.sq.objs = {}
for i, w in ipairs(world) do if w == C then table.remove(world, i) break end end
list = CR.inverters(A:getSquare(), 50)
check(names(list) == "A BOOM G B", "a picked-up inverter is not listed, got " .. names(list))
check(#CR.inverters(nil, 50) == 0, "no square: empty list")

---------------------------------------------------------------- CR.reachable (Live Wire's `inverters`)
optionValue = 50
check(names(CR.reachable(A:getSquare())) == "A BOOM G B", "reachable: within the coupling range (50)")
optionValue = 0
check(names(CR.reachable(A:getSquare())) == "A BOOM G", "reachable, option 0: within the cable range (30)")
optionValue = nil

---------------------------------------------------------------- CR.inverterById
check(CR.inverterById(A:getSquare(), "D") == D, "finds an inverter past the cable range through its anchor")
check(CR.inverterById(A:getSquare(), "F") == nil, "an inverter on an unloaded square is not found")
check(CR.inverterById(A:getSquare(), "G") == G, "an inverter without anchor is found by the usual search")
check(CR.inverterById(A:getSquare(), "C") == nil, "a picked-up inverter is not found")
check(CR.inverterById(A:getSquare(), nil) == nil, "no id: nil")

print(string.format("%d passed, %d failed", passes, fails))
return fails
