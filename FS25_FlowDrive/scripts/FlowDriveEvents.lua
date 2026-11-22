-- FlowDrive network events (1.1.0, multiplayer)
--
-- FlowDriveSettingsEvent: per-vehicle settings (keys and menu). Sent by the player who changes them;
--   the server applies them and passes them on to the other players.
-- FlowDriveInputEvent: player -> server only. Inching key held and cylinder moving: the server does
--   not see the cylinder commands of a remote player (only the resulting positions), so the player tells it.
--
-- The serialisation of the settings lives in FlowDriveSpec (writeSettings / readSettings), shared with the
-- initial state sent to a player who joins the game (onWriteStream / onReadStream).

FlowDriveSettingsEvent = {}
local FlowDriveSettingsEvent_mt = Class(FlowDriveSettingsEvent, Event)
InitEventClass(FlowDriveSettingsEvent, "FlowDriveSettingsEvent")

function FlowDriveSettingsEvent.emptyNew()
    return Event.new(FlowDriveSettingsEvent_mt)
end

function FlowDriveSettingsEvent.new(vehicle)
    local self = FlowDriveSettingsEvent.emptyNew()
    self.vehicle = vehicle
    self.data = FlowDriveSpec.getSettingsData(vehicle.spec_flowDrive)
    return self
end

function FlowDriveSettingsEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    FlowDriveSpec.writeSettings(streamId, self.data)
end

function FlowDriveSettingsEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.data = FlowDriveSpec.readSettings(streamId)
    self:run(connection)
end

function FlowDriveSettingsEvent:run(connection)
    if not connection:getIsServer() then
        -- received by the server from a player: passed on to the other players
        g_server:broadcastEvent(self, false, connection, self.vehicle)
    end
    local vehicle = self.vehicle
    if vehicle ~= nil and vehicle.spec_flowDrive ~= nil
        and (vehicle.getIsSynchronized == nil or vehicle:getIsSynchronized()) then
        FlowDriveSpec.applySettingsData(vehicle, self.data, true)
    end
end

-- Sends the current settings of the vehicle (multiplayer only)
function FlowDriveSettingsEvent.sendEvent(vehicle)
    if g_server ~= nil then
        g_server:broadcastEvent(FlowDriveSettingsEvent.new(vehicle), false, nil, vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(FlowDriveSettingsEvent.new(vehicle))
    end
end

------------------------------------------------------------------------------------------

FlowDriveInputEvent = {}
local FlowDriveInputEvent_mt = Class(FlowDriveInputEvent, Event)
InitEventClass(FlowDriveInputEvent, "FlowDriveInputEvent")

function FlowDriveInputEvent.emptyNew()
    return Event.new(FlowDriveInputEvent_mt)
end

function FlowDriveInputEvent.new(vehicle, inchHeld, hydraulic)
    local self = FlowDriveInputEvent.emptyNew()
    self.vehicle = vehicle
    self.inchHeld = inchHeld == true
    self.hydraulic = hydraulic == true
    return self
end

function FlowDriveInputEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.inchHeld)
    streamWriteBool(streamId, self.hydraulic)
end

function FlowDriveInputEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.inchHeld = streamReadBool(streamId)
    self.hydraulic = streamReadBool(streamId)
    self:run(connection)
end

function FlowDriveInputEvent:run(connection)
    -- only the server uses it (the driving law runs there)
    local s = self.vehicle ~= nil and self.vehicle.spec_flowDrive or nil
    if not connection:getIsServer() and s ~= nil then
        s.netInchHeld = self.inchHeld
        s.netHydraulic = self.hydraulic
    end
end

-- Sent by a player who is not the server (on the host, the server reads the keys itself)
function FlowDriveInputEvent.sendEvent(vehicle, inchHeld, hydraulic)
    if g_server == nil and g_client ~= nil then
        g_client:getServerConnection():sendEvent(FlowDriveInputEvent.new(vehicle, inchHeld, hydraulic))
    end
end
