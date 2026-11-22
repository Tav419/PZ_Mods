-- LiveWire: Coupled Inverter Zones add-on (DEV). Street lamps inside a powered zone
-- light up at night (client only, a local display like LWC_ZonesView.lua).
--
-- Why: vanilla Build 42 lets only the power grid light "streetlight" tiles (IsoLightSwitch
-- objects whose sprite has the `streetlight` property; couldBePoweredByGenerator() is
-- false for them). An inverter's powered zone is a generator anchor, so it never lights
-- them, and once the grid is off (the usual state later in a game) every street lamp
-- stays dark. This file gives such a lamp its own engine light while an inverter zone
-- covers it, the same way a mod light is added with IsoCell:addLamppost.
--
-- What counts as powered: LiveWire.API.anchors() (every zone known on this side, a
-- coupled inverter's included while this add-on keeps its zone) whose `on` flag is set,
-- and LiveWire.Coverage.covers (the disc of the tile range and floors, or whatever
-- LiveWire Extended covers). So a zone that is off, out of battery or removed lights
-- nothing, and each coupled inverter's own zone lights its own lamps.
--
-- Only street lamps (poles): not signs, billboards, traffic lights, lamps inside a room,
-- lamps switched off or without a bulb, or lamps the grid already lights.
-- Sandbox option LiveWireCoupling.PowerStreetlights (default on) turns it off.
if isServer() then return end

require "LiveWire/LW_Config"
require "LiveWire/LW_API"
require "LiveWire/LW_Coverage"

LiveWire = LiveWire or {}

local SL = LiveWire.CouplingStreetlights or {}
LiveWire.CouplingStreetlights = SL

SL.CHECK_TICKS = 60        -- how often lamps and zones are looked at (about a second)
SL.NIGHT = 0.01            -- GameTime:getNight() above this counts as night (shortly after dusk)
SL.COLOR = { r = 1.0, g = 0.78, b = 0.4 }   -- warm lamp light (tuned in the first solo test)
SL.MIN_RADIUS = 12         -- tiles; a vanilla lamp's own radius is used when larger
SL.MAX_RADIUS = 20         -- the engine clamps every lamppost radius to 20
SL.MAX_LIGHTS = 400        -- safety cap on the lights this add-on keeps

local POLE_PREFIXES = { "lighting_outdoor_", "appliances_com_" }
local TRAFFIC_HEAD_EXACT = {
    street_decoration_01_48 = true, street_decoration_01_49 = true,
    street_decoration_01_50 = true, street_decoration_01_51 = true,
}

SL.lit = {}      -- key "x_y_z" -> { light = IsoLightSource (ours), src = vanilla lamp }
SL.count = 0
SL.ticks = 0

local function say(msg) print("[LiveWireCoupling] " .. msg) end

function SL.enabled()
    local opts = getSandboxOptions and getSandboxOptions()
    local opt = opts and opts:getOptionByName("LiveWireCoupling.PowerStreetlights")
    if opt then return opt:getValue() ~= false end
    if SandboxVars and SandboxVars.LiveWireCoupling and SandboxVars.LiveWireCoupling.PowerStreetlights ~= nil then
        return SandboxVars.LiveWireCoupling.PowerStreetlights ~= false
    end
    return true
end

function SL.isNight()
    local gt = getGameTime and getGameTime()
    if not gt then return false end
    if gt.getNight then
        local v = gt:getNight()
        if v ~= nil then return v > SL.NIGHT end
    end
    local hour = gt:getHour()
    local dusk = gt.getDusk and gt:getDusk() or 20
    local dawn = gt.getDawn and gt:getDawn() or 6
    return hour >= dusk or hour < dawn
end

local function hasPrefix(name, list)
    for i = 1, #list do
        if string.sub(name, 1, #list[i]) == list[i] then return true end
    end
    return false
end

-- lighting_outdoor_01_12..23 are traffic light overlays when a signal head is next to them.
local function isTrafficOverlay(name)
    local n = tonumber(string.match(name, "^lighting_outdoor_01_(%d+)$") or "")
    return n ~= nil and n >= 12 and n <= 23
end

local function trafficHeadNear(cell, x, y, z)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(x + dx, y + dy, z)
            local objs = sq and sq:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    local spr = objs:get(i) and objs:get(i):getSprite()
                    local name = spr and spr:getName()
                    if name and TRAFFIC_HEAD_EXACT[string.lower(name)] then return true end
                end
            end
        end
    end
    return false
end

-- Looks at one entry of the cell's lamppost list. Returns a table for a street lamp this
-- add-on may light (kept in `cache` so a lamp is classified once per pass), or false.
function SL.classify(cell, light)
    local switches = light:getSwitches()
    if switches == nil or switches:isEmpty() then return false end   -- fires, mod lights, our own
    local sw = switches:get(0)
    if sw == nil then return false end
    if sw.couldBePoweredByGenerator and sw:couldBePoweredByGenerator() then return false end
    local spr = sw:getSprite()
    local name = spr and spr:getName()
    if not name then return false end
    name = string.lower(name)
    if not hasPrefix(name, POLE_PREFIXES) then return false end      -- signs, billboards: not here
    local x, y, z = light:getX(), light:getY(), light:getZ()
    local sq = sw:getSquare() or cell:getGridSquare(x, y, z)
    if sq and sq:getRoom() then return false end                     -- indoor lamps stay as they are
    if isTrafficOverlay(name) and trafficHeadNear(cell, x, y, z) then return false end
    return { x = x, y = y, z = z, src = light, sw = sw, r = light:getRadius() }
end

-- Zones that are on: { { id, a = {x, y, z} }, ... }.
function SL.zones()
    local out = {}
    for id, a in pairs(LiveWire.API.anchors()) do
        if a.on then out[#out + 1] = { id = id, a = a } end
    end
    return out
end

function SL.covered(zones, x, y, z)
    local R, V = LiveWire.Config.tileRange(), LiveWire.Config.verticalRange()
    for i = 1, #zones do
        if LiveWire.Coverage.covers(zones[i].id, zones[i].a, x, y, z, R, V) then return true end
    end
    return false
end

-- Should this street lamp be lit right now?
function SL.wants(rec, zones)
    local sw = rec.sw
    if sw:getObjectIndex() == -1 then return false end   -- gone from the world
    if not sw:isActivated() then return false end        -- switched off by a player
    if not sw:hasLightBulb() then return false end       -- no bulb
    if sw:hasGridPower() then return false end           -- the grid lights it already
    if not rec.src:isInBounds() then return false end    -- the engine would drop our light
    return SL.covered(zones, rec.x, rec.y, rec.z)
end

local function key(x, y, z) return x .. "_" .. y .. "_" .. z end

function SL.release(cell, k)
    local e = SL.lit[k]
    if not e then return end
    SL.lit[k] = nil
    SL.count = SL.count - 1
    if e.light and e.light:isInBounds() then cell:removeLamppost(e.light) end
end

function SL.releaseAll()
    local cell = getCell()
    if not cell then return end
    for k in pairs(SL.lit) do SL.release(cell, k) end
end

function SL.add(cell, rec)
    if SL.count >= SL.MAX_LIGHTS then return end
    local c = SL.COLOR
    local radius = math.min(SL.MAX_RADIUS, math.max(SL.MIN_RADIUS, rec.r or 0))
    local light = cell:addLamppost(rec.x, rec.y, rec.z, c.r, c.g, c.b, radius)
    if light then
        SL.lit[key(rec.x, rec.y, rec.z)] = { light = light, src = rec.src }
        SL.count = SL.count + 1
    end
end

-- One pass: light what is covered, release what no longer is.
function SL.update()
    local cell = getCell()
    if not cell then return end
    if not (SL.enabled() and SL.isNight()) then SL.releaseAll() return end
    local zones = SL.zones()
    if #zones == 0 then SL.releaseAll() return end
    local stack = cell:getLamppostPositions()
    if not stack then return end
    local want, cache = {}, {}
    for i = 0, stack:size() - 1 do
        local light = stack:get(i)
        if light then
            local rec = SL.known and SL.known[light]
            if rec == nil then rec = SL.classify(cell, light) end
            cache[light] = rec
            if rec and SL.wants(rec, zones) then want[key(rec.x, rec.y, rec.z)] = rec end
        end
    end
    SL.known = cache   -- lamps that left the list drop out of the cache here
    for k in pairs(SL.lit) do
        local e = SL.lit[k]
        if not want[k] or e.src ~= want[k].src then SL.release(cell, k) end
    end
    for k, rec in pairs(want) do
        if not SL.lit[k] then SL.add(cell, rec) end
    end
end

function SL.onTick()
    SL.ticks = SL.ticks + 1
    if SL.ticks < SL.CHECK_TICKS then return end
    SL.ticks = 0
    local ok, err = pcall(SL.update)
    if not ok then
        if not SL.failed then say("street lamp update failed: " .. tostring(err)) end
        SL.failed = true
    end
end

-- Our lights belong to the cell, which is rebuilt when a game is loaded: start clean.
function SL.reset()
    SL.lit, SL.count, SL.known, SL.ticks, SL.failed = {}, 0, nil, 0, nil
end

if SL.tickHandler then Events.OnTick.Remove(SL.tickHandler) end
SL.tickHandler = function() return SL.onTick() end
Events.OnTick.Add(SL.tickHandler)
if Events.OnGameStart and not SL.startHandler then
    SL.startHandler = function() return SL.reset() end
    Events.OnGameStart.Add(SL.startHandler)
end
