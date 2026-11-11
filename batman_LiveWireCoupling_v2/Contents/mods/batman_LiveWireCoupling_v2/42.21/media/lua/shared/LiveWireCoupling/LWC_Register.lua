-- Live Wire: Coupled Inverter Zones add-on. Registers with Live Wire's coupling
-- extension point (LiveWire.Coupling, LW_Coupling.lua). Live Wire then does the
-- rest itself: a coupled (slave) inverter keeps its own powered zone, the network
-- shares one load and one capacity, and billing, circuits, power state, load
-- shedding, "Show range" on a coupled inverter and the master's screen from a
-- coupled inverter (it stays open near any inverter of the network) cover every
-- zone. The add-on adds:
--   range     = the "Coupling range" sandbox option (LWC_CouplingRange.lua)
--   inverters = inverters within that range, also past the cable range
--   menu      = "Show all powered areas" (LWC_ZonesView.lua, client)
-- Registration must happen while Lua files load, before OnInitGlobalModData; this
-- shared file loads on both the client and the server.
require "LiveWire/LW_Coupling"
require "LiveWire/LW_API"
require "LiveWireCoupling/LWC_CouplingRange"

LiveWire = LiveWire or {}

local Reg = LiveWire.CouplingAddon or {}
LiveWire.CouplingAddon = Reg

local function say(msg) print("[LiveWireCoupling] " .. msg) end

-- The add-on reads Live Wire through LiveWire.API revision 3 or newer (networkInverters,
-- anchors, the range view services).
Reg.API_REVISION = 3

local function provider()
    local CR = LiveWire.CouplingRange
    return {
        slaveKeepsZone = true,
        range = function() return CR.get() end,
        inverters = function(sq) return CR.reachable(sq) end,
        -- Client only: Live Wire calls it while building an inverter's menu.
        menu = function(menu, player, obj, mark, isSlave)
            local ZV = LiveWire.ZonesView
            if ZV and ZV.addMenu then ZV.addMenu(menu, player, obj, mark, isSlave) end
        end,
    }
end

-- Registers once (a reloaded file does not register again). Returns true, or false
-- and a reason: "no_coupling_api" (Live Wire older than its coupling extension
-- point), "old_api" (LiveWire.API older than revision 3), or Live Wire's own reason ("already_registered": another add-on took the
-- extension point; "registration_closed"; "invalid_provider").
function Reg.register()
    if Reg.ok then return true end
    local C = LiveWire.Coupling
    if type(C) ~= "table" or type(C.register) ~= "function" then
        Reg.ok, Reg.why = false, "no_coupling_api"
        say("this LiveWire has no coupling extension point (LiveWire.Coupling). "
            .. "Add-on 2.0.0 needs a newer LiveWire; coupled inverters keep LiveWire's own behaviour.")
        return false, Reg.why
    end
    local API = LiveWire.API
    local ver = type(API) == "table" and tonumber(API.version) or 0
    local rev = type(API) == "table" and tonumber(API.revision) or 0
    if ver < 1 or (ver == 1 and rev < Reg.API_REVISION) then
        Reg.ok, Reg.why = false, "old_api"
        say("this LiveWire's API is revision " .. tostring(rev) .. "; add-on 2.0.0 needs revision "
            .. Reg.API_REVISION .. " or newer. Coupled inverters keep LiveWire's own behaviour.")
        return false, Reg.why
    end
    local ok, why = C.register(provider())
    Reg.ok, Reg.why = ok == true, why
    if Reg.ok then
        say("registered with LiveWire's coupling extension point (version "
            .. tostring(C.version) .. "): coupled inverters keep their own zone.")
    else
        say("could not register with LiveWire's coupling extension point: " .. tostring(why)
            .. ". Coupled inverters keep LiveWire's own behaviour.")
    end
    return Reg.ok, why
end

Reg.register()
