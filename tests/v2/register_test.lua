-- Offline test of the 2.0 build's registration with Live Wire's coupling extension
-- point (LWC_Register.lua), running Live Wire's own LW_Extension.lua and
-- LW_Coupling.lua. Run by run_tests.py with Lua 5.1 (the game's Kahlua is 5.1).
-- Globals set by the runner: MOD_LUA (the add-on's media/lua folder), LIVEWIRE_LUA
-- (Live Wire's media/lua folder, with LW_Coupling.lua).

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
if not LIVEWIRE_LUA then
    print("FAIL: register_test.lua needs --livewire <Live Wire media/lua folder> (see the README)")
    return 1
end

---------------------------------------------------------------- game stubs
function require() end
local onInit = {}
Events = setmetatable({
    OnInitGlobalModData = { Add = function(f) onInit[#onInit + 1] = f end },
}, { __index = function(t, name)
    local e = { Add = function() end }
    rawset(t, name, e)
    return e
end })
local function initGlobalModData() for _, f in ipairs(onInit) do f() end end

local printed = {}
local realPrint = print
function print(s) printed[#printed + 1] = tostring(s) end
local function lastPrint() return printed[#printed] or "" end

local optionValue = 0
function getSandboxOptions()
    return { getOptionByName = function(_, name)
        if name == "LiveWireCoupling.CouplingRange" then
            return { getValue = function() return optionValue end }
        end
    end }
end

local function square(x, y, z)
    local sq = { x = x, y = y, z = z, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    return sq
end
local squares, anchors, world = {}, {}, {}
function getCell()
    return { getGridSquare = function(_, x, y, z) return squares[x .. "," .. y .. "," .. z] end }
end
local function inverter(id, x, y, z)
    local sq = square(x, y, z)
    squares[x .. "," .. y .. "," .. z] = sq
    local o = { mark = { id = id }, sq = sq }
    function o:getSquare() return self.sq end
    sq.objs[1] = o
    world[#world + 1] = o
    anchors[id] = { x = x, y = y, z = z }
    return o
end

local function freshLiveWire(withApi)
    LiveWire = {}
    LiveWire.Config = { get = function(k) return ({ LinkRange = 30, LinkVerticalRange = 3 })[k] end }
    LiveWire.Marks = { get = function(o) return o and o.mark end }
    function LiveWire.Marks.findOnSquare(sq, id)
        for _, o in ipairs(sq.objs) do if o.mark.id == id then return o end end
    end
    LiveWire.Anchor = { table = function() return anchors end }
    local Install = {}
    LiveWire.Install = Install
    function Install.distance(x1, y1, z1, x2, y2, z2)
        local dx, dy = x1 - x2, y1 - y2
        return math.sqrt(dx * dx + dy * dy), math.abs(z1 - z2)
    end
    function Install.invertersInRange(sq)
        local out = {}
        for _, o in ipairs(world) do
            local s = o:getSquare()
            local d, dz = Install.distance(sq.x, sq.y, sq.z, s.x, s.y, s.z)
            if d <= 30 and dz <= 3 then out[#out + 1] = { obj = o, dist = d, kind = "device" } end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end
    function Install.inverterById(sq, id)
        for _, e in ipairs(Install.invertersInRange(sq)) do if e.obj.mark.id == id then return e.obj end end
    end
    onInit = {}
    if withApi then
        dofile(LIVEWIRE_LUA .. "/shared/LiveWire/LW_Extension.lua")
        dofile(LIVEWIRE_LUA .. "/shared/LiveWire/LW_Coupling.lua")
        dofile(LIVEWIRE_LUA .. "/shared/LiveWire/LW_API.lua")
    end
    dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_CouplingRange.lua")
end
local function loadAddon() dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_Register.lua") end

local A = inverter("A", 0, 0, 0)
local B = inverter("B", 25, 0, 0)    -- within the cable range
local C = inverter("C", 60, 0, 0)    -- past it
local function names(list)
    local s = {}
    for _, e in ipairs(list) do s[#s + 1] = e.obj.mark.id end
    return table.concat(s, " ")
end

---------------------------------------------------------------- Live Wire alone
freshLiveWire(true)
local Coupling = LiveWire.Coupling
check(Coupling ~= nil and type(Coupling.register) == "function", "Live Wire has the coupling extension point")
check(Coupling.version == 1, "extension point version 1 (the add-on is written for it), got " .. tostring(Coupling.version))
check(not Coupling.active() and not Coupling.slaveKeepsZone(), "without the add-on: nothing registered")
optionValue = 70
check(Coupling.range() == 30, "without the add-on: the cable range")
check(names(Coupling.inverters(A:getSquare())) == "A B", "without the add-on: Live Wire's own search")

---------------------------------------------------------------- with the add-on
loadAddon()
local Reg = LiveWire.CouplingAddon
check(Reg.ok == true and Reg.why == nil, "registered, got " .. tostring(Reg.ok) .. " " .. tostring(Reg.why))
check(lastPrint():find("registered with LiveWire", 1, true) ~= nil, "logs the registration: " .. lastPrint())
check(Coupling.active() and Coupling.slaveKeepsZone(), "coupled inverters keep their zone")
optionValue = 70
check(Coupling.range() == 70, "range: the Coupling range option (70)")
check(names(Coupling.inverters(A:getSquare())) == "A B C", "inverters: up to 70 tiles, through anchors")
check(Coupling.inverterById(A:getSquare(), "C") == C, "inverterById finds a master 60 tiles away")
optionValue = 0
check(Coupling.range() == 30, "option 0: the cable range")
check(names(Coupling.inverters(A:getSquare())) == "A B", "option 0: within the cable range")
optionValue = 50
check(Coupling.range() == 50 and names(Coupling.inverters(A:getSquare())) == "A B", "option 50: C (60) is out")
-- The menu goes to LWC_ZonesView.lua on the client; nothing (no error) on the server.
local ok = pcall(Coupling.addMenu, {}, nil, A, A.mark, true)
check(ok, "menu without LWC_ZonesView (server): no error")
local got
LiveWire.ZonesView = { addMenu = function(menu, player, obj, mark, isSlave) got = { obj, mark, isSlave } end }
Coupling.addMenu({}, "p", A, A.mark, true)
check(got and got[1] == A and got[2] == A.mark and got[3] == true, "menu calls ZonesView.addMenu for a slave")
Coupling.addMenu({}, "p", B, B.mark, false)
check(got and got[1] == B and got[3] == false, "menu calls ZonesView.addMenu for a master")
LiveWire.ZonesView = nil
-- Reloading the file does not register twice (and does not log a failure).
local n = #printed
loadAddon()
check(Reg.ok == true and #printed == n, "reloading: still registered, nothing logged")

---------------------------------------------------------------- closed after OnInitGlobalModData
freshLiveWire(true)
initGlobalModData()
loadAddon()
Reg = LiveWire.CouplingAddon
check(Reg.ok == false and Reg.why == "registration_closed", "too late: registration_closed")
check(lastPrint():find("could not register", 1, true) ~= nil, "logs the failure: " .. lastPrint())
check(not LiveWire.Coupling.slaveKeepsZone(), "too late: Live Wire's own behaviour")

---------------------------------------------------------------- another add-on first
freshLiveWire(true)
check(LiveWire.Coupling.register({ range = function() return 5 end }) == true, "another add-on registers")
loadAddon()
Reg = LiveWire.CouplingAddon
check(Reg.ok == false and Reg.why == "already_registered", "taken: already_registered")
check(lastPrint():find("already_registered", 1, true) ~= nil, "logs the reason: " .. lastPrint())

---------------------------------------------------------------- LiveWire.API older than revision 3
freshLiveWire(true)
check(LiveWire.API.version == 1 and LiveWire.API.revision >= 3,
    "Live Wire's API is version 1, revision 3 or newer, got " .. tostring(LiveWire.API.revision))
check(type(LiveWire.API.anchors) == "function" and type(LiveWire.API.onRangeView) == "function"
    and type(LiveWire.API.rangeColor) == "function" and type(LiveWire.API.hideRange) == "function"
    and type(LiveWire.API.rangeShown) == "function" and type(LiveWire.API.mark) == "function"
    and type(LiveWire.API.markOnSquare) == "function" and type(LiveWire.API.invertersInRange) == "function"
    and type(LiveWire.API.distance) == "function", "the API functions the add-on uses exist")
LiveWire.API.revision = 2
loadAddon()
Reg = LiveWire.CouplingAddon
check(Reg.ok == false and Reg.why == "old_api", "API revision 2: old_api, got " .. tostring(Reg.why))
check(lastPrint():find("needs revision 3", 1, true) ~= nil, "logs that the API is too old: " .. lastPrint())
check(not LiveWire.Coupling.slaveKeepsZone(), "old API: Live Wire's own behaviour")

---------------------------------------------------------------- Live Wire without the extension point
freshLiveWire(false)
loadAddon()
Reg = LiveWire.CouplingAddon
check(Reg.ok == false and Reg.why == "no_coupling_api", "old Live Wire: no_coupling_api")
check(lastPrint():find("no coupling extension point", 1, true) ~= nil, "logs that Live Wire is too old: " .. lastPrint())

print = realPrint
print(string.format("%d passed, %d failed", passes, fails))
return fails
