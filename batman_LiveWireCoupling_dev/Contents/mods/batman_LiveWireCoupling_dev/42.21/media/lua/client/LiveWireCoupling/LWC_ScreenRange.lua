-- Live Wire: Coupled Inverter Zones add-on. The inverter screen of a coupled network.
-- Clicking a coupled (slave) inverter opens its master's screen (LW_Equipment.lua),
-- and that screen closes when the player is farther than 30 tiles from the master
-- (LW_InverterPanel.lua, Panel:update and CLOSE_RANGE). With the Coupling range
-- (LWC_CouplingRange.lua) a slave can be up to 70 tiles from its master, so its
-- screen closed as soon as it opened. The wrappers below keep the screen open while
-- the player is within that distance of any inverter of the network (the master or
-- one of its slaves), so LW_InverterPanel.lua is not replaced. The server sends the
-- screen's data and accepts its buttons on the same terms (LW_Commands.lua).
if isServer() then return end

require "LiveWire/LW_InverterPanel"
require "LiveWire/LW_Anchor"
require "LiveWire/LW_Marks"

LiveWire = LiveWire or {}

local SR = LiveWire.ScreenRange or {}
LiveWire.ScreenRange = SR

SR.RANGE = 30          -- LW_InverterPanel.lua CLOSE_RANGE
SR.REFRESH_MS = 2000   -- how often the network's inverters are looked up again

local Panel = LiveWire.InverterPanel

-- Live Wire's own functions, kept once (a reloaded file must not wrap the wrapper).
SR.baseUpdate = SR.baseUpdate or Panel.update
SR.baseClose = SR.baseClose or Panel.close

-- Ids of the inverters of network `netId` (its master's id): the master, `extraId`,
-- and every inverter on a loaded square whose mark says it is coupled to the master.
-- Found through the public anchor table (every inverter has an anchor), no square scan.
function SR.members(netId, extraId)
    local ids, seen = {}, {}
    local function add(id)
        if id ~= nil and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    add(netId)
    add(extraId)
    local cell = getCell()
    for id, a in pairs(LiveWire.Anchor.table()) do
        if not seen[id] and a.x and a.y and a.z then
            local sq = cell and cell:getGridSquare(a.x, a.y, a.z)
            local o = sq and LiveWire.Marks.findOnSquare(sq, id)
            local m = o and LiveWire.Marks.get(o)
            if m and m.cpl == netId then add(id) end
        end
    end
    return ids
end

-- True when the panel's player is within SR.RANGE tiles of an inverter of the
-- panel's network: through the inverters' anchors, and the square of the inverter
-- the screen was opened from (in case its anchor is missing).
function SR.nearNetwork(panel)
    local player = panel.player
    if not player then return false end
    local now = getTimestampMs()
    if not panel.lwcMembers or now - (panel.lwcMembersAt or 0) >= SR.REFRESH_MS then
        local m = panel.obj and LiveWire.Marks.get(panel.obj)
        panel.lwcMembers = SR.members(panel.inverterId, m and m.id)
        panel.lwcMembersAt = now
    end
    local px, py = player:getX(), player:getY()
    local r2 = SR.RANGE * SR.RANGE
    local function near(x, y)
        local dx, dy = px - x, py - y
        return dx * dx + dy * dy <= r2
    end
    local anchors = LiveWire.Anchor.table()
    for i = 1, #panel.lwcMembers do
        local a = anchors[panel.lwcMembers[i]]
        if a and a.x and a.y and near(a.x, a.y) then return true end
    end
    local o = panel.obj
    if o and o:getObjectIndex() ~= -1 then
        local sq = o:getSquare()
        if sq and near(sq:getX(), sq:getY()) then return true end
    end
    return false
end

-- Live Wire's update. Its distance check calls close, which is skipped while the
-- player is near another inverter of the network. The other closes (the x button,
-- opening another screen, leaving the game) happen outside update and still work.
function Panel:update()
    self.lwcInUpdate = true
    local ok, err = pcall(SR.baseUpdate, self)
    self.lwcInUpdate = nil
    if not ok then error(err, 0) end
end

function Panel:close(sessionEnded)
    if self.lwcInUpdate and not sessionEnded and SR.nearNetwork(self) then return end
    return SR.baseClose(self, sessionEnded)
end
