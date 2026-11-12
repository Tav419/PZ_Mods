-- Live Wire: Coupled Inverter Zones add-on. Coupling range: how far a coupled
-- (slave) inverter can be from its master, set by the sandbox option
-- LiveWireCoupling.CouplingRange (0 = Live Wire's cable range, LinkRange).
-- Live Wire reads it through its coupling extension point (LW_Coupling.lua):
-- LWC_Register.lua hands it CR.get as `range` and CR.inverters as `inverters`, so
-- Install.checkCouple and the "Couple to an inverter" menu use it. The cable range
-- for equipment is unchanged.
-- Inverters past the cable range are found through Live Wire's anchors
-- (LiveWire.API.anchors: every inverter has one from the moment it is placed), not
-- by scanning every square. Only loaded squares count: the master must be within
-- the area loaded around the player.
-- Everything goes through LiveWire.API except the two cable settings (LinkRange,
-- LinkVerticalRange), read with LiveWire.Config.get: the API has no getter for them.
require "LiveWire/LW_Config"
require "LiveWire/LW_API"

LiveWire = LiveWire or {}

local CR = LiveWire.CouplingRange or {}
LiveWire.CouplingRange = CR

local Config, API = LiveWire.Config, LiveWire.API

local function option()
    local opts = getSandboxOptions and getSandboxOptions()
    local opt = opts and opts:getOptionByName("LiveWireCoupling.CouplingRange")
    if opt then return opt:getValue() end
    if SandboxVars and SandboxVars.LiveWireCoupling then
        return SandboxVars.LiveWireCoupling.CouplingRange
    end
    return nil
end

-- Coupling range in tiles.
function CR.get()
    local v = option()
    if not v or v <= 0 then return Config.get("LinkRange") end
    return v
end

-- Inverters on loaded squares within `range` tiles of `sq` and within Live Wire's
-- vertical cable range, nearest first ({ obj, dist, kind }). `range` nil: any distance, any floor. Live Wire's usual
-- search (within cable range) plus the anchors of the farther ones.
function CR.inverters(sq, range)
    local out, seen = {}, {}
    if not sq then return out end
    local function add(o, id, dist, kind)
        if id == nil or seen[id] then return end
        seen[id] = true
        out[#out + 1] = { obj = o, dist = dist, kind = kind or "device" }
    end
    local near = API.invertersInRange(sq)
    for i = 1, #near do
        local e = near[i]
        local m = API.mark(e.obj)
        if not range or e.dist <= range then add(e.obj, m and m.id, e.dist, e.kind) end
    end
    local x0, y0, z0 = sq:getX(), sq:getY(), sq:getZ()
    local floors = Config.get("LinkVerticalRange")
    local cell = getCell()
    for id, a in pairs(API.anchors()) do
        if not seen[id] and a.x and a.y and a.z then
            local dist, dz = API.distance(x0, y0, z0, a.x, a.y, a.z)
            if not range or (dist <= range and dz <= floors) then
                local s = cell and cell:getGridSquare(a.x, a.y, a.z)
                local o = s and API.markOnSquare(s, id)
                if o then add(o, id, dist) end
            end
        end
    end
    table.sort(out, function(p, q) return p.dist < q.dist end)
    return out
end

-- Inverters a coupling can reach from `sq`: within the coupling range. Handed to
-- Live Wire as the extension point's `inverters` (LWC_Register.lua).
function CR.reachable(sq)
    return CR.inverters(sq, CR.get())
end

-- Inverter with device id `id` on a loaded square, at any distance (through its
-- anchor), else among the inverters within cable range of `sq`; nil when not found.
function CR.inverterById(sq, id)
    if not id then return nil end
    local a = API.anchors()[id]
    local cell = getCell()
    local s = a and a.x and cell and cell:getGridSquare(a.x, a.y, a.z)
    local o = s and API.markOnSquare(s, id)
    if o then return o end
    local near = sq and API.invertersInRange(sq) or {}
    for i = 1, #near do
        local m = API.mark(near[i].obj)
        if m and m.id == id then return near[i].obj end
    end
    return nil
end
