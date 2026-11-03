-- Live Wire: Coupled Inverter Zones add-on. Coupling range: how far a coupled
-- (slave) inverter can be from its master, set by the sandbox option
-- LiveWireCoupling.CouplingRange (0 = Live Wire's cable range, LinkRange).
-- Live Wire checks the coupling distance in Install.checkCouple (LW_Install.lua),
-- on the client for the menu and on the authority when the coupling action
-- completes. The wrapper below makes that check use the coupling range, so
-- LW_Install.lua is not replaced. Cable range for equipment is unchanged.
-- Inverters past the cable range are found through the public anchor table (every
-- inverter has an anchor from the moment it is placed), not by scanning every
-- square. Only loaded squares count: the master must be within the area loaded
-- around the player.
require "LiveWire/LW_Config"
require "LiveWire/LW_Install"
require "LiveWire/LW_Anchor"
require "LiveWire/LW_Marks"

LiveWire = LiveWire or {}

local CR = LiveWire.CouplingRange or {}
LiveWire.CouplingRange = CR

local Config, Install = LiveWire.Config, LiveWire.Install

-- Live Wire's own check, kept once (a reloaded file must not wrap the wrapper).
CR.baseCheckCouple = CR.baseCheckCouple or Install.checkCouple

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

-- Live Wire's check, with its cable range read as the coupling range while it runs.
function Install.checkCouple(...)
    local get = Config.get
    local range = CR.get()
    Config.get = function(name)
        if name == "LinkRange" then return range end
        return get(name)
    end
    local ok, a, b, c, d = pcall(CR.baseCheckCouple, ...)
    Config.get = get
    if not ok then error(a, 0) end
    return a, b, c, d
end

-- Inverters on loaded squares within `range` tiles of `sq` and within Live Wire's
-- vertical cable range, nearest first, as Install.invertersInRange returns them
-- ({ obj, dist, kind }). `range` nil: any distance, any floor. Live Wire's usual
-- search (within cable range) plus the anchors of the farther ones.
function CR.inverters(sq, range)
    local out, seen = {}, {}
    if not sq then return out end
    local function add(o, id, dist, kind)
        if id == nil or seen[id] then return end
        seen[id] = true
        out[#out + 1] = { obj = o, dist = dist, kind = kind or "device" }
    end
    local near = Install.invertersInRange(sq)
    for i = 1, #near do
        local e = near[i]
        local m = LiveWire.Marks.get(e.obj)
        if not range or e.dist <= range then add(e.obj, m and m.id, e.dist, e.kind) end
    end
    local x0, y0, z0 = sq:getX(), sq:getY(), sq:getZ()
    local floors = Config.get("LinkVerticalRange")
    local cell = getCell()
    for id, a in pairs(LiveWire.Anchor.table()) do
        if not seen[id] and a.x and a.y and a.z then
            local dist, dz = Install.distance(x0, y0, z0, a.x, a.y, a.z)
            if not range or (dist <= range and dz <= floors) then
                local s = cell and cell:getGridSquare(a.x, a.y, a.z)
                local o = s and LiveWire.Marks.findOnSquare(s, id)
                if o then add(o, id, dist) end
            end
        end
    end
    table.sort(out, function(p, q) return p.dist < q.dist end)
    return out
end

-- Inverter with device id `id` on a loaded square, at any distance (through its
-- anchor), else Live Wire's search within cable range of `sq`; nil when not found.
function CR.inverterById(sq, id)
    if not id then return nil end
    local a = LiveWire.Anchor.table()[id]
    local cell = getCell()
    local s = a and a.x and cell and cell:getGridSquare(a.x, a.y, a.z)
    return (s and LiveWire.Marks.findOnSquare(s, id)) or Install.inverterById(sq, id)
end
