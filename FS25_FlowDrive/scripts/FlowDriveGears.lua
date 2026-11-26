-- FlowDrive: gearboxes with fixed gears (powershift, semi-powershift, manual boxes used in automatic).
-- Next version: transmission detection (read from the engine, no guessing), then three automatic aids:
--   1. downshift under load,
--   2. engine braking: downshift when the pedal is released,
--   3. automatic gear groups (ranges): earlier upshift, downshift under load.
--
-- The game chooses the gear in VehicleMotor:findGearChangeTargetGearPrediction. Its scoring constants are
-- local to that function, so they cannot be tuned: this file calls the original function (and those of
-- other mods), then corrects the gear it returns. The group change is made from the same hook, with the
-- engine's own VehicleMotor:setGearGroup, the way the engine does it in updateGear.
--
-- It only acts when:
--   - the vehicle has fixed gears (motor.forwardGears) and a non-electric engine,
--   - FlowDrive is on for this vehicle (menu / key),
--   - the game itself shifts automatically: motor:getUseAutomaticGearShifting() for the gears,
--     motor:getUseAutomaticGroupShifting() for the groups (the player's gearbox setting is "automatic",
--     or the vehicle cannot be shifted by hand). A player who shifts by hand is never touched.
-- Each aid has a general setting (FlowDrive.settings.gearLoad / gearCoast / gearGroups).
-- The hook is only called on the server (the game runs the gearbox there), so nothing is synchronised
-- except the settings, which follow the host.

FlowDriveGears = FlowDriveGears or {}
local G = FlowDriveGears

-- Downshift under load
G.LOAD_HIGH = 0.85       -- smoothed engine load from which the engine counts as "under load"
G.LOAD_TIME = 500        -- ms: smoothing of the load
G.LOAD_HOLD = 800        -- ms: the load must stay high this long before a downshift
G.MIN_SPEED = 2          -- km/h: below this the game's start-gear logic keeps control
G.MIN_PEDAL = 0.3        -- accelerator share counted as "accelerating"
G.POWER_FLOOR = 0.85     -- below the engine speed that keeps this share of peak power, the engine is lugging
G.MIN_GAIN = 1.05        -- the lower gear must give at least this much more power (no useless shift)
G.HEADROOM = 0.82        -- after the downshift, engine speed stays under idle + this share of the range
G.UP_HOLD = 4000         -- ms: after our downshift the game's upshift is refused (anti hunting)...
G.UP_HOLD_RPM = 0.92     -- ... unless engine speed is above idle + this share of the range
G.CURVE_STEP = 50        -- rpm: step used to read the torque curve
-- Upshift guard: the game accepts gears that give only 50 % of the peak power and may jump several gears,
-- so it climbs into a gear where the engine lugs, then goes back down, and so on. FlowDrive refuses an
-- upshift when the load the engine would have to carry after it is too high.
G.UPSHIFT_CHECK_LOAD = 0.50  -- smoothed load from which the guard looks at the upshift
G.UPSHIFT_LOAD_MAX = 0.80    -- predicted load after the upshift above which it is refused (under LOAD_HIGH: no hunting)
G.GUARD_LOG_INTERVAL = 2000  -- ms between two log lines of the guard

-- Engine braking (pedal released)
G.COAST_PEDAL = 0.05     -- accelerator share counted as "released"
G.COAST_TIME = 600       -- ms released before the engine brakes (a short lift does nothing)
G.COAST_MIN_SPEED = 6    -- km/h
G.COAST_SHARE_MIN = 0.30 -- downshift when engine speed is under idle + this share of the range (vehicle alone)...
G.COAST_SHARE_MAX = 0.50 -- ... up to this share with a heavy attached load (same mass factor as the CVT engine braking)
G.COAST_HEADROOM = 0.75  -- engine speed after the downshift stays under idle + this share of the range
G.COAST_UP_HOLD = 2000   -- ms: upshift refused after an engine-braking downshift (pedal still released)
G.COAST_REPEAT = 1500    -- ms between two engine-braking downshifts in a row (the first one waits COAST_TIME)

-- Gear groups (ranges)
G.GROUP_UP_RPM = 0.90    -- upshift of the group from the top gear when engine speed reaches idle + this share (game: max - 50 rpm)
G.GROUP_UP_LOAD = 0.80   -- after the shift the engine must stay under this load (under LOAD_HIGH: no shift back down)
G.GROUP_HOLD = 4000      -- ms between two group changes

local function isNumber(value)
    return type(value) == "number" and value == value
end

-- Name of a VehicleMotor.TRANSMISSION_TYPE value ("default", "powershift"), "?" when unknown
local function typeName(value)
    local types = VehicleMotor ~= nil and VehicleMotor.TRANSMISSION_TYPE or nil
    if type(types) ~= "table" or value == nil then
        return "?"
    end
    for name, v in pairs(types) do
        if v == value then
            return string.lower(tostring(name))
        end
    end
    return "?"
end

------------------------------------------------------------------------------------------
-- Detection: facts exposed by the engine, not a guess
------------------------------------------------------------------------------------------

-- kind: "continuous" (CVT, hydrostatic), "discrete" (fixed gears) or "none"
function G.detect(motor)
    local info = {kind = "none", gears = 0, groups = 0, gearType = "-", groupType = "-",
        manualGears = false, manualGroups = false}
    if motor == nil then
        return info
    end
    if motor.minForwardGearRatio ~= nil then
        info.kind = "continuous"
    elseif type(motor.forwardGears) == "table" then
        info.kind = "discrete"
        info.gears = #motor.forwardGears
        info.gearType = typeName(motor.gearType)
        if type(motor.gearGroups) == "table" then
            info.groups = #motor.gearGroups
            info.groupType = typeName(motor.groupType)
        end
    end
    info.manualGears = motor.manualShiftGears == true
    info.manualGroups = motor.manualShiftGroups == true
    return info
end

-- Electric engines (no diesel, an electric charge) stay with the game
function G.isElectric(vehicle)
    local motorized = vehicle ~= nil and vehicle.spec_motorized or nil
    local consumers = motorized ~= nil and motorized.consumersByFillTypeName or nil
    return type(consumers) == "table" and consumers.DIESEL == nil and consumers.ELECTRICCHARGE ~= nil
end

-- True when the game shifts the gears of this motor by itself right now
function G.isAutomatic(motor)
    if motor == nil or type(motor.getUseAutomaticGearShifting) ~= "function" then
        return false
    end
    local ok, value = pcall(motor.getUseAutomaticGearShifting, motor)
    return ok and value == true
end

-- One log line per vehicle, when it is loaded: what the engine says about the gearbox, and what FlowDrive does
function G.logDetection(vehicle, s)
    local info = s ~= nil and s.gearInfo or nil
    if info == nil then
        return
    end
    local motorized = vehicle.spec_motorized
    local motor = motorized ~= nil and motorized.motor or nil
    local name = vehicle.getFullName ~= nil and vehicle:getFullName() or "?"
    local handled
    if s.eligible then
        handled = "profil " .. tostring(s.profile)
    elseif s.gearEligible then
        handled = "rapports automatiques"
    else
        handled = "non gere (" .. tostring(s.reason) .. ")"
    end
    print(string.format("%s boite : %s | type=%s | rapports=%d gammes=%d | boite=%s gammes=%s | manuel possible : rapports=%s gammes=%s | automatique maintenant=%s | categorie=%s | %s",
        FlowDrive.logPrefix(), tostring(name), info.kind, info.gears, info.groups, info.gearType, info.groupType,
        tostring(info.manualGears), tostring(info.manualGroups), tostring(G.isAutomatic(motor)),
        tostring(s.category), handled))
end

-- Status line for the menu: nil when the gear logic does not apply to this vehicle
function G.getStatusKey(vehicle, s)
    if s == nil or not s.gearEligible then
        return nil
    end
    if not s.enabled then
        return "fd_gear_off"
    end
    local motorized = vehicle.spec_motorized
    if not G.isAutomatic(motorized ~= nil and motorized.motor or nil) then
        return "fd_gear_manual"
    end
    return "fd_gear_auto"
end

------------------------------------------------------------------------------------------
-- Engine curve (power by engine speed), read once per motor
------------------------------------------------------------------------------------------

local function buildCurve(motor, s)
    local idle, rated = motor.minRpm, motor.maxRpm
    if not isNumber(idle) or not isNumber(rated) or rated <= idle then
        return nil
    end
    local points, peak = {}, 0
    -- the boost factor of FlowDrive is left out of the measurement (same flag as the CVT code)
    s.measuringCurve = true
    for rpm = idle, rated, G.CURVE_STEP do
        local ok, torque = pcall(motor.getTorqueCurveValue, motor, rpm)
        if ok and isNumber(torque) then
            local power = torque * rpm
            points[#points + 1] = {rpm = rpm, power = power}
            if power > peak then
                peak = power
            end
        end
    end
    s.measuringCurve = false
    if peak <= 0 then
        return nil
    end
    local floorRpm = rated
    for _, point in ipairs(points) do
        if point.power >= peak * G.POWER_FLOOR then
            floorRpm = point.rpm
            break
        end
    end
    return {idle = idle, rated = rated, range = rated - idle, peak = peak, floorRpm = floorRpm}
end

local function powerAt(motor, rpm)
    local ok, torque = pcall(motor.getTorqueCurveValue, motor, rpm)
    if ok and isNumber(torque) then
        return torque * rpm
    end
    return nil
end

------------------------------------------------------------------------------------------
-- Hook: findGearChangeTargetGearPrediction
------------------------------------------------------------------------------------------

local function logShift(vehicle, s, who, fromGear, toGear, load, rpm, speed, extra)
    if not s.debug then
        return
    end
    local motorized = vehicle.spec_motorized
    local motor = motorized ~= nil and motorized.motor or nil
    local group = ""
    if motor ~= nil and type(motor.gearGroups) == "table" and motor.activeGearGroupIndex ~= nil then
        local entry = motor.gearGroups[motor.activeGearGroupIndex]
        group = string.format(" | gamme %d/%d%s", motor.activeGearGroupIndex, #motor.gearGroups,
            entry ~= nil and entry.name ~= nil and (" (" .. tostring(entry.name) .. ")") or "")
    end
    print(string.format("%s rapports : %s | %s %d -> %d | charge %.2f regime %.0f vitesse %.1f km/h%s%s",
        FlowDrive.logPrefix(), tostring(vehicle.getFullName ~= nil and vehicle:getFullName() or "?"),
        who, fromGear, toGear, load, rpm, speed, group, extra or ""))
end

local function logGroup(vehicle, s, fromGroup, toGroup, why, gear, load, rpm, speed, extra)
    if not s.debug then
        return
    end
    print(string.format("%s gammes : %s | FlowDrive gamme %d -> %d (%s), rapport %d | charge %.2f regime %.0f vitesse %.1f km/h%s",
        FlowDrive.logPrefix(), tostring(vehicle.getFullName ~= nil and vehicle:getFullName() or "?"),
        fromGroup, toGroup, why, gear, load, rpm, speed, extra or ""))
end

local function sign(value)
    if value > 0 then return 1 end
    if value < 0 then return -1 end
    return 0
end

local function groupsAutomatic(motor)
    if type(motor.gearGroups) ~= "table" or #motor.gearGroups < 2 or type(motor.getUseAutomaticGroupShifting) ~= "function" then
        return false
    end
    local ok, value = pcall(motor.getUseAutomaticGroupShifting, motor)
    return ok and value == true and motor.gearGroupChangedIsLocked ~= true
end

-- Automatic gear groups. Returns the gear to use in the new group when a group change was made, else nil.
-- The gear is chosen here for the new group (the engine does the same after its own group upshift).
local function adjustGroups(motor, s, g, curve, curGear, gears, pedal, speed, diffRpm, curRpm)
    local groups = motor.gearGroups
    local active = motor.activeGearGroupIndex
    if not isNumber(active) or groups[active] == nil or (g_time or 0) < g.groupHoldUntil then
        return nil
    end
    local curPower = powerAt(motor, curRpm)
    if curPower == nil or speed < G.MIN_SPEED then
        return nil
    end
    local newGroup, why
    local bestGear, bestPower = nil, nil
    local headroomRpm = curve.idle + curve.range * G.HEADROOM
    local activeRatio = groups[active].ratio

    if g.highTime >= G.LOAD_HOLD and curGear == 1 and active > 1 and curRpm < curve.floorRpm
        and groups[active - 1] ~= nil and sign(groups[active - 1].ratio) == sign(activeRatio) then
        -- lugging in the lowest gear of the group: down one group, smallest step that gives power
        newGroup, why = active - 1, "charge"
        for k = #gears, 1, -1 do
            local rpm = diffRpm * math.abs(gears[k].ratio * groups[newGroup].ratio)
            local power = powerAt(motor, rpm)
            if power ~= nil and rpm <= headroomRpm and power >= curPower * G.MIN_GAIN then
                bestGear, bestPower = k, power
                break
            end
        end
    elseif pedal >= G.MIN_PEDAL and curGear == #gears and active < #groups
        and curRpm >= curve.idle + curve.range * G.GROUP_UP_RPM
        and groups[active + 1] ~= nil and sign(groups[active + 1].ratio) == sign(activeRatio) then
        -- top gear of the group and engine speed high: up one group before the rev limiter, in the gear
        -- that gives the most power, as long as the engine can still deliver the power needed
        newGroup, why = active + 1, "regime"
        local needed = curPower * math.max(g.load, 0.3) / G.GROUP_UP_LOAD
        for k = 1, #gears do
            local rpm = diffRpm * math.abs(gears[k].ratio * groups[newGroup].ratio)
            local power = powerAt(motor, rpm)
            if power ~= nil and rpm <= headroomRpm and power >= needed
                and (bestPower == nil or power > bestPower) then
                bestGear, bestPower = k, power
            end
        end
    end
    if newGroup == nil or bestGear == nil then
        return nil
    end
    local ok = pcall(motor.setGearGroup, motor, newGroup)
    if not ok then
        return nil
    end
    g.groupHoldUntil = (g_time or 0) + G.GROUP_HOLD
    g.noUpUntil = g.groupHoldUntil
    g.noUpCoast = false
    g.highTime = 0
    g.groupShifts = g.groupShifts + 1
    g.ownGroup = true
    g.ownTarget = bestGear
    logGroup(motor.vehicle, s, active, newGroup, why, bestGear, g.load, curRpm, speed,
        string.format(" | puissance x%.2f", bestPower / math.max(curPower, 0.0001)))
    return bestGear
end

-- The engine cancels a downshift requested under acceleration for 3 s after one of its upshifts
-- (updateGear: allowGearChangeTimer / allowGearChangeDirection). Asking during that time only wastes the request.
function G.gameBlocksDownshift(motor, pedal)
    return (motor.allowGearChangeTimer or 0) > 0 and (motor.allowGearChangeDirection or 0) ~= -1
        and pedal > 0 and (motor.currentDirection or 1) > 0
end

-- Returns the gear to use. Never raises: an error leaves the game's choice untouched.
function G.adjust(motor, newGear, curGear, gears, gearSign, acceleratorPedal, dt)
    local vehicle = motor.vehicle
    local s = vehicle ~= nil and vehicle.spec_flowDrive or nil
    if s == nil or not s.gearEligible or not s.enabled or not vehicle.isServer then
        return newGear
    end
    local g = s.gear
    if g == nil or type(gears) ~= "table" or gears[curGear] == nil or not isNumber(newGear) then
        return newGear
    end
    local cfg = FlowDrive.settings or {}
    local gearsAuto = G.isAutomatic(motor)
    -- the player shifts the gears by hand: FlowDrive does nothing on them (the groups may still be automatic)
    if not gearsAuto then
        g.lastGear = nil
        g.highTime = 0
        g.coastTime = 0
    end
    if g.curve == nil and not g.curveFailed then
        g.curve = buildCurve(motor, s)
        g.curveFailed = g.curve == nil
    end
    local curve = g.curve
    if curve == nil then
        return newGear
    end

    local pedal = math.abs(acceleratorPedal or 0)
    local speed = (type(vehicle.getLastSpeed) == "function" and vehicle:getLastSpeed()) or 0
    local load = 0
    if type(vehicle.getMotorLoadPercentage) == "function" then
        local value = vehicle:getMotorLoadPercentage()
        if isNumber(value) then
            load = math.max(0, math.min(value, 1))
        end
    end
    g.load = g.load + (load - g.load) * math.min((dt or 0) / G.LOAD_TIME, 1)
    if g.load >= G.LOAD_HIGH and pedal >= G.MIN_PEDAL then
        g.highTime = g.highTime + (dt or 0)
    else
        g.highTime = 0
    end
    if pedal < G.COAST_PEDAL then
        g.coastTime = g.coastTime + (dt or 0)
    else
        g.coastTime = 0
    end

    local mult = 1
    if type(motor.getGearRatioMultiplier) == "function" then
        mult = motor:getGearRatioMultiplier() or 1
    end
    local diffRpm = math.max((motor.differentialRotSpeed or 0) * gearSign, 0.0001) * 30 / math.pi
    local curRatio = math.abs(gears[curGear].ratio * mult)
    local curRpm = diffRpm * curRatio

    -- gear changed since the last call: reset the timers; a shift the game chose is logged
    -- (measurement, to compare with and without FlowDrive), one we asked for was logged when decided
    -- group changed by the game (measurement): logged once, with the state that led to it
    local activeGroup = motor.activeGearGroupIndex
    if g.lastGroup ~= nil and activeGroup ~= nil and activeGroup ~= g.lastGroup then
        if not g.ownGroup and s.debug then
            print(string.format("%s gammes : %s | jeu gamme %d -> %d | rapport %d charge %.2f regime %.0f vitesse %.1f km/h",
                FlowDrive.logPrefix(), tostring(vehicle.getFullName ~= nil and vehicle:getFullName() or "?"),
                g.lastGroup, activeGroup, curGear, g.load, curRpm, speed))
        end
        g.ownGroup = nil
    end
    g.lastGroup = activeGroup

    if g.lastGear ~= nil and curGear ~= g.lastGear then
        g.highTime = 0
        g.coastTime = g.ownCoast and (G.COAST_TIME - G.COAST_REPEAT) or 0
        g.ownCoast = nil
        if curGear ~= g.ownTarget then
            logShift(vehicle, s, "jeu", g.lastGear, curGear, g.load, curRpm, speed, "")
        end
        g.ownTarget = nil
    end
    g.lastGear = curGear

    -- gear groups first: a group change changes the ratios of every gear
    if newGear == curGear and cfg.gearGroups ~= false and groupsAutomatic(motor) then
        local result = adjustGroups(motor, s, g, curve, curGear, gears, pedal, speed, diffRpm, curRpm)
        if result ~= nil then
            return result
        end
    end

    if not gearsAuto then
        return newGear
    end

    if newGear > curGear and cfg.gearLoad ~= false and pedal >= G.MIN_PEDAL and g.load >= G.UPSHIFT_CHECK_LOAD then
        -- upshift guard: keep the highest gear the engine can carry after the shift
        local curPower = powerAt(motor, curRpm)
        if curPower ~= nil then
            local k = newGear
            while k > curGear do
                local rpm = diffRpm * math.abs(gears[k].ratio * mult)
                local power = powerAt(motor, rpm)
                if power ~= nil and rpm >= curve.idle and curPower * g.load / math.max(power, 0.0001) <= G.UPSHIFT_LOAD_MAX then
                    break
                end
                k = k - 1
            end
            if k < newGear then
                g.upGuards = g.upGuards + 1
                if s.debug and (g_time or 0) >= g.guardLogAt then
                    g.guardLogAt = (g_time or 0) + G.GUARD_LOG_INTERVAL
                    print(string.format("%s rapports : %s | FlowDrive refuse la montee %d -> %d (garde %d) | charge %.2f regime %.0f vitesse %.1f km/h",
                        FlowDrive.logPrefix(), tostring(vehicle.getFullName ~= nil and vehicle:getFullName() or "?"),
                        curGear, newGear, k, g.load, curRpm, speed))
                end
                newGear = k
            end
        end
    end

    if newGear ~= curGear then
        -- the game wants to shift. After our downshift, an upshift is refused while there is room
        -- (the engine speed rose, the load fell: the game would shift back up at once). After an
        -- engine-braking downshift the veto stops as soon as the driver accelerates again.
        if newGear > curGear and g_time ~= nil and g_time < g.noUpUntil
            and not (g.noUpCoast and pedal >= G.MIN_PEDAL)
            and curRpm < curve.idle + curve.range * G.UP_HOLD_RPM then
            g.upVetoes = g.upVetoes + 1
            return curGear
        end
        return newGear
    end

    -- downshift under load
    if cfg.gearLoad ~= false and curGear > 1 and g.highTime >= G.LOAD_HOLD and speed >= G.MIN_SPEED
        and gears[curGear - 1] ~= nil and not G.gameBlocksDownshift(motor, pedal) then
        local candRpm = diffRpm * math.abs(gears[curGear - 1].ratio * mult)
        if candRpm <= curve.idle + curve.range * G.HEADROOM then
            local curPower = powerAt(motor, curRpm)
            local candPower = powerAt(motor, candRpm)
            if curPower ~= nil and candPower ~= nil and curRpm < curve.floorRpm
                and candPower >= curPower * G.MIN_GAIN then
                g.highTime = 0
                g.ownTarget = curGear - 1
                g.noUpUntil = (g_time or 0) + G.UP_HOLD
                g.noUpCoast = false
                g.downshifts = g.downshifts + 1
                logShift(vehicle, s, "FlowDrive", curGear, curGear - 1, g.load, curRpm, speed,
                    string.format(" | regime apres %.0f, puissance x%.2f", candRpm, candPower / math.max(curPower, 0.0001)))
                return curGear - 1
            end
        end
    end

    -- engine braking: pedal released, engine speed low for the weight carried
    if cfg.gearCoast ~= false and curGear > 1 and g.coastTime >= G.COAST_TIME and speed >= G.COAST_MIN_SPEED
        and gears[curGear - 1] ~= nil then
        local massFactor = s.brakeMassFactor
        if not isNumber(massFactor) then
            massFactor = 1
        end
        local minMass = (FlowDrive.BRAKE_MASS_MIN or 0.5)
        local heavy = math.max(0, math.min((1 - massFactor) / math.max(1 - minMass, 0.01), 1))
        local share = G.COAST_SHARE_MIN + (G.COAST_SHARE_MAX - G.COAST_SHARE_MIN) * heavy
        local candRpm = diffRpm * math.abs(gears[curGear - 1].ratio * mult)
        if curRpm < curve.idle + curve.range * share and candRpm <= curve.idle + curve.range * G.COAST_HEADROOM then
            g.coastTime = 0
            g.ownCoast = true
            g.ownTarget = curGear - 1
            g.noUpUntil = (g_time or 0) + G.COAST_UP_HOLD
            g.noUpCoast = true
            g.coastShifts = g.coastShifts + 1
            logShift(vehicle, s, "FlowDrive frein moteur", curGear, curGear - 1, g.load, curRpm, speed,
                string.format(" | seuil %.0f %%, regime apres %.0f", share * 100, candRpm))
            return curGear - 1
        end
    end
    return newGear
end

function G.hookFindGear(motor, superFunc, ...)
    local newGear = superFunc(motor, ...)
    local curGear, gears, gearSign, _, acceleratorPedal, dt = ...
    local ok, result = pcall(G.adjust, motor, newGear, curGear, gears, gearSign, acceleratorPedal, dt)
    if ok then
        return result
    end
    if not G.errorLogged then
        G.errorLogged = true
        print("[FlowDrive] ERREUR rapports automatiques (le choix du jeu est conserve) : " .. tostring(result))
    end
    return newGear
end
