-- Offline test of the dev build's street lamp lighting (LWC_Streetlights.lua) with
-- stubs for the game and Live Wire. Globals set by the runner: MOD_LUA.
local fails, passes = 0, 0
local function check(c, m) if c then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. m) end end

function isServer() return false end
local ticks = {}
Events = { OnTick = { Add = function(f) ticks[#ticks+1] = f end, Remove = function() end },
           OnGameStart = { Add = function() end } }
function require() end
local opt = true
function getSandboxOptions() return { getOptionByName = function() return { getValue = function() return opt end } end } end
local night = 1
function getGameTime() return { getNight = function() return night end } end

local anchors = {}
LiveWire = { Config = { tileRange = function() return 20 end, verticalRange = function() return 3 end },
  API = { anchors = function() return anchors end },
  Coverage = { covers = function(id, a, x, y, z, R, V)
      local dx, dy = x - a.x, y - a.y
      return dx*dx + dy*dy <= R*R and math.abs(z - a.z) <= V end } }

local added, removed = {}, 0
local function lamp(x, y, sprite, o)
  o = o or {}
  local sw = { couldBePoweredByGenerator = function() return false end,
    getSprite = function() return { getName = function() return sprite end } end,
    getSquare = function() return { getRoom = function() return o.room end } end,
    getObjectIndex = function() return 0 end, isActivated = function() return o.off ~= true end,
    hasLightBulb = function() return o.bulb ~= false end, hasGridPower = function() return o.grid == true end }
  local l = { getSwitches = function() return { isEmpty = function() return false end, get = function() return sw end } end,
    getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
    getRadius = function() return 8 end, isInBounds = function() return true end }
  return l
end
local list = {}
local cell = { getLamppostPositions = function() return { size = function() return #list end, get = function(_, i) return list[i+1] end } end,
  getGridSquare = function() return nil end,
  addLamppost = function(_, x, y, z, r, g, b, rad)
    added[#added+1] = { x = x, y = y, rad = rad }
    return { isInBounds = function() return true end, getSwitches = function() return { isEmpty = function() return true end } end } end,
  removeLamppost = function() removed = removed + 1 end }
function getCell() return cell end

dofile(MOD_LUA .. "/client/LiveWireCoupling/LWC_Streetlights.lua")
local SL = LiveWire.CouplingStreetlights
local function run() SL.update() end

list = { lamp(100, 100, "lighting_outdoor_01_0"),            -- in zone A
         lamp(130, 100, "lighting_outdoor_01_0"),            -- in zone B (a coupled inverter)
         lamp(200, 100, "lighting_outdoor_01_0"),            -- outside every zone
         lamp(101, 100, "advertising_01_36"),                -- a sign
         lamp(102, 100, "lighting_outdoor_01_0", { room = true }),
         lamp(103, 100, "lighting_outdoor_01_0", { off = true }),
         lamp(104, 100, "lighting_outdoor_01_0", { bulb = false }),
         lamp(105, 100, "lighting_outdoor_01_0", { grid = true }) }
anchors = { A = { x = 100, y = 110, z = 0, on = true }, B = { x = 130, y = 110, z = 0, on = true } }
run()
check(#added == 2, "two lamps lit (one per zone), got " .. #added)
check(SL.count == 2, "count 2")
run()
check(#added == 2, "a second pass adds nothing new")
anchors.B.on = false; run()
check(removed == 1 and SL.count == 1, "zone B off puts its lamp out")
anchors.B.on = true; run()
check(SL.count == 2, "zone B back on lights it again")
night = 0; run()
check(SL.count == 0, "daytime releases every lamp")
night = 1; opt = false; run()
check(SL.count == 0, "option off lights nothing")
opt = true; anchors = {}; run()
check(SL.count == 0, "no zones, no lamps")
print(string.format("streetlights_test: %d passed, %d failed", passes, fails))
return fails
