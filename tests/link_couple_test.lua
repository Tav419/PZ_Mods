-- Offline test of linking and coupling with the add-on loaded (dev build 1.4.0).
-- Live Wire's own files (LIVEWIRE_LUA: LW_Core, LW_Config, LW_Defs, LW_Marks,
-- LW_Install, LW_Backup, TimedActions/LW_TimedActions) run with the add-on's
-- replacements (MOD_LUA: LW_Registry, LW_Devices, LW_Computer) and its coupling
-- range wrapper, as on the server. Since Live Wire 1.7.2 the link and couple actions
-- call Devices.wired once the link is made, and Install.checkLink reads the
-- inverter mark's `svc` (in service) field; both come from LW_Devices.lua.
-- Run by run_tests.py with --livewire. Globals set by the runner: MOD_LUA, LIVEWIRE_LUA.

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
if not LIVEWIRE_LUA then
    print("FAIL: link_couple_test.lua needs --livewire <Live Wire media/lua folder> (see the README)")
    return 1
end

---------------------------------------------------------------- game stubs
function isClient() return false end
function isServer() return true end   -- dedicated server: the authority
function require() end
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function() end }
    rawset(t, name, e)
    return e
end })
Perks = { Electricity = "Electricity" }
function instanceof(o, cls) return type(o) == "table" and o.javaClass == cls end
function sendRemoveItemFromContainer() end
function sendAddItemToContainer() end
function getGameTime() return { getWorldAgeHours = function() return 100 end } end
local globalData = {}
ModData = { getOrCreate = function(k) globalData[k] = globalData[k] or {}; return globalData[k] end }

-- The server's sandbox: cable range 30, coupling range 70, level requirements on.
local sandbox = {
    ["LiveWire.LinkRange"] = 30, ["LiveWire.LinkVerticalRange"] = 3,
    ["LiveWire.WirePerTiles"] = 4, ["LiveWire.SkillGates"] = true,
    ["LiveWireCoupling.CouplingRange"] = 70,
}
function getSandboxOptions()
    return { getOptionByName = function(_, name)
        if sandbox[name] == nil then return nil end
        return { getValue = function() return sandbox[name] end }
    end }
end

ISBaseTimedAction = {}
ISBaseTimedAction.__index = ISBaseTimedAction
function ISBaseTimedAction:derive(name)
    local c = setmetatable({}, self)
    c.__index = c
    c.Type = name
    return c
end
function ISBaseTimedAction.new(self, character)
    return setmetatable({ character = character }, self)
end

-- World: squares and objects.
local squares = {}
local function square(x, y, z)
    local k = x .. "," .. y .. "," .. z
    if squares[k] then return squares[k] end
    local sq = { x = x, y = y, z = z, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:isOutside() return true end
    function sq:getObjects()
        local list = self.objs
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    squares[k] = sq
    return sq
end
function getCell() return { getGridSquare = function(_, x, y, z) return square(x, y, z) end } end

local Obj = {}
Obj.__index = Obj
function Obj:getSquare() return self.sq end
function Obj:getObjectIndex() return 0 end
function Obj:getSprite()
    local name = self.sprite
    return { getName = function() return name end, getProperties = function() return nil end }
end
function Obj:getModData() return self.md end
function Obj:hasModData() return true end
function Obj:transmitModData() end
-- A vanilla generator: fuelled, plugged in, off.
function Obj:getFuel() return 5 end
function Obj:isConnected() return true end
function Obj:getCondition() return 100 end
function Obj:isActivated() return false end
local function object(x, y, z, sprite, javaClass, md)
    local sq = square(x, y, z)
    local o = setmetatable({ sq = sq, sprite = sprite, javaClass = javaClass, md = md or {} }, Obj)
    sq.objs[#sq.objs + 1] = o
    return o
end

-- Players: an Electrical level, 100 wires and 3 coupling kits; actions are instant.
local function newChar(name, level)
    local c = { name = name, level = level, x = 0, y = 0, z = 0, xp = 0,
                items = { ["Base.ElectricWire"] = 100, ["LiveWire.CouplingKit"] = 3 } }
    function c:getPerkLevel() return self.level end
    function c:getX() return self.x end
    function c:getY() return self.y end
    function c:getZ() return self.z end
    function c:isDead() return false end
    function c:getUsername() return self.name end
    function c:isTimedActionInstant() return true end
    function c:removeFromHands() end
    local inv = {}
    function inv:getCountTypeRecurse(t) return c.items[t] or 0 end
    function inv:getSomeTypeRecurse(t, n)
        local container = { DoRemoveItem = function(_, it) c.items[it.t] = c.items[it.t] - 1 end }
        local list = {}
        for i = 1, math.min(n, c.items[t] or 0) do
            list[i] = { t = t, getContainer = function() return container end }
        end
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    function c:getInventory() return inv end
    return c
end

---------------------------------------------------------------- load Live Wire + the add-on
local LW = LIVEWIRE_LUA
dofile(LW .. "/shared/LiveWire/LW_Core.lua")
local warnings = {}
function LiveWire.log() end
function LiveWire.warn(m) warnings[#warnings + 1] = m end
local notices = {}
function LiveWire.notify(ch, key, args) notices[#notices + 1] = key end
function LiveWire.notifyNear() end
LiveWire.Xp = { award = function(ch, n) ch.xp = ch.xp + (n or 0) end }
LiveWire.Maintenance = { liveWork = function() return false end }
LiveWire.Migration = { run = function() return true end }
LiveWire.PowerHistory = { init = function() end, record = function() end }
LiveWire.Sim = { updateAnchor = function() end, refresh = function() end, subscribers = {} }
LiveWire.Demand = { invalidate = function() end, reset = function() end, forget = function() end }
local anchorOff = {}
LiveWire.Anchor = {
    set = function(id, a, on) if on == false then anchorOff[id] = true end end,
    table = function() return LiveWire.Registry.anchors end,
}
dofile(LW .. "/shared/LiveWire/LW_Config.lua")
dofile(LW .. "/shared/LiveWire/LW_Defs.lua")
dofile(LW .. "/shared/LiveWire/LW_Marks.lua")
dofile(LW .. "/shared/LiveWire/LW_Install.lua")
dofile(LW .. "/shared/LiveWire/TimedActions/LW_TimedActions.lua")
dofile(LW .. "/server/LiveWire/LW_Backup.lua")
dofile(MOD_LUA .. "/server/LiveWire/LW_Registry.lua")
dofile(MOD_LUA .. "/server/LiveWire/LW_Devices.lua")
dofile(MOD_LUA .. "/server/LiveWire/LW_Computer.lua")
dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_CouplingRange.lua")

local R, Devices, Install, Defs = LiveWire.Registry, LiveWire.Devices, LiveWire.Install, LiveWire.Defs
R.init()
check(R.ready and not R.readOnly, "registry ready")
check(type(Devices.wired) == "function",
    "LW_Devices.lua defines Devices.wired (Live Wire 1.7.2's link and couple actions call it)")

local function place(ch, model, x, y, z, raw)
    local md = raw and { movableData = { LiveWire = raw } } or nil
    local o = object(x, y, z, Defs.SHEET .. "_" .. Defs.devices[model].tile, "IsoObject", md)
    return o, Devices.onPlaced(ch, o:getSquare(), o.sprite)
end
local function mark(o) return LiveWire.Marks.get(o) end
local function stand(ch, o)
    local sq = o:getSquare()
    ch.x, ch.y, ch.z = sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()
end
-- complete() runs on the authority; a Lua error comes back as a string.
local function run(action)
    local ok, res = pcall(action.complete, action)
    if not ok then return "error: " .. tostring(res) end
    return res
end
local function link(ch, target, invObj)
    stand(ch, target)
    return run(LWLinkAction:new(ch, target, invObj))
end
local function couple(ch, slaveObj, masterObj)
    stand(ch, slaveObj)
    return run(LWCoupleAction:new(ch, slaveObj, masterObj))
end

local pro = newChar("pro", 5)   -- places everything
local low = newChar("low", 2)
local mid = newChar("mid", 3)

---------------------------------------------------------------- placing
local A, a = place(pro, "Inverter", 100, 100, 0)
check(a and a.level == 0 and a.xpd == false and a.grid and R.grid(a.grid) ~= nil,
    "placed inverter: level 0, own grid, link experience still due")
check(pro.xp == 0, "placing gives no experience")
check(mark(A) and mark(A).svc == nil, "a new inverter is not in service")
local P1, p1 = place(pro, "SolarPanel", 104, 100, 0)

---------------------------------------------------------------- link a device: level gate
local ok, why, arg = Install.checkLink(low, P1, A)
check(not ok and why == "Tooltip_LW_NeedLevel" and arg == 3, "level 2 cannot link a solar panel (level 3)")
local wire0 = low.items["Base.ElectricWire"]
local res = link(low, P1, A)
check(res == false and p1.grid == nil and low.items["Base.ElectricWire"] == wire0,
    "refused link: nothing linked, no wire used, got " .. tostring(res))

---------------------------------------------------------------- link a device
res = link(mid, P1, A)
check(res == true, "level 3 links a solar panel to a new inverter, got " .. tostring(res))
check(p1.grid == a.grid and R.grid(a.grid).members[p1.id], "the panel is on the inverter's network")
check(p1.level == 3 and p1.eff == Defs.installEfficiency(3), "the panel takes the linker's level and efficiency")
check(a.svc == true and mark(A).svc == true, "the inverter is in service (registry and mark)")
check(p1.xpd == true and a.xpd == true and mid.xp == 10 + 25,
    "first link: panel + inverter experience, got " .. mid.xp)
check(mid.items["Base.ElectricWire"] == 99, "one wire for 4 tiles")
check(link(mid, P1, A) == false, "linking it again is refused")

-- Level 2 adds a level 2 device to an inverter in service...
local W1, w1 = place(pro, "WindTurbine", 100, 106, 0)
res = link(low, W1, A)
check(res == true and w1.grid == a.grid and w1.level == 2 and low.xp == 20,
    "level 2 links a wind turbine to an inverter in service, got " .. tostring(res))
-- ...but cannot put a new inverter in service.
local B, b = place(pro, "Inverter", 130, 100, 0)
local W2 = place(pro, "WindTurbine", 130, 106, 0)
ok, why, arg = Install.checkLink(low, W2, B)
check(not ok and why == "Tooltip_LW_NeedLevel" and arg == 3, "level 2 cannot put a new inverter in service")
sandbox["LiveWire.SkillGates"] = false
check(Install.checkLink(low, W2, B) == true, "with level requirements off, level 2 can")
sandbox["LiveWire.SkillGates"] = true
-- A weaker electrician re-linking never lowers a device.
local P3, p3 = place(pro, "SolarPanel", 96, 100, 0)
check(link(pro, P3, A) == true and p3.level == 5, "level 5 links a panel")
local eff5 = p3.eff
check(Devices.wired(mid, p3, a) == 0 and p3.level == 5 and p3.eff == eff5, "a level 3 re-link keeps level 5")

---------------------------------------------------------------- link a generator and a computer
local GEN = object(133, 100, 0, "appliances_misc_01_0", "IsoGenerator")
ok, why, arg = Install.checkLink(low, GEN, B)
check(not ok and why == "Tooltip_LW_NeedLevel" and arg == 3,
    "a generator (level 2) on a new inverter needs the inverter's level 3")
local xp0 = mid.xp
res = link(mid, GEN, B)
check(res == true, "level 3 links a generator to a new inverter, got " .. tostring(res))
local gm = Install.vanillaMark(GEN)
local gdev = gm and R.device(gm.id)
check(gdev and gdev.role == "backup" and gdev.grid == b.grid, "the generator is the network's backup")
check(b.svc == true and mark(B).svc == true and mid.xp - xp0 == 3 + 25,
    "the generator link puts the inverter in service, experience 3 + 25, got " .. (mid.xp - xp0))
local GEN2 = object(97, 104, 0, "appliances_misc_01_0", "IsoGenerator")
res = link(low, GEN2, A)
check(res == true, "level 2 links a generator to an inverter in service, got " .. tostring(res))
local PC = object(127, 100, 0, "appliances_com_01_72", "IsoObject")
check(link(low, PC, B) == false, "level 2 cannot link a computer (level 3)")
xp0 = mid.xp
res = link(mid, PC, B)
local cm = Install.vanillaMark(PC)
local cdev = cm and R.device(cm.id)
check(res == true and cdev and cdev.role == "computer" and cdev.grid == b.grid,
    "level 3 links a management computer, got " .. tostring(res))
check(mid.xp - xp0 == 3, "the inverter's experience is not given twice, got " .. (mid.xp - xp0))

---------------------------------------------------------------- couple
local M, m = place(pro, "Inverter", 200, 100, 0)
local S, s = place(pro, "Inverter", 260, 100, 0)   -- 60 tiles: past the cable range (30)
ok, why, arg = Install.checkCouple(low, S, M)
check(not ok and why == "Tooltip_LW_NeedLevel" and arg == 3, "level 2 cannot couple (level 3)")
local kit0 = low.items["LiveWire.CouplingKit"]
check(couple(low, S, M) == false and s.coupled == nil and low.items["LiveWire.CouplingKit"] == kit0,
    "refused coupling: nothing coupled, no kit used")
xp0, wire0 = mid.xp, mid.items["Base.ElectricWire"]
res = couple(mid, S, M)
check(res == true, "level 3 couples a slave 60 tiles from its master, got " .. tostring(res))
check(s.coupled == m.id and s.grid == m.grid and R.grid(m.grid).slaves[s.id],
    "the slave is on the master's network")
check(R.grid(m.grid).inverter == m.id and #R.slaves(R.grid(m.grid)) == 1, "the master keeps its grid")
check(mark(S).cpl == m.id and mark(S).svc == true and m.svc == true and mark(M).svc == true,
    "both inverters in service, marks updated")
check(s.level == 3 and mid.xp - xp0 == 5 + 25 + 25,
    "coupling: 5 + both inverters' first experience, got " .. (mid.xp - xp0))
check(mid.items["LiveWire.CouplingKit"] == 2 and wire0 - mid.items["Base.ElectricWire"] == 15,
    "one coupling kit and 15 wires used")
check(LiveWire.Config.get("LinkRange") == 30, "the cable range is unchanged after coupling")
local P4 = place(pro, "SolarPanel", 262, 100, 0)
ok, why = Install.checkLink(mid, P4, S)
check(not ok and why == "Tooltip_LW_CoupledInverter", "equipment cannot be linked to a slave")
local W3, w3 = place(pro, "WindTurbine", 200, 104, 0)
check(link(low, W3, M) == true and w3.grid == m.grid, "level 2 links a wind turbine to a coupled master")

---------------------------------------------------------------- saves from before 1.7.2 (no svc field)
m.svc, s.svc = nil, nil
local W4 = place(pro, "WindTurbine", 204, 104, 0)
R.grid(m.grid).members[w3.id] = nil   -- a master with a slave and no equipment
w3.grid = nil
Devices.syncMark(m)
Devices.syncMark(s)
check(mark(M).svc == true, "an old master with only a slave is in service")
check(mark(S).svc == true, "an old slave is in service")
check(link(low, W4, M) == true, "level 2 links a wind turbine to an old master with a slave")
local C, c = place(pro, "Inverter", 300, 100, 0)
c.svc = true
Devices.find(c)
check(mark(C).svc == true, "Devices.find refreshes a mark whose service state changed")

---------------------------------------------------------------- a moved device
-- A picked-up device keeps its mark on the item; placed again, it is a new device.
local P2, p2 = place(pro, "SolarPanel", 204, 100, 0, { cond = 90, xpd = true })
check(p2 and p2.xpd == true and p2.cond == 90 and p2.level == 0, "a re-placed panel keeps its condition and its xpd")
xp0 = mid.xp
check(link(mid, P2, M) == true and mid.xp == xp0, "re-linking a moved panel gives no experience again")

---------------------------------------------------------------- removing inverters
LiveWire.Devices.remove(s.id)
check(anchorOff[s.id] == true, "a picked-up slave's own zone is switched off")
check(R.device(s.id) == nil and not R.grid(m.grid).slaves[s.id], "the slave leaves the master's network")
local S2, s2 = place(pro, "Inverter", 230, 100, 0)
check(couple(mid, S2, M) == true, "a second slave couples")
LiveWire.Devices.remove(m.id)
check(anchorOff[m.id] == true and R.device(m.id) == nil, "the master is removed and its zone switched off")
check(s2.coupled == nil and s2.grid and R.grid(s2.grid) and R.grid(s2.grid).inverter == s2.id,
    "its slave is independent again, with its own grid")
-- As in Live Wire: coupling puts only the master in service (Devices.wired), so a
-- freed slave's first link needs the inverter's level again.
check(mark(S2).cpl == nil and mark(S2).svc == nil, "the freed slave's mark: not coupled, not in service")

check(#warnings == 0, "no warnings: " .. table.concat(warnings, " | "))

print(string.format("%d passed, %d failed", passes, fails))
return fails
