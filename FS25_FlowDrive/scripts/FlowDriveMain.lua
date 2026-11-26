-- FlowDrive - realistic CVT / hydrostatic transmission behaviour for FS25
-- This file: constants, specialization registration, motor hooks.
--
-- Principle: FlowDrive never rewrites engine speed, gear ratio or load after the fact.
-- It answers the questions the game asks the motor every frame:
--   getMinMaxGearRatio                -> allowed ratios (field range)
--   getAccelerationLimit              -> maximum acceleration (ramp)
--   getMotorRotationAccelerationLimit -> how fast engine speed rises (ramp)
--   getRequiredMotorRpmRange          -> maximum allowed engine speed (eco, load limit)
-- Each hook first calls the original function (and those of other mods, ADS included),
-- then adjusts the result. When FlowDrive is not active on the vehicle, it changes nothing.

FlowDrive = FlowDrive or {}
FlowDrive.MOD_NAME = g_currentModName
FlowDrive.MOD_DIR = g_currentModDirectory
FlowDrive.VERSION = "1.1.0.0"
FlowDrive.SPEC_NAME = "flowDrive"

-- Ramps: maximum acceleration (m/s2), share of engine speed rise,
-- minimum engine speed while accelerating (share of the idle-rated range, 0.1.2),
-- minimum engine speed off-pedal = engine braking by shortening the ratio (0.1.3),
-- and off-pedal braking (0.1.4): multiplier of lowBrakeForceScale. Off-pedal, the game brakes with
-- brakePedal = lowBrakeForceScale above 3.6 km/h (WheelsUtil.updateWheelsPhysics).
-- Measured in 0.1.4 on an empty Q305: deceleration ~ 0.15 + 4.8 x lowBrakeForceScale (m/s2).
-- Measured in 0.1.5, empty: 0.05 -> 0.40 m/s2; 0.26 -> 1.77 m/s2 (not quite linear).
-- 0.1.6: factors fitted on these two points for 0.4 / 0.7 / 1.0 / 1.4 m/s2 empty (original value 0.10).
FlowDrive.RAMPS = {
    {accel = 0.4, rot = 0.50, accelRpmShare = 0.35, overrunRpmShare = 0.00, brakeFactor = 0.50},
    {accel = 0.8, rot = 0.70, accelRpmShare = 0.50, overrunRpmShare = 0.20, brakeFactor = 1.00},
    {accel = 1.3, rot = 0.85, accelRpmShare = 0.75, overrunRpmShare = 0.35, brakeFactor = 1.40},
    {accel = 2.0, rot = 1.00, accelRpmShare = 1.00, overrunRpmShare = 0.50, brakeFactor = 2.05}
}
-- 0.1.5: with an attached load, engine braking holds less (square root of own mass / total mass)
FlowDrive.BRAKE_MASS_MIN = 0.5
FlowDrive.OVERRUN_MIN_SPEED = 3        -- km/h: below this speed, no forced engine braking (smooth stop)
FlowDrive.DEFAULT_RAMP = 3

-- Ranges
FlowDrive.RANGE_AUTO = 0
FlowDrive.RANGE_FIELD = 1
FlowDrive.RANGE_ROAD = 2
FlowDrive.RANGE_NAMES = {[0] = "auto", [1] = "champ", [2] = "route"}
FlowDrive.FIELD_SPEED_SHARE = 0.55     -- field range: 55 % of top speed
FlowDrive.RANGE_CHANGE_MAX_SPEED = 10  -- km/h: 0.7.0: above this, range change refused (design choice: block and warn)

-- Eco engine speed and load limit
FlowDrive.ECO_TARGET_LOAD = 0.80       -- eco engine speed aims at 80 % engine load
FlowDrive.ACCEL_TARGET_LOAD = 0.70     -- while accelerating, engine speed rises up to 70 % load (0.1.1)
FlowDrive.RPM_FLOOR_MARGIN = 1.05      -- floor: engine speed needed to hold the speed at the minimum ratio, + 5 % (0.1.1)
FlowDrive.DROOP_MIN_POWER = 0.90       -- the load limit keeps at least 90 % of peak power (0.1.1)
FlowDrive.ECO_MIN_SHARE = 0.35         -- minimum eco engine speed: idle + 35 % of the range
FlowDrive.CAP_RISE_TIME = 400          -- ms: engine speed rises quickly on demand
FlowDrive.CAP_FALL_TIME = 2500         -- ms: it falls back slowly
FlowDrive.DROOP_LOAD_ON = 0.93         -- full load
FlowDrive.DROOP_LOAD_OFF = 0.85
FlowDrive.DROOP_DELAY = 1500           -- ms of full load without accelerating before the engine speed drop
FlowDrive.DROOP = {transport = 0.15, traction = 0.25}

FlowDrive.WORK_NAMES = {transport = "transport", traction = "traction", pto = "prise de force"}

-- 0.2.0: eco PTO (540E / 1000E: same PTO speed at about 78 % of engine speed)
FlowDrive.PTO_ECO_FACTOR = 0.78
FlowDrive.PTO_RPM_MARGIN = 1.03        -- with the PTO, maximum allowed engine speed = PTO engine speed + 3 %
-- 0.2.0: default engine speed memories (share of the idle-rated range) and adjustment step
FlowDrive.MEMORY_SHARES = {0.65, 0.90}
FlowDrive.MEMORY_STEP = 50
-- 0.2.0: boost (Sigma Power / IPM style) on the road and with the PTO.
-- 0.8.0: off by default; percentage entered per vehicle (0 to BOOST_MAX_PCT);
-- "included": the game power is already the boosted power (base game John Deere, Case IH, Valtra, Fendt 728),
-- FlowDrive removes it outside boost. "added": the boost comes on top (base game Massey Ferguson).
FlowDrive.BOOST_DEFAULT_PCT = 8
FlowDrive.BOOST_MAX_PCT = 30
FlowDrive.BOOST_SPEED_ON = 16          -- km/h
FlowDrive.BOOST_SPEED_OFF = 12         -- km/h (hysteresis)
FlowDrive.BOOST_MIN_INTERVAL = 1500    -- ms between two changes (each change reloads the engine curve)

-- 0.8.0: auto ramp (ramp 0): 2 at work or heavily loaded, 3 when empty, 4 on loaders
FlowDrive.RAMP_AUTO = 0
FlowDrive.RAMP_AUTO_HEAVY = 2.0        -- total mass / tractor mass above which the ramp stays at 2
FlowDrive.RAMP_AUTO_HOLD = 2000        -- ms: the situation must last this long before the ramp changes

-- 0.3.0: transmission profiles. cvt = tractors; hst = loaders, telehandlers, self-propelled machines.
-- hydShare: hydraulic engine speed (share of the idle-rated range) when a cylinder moves
-- brakeMult: off-pedal braking (a hydrostatic drive holds harder than a tractor CVT)
-- fieldShare / fieldName: slow range (field for a tractor, work for a loader)
-- 0.4.0: turnOnShare: engine speed held when the machine itself is running (mixing, threshing) with no
-- PTO speed defined; autoField: the auto range switches to the slow range when the machine is running
FlowDrive.PROFILES = {
    cvt = {label = "CVT tracteur", hydShare = 0.50, turnOnShare = 0.50, brakeMult = 1.0, fieldShare = 0.55, fieldName = "champ", autoField = false},
    hst = {label = "HST", hydShare = 0.60, turnOnShare = 0.60, brakeMult = 1.5, fieldShare = 0.50, fieldName = "travail", autoField = false},
    harvester = {label = "moissonneuse", hydShare = 0.60, turnOnShare = 1.00, brakeMult = 1.5, fieldShare = 0.40, fieldName = "recolte", autoField = true}
}
-- 0.4.0: harvester crop flow control (engine load smoothed over FLOW_LOAD_TIME ms)
FlowDrive.FLOW_LOAD_HIGH = 0.90        -- above: target speed drops
FlowDrive.FLOW_LOAD_LOW = 0.75         -- below: it rises back to the setpoint
FlowDrive.FLOW_DOWN_RATE = 1.0         -- km/h per second
FlowDrive.FLOW_UP_RATE = 0.4           -- km/h per second
FlowDrive.FLOW_MIN_SPEED = 1.5         -- km/h
FlowDrive.FLOW_LOAD_TIME = 1000        -- ms

-- 0.5.0: automatic preheating when starting (air temperature from the game weather)
FlowDrive.PREHEAT_AMBIENT = 5          -- degrees C: below, preheating
FlowDrive.PREHEAT_ENGINE_MAX = 30      -- degrees C: engine still warm above, no preheating
FlowDrive.PREHEAT_MIN = 2000           -- ms (at 5 degrees)
FlowDrive.PREHEAT_MAX = 15000          -- ms (around -20 degrees)
FlowDrive.PREHEAT_PER_DEGREE = 520     -- ms per degree below PREHEAT_AMBIENT
-- 0.5.0: cold engine. 50 degree threshold like ADS (stable and beta); 40 without ADS.
-- Cap at 72 % of max engine speed: below the ADS beta cold engine warning (75 %).
FlowDrive.COLD_TEMP_ADS = 50
FlowDrive.COLD_TEMP_DEFAULT = 40
FlowDrive.COLD_HYSTERESIS = 2
FlowDrive.COLD_RPM_SHARE = 0.72
FlowDrive.COLD_MAX_RAMP = 2
-- 0.5.0: cold test mode (optional key): air at -15 degrees, simulated engine that warms up while driving
FlowDrive.COLDTEST_AMBIENT = -15
FlowDrive.COLDTEST_WARM_RATE = 0.6     -- degrees per second at full load
-- 0.5.0: fuel consumption measured from the drop of the diesel level
FlowDrive.FUEL_WINDOW = 10000          -- ms

------------------------------------------------------------------------------------------
-- 0.6.0: texts (l10n/l10n_fr.xml, l10n_en.xml) and general settings (modSettings)
------------------------------------------------------------------------------------------

-- Translated text. A mod's texts live in its own environment (the way CVT Addon and ADS read them).
function FlowDrive.t(key)
    local i18n = g_i18n
    if i18n ~= nil and i18n.modEnvironments ~= nil and i18n.modEnvironments[FlowDrive.MOD_NAME] ~= nil then
        i18n = i18n.modEnvironments[FlowDrive.MOD_NAME]
    end
    if i18n ~= nil and i18n.getText ~= nil then
        local ok, text = pcall(i18n.getText, i18n, key)
        if ok and type(text) == "string" then
            return text
        end
    end
    return key
end

function FlowDrive.tf(key, ...)
    local ok, text = pcall(string.format, FlowDrive.t(key), ...)
    if ok then
        return text
    end
    return FlowDrive.t(key)
end

-- General settings, shared by all vehicles and all savegames
-- 1.2.0: gearLoad / gearCoast / gearGroups: aids of the fixed-gear boxes (FlowDriveGears.lua)
FlowDrive.settings = {hydraulic = true, preheat = true, coldProtect = true, hud = true, hudPos = 1, dbl = true,
    gearLoad = true, gearCoast = true, gearGroups = true}
FlowDrive.SETTINGS_BOOLS = {"hydraulic", "preheat", "coldProtect", "hud", "dbl", "gearLoad", "gearCoast", "gearGroups"}

function FlowDrive.getSettingsPath()
    if getUserProfileAppPath == nil then
        return nil
    end
    return getUserProfileAppPath() .. "modSettings/FS25_FlowDrive.xml"
end

function FlowDrive.loadSettings()
    local path = FlowDrive.getSettingsPath()
    if path == nil or fileExists == nil or not fileExists(path) then
        return
    end
    local xml = loadXMLFile("FlowDriveSettings", path)
    if xml == nil or xml == 0 then
        return
    end
    for _, name in ipairs(FlowDrive.SETTINGS_BOOLS) do
        local value = getXMLBool(xml, "flowDrive.settings#" .. name)
        if value ~= nil then
            FlowDrive.settings[name] = value
        end
    end
    local hudPos = getXMLInt(xml, "flowDrive.settings#hudPos")
    if hudPos == 1 or hudPos == 2 then
        FlowDrive.settings.hudPos = hudPos
    end
    delete(xml)
end

function FlowDrive.saveSettings()
    local path = FlowDrive.getSettingsPath()
    if path == nil then
        return
    end
    if createFolder ~= nil then
        createFolder(getUserProfileAppPath() .. "modSettings/")
    end
    local xml = createXMLFile("FlowDriveSettings", path, "flowDrive")
    if xml == nil or xml == 0 then
        print("[FlowDrive] ATTENTION : reglages generaux non enregistres (" .. tostring(path) .. ")")
        return
    end
    for _, name in ipairs(FlowDrive.SETTINGS_BOOLS) do
        setXMLBool(xml, "flowDrive.settings#" .. name, FlowDrive.settings[name] == true)
    end
    setXMLInt(xml, "flowDrive.settings#hudPos", FlowDrive.settings.hudPos or 1)
    saveXMLFile(xml)
    delete(xml)
end

pcall(FlowDrive.loadSettings)

------------------------------------------------------------------------------------------
-- 1.1.0: multiplayer
-- The driving law runs on the server only (the game calls the motor hooks there). Players send their
-- settings and inputs to the server (FlowDriveEvents.lua); the server sends back what the display needs.
------------------------------------------------------------------------------------------

FlowDrive.SYNC_INTERVAL = 250          -- ms: the server checks at most this often whether the display state changed
-- General settings that act on the driving law: in multiplayer, those of the server apply to everyone
FlowDrive.SERVER_RULES = {"hydraulic", "preheat", "coldProtect", "gearLoad", "gearCoast", "gearGroups"}
FlowDrive.serverRules = nil            -- received from the server (player who is not the server)

function FlowDrive.isMultiplayer()
    local mission = g_currentMission
    return mission ~= nil and mission.missionDynamicInfo ~= nil and mission.missionDynamicInfo.isMultiplayer == true
end

-- "solo", "hote" (player hosting the game), "serveur" (dedicated server) or "joueur" (player who joined)
function FlowDrive.getRole()
    if not FlowDrive.isMultiplayer() then
        return "solo"
    end
    if g_server ~= nil then
        if g_dedicatedServer ~= nil or g_dedicatedServerInfo ~= nil then
            return "serveur"
        end
        return "hote"
    end
    return "joueur"
end

-- Log prefix: unchanged in single player, with the role in multiplayer ("[FlowDrive][joueur]")
function FlowDrive.logPrefix()
    if FlowDrive.isMultiplayer() then
        return "[FlowDrive][" .. FlowDrive.getRole() .. "]"
    end
    return "[FlowDrive]"
end

-- Value of a general setting that acts on the driving law: the server's one for a player who joined
function FlowDrive.rule(name)
    if g_server == nil and FlowDrive.serverRules ~= nil and FlowDrive.serverRules[name] ~= nil then
        return FlowDrive.serverRules[name]
    end
    return FlowDrive.settings[name]
end

FlowDrive.HST_CATEGORIES = {
    FRONTLOADERVEHICLES = true, TELELOADERVEHICLES = true, SKIDSTEERVEHICLES = true,
    WHEELLOADERVEHICLES = true, FORAGEMIXERS = true, FORKLIFTS = true
}
-- 0.3.0: hydraulic engine speed
FlowDrive.HYD_COMMAND_MIN = 0.05       -- minimum cylinder command counted as a movement
FlowDrive.HYD_HOLD = 800               -- ms: engine speed stays high after the movement (0.3.1: 2000 was too long)
FlowDrive.HYD_FALL = 1000              -- ms: then falls back over this time (0.3.1: was 1500)
-- 0.3.0: inching, optional key with no default binding
FlowDrive.INCH_RATE = 5                -- km/h per second while the key is held
FlowDrive.INCH_MIN_SPEED = 1.0         -- km/h

local SPEC_NAME = FlowDrive.SPEC_NAME

if g_specializationManager:getSpecializationByName(SPEC_NAME) == nil then
    g_specializationManager:addSpecialization(SPEC_NAME, "FlowDriveSpec", FlowDrive.MOD_DIR .. "scripts/FlowDriveSpec.lua", nil)
end

for typeName, typeEntry in pairs(g_vehicleTypeManager.types) do
    if SpecializationUtil.hasSpecialization(Motorized, typeEntry.specializations)
        and SpecializationUtil.hasSpecialization(Drivable, typeEntry.specializations)
        and not SpecializationUtil.hasSpecialization(Locomotive, typeEntry.specializations) then
        g_vehicleTypeManager:addSpecialization(typeName, FlowDrive.MOD_NAME .. "." .. SPEC_NAME)
    end
end

-- FlowDrive state of the motor, or nil when FlowDrive does not act on this vehicle
local function getState(motor)
    local vehicle = motor.vehicle
    if vehicle == nil then
        return nil
    end
    local state = vehicle.spec_flowDrive
    if state == nil or not state.active then
        return nil
    end
    return state
end

function FlowDrive.hookMinMaxGearRatio(motor, superFunc, ...)
    local minRatio, maxRatio = superFunc(motor, ...)
    local state = getState(motor)
    if state == nil or type(minRatio) ~= "number" or type(maxRatio) ~= "number" then
        return minRatio, maxRatio
    end
    state.ratioIn = minRatio
    -- forward only (positive ratios)
    if state.fieldMinRatio ~= nil and state.rangeActive == FlowDrive.RANGE_FIELD and minRatio > 0 and maxRatio > minRatio then
        minRatio = math.min(math.max(minRatio, state.fieldMinRatio), maxRatio)
    end
    -- 0.3.0: inching: the ratio lengthens to slow down without lowering engine speed
    if state.inchMinRatio ~= nil and minRatio > 0 and maxRatio > minRatio then
        minRatio = math.min(math.max(minRatio, state.inchMinRatio), maxRatio)
    end
    -- 0.4.0: crop flow control: same principle, top speed follows engine load
    if state.flowMinRatio ~= nil and minRatio > 0 and maxRatio > minRatio then
        minRatio = math.min(math.max(minRatio, state.flowMinRatio), maxRatio)
    end
    return minRatio, maxRatio
end

function FlowDrive.hookAccelerationLimit(motor, superFunc, ...)
    local limit = superFunc(motor, ...)
    local state = getState(motor)
    if state == nil or type(limit) ~= "number" then
        return limit
    end
    -- 0.5.0: rampEff = ramp actually applied (limited when the engine is cold)
    local ramp = FlowDrive.RAMPS[state.rampEff or state.ramp] or FlowDrive.RAMPS[FlowDrive.DEFAULT_RAMP]
    return math.min(limit, ramp.accel)
end

function FlowDrive.hookMotorRotationAccelerationLimit(motor, superFunc, ...)
    local limit = superFunc(motor, ...)
    local state = getState(motor)
    if state == nil or type(limit) ~= "number" then
        return limit
    end
    local ramp = FlowDrive.RAMPS[state.rampEff or state.ramp] or FlowDrive.RAMPS[FlowDrive.DEFAULT_RAMP]
    return limit * ramp.rot
end

function FlowDrive.hookRequiredMotorRpmRange(motor, superFunc, ...)
    local minRpm, maxRpm = superFunc(motor, ...)
    local state = getState(motor)
    if state == nil or type(minRpm) ~= "number" or type(maxRpm) ~= "number" then
        return minRpm, maxRpm
    end
    -- engine speed imposed by the PTO (already reduced in eco PTO: the spec changes motor.ptoMotorRpmRatio, 0.2.1)
    state.requiredMinRpm = minRpm
    -- 0.2.0: engine speed memory: the engine holds this speed
    if state.fixedRpm ~= nil then
        minRpm = math.max(minRpm, math.min(state.fixedRpm, maxRpm))
    end
    -- 0.3.0: hydraulic engine speed (moving cylinder) and engine speed held while inching
    if state.extraMinRpm ~= nil then
        minRpm = math.max(minRpm, math.min(state.extraMinRpm, maxRpm))
    end
    if state.rpmCap ~= nil then
        maxRpm = math.max(minRpm, math.min(maxRpm, state.rpmCap))
    end
    -- 0.1.3: off-pedal engine braking, the transmission shortens the ratio to hold this speed
    if state.overrunMinRpm ~= nil then
        minRpm = math.max(minRpm, math.min(state.overrunMinRpm, maxRpm))
    end
    return minRpm, maxRpm
end

-- 0.2.0: boost. Same method as ADS: the torque curve is multiplied here, and the spec calls
-- vehicle:updateMotorProperties() when the boost changes, so the physics motor reads it again.
-- 0.8.0: torqueFactor is computed by the spec (1 when FlowDrive is inactive or boost is off); it can be
-- below 1 in "included" mode outside boost. Read directly (not getState): the spec resets it to 1 itself.
function FlowDrive.hookTorqueCurveValue(motor, superFunc, ...)
    local torque = superFunc(motor, ...)
    local vehicle = motor.vehicle
    local state = vehicle ~= nil and vehicle.spec_flowDrive or nil
    if state ~= nil and not state.measuringCurve and type(state.torqueFactor) == "number"
        and state.torqueFactor ~= 1 and type(torque) == "number" then
        return torque * state.torqueFactor
    end
    return torque
end

local function installMotorHook(functionName, hook)
    if VehicleMotor == nil or VehicleMotor[functionName] == nil then
        print(string.format("[FlowDrive] ATTENTION : VehicleMotor.%s introuvable, accroche non installee", functionName))
        return
    end
    VehicleMotor[functionName] = Utils.overwrittenFunction(VehicleMotor[functionName], hook)
end

if not FlowDrive.hooksInstalled then
    FlowDrive.hooksInstalled = true
    installMotorHook("getMinMaxGearRatio", FlowDrive.hookMinMaxGearRatio)
    installMotorHook("getAccelerationLimit", FlowDrive.hookAccelerationLimit)
    installMotorHook("getMotorRotationAccelerationLimit", FlowDrive.hookMotorRotationAccelerationLimit)
    installMotorHook("getRequiredMotorRpmRange", FlowDrive.hookRequiredMotorRpmRange)
    installMotorHook("getTorqueCurveValue", FlowDrive.hookTorqueCurveValue)
    -- 1.2.0: gear choice of boxes with fixed gears (FlowDriveGears.lua). Only the server runs it.
    if FlowDriveGears ~= nil then
        installMotorHook("findGearChangeTargetGearPrediction", FlowDriveGears.hookFindGear)
    else
        print("[FlowDrive] ATTENTION : FlowDriveGears.lua non charge, rapports automatiques inactifs")
    end
    -- 1.0.1: start key (Enter): starts preheating when it is cold. Replaced before vehicles are loaded,
    -- so ADS, which calls Motorized.actionEventToggleMotorState again, sees it too.
    local function wrapStartAction(name)
        if Motorized == nil or type(Motorized[name]) ~= "function" then
            print("[FlowDrive] ATTENTION : Motorized." .. name .. " introuvable, prechauffage sans touche")
            return
        end
        local original = Motorized[name]
        Motorized[name] = function(vehicle, ...)
            if FlowDriveSpec ~= nil and FlowDriveSpec.onStartKey ~= nil and vehicle ~= nil then
                local ok, keep = pcall(FlowDriveSpec.onStartKey, vehicle)
                if ok and keep then
                    return
                end
            end
            return original(vehicle, ...)
        end
    end
    wrapStartAction("actionEventToggleMotorState")
    wrapStartAction("actionEventSetMotorStateOn")
    print("[FlowDrive] version " .. FlowDrive.VERSION .. " chargee")
    -- 1.1.0: role in the game (solo, host, dedicated server, player), once the mission has started
    if FSBaseMission ~= nil and type(FSBaseMission.onStartMission) == "function" then
        FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, function()
            print(string.format("[FlowDrive] partie lancee : role=%s multijoueur=%s version %s",
                FlowDrive.getRole(), tostring(FlowDrive.isMultiplayer()), FlowDrive.VERSION))
        end)
    end
    -- 0.7.0: neighbouring mods detected (compatibility)
    local function loaded(name)
        return g_modIsLoaded ~= nil and g_modIsLoaded[name] == true
    end
    print(string.format("[FlowDrive] mods voisins : ADS=%s CVT_Addon=%s EngineBrakeforceCompensation=%s DashboardLive=%s Courseplay=%s DynamicDrivePro=%s extendedCruiseControl=%s",
        tostring(loaded("FS25_AdvancedDamageSystem")), tostring(loaded("FS25_CVT_Addon")),
        tostring(loaded("FS25_EngineBrakeforceCompensation")), tostring(loaded("FS25_DashboardLive")),
        tostring(loaded("FS25_Courseplay")), tostring(loaded("FS25_DynamicDrivePro")), tostring(loaded("FS25_extendedCruiseControl"))))
    if loaded("FS25_CVT_Addon") then
        print("[FlowDrive] ATTENTION : CVT Addon est charge. FlowDrive n'interviendra pas sur les vehicules ou CVT Addon est actif.")
    end
end
