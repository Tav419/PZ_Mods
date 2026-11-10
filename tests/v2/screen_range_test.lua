-- Offline test of the inverter screen of a coupled network (2.0 build):
-- LWC_ScreenRange.lua (the screen stays open near any inverter of the network) and
-- the server side, which since 2.0 is Live Wire's own LW_Commands.lua (C_SUBSCRIBE,
-- inverter commands) and LW_Simulation.lua (Sim.publish) with the add-on registered
-- with its coupling extension point. Stubs for the game's globals, run by
-- run_tests.py with Lua 5.1. Globals set by the runner: MOD_LUA (the add-on's
-- media/lua folder), LIVEWIRE_LUA (Live Wire's media/lua folder).

local fails, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
if not LIVEWIRE_LUA then
    print("FAIL: screen_range_test.lua needs --livewire <Live Wire media/lua folder> (see the README)")
    return 1
end

---------------------------------------------------------------- game stubs
local serverMode = false
function isServer() return serverMode end
function isClient() return false end
function require() end

local events = {}
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function(fn)
        events[name] = events[name] or {}
        table.insert(events[name], fn)
    end }
    rawset(t, name, e)
    return e
end })

local now = 0
function getTimestampMs() return now end

local function square(x, y, z)
    local sq = { x = x, y = y, z = z, objs = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    return sq
end
local squares, anchors = {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
function getCell()
    return { getGridSquare = function(_, x, y, z)
        local k = key(x, y, z)
        squares[k] = squares[k] or square(x, y, z)
        return squares[k]
    end }
end

LiveWire = { MODULE = "LiveWire" }
LiveWire.Marks = { get = function(o) return o and o.mark end }
function LiveWire.Marks.findOnSquare(sq, id)
    for _, o in ipairs(sq.objs) do if o.mark and o.mark.id == id then return o end end
end
LiveWire.Anchor = { table = function() return anchors end }

-- Registry devices and grids (server side), plus their placed objects (client side).
local devices, grids, objects = {}, {}, {}
local function inverter(id, x, y, z, master, noAnchor)
    local sq = getCell():getGridSquare(x, y, z)
    local o = { mark = { id = id, model = "Inverter", cpl = master }, sq = sq }
    function o:getSquare() return self.sq end
    function o:getObjectIndex() return self.removed and -1 or 0 end
    sq.objs[#sq.objs + 1] = o
    objects[id] = o
    if not noAnchor then anchors[id] = { x = x, y = y, z = z, on = true } end
    local gid = master and devices[master].grid or ("g" .. id)
    devices[id] = { id = id, role = "inverter", model = "Inverter", x = x, y = y, z = z,
                    grid = gid, coupled = master, state = "on" }
    if master then
        grids[gid].slaves[id] = true
    else
        grids[gid] = { id = gid, inverter = id, slaves = {}, members = {} }
    end
    return o
end

-- Network A: master mA, slaves 60 tiles east (sA1) and 60 tiles north (sA2).
-- Network B: master mB far east, its slave sB1 at x = 120.
inverter("mA", 0, 0, 0)
inverter("sA1", 60, 0, 0, "mA")
inverter("sA2", 0, 60, 0, "mA")
inverter("mB", 200, 0, 0)
inverter("sB1", 120, 0, 0, "mB")

local function newPlayer(name, x, y, z)
    local p = { name = name, x = x, y = y, z = z or 0, notices = {} }
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isDead() return false end
    function p:getUsername() return self.name end
    return p
end

---------------------------------------------------------------- client: the screen
-- Stand-in for LW_InverterPanel.lua: the same close check as Panel:update.
local CLOSE_RANGE = 30
local Panel = {}
Panel.__index = Panel
LiveWire.InverterPanel = Panel
local function openPanel(player, inverterId, obj)
    return setmetatable({ player = player, inverterId = inverterId, obj = obj,
                          shown = true, closes = 0 }, Panel)
end
function Panel:update()
    if self.failNext then
        self.failNext = nil
        error("boom")
    end
    local a = LiveWire.Anchor.table()[self.inverterId]
    if a then
        local dx, dy = self.player:getX() - a.x, self.player:getY() - a.y
        if dx * dx + dy * dy > CLOSE_RANGE * CLOSE_RANGE then self:close() end
    end
end
function Panel:close(sessionEnded)
    self.shown = false
    self.closes = self.closes + 1
end

dofile(MOD_LUA .. "/client/LiveWireCoupling/LWC_ScreenRange.lua")
local SR = LiveWire.ScreenRange
check(SR ~= nil and Panel.update ~= SR.baseUpdate and Panel.close ~= SR.baseClose,
    "the screen's update and close are wrapped")

do
    local p = newPlayer("c1", 60, 2)
    local panel = openPanel(p, "mA", objects.sA1)   -- clicked the far slave sA1
    panel:update()
    check(panel.shown, "screen opened from a slave 60 tiles from its master stays open")

    p.x, p.y = 1, 58                                -- walk to the other slave sA2
    panel:update()
    check(panel.shown, "stays open near another slave of the network")

    p.x, p.y = 2, 2
    panel:update()
    check(panel.shown and panel.closes == 0, "stays open near the master (Live Wire's own case)")

    p.x, p.y = 45, 45                               -- more than 30 from every inverter of A
    panel:update()
    check(not panel.shown, "closes when far from every inverter of the network")
end

do
    local p = newPlayer("c2", 120, 5)               -- next to sB1, a slave of network B
    local panel = openPanel(p, "mA", objects.sA1)
    panel:update()
    check(not panel.shown, "a slave of another network does not keep the screen open")
end

do
    local p = newPlayer("c3", 60, 2)
    local panel = openPanel(p, "mA", objects.sA1)
    panel:close()
    check(not panel.shown, "the x button still closes the screen near a slave")
    panel = openPanel(p, "mA", objects.sA1)
    panel:close(true)
    check(not panel.shown, "leaving the game still closes the screen")
end

do
    local p = newPlayer("c4", 60, 2)
    local panel = openPanel(p, "mA", objects.sA1)
    panel.failNext = true
    local ok, err = pcall(panel.update, panel)
    check(not ok and tostring(err):find("boom") ~= nil, "an error in Live Wire's update is passed on")
    check(panel.lwcInUpdate == nil, "the in-update flag is cleared after an error")
    panel:close()
    check(not panel.shown, "the x button works after an error in update")
end

do
    -- A slave with no anchor: the square of the inverter the screen was opened from.
    local o = inverter("sA3", 0, -60, 0, "mA", true)
    local p = newPlayer("c5", 0, -58)
    local panel = openPanel(p, "mA", o)
    panel:update()
    check(panel.shown, "stays open near the clicked slave when it has no anchor")
    o.removed = true
    panel:update()
    check(not panel.shown, "closes when the clicked slave (no anchor) is gone")
end

do
    -- A slave coupled while the screen is open counts after the next lookup.
    now = 0
    local p = newPlayer("c6", 60, 2)
    local panel = openPanel(p, "mA", objects.sA1)
    p.x, p.y = 45, 45
    panel:update()                                  -- looks the network up, then closes
    check(not panel.shown, "closes far from the network (first lookup)")
    inverter("sA4", -60, 0, 0, "mA")
    panel = openPanel(p, "mA", objects.sA1)
    panel.lwcMembers, panel.lwcMembersAt = { "mA", "sA1", "sA2" }, 0   -- cached before sA4
    p.x, p.y = -58, 0
    now = 500
    panel:update()
    check(not panel.shown, "before the refresh, the new slave is not known yet")
    panel = openPanel(p, "mA", objects.sA1)
    panel.lwcMembers, panel.lwcMembersAt = { "mA", "sA1", "sA2" }, 0
    now = SR.REFRESH_MS + 1
    panel:update()
    check(panel.shown, "after the refresh, the new slave keeps the screen open")
end

---------------------------------------------------------------- server: commands
local P = setmetatable({}, { __index = function(_, k) return k end })
function P.isDeviceId(v) return type(v) == "string" end
function P.isBool(v) return v == true or v == false end
LiveWire.Protocol = P

local subscribed, refreshed = {}, {}
LiveWire.Registry = { ready = true, readOnly = false }
function LiveWire.Registry.device(id) return devices[id] end
function LiveWire.Registry.grid(id) return grids[id] end
function LiveWire.Registry.slaves(grid)
    local ids, out = {}, {}
    for id in pairs(grid.slaves or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do out[#out + 1] = devices[ids[i]] end
    return out
end
function LiveWire.Registry.hasOption() return nil end
LiveWire.Sim = { SUBSCRIBE_RANGE = 30 }
function LiveWire.Sim.subscribe(player, gridId) subscribed[player:getUsername() .. ":" .. gridId] = true end
function LiveWire.Sim.snapshot() return { ok = true } end
function LiveWire.Sim.refresh(grid) refreshed[#refreshed + 1] = grid and grid.id end
function LiveWire.Sim.capacityW() return 3000 end
LiveWire.Inverters = { capacityW = function() return 3000 end }   -- the beta moved it out of Sim
LiveWire.Config = { verticalRange = function() return 3 end, get = function() return nil end }
LiveWire.Demand = { measureGrid = function() return 100 end, measure = function() return 100 end }
LiveWire.Xp = { awardLimited = function() end }
LiveWire.Defs = { devices = { Inverter = { role = "inverter", maxW = 1500 } } }
LiveWire.Computer = nil
function LiveWire.notify(player, keyName) player.notices[#player.notices + 1] = keyName end
function LiveWire.warn(msg) print("WARN " .. tostring(msg)) end
function sendServerCommand() end

-- Live Wire's shared safehouse guard (LW_Core.lua).
function LiveWire.canTouch(player, sq)
    return not SafeHouse or SafeHouse.isSafehouseAllowInteract(sq, player)
end
dofile(LIVEWIRE_LUA .. "/shared/LiveWire/LW_Extension.lua")
dofile(LIVEWIRE_LUA .. "/shared/LiveWire/LW_Coupling.lua")
LiveWire.Install = LiveWire.Install or {}
dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_CouplingRange.lua")
dofile(MOD_LUA .. "/shared/LiveWireCoupling/LWC_Register.lua")
check(LiveWire.CouplingAddon.ok == true, "the add-on registered: " .. tostring(LiveWire.CouplingAddon.why))
dofile(LIVEWIRE_LUA .. "/server/LiveWire/LW_Commands.lua")
local onClientCommand = events.OnClientCommand and events.OnClientCommand[1]
check(onClientCommand ~= nil, "LW_Commands registers its command handler")

local function send(player, command, args)
    now = now + 2000   -- stay under the command rate limit
    onClientCommand("LiveWire", command, player, args)
end

do
    local p = newPlayer("s1", 60, 2)
    send(p, "C_SUBSCRIBE", { inverter = "mA" })
    check(subscribed["s1:gmA"], "the screen's data is sent to a player at a far slave")
    local q = newPlayer("s2", 2, 2)
    send(q, "C_SUBSCRIBE", { inverter = "mA" })
    check(subscribed["s2:gmA"], "the screen's data is sent to a player at the master")
    local r = newPlayer("s3", 45, 45)
    send(r, "C_SUBSCRIBE", { inverter = "mA" })
    check(not subscribed["s3:gmA"], "no data far from every inverter of the network")
    local s = newPlayer("s4", 120, 5)
    send(s, "C_SUBSCRIBE", { inverter = "mA" })
    check(not subscribed["s4:gmA"], "no data next to another network's slave")
    local t = newPlayer("s5", 60, 2, 5)
    send(t, "C_SUBSCRIBE", { inverter = "mA" })
    check(not subscribed["s5:gmA"], "no data from beyond the vertical range of the slave")
end

do
    local mA = devices.mA
    local p = newPlayer("s6", 61, 1)                -- within 3 tiles of sA1
    send(p, "C_SET_INVERTER", { inverter = "mA", on = false })
    check(mA.state == "off", "the screen's I/O button works at a far slave")
    check(refreshed[#refreshed] == "gmA", "switching from a slave refreshes the network")
    mA.state = "on"

    local q = newPlayer("s7", 65, 0)                -- 5 tiles from sA1, 65 from mA
    send(q, "C_SET_INVERTER", { inverter = "mA", on = false })
    check(mA.state == "on" and q.notices[1] == "Tooltip_LW_TooFar",
        "refused 5 tiles from the slave (same 3-tile reach as at the master)")

    local r = newPlayer("s8", 2, 2)
    send(r, "C_SET_INVERTER", { inverter = "sA1", on = false })
    check(devices.sA1.state == "on", "a slave's own switch still needs the slave itself")

    mA.state = "tripped"
    local s = newPlayer("s9", 61, 1)
    send(s, "C_RESET", { inverter = "mA" })
    check(mA.state == "on", "the screen's Reset button works at a far slave")
end

do
    -- Safehouses: the slave's square and the master's square must both be usable.
    SafeHouse = { isSafehouseAllowInteract = function(sq) return not sq.private end }
    local mA = devices.mA
    local slaveSq = getCell():getGridSquare(60, 0, 0)
    slaveSq.private = true
    local p = newPlayer("s10", 61, 1)
    send(p, "C_SET_INVERTER", { inverter = "mA", on = false })
    check(mA.state == "on", "refused when the slave is in a safehouse the player can't use")
    slaveSq.private = nil

    local masterSq = getCell():getGridSquare(0, 0, 0)
    masterSq.private = true
    local q = newPlayer("s11", 61, 1)
    send(q, "C_SET_INVERTER", { inverter = "mA", on = false })
    check(mA.state == "on" and q.notices[1] == "Tooltip_LW_Safehouse",
        "refused when the master is in a safehouse the player can't use")
    masterSq.private = nil
    SafeHouse = nil
end

---------------------------------------------------------------- server: Sim.publish
dofile(LIVEWIRE_LUA .. "/server/LiveWire/LW_Simulation.lua")
local Sim = LiveWire.Sim
check(Sim and Sim.publish and Sim.SUBSCRIBE_RANGE == 30, "LW_Simulation loads")
local sent = {}
function sendServerCommand(player) sent[player:getUsername()] = (sent[player:getUsername()] or 0) + 1 end
Sim.snapshot = function() return { ok = true } end
serverMode = true
do
    local atSlave, atMaster, far = newPlayer("p1", 60, 2), newPlayer("p2", 2, 2), newPlayer("p3", 45, 45)
    now = 1000
    Sim.subscribers.gmA = {
        p1 = { player = atSlave, expires = now + 100000 },
        p2 = { player = atMaster, expires = now + 100000 },
        p3 = { player = far, expires = now + 100000 },
    }
    Sim.publish(grids.gmA)
    local list = Sim.subscribers.gmA
    check(sent.p1 == 1 and list.p1 ~= nil, "updates keep going to a player at a far slave")
    check(sent.p2 == 1 and list.p2 ~= nil, "updates keep going to a player at the master")
    check(sent.p3 == nil and list.p3 == nil, "a player far from the network is dropped")
end
serverMode = false

print(passes .. " passed, " .. fails .. " failed")
return fails
