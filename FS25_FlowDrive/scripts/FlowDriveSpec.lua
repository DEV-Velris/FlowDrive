-- FlowDrive 0.1.0 - etape 1 : CVT moderne, mode pedale
-- Specialisation : etat par vehicule, sauvegarde, touches, loi de conduite, panneau de reglage.
-- Les consignes calculees ici sont lues par les accroches de FlowDriveMain.lua.

FlowDriveSpec = {}

local SCAN_INTERVAL = 500      -- ms : verifications lentes (outils, CVT Addon, prise de force)
local LOG_INTERVAL = 1000      -- ms : journal du mode reglage
local K_DEFAULT = 0.38         -- km/h par (tr/min / rapport), mesure sur le Q305 a l'etape 0
local KMH_PER_RADIUS = 3.6 * math.pi / 30

------------------------------------------------------------------------------------------
-- Outils
------------------------------------------------------------------------------------------

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function num(value, decimals)
    if type(value) ~= "number" then
        return "-"
    end
    return string.format("%." .. tostring(decimals or 0) .. "f", value)
end

local function safeCall(object, methodName, ...)
    if object == nil or object[methodName] == nil then
        return nil
    end
    local ok, result = pcall(object[methodName], object, ...)
    if ok then
        return result
    end
    return nil
end

local function notify(text)
    if g_currentMission == nil then
        return
    end
    local hud = g_currentMission.hud
    if hud ~= nil and hud.addSideNotification ~= nil then
        hud:addSideNotification({1, 1, 1, 1}, text, 2500)
    elseif g_currentMission.showBlinkingWarning ~= nil then
        g_currentMission:showBlinkingWarning(text, 2000)
    end
end

------------------------------------------------------------------------------------------
-- Enregistrement
------------------------------------------------------------------------------------------

function FlowDriveSpec.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function FlowDriveSpec.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)." .. FlowDrive.MOD_NAME .. "." .. FlowDrive.SPEC_NAME
    schema:register(XMLValueType.BOOL, key .. "#enabled", "FlowDrive actif sur ce vehicule", true)
    schema:register(XMLValueType.INT, key .. "#ramp", "Rampe d'acceleration (0 auto, 1 a 4)", FlowDrive.RAMP_AUTO)
    schema:register(XMLValueType.INT, key .. "#range", "Gamme (0 auto, 1 champ, 2 route)", FlowDrive.RANGE_AUTO)
    -- 0.2.0
    schema:register(XMLValueType.BOOL, key .. "#ptoEco", "Prise de force eco", false)
    schema:register(XMLValueType.BOOL, key .. "#boost", "Boost actif", false)
    -- 0.8.0
    schema:register(XMLValueType.INT, key .. "#boostPct", "Boost en pourcentage", FlowDrive.BOOST_DEFAULT_PCT)
    schema:register(XMLValueType.BOOL, key .. "#boostIncluded", "Puissance du jeu deja boostee", true)
    schema:register(XMLValueType.INT, key .. "#mem1", "Regime memorise 1 (tr/min)", 0)
    schema:register(XMLValueType.INT, key .. "#mem2", "Regime memorise 2 (tr/min)", 0)
    -- 0.4.0
    schema:register(XMLValueType.BOOL, key .. "#flow", "Regulation de debit (moissonneuses)", true)
end

function FlowDriveSpec.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", FlowDriveSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", FlowDriveSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", FlowDriveSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", FlowDriveSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", FlowDriveSpec)
end

------------------------------------------------------------------------------------------
-- Chargement et sauvegarde
------------------------------------------------------------------------------------------

function FlowDriveSpec:onLoad(savegame)
    self.spec_flowDrive = {}
    local s = self.spec_flowDrive
    s.enabled = true
    s.eligible = false
    s.reason = ""
    s.active = false
    s.ramp = FlowDrive.RAMP_AUTO       -- 0.8.0 : rampe auto par defaut
    s.rampAuto = nil                   -- rampe choisie par le mode auto
    s.rampAutoCandidate = nil
    s.rampAutoTimer = 0
    s.range = FlowDrive.RANGE_AUTO
    s.rangeActive = FlowDrive.RANGE_ROAD
    s.debug = false
    s.actionEvents = {}
    s.scanTimer = 0
    s.logTimer = 0
    s.rpmCap = nil
    s.loadSmooth = 0
    s.accelSmooth = 0
    s.lastSpeed = nil
    s.droopTimer = 0
    s.droopActive = false
    s.mode = "-"
    s.work = "transport"
    s.k = nil
    s.kCalibrated = false
    s.fieldSpeed = nil
    s.fieldMinRatio = nil
    s.peakTorqueRpm = nil
    s.originalBrakeScale = nil
    s.overrunMinRpm = nil
    s.requiredMinRpm = nil
    s.displayLines = {}
    -- 0.2.0 : prise de force eco, regime memorise, boost
    s.ptoEco = false
    s.memory = 0               -- 0 : aucun, 1 ou 2 : memoire active (non sauvegarde, comme un vrai tracteur)
    s.memRpm = {nil, nil}
    s.fixedRpm = nil
    s.boostEnabled = false     -- 0.8.0 : coupe par defaut sur toutes les marques
    s.boostPct = FlowDrive.BOOST_DEFAULT_PCT
    s.boostIncluded = true     -- puissance du jeu deja boostee (cas le plus courant dans le jeu de base)
    s.torqueFactor = 1         -- multiplicateur de couple applique (FlowDriveMain.hookTorqueCurveValue)
    s.boostApplied = false
    s.boostCooldown = 0
    -- 0.3.0 : profil, regime hydraulique, approche lente, consommation
    s.profile = "cvt"
    s.category = nil
    s.hydCommand = 0
    s.hydLevel = 0
    s.hydHold = 0
    s.hydRpm = nil
    s.turnedOn = false
    s.extraMinRpm = nil
    s.inchHeld = false
    s.inchSpeed = nil
    s.inchRpm = nil
    s.inchMinRatio = nil
    s.fuelSmooth = nil
    -- 0.4.0 : regulation de debit des moissonneuses
    s.flowEnabled = true
    s.flowLoad = 0
    s.flowSpeed = nil
    s.flowMinRatio = nil
    s.turnOnRpm = nil
    -- 0.5.0 : prechauffage, moteur froid, essai froid, consommation mesuree
    s.preheatTimer = 0
    s.preheatTotal = 0
    s.preheatDone = false
    s.startRequested = false
    s.wasMotorOn = false
    s.cold = false
    s.coldNotified = false
    s.coldCap = nil
    s.rampEff = nil
    s.coldTest = false
    s.coldTestTemp = nil
    s.engineTemp = nil
    s.engineTempSource = "-"
    s.ambientTemp = nil
    s.fuelRefLevel = nil
    s.fuelWinTime = 0
end

------------------------------------------------------------------------------------------
-- 0.5.0 : temperatures, prechauffage (le jeu refuse le demarrage tant qu'il dure)
------------------------------------------------------------------------------------------

function FlowDriveSpec.registerOverwrittenFunctions(vehicleType)
    -- uniquement si le type de vehicule les a (Motorized), pour ne jamais casser un type inconnu
    if vehicleType.functions ~= nil and vehicleType.functions.getCanMotorRun ~= nil then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", FlowDriveSpec.getCanMotorRun)
        FlowDrive.preheatTypes = (FlowDrive.preheatTypes or 0) + 1
    else
        FlowDrive.preheatMissing = (FlowDrive.preheatMissing or 0) + 1
    end
    if vehicleType.functions ~= nil and vehicleType.functions.getMotorNotAllowedWarning ~= nil then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMotorNotAllowedWarning", FlowDriveSpec.getMotorNotAllowedWarning)
    end
end

-- Temperature de l'air (degres C) : celle de la meteo du jeu, ou celle du mode essai froid
function FlowDriveSpec.getAmbientTemperature(s)
    if s.coldTest then
        return FlowDrive.COLDTEST_AMBIENT
    end
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    local weather = environment ~= nil and environment.weather or nil
    if weather ~= nil and weather.getCurrentTemperature ~= nil then
        local ok, value = pcall(weather.getCurrentTemperature, weather)
        if ok and type(value) == "number" then
            return value
        end
    end
    return nil
end

-- Temperature moteur (degres C) : ADS si present, sinon celle du jeu ; le mode essai froid la simule
function FlowDriveSpec.getEngineTemperature(vehicle, s)
    if s.coldTest and s.coldTestTemp ~= nil then
        s.engineTempSource = "essai"
        return s.coldTestTemp
    end
    local ads = vehicle.spec_AdvancedDamageSystem
    if ads ~= nil and type(ads.engineTemperature) == "number" then
        s.engineTempSource = "ADS"
        return ads.engineTemperature
    end
    local motorized = vehicle.spec_motorized
    if motorized ~= nil and type(motorized.motorTemperature) == "table" and type(motorized.motorTemperature.value) == "number" then
        s.engineTempSource = "jeu"
        return motorized.motorTemperature.value
    end
    s.engineTempSource = "-"
    return nil
end

local function isPlayerControlled(vehicle)
    if vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        return false
    end
    if vehicle.getIsControlled ~= nil then
        return vehicle:getIsControlled() == true
    end
    return vehicle.getIsEntered ~= nil and vehicle:getIsEntered() == true
end

-- Lance le prechauffage si besoin. Rend true tant qu'il dure.
function FlowDriveSpec.updatePreheatNeed(vehicle, s)
    if s.preheatTimer > 0 then
        return true
    end
    if s.preheatDone or not s.enabled or not s.eligible or not FlowDrive.settings.preheat or not isPlayerControlled(vehicle) then
        return false
    end
    if vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then
        return false
    end
    local ambient = FlowDriveSpec.getAmbientTemperature(s)
    local engineTemp = FlowDriveSpec.getEngineTemperature(vehicle, s)
    if ambient == nil or ambient >= FlowDrive.PREHEAT_AMBIENT or (engineTemp ~= nil and engineTemp >= FlowDrive.PREHEAT_ENGINE_MAX) then
        s.preheatDone = true
        return false
    end
    local duration = clamp(FlowDrive.PREHEAT_MIN + (FlowDrive.PREHEAT_AMBIENT - ambient) * FlowDrive.PREHEAT_PER_DEGREE,
        FlowDrive.PREHEAT_MIN, FlowDrive.PREHEAT_MAX)
    s.preheatTimer = duration
    s.preheatTotal = duration
    notify(FlowDrive.tf("fd_msg_preheat", math.ceil(duration / 1000), math.floor(ambient + 0.5)))
    print(string.format("[FlowDrive] prechauffage : %s | air %s moteur %s (%s) duree %s ms",
        tostring(safeCall(vehicle, "getFullName") or "?"), num(ambient, 1), num(engineTemp, 1), s.engineTempSource, num(duration)))
    return true
end

------------------------------------------------------------------------------------------
-- 0.6.0 : ecrans DashboardLive
-- DashboardLive lit vehicle.spec_CVTaddon.forDBL_<nom>. Si CVT Addon n'est pas la, FlowDrive cree une
-- petite table a ce nom, SANS CVTcfgExists ni CVTconfig : ADS (stable et beta) et FlowDrive ne la
-- prennent donc pas pour CVT Addon. Une vraie table CVT Addon n'est jamais touchee.
------------------------------------------------------------------------------------------

function FlowDriveSpec.updateDbl(vehicle, s)
    local existing = vehicle.spec_CVTaddon
    local owned = existing ~= nil and existing == s.dblTable
    if existing ~= nil and not owned then
        return
    end
    if not (FlowDrive.settings.dbl and s.active) then
        if owned then
            vehicle.spec_CVTaddon = nil
        end
        s.dblTable = nil
        return
    end
    local t = s.dblTable
    if t == nil then
        t = {isFlowDrive = true, CVTdamage = 0}
        s.dblTable = t
        vehicle.spec_CVTaddon = t
    end
    local motor = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil
    t.forDBL_accramp = s.rampEff or s.ramp
    -- CVT Addon : 1 = gamme lente, 2 = gamme route
    t.forDBL_drivinglevel = s.rangeActive == FlowDrive.RANGE_FIELD and 1 or 2
    t.forDBL_motorcoldlamp = s.cold and 1 or 0
    t.forDBL_preglowing = s.preheatTimer > 0 and 1 or 0
    t.forDBL_glowingstate = s.preheatTimer > 0 and 1 or 0
    t.forDBL_isvariotm = true
    t.forDBL_vmaxfoward = tostring(math.floor((s.targetSpeed or s.vmax or 0) + 0.5))
    t.forDBL_vmaxbackward = motor ~= nil and motor.maxBackwardSpeed ~= nil and tostring(math.floor(motor.maxBackwardSpeed * 3.6 + 0.5)) or "0"
    t.forDBL_tmspedalvmax = t.forDBL_vmaxfoward
    t.forDBL_ipmactive = s.boostApplied and 1 or 0
    t.forDBL_brakeramp = "0"
    t.forDBL_autodiffs = 0
    t.forDBL_preautodiffs = 0
    t.forDBL_warnheat = 0
    t.forDBL_critheat = 0
    t.forDBL_warndamage = 0
    t.forDBL_critdamage = 0
    t.forDBL_highpressure = 0
    t.forDBL_cvtwear = 0
    t.forDBL_cvtclutch = 0
end

------------------------------------------------------------------------------------------
-- 0.6.0 : affichage (rampe, gamme, etat)
------------------------------------------------------------------------------------------

function FlowDriveSpec.getHudLines(vehicle, s)
    if not s.eligible then
        return nil
    end
    if not s.active then
        return {FlowDrive.t("fd_hud_off")}
    end
    local line1 = FlowDrive.tf("fd_hud_line1", FlowDriveSpec.getRampLabel(s), FlowDriveSpec.getRangeLabel(s, s.rangeActive))
    local parts = {}
    if s.preheatTimer > 0 then
        table.insert(parts, FlowDrive.tf("fd_hud_preheat", math.ceil(s.preheatTimer / 1000)))
    end
    if s.fixedRpm ~= nil then
        table.insert(parts, FlowDrive.tf("fd_hud_memory", math.floor(s.fixedRpm + 0.5)))
    elseif s.work == "pto" and s.requiredMinRpm ~= nil then
        table.insert(parts, FlowDrive.tf(s.ptoEco and "fd_hud_ptoEco" or "fd_hud_pto", math.floor(s.requiredMinRpm + 0.5)))
    elseif s.flowMinRatio ~= nil and s.flowSpeed ~= nil then
        table.insert(parts, FlowDrive.tf("fd_hud_flow", string.format("%.1f", s.flowSpeed)))
    elseif s.droopActive then
        table.insert(parts, FlowDrive.t("fd_hud_droop"))
    elseif s.inchSpeed ~= nil then
        table.insert(parts, FlowDrive.t("fd_hud_inching"))
    elseif s.hydLevel > 0 then
        table.insert(parts, FlowDrive.t("fd_hud_hydraulic"))
    elseif s.turnedOn then
        table.insert(parts, FlowDrive.t("fd_hud_working"))
    end
    if s.cold then
        table.insert(parts, FlowDrive.t("fd_hud_cold"))
    end
    if s.boostApplied then
        table.insert(parts, FlowDrive.t("fd_hud_boost"))
    end
    if #parts == 0 then
        return {line1}
    end
    return {line1, table.concat(parts, "  ·  ")}
end

function FlowDriveSpec.drawHud(vehicle, s)
    local lines = FlowDriveSpec.getHudLines(vehicle, s)
    if lines == nil then
        return
    end
    local right = FlowDrive.settings.hudPos ~= 2
    local x = right and 0.985 or 0.015
    local y = right and 0.30 or 0.36
    local size = 0.014
    setTextAlignment(right and RenderText.ALIGN_RIGHT or RenderText.ALIGN_LEFT)
    setTextBold(false)
    for index, line in ipairs(lines) do
        local lineY = y - (index - 1) * (size * 1.35)
        -- ombre pour rester lisible sur fond clair
        setTextColor(0, 0, 0, 0.75)
        renderText(x + 0.0008, lineY - 0.0012, size, line)
        if index == 1 then
            setTextColor(1, 1, 1, 0.95)
        else
            setTextColor(1, 0.75, 0.3, 0.95)
        end
        renderText(x, lineY, size, line)
    end
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

local function isAutoMotorStart()
    return g_currentMission ~= nil and g_currentMission.missionInfo ~= nil
        and g_currentMission.missionInfo.automaticMotorStartEnabled == true
end

-- 1.0.1 : le prechauffage ne part plus en montant dans la machine. Il part a l'appui sur la touche de
-- demarrage (Entree), intercepte dans FlowDriveMain (Motorized.actionEventToggleMotorState), puis le
-- moteur demarre a la fin. Seul le demarrage automatique du jeu (option) le lance en montant.
function FlowDriveSpec:getCanMotorRun(superFunc, ...)
    local s = self.spec_flowDrive
    if s ~= nil then
        if s.preheatTimer > 0 then
            return false
        end
        if isAutoMotorStart() and FlowDriveSpec.updatePreheatNeed(self, s) then
            s.startRequested = true
            return false
        end
    end
    return superFunc(self, ...)
end

-- Le jeu appelle cette fonction aussi pour l'aide des touches : elle ne doit rien declencher (bug 1.0.0)
function FlowDriveSpec:getMotorNotAllowedWarning(superFunc, ...)
    local s = self.spec_flowDrive
    if s ~= nil and s.preheatTimer > 0 then
        return FlowDrive.tf("fd_msg_preheatWarning", math.ceil(s.preheatTimer / 1000))
    end
    return superFunc(self, ...)
end

-- 1.0.1 : appui sur la touche de demarrage. Rend true si FlowDrive garde l'appui pour lui
-- (prechauffage lance ou en cours) ; false : le jeu demarre normalement.
function FlowDriveSpec.onStartKey(vehicle)
    local s = vehicle.spec_flowDrive
    if s == nil or (vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()) then
        return false
    end
    if s.preheatTimer > 0 then
        s.startRequested = true
        notify(FlowDrive.tf("fd_msg_preheatWarning", math.ceil(s.preheatTimer / 1000)))
        return true
    end
    if FlowDriveSpec.updatePreheatNeed(vehicle, s) then
        s.startRequested = true
        return true
    end
    return false
end

local function getProfile(s)
    return FlowDrive.PROFILES[s.profile] or FlowDrive.PROFILES.cvt
end

local function rangeName(s, range)
    if range == FlowDrive.RANGE_FIELD then
        return getProfile(s).fieldName
    end
    return FlowDrive.RANGE_NAMES[range] or "?"
end

-- 0.6.0 : noms traduits (menu, messages, affichage)
local FIELD_KEYS = {cvt = "fd_range_field", hst = "fd_range_work", harvester = "fd_range_harvest"}
function FlowDriveSpec.getRangeLabel(s, range)
    if range == FlowDrive.RANGE_FIELD then
        return FlowDrive.t(FIELD_KEYS[s.profile] or "fd_range_field")
    elseif range == FlowDrive.RANGE_ROAD then
        return FlowDrive.t("fd_range_road")
    end
    return FlowDrive.t("fd_range_auto")
end

function FlowDriveSpec.getReasonText(s)
    if s.reasonKey == "fd_reason_category" then
        return FlowDrive.tf("fd_reason_category", tostring(s.category))
    elseif s.reasonKey ~= nil then
        return FlowDrive.t(s.reasonKey)
    end
    return s.reason or "?"
end

function FlowDriveSpec:onPostLoad(savegame)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    if savegame ~= nil and savegame.xmlFile ~= nil then
        local key = savegame.key .. "." .. FlowDrive.MOD_NAME .. "." .. FlowDrive.SPEC_NAME
        s.enabled = savegame.xmlFile:getValue(key .. "#enabled", s.enabled)
        s.ramp = clamp(savegame.xmlFile:getValue(key .. "#ramp", s.ramp) or FlowDrive.RAMP_AUTO, 0, #FlowDrive.RAMPS)
        s.range = clamp(savegame.xmlFile:getValue(key .. "#range", s.range) or FlowDrive.RANGE_AUTO, 0, 2)
        s.ptoEco = savegame.xmlFile:getValue(key .. "#ptoEco", s.ptoEco) == true
        -- 0.8.0 : une sauvegarde d'avant la 0.8.0 (sans #boostPct) repart boost coupe
        local savedPct = savegame.xmlFile:getValue(key .. "#boostPct", nil)
        if savedPct ~= nil then
            s.boostPct = clamp(savedPct, 1, FlowDrive.BOOST_MAX_PCT)
            s.boostEnabled = savegame.xmlFile:getValue(key .. "#boost", false) == true
            s.boostIncluded = savegame.xmlFile:getValue(key .. "#boostIncluded", true) ~= false
        else
            s.boostEnabled = false
        end
        local mem1 = savegame.xmlFile:getValue(key .. "#mem1", 0) or 0
        local mem2 = savegame.xmlFile:getValue(key .. "#mem2", 0) or 0
        s.memRpm = {mem1 > 0 and mem1 or nil, mem2 > 0 and mem2 or nil}
        s.flowEnabled = savegame.xmlFile:getValue(key .. "#flow", true) ~= false
    end
    FlowDriveSpec.checkEligible(self)
end

function FlowDriveSpec:saveToXMLFile(xmlFile, key, usedModNames)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    xmlFile:setValue(key .. "#enabled", s.enabled)
    xmlFile:setValue(key .. "#ramp", s.ramp)
    xmlFile:setValue(key .. "#range", s.range)
    xmlFile:setValue(key .. "#ptoEco", s.ptoEco == true)
    xmlFile:setValue(key .. "#boost", s.boostEnabled == true)
    xmlFile:setValue(key .. "#boostPct", math.floor(s.boostPct or FlowDrive.BOOST_DEFAULT_PCT))
    xmlFile:setValue(key .. "#boostIncluded", s.boostIncluded ~= false)
    xmlFile:setValue(key .. "#mem1", math.floor((s.memRpm[1] or 0) + 0.5))
    xmlFile:setValue(key .. "#mem2", math.floor((s.memRpm[2] or 0) + 0.5))
    xmlFile:setValue(key .. "#flow", s.flowEnabled ~= false)
end

------------------------------------------------------------------------------------------
-- Vehicules concernes
------------------------------------------------------------------------------------------

local function isCvtAddonActive(vehicle)
    local cvt = vehicle.spec_CVTaddon
    if cvt == nil or not cvt.CVTcfgExists then
        return false
    end
    return cvt.CVTconfig ~= nil and cvt.CVTconfig ~= 0 and cvt.CVTconfig ~= 8
end

-- Etape 1 : CVT des tracteurs. Etape 3 (0.3.0) : HST des chargeuses, telescopiques et automotrices.
-- Les moissonneuses (etape 4) viendront ensuite ; l'electrique reste au jeu.
function FlowDriveSpec.checkEligible(vehicle)
    local s = vehicle.spec_flowDrive
    local motorized = vehicle.spec_motorized
    local motor = motorized ~= nil and motorized.motor or nil
    s.eligible = false
    local storeItem = g_storeManager ~= nil and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    local category = storeItem ~= nil and storeItem.categoryName or nil
    s.category = category
    s.reasonKey = nil
    if motor == nil then
        s.reason = "pas de moteur"
        s.reasonKey = "fd_reason_noMotor"
        return
    end
    if motor.minForwardGearRatio == nil then
        s.reason = "pas une boite CVT"
        s.reasonKey = "fd_reason_noCvt"
        return
    end
    -- 0.3.0 : moteur electrique laisse au jeu (pas de gasoil mais une charge electrique)
    local consumers = motorized.consumersByFillTypeName
    if type(consumers) == "table" and consumers.DIESEL == nil and consumers.ELECTRICCHARGE ~= nil then
        s.reason = "moteur electrique (laisse au jeu)"
        s.reasonKey = "fd_reason_electric"
        return
    end
    local upperCategory = category ~= nil and string.upper(category) or nil
    if vehicle.spec_combine ~= nil then
        -- 0.4.0 : moissonneuses, ensileuses, arracheuses, machines a vendanger automotrices
        s.profile = "harvester"
    elseif upperCategory == nil or string.find(upperCategory, "TRACTOR", 1, true) ~= nil then
        s.profile = "cvt"
    elseif FlowDrive.HST_CATEGORIES[upperCategory] then
        s.profile = "hst"
    else
        s.reason = "categorie " .. tostring(category) .. " (pas encore geree)"
        s.reasonKey = "fd_reason_category"
        return
    end
    s.eligible = true
    s.reason = ""
    local profile = getProfile(s)

    -- Donnees de base du vehicule
    s.ratedRpm = motor.maxRpm
    s.idleRpm = motor.minRpm
    local maxSpeed = safeCall(motor, "getMaximumForwardSpeed")
    s.vmax = type(maxSpeed) == "number" and maxSpeed * 3.6 or 50
    s.fieldSpeed = math.floor(s.vmax * profile.fieldShare + 0.5)
    s.hydRpm = (s.idleRpm ~= nil and s.ratedRpm ~= nil) and math.floor((s.idleRpm + (s.ratedRpm - s.idleRpm) * profile.hydShare) / 10 + 0.5) * 10 or nil
    s.turnOnRpm = (s.idleRpm ~= nil and s.ratedRpm ~= nil) and math.floor((s.idleRpm + (s.ratedRpm - s.idleRpm) * profile.turnOnShare) / 10 + 0.5) * 10 or nil

    -- 0.2.0 : regimes memorises par defaut (0.8.0 : le boost n'est plus active selon la marque)
    for index, share in ipairs(FlowDrive.MEMORY_SHARES) do
        if s.memRpm[index] == nil and s.idleRpm ~= nil and s.ratedRpm ~= nil then
            s.memRpm[index] = math.floor((s.idleRpm + (s.ratedRpm - s.idleRpm) * share) / 10 + 0.5) * 10
        end
    end

    -- Constante vitesse / (regime / rapport) : rayon de la plus grande roue, recalibree en roulant
    local radius = 0
    if vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil then
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            local r = (wheel.physics ~= nil and wheel.physics.radius) or wheel.radius
            if type(r) == "number" and r > radius then
                radius = r
            end
        end
    end
    s.k = radius > 0.2 and radius * KMH_PER_RADIUS or K_DEFAULT

    -- Courbe du moteur : regime de couple maxi, puissance maxi, et plancher de la limite de charge
    -- (le regime le plus bas qui garde FlowDrive.DROOP_MIN_POWER de la puissance maxi)
    local bestTorque, bestRpm, bestPower = 0, nil, 0
    local powers = {}
    if motor.getTorqueCurveValue ~= nil and s.idleRpm ~= nil and s.ratedRpm ~= nil then
        -- 0.8.0 : courbe d'origine, sans le facteur de boost
        s.measuringCurve = true
        for rpm = s.idleRpm, s.ratedRpm, 50 do
            local ok, torque = pcall(motor.getTorqueCurveValue, motor, rpm)
            if ok and type(torque) == "number" then
                if torque > bestTorque then
                    bestTorque, bestRpm = torque, rpm
                end
                local power = torque * rpm
                table.insert(powers, {rpm = rpm, power = power})
                if power > bestPower then
                    bestPower = power
                end
            end
        end
        s.measuringCurve = false
    end
    s.peakTorqueRpm = bestRpm
    s.peakPower = bestPower > 0 and bestPower or nil
    s.droopFloorRpm = nil
    for _, entry in ipairs(powers) do
        if entry.power >= bestPower * FlowDrive.DROOP_MIN_POWER then
            s.droopFloorRpm = entry.rpm
            break
        end
    end
end

-- Part de la puissance maxi disponible a un regime donne (pour le journal)
local function getPowerShare(vehicle, s, rpm)
    local motor = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil
    if motor == nil or s.peakPower == nil or type(rpm) ~= "number" or motor.getTorqueCurveValue == nil then
        return nil
    end
    local ok, torque = pcall(motor.getTorqueCurveValue, motor, rpm)
    if not ok or type(torque) ~= "number" then
        return nil
    end
    return torque * rpm / s.peakPower
end

------------------------------------------------------------------------------------------
-- Detection du travail
------------------------------------------------------------------------------------------

local function hasLoweredImplement(vehicle, depth)
    if depth > 4 or vehicle.getAttachedImplements == nil then
        return false
    end
    for _, implement in pairs(vehicle:getAttachedImplements() or {}) do
        local object = implement.object
        if object ~= nil then
            if object.getIsLowered ~= nil then
                local ok, lowered = pcall(object.getIsLowered, object, false)
                if ok and lowered then
                    return true
                end
            end
            if hasLoweredImplement(object, depth + 1) then
                return true
            end
        end
    end
    return false
end

-- 0.3.0 : plus forte commande de verin (chargeur, bras, benne, fraise...) sur le vehicule et ses outils.
-- Methode validee a l'etape 0 : movingTools[i].move vaut la commande du joueur (-1 a 1) pendant le mouvement.
local function getToolCommand(object)
    local strongest = 0
    local cylindered = type(object) == "table" and object.spec_cylindered or nil
    if cylindered ~= nil and cylindered.movingTools ~= nil then
        for _, tool in ipairs(cylindered.movingTools) do
            local move = math.abs(tonumber(tool.move) or 0)
            if move > strongest then
                strongest = move
            end
        end
    end
    return strongest
end

local function getHydraulicCommand(vehicle)
    local strongest = getToolCommand(vehicle)
    local root = vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() or nil
    if root ~= nil and root ~= vehicle then
        strongest = math.max(strongest, getToolCommand(root))
    end
    local base = root or vehicle
    if base.getChildVehicles ~= nil then
        local ok, children = pcall(base.getChildVehicles, base)
        if ok and type(children) == "table" then
            for key, value in pairs(children) do
                local child = type(value) == "table" and value or key
                if child ~= vehicle and child ~= root then
                    strongest = math.max(strongest, getToolCommand(child))
                end
            end
        end
    end
    return strongest
end

local function scan(vehicle, s)
    local wasActive = s.active
    local cvtAddon = isCvtAddonActive(vehicle)
    if cvtAddon and not s.cvtAddonLogged then
        s.cvtAddonLogged = true
        print("[FlowDrive] CVT Addon actif sur " .. tostring(safeCall(vehicle, "getFullName") or "?") .. " : FlowDrive n'intervient pas")
    end
    s.active = s.enabled and s.eligible and not cvtAddon
    if s.active ~= wasActive then
        s.rpmCap = nil
        s.droopTimer = 0
    end
    -- 0.1.5 : frein moteur moins fort avec une charge attelee
    local ownMass = safeCall(vehicle, "getTotalMass", true)
    local totalMass = safeCall(vehicle, "getTotalMass")
    if type(ownMass) == "number" and type(totalMass) == "number" and ownMass > 0 and totalMass >= ownMass then
        s.brakeMassFactor = clamp(math.sqrt(ownMass / totalMass), FlowDrive.BRAKE_MASS_MIN, 1)
    else
        s.brakeMassFactor = 1
    end
    if s.requiredMinRpm ~= nil and s.idleRpm ~= nil and s.requiredMinRpm > s.idleRpm + 100 then
        s.work = "pto"
    elseif hasLoweredImplement(vehicle, 0) then
        s.work = "traction"
    else
        s.work = "transport"
    end
    -- 0.3.0 : automotrice en marche (melange, fraise) sans regime de PdF : regime hydraulique
    s.turnedOn = vehicle.spec_turnOnVehicle ~= nil and safeCall(vehicle, "getIsTurnedOn") == true

    -- 0.8.0 : rampe auto, choisie selon la situation, changee seulement si elle dure RAMP_AUTO_HOLD
    local autoWanted
    if s.profile == "hst" then
        autoWanted = 4
    elseif s.profile == "harvester" then
        autoWanted = s.turnedOn and 2 or 3
    elseif s.work == "traction" or s.work == "pto" then
        autoWanted = 2
    elseif type(ownMass) == "number" and type(totalMass) == "number" and ownMass > 0
        and totalMass > ownMass * FlowDrive.RAMP_AUTO_HEAVY then
        autoWanted = 2
    else
        autoWanted = 3
    end
    s.rampAutoMass = (type(ownMass) == "number" and ownMass > 0 and type(totalMass) == "number") and totalMass / ownMass or nil
    if s.rampAuto == nil then
        s.rampAuto = autoWanted
    elseif autoWanted ~= s.rampAuto then
        if autoWanted ~= s.rampAutoCandidate then
            s.rampAutoCandidate = autoWanted
            s.rampAutoTimer = 0
        else
            s.rampAutoTimer = s.rampAutoTimer + SCAN_INTERVAL
            if s.rampAutoTimer >= FlowDrive.RAMP_AUTO_HOLD then
                s.rampAuto = autoWanted
                s.rampAutoCandidate = nil
                s.rampAutoTimer = 0
            end
        end
    else
        s.rampAutoCandidate = nil
        s.rampAutoTimer = 0
    end

    -- 0.2.0 : boost en transport (au-dessus de BOOST_SPEED_ON km/h) et avec la prise de force.
    -- Le couple est modifie dans getTorqueCurveValue (FlowDriveMain) ; le moteur physique ne lit
    -- la courbe qu'a updateMotorProperties, appele seulement quand le facteur change.
    -- 0.8.0 : facteur = 1 + pct en mode "en plus" pendant le boost ; 1 / (1 + pct) en mode "inclus" hors boost.
    local speed = safeCall(vehicle, "getLastSpeed") or 0
    local boostOn = s.active and s.boostEnabled and (s.boostPct or 0) > 0
    local wantBoost = false
    if boostOn then
        if s.work == "pto" then
            wantBoost = true
        elseif s.work == "transport" then
            wantBoost = speed > (s.boostApplied and FlowDrive.BOOST_SPEED_OFF or FlowDrive.BOOST_SPEED_ON)
        end
    end
    local factor = 1
    if boostOn then
        local gain = 1 + s.boostPct / 100
        if s.boostIncluded then
            factor = wantBoost and 1 or 1 / gain
        else
            factor = wantBoost and gain or 1
        end
    end
    local factorChanged = math.abs(factor - (s.torqueFactor or 1)) > 0.0005
    if (wantBoost ~= s.boostApplied or factorChanged) and ((s.boostCooldown or 0) <= 0 or not boostOn) then
        s.boostApplied = wantBoost
        if factorChanged then
            s.torqueFactor = factor
            s.boostCooldown = FlowDrive.BOOST_MIN_INTERVAL
            local motorized = vehicle.spec_motorized
            if vehicle.updateMotorProperties ~= nil and motorized ~= nil and motorized.motorizedNode ~= nil and motorized.motorizedNode ~= 0 then
                pcall(vehicle.updateMotorProperties, vehicle)
            end
        end
    end
end

-- 0.8.0 : rampe de base (auto ou choisie), avant la limite moteur froid
function FlowDriveSpec.getBaseRamp(s)
    if s.ramp == FlowDrive.RAMP_AUTO then
        return s.rampAuto or FlowDrive.DEFAULT_RAMP
    end
    return s.ramp
end

-- Libelle de la rampe pour l'affichage : "3" ou "auto 3"
function FlowDriveSpec.getRampLabel(s)
    local value = s.rampEff or FlowDriveSpec.getBaseRamp(s)
    if s.ramp == FlowDrive.RAMP_AUTO then
        return FlowDrive.tf("fd_ramp_autoShort", value)
    end
    return tostring(value)
end

------------------------------------------------------------------------------------------
-- Loi de conduite
------------------------------------------------------------------------------------------

function FlowDriveSpec:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local s = self.spec_flowDrive
    local motorized = self.spec_motorized
    if s == nil or motorized == nil or motorized.motor == nil then
        return
    end
    local motor = motorized.motor

    s.boostCooldown = math.max((s.boostCooldown or 0) - dt, 0)
    s.scanTimer = s.scanTimer - dt
    if s.scanTimer <= 0 then
        s.scanTimer = SCAN_INTERVAL
        scan(self, s)
    end
    -- 0.1.4 : frein pied leve selon la rampe. Ecrit seulement quand la rampe ou l'etat change.
    if motor.lowBrakeForceScale ~= nil then
        if s.originalBrakeScale == nil then
            s.originalBrakeScale = motor.lowBrakeForceScale
            local base = motor.lowBrakeForceScale
            -- EngineBrakeforceCompensation multiplie celui des CVT par 2,9 : on repart de la valeur d'origine
            if g_modIsLoaded ~= nil and g_modIsLoaded["FS25_EngineBrakeforceCompensation"] and base >= 0.25 then
                base = base / 2.9
            end
            s.baseBrakeScale = base
        end
        local wanted = s.originalBrakeScale
        if s.active then
            local rampEntry = FlowDrive.RAMPS[s.rampEff or s.ramp] or FlowDrive.RAMPS[FlowDrive.DEFAULT_RAMP]
            wanted = clamp(s.baseBrakeScale * (rampEntry.brakeFactor or 1) * (s.brakeMassFactor or 1) * getProfile(s).brakeMult, 0, 1)
        end
        -- ecrit seulement si la valeur change vraiment (rampe, etat, ou masse attelee)
        if s.appliedBrakeScale == nil or math.abs(wanted - s.appliedBrakeScale) > 0.002 then
            s.appliedBrakeScale = wanted
            motor.lowBrakeForceScale = wanted
        end
    end
    -- 0.2.1 : PdF eco. Le jeu impose le regime de PdF directement dans VehicleMotor:update
    -- (PowerConsumer.getMaxPtoRpm x ptoMotorRpmRatio), sans passer par getRequiredMotorRpmRange.
    -- On change donc ce rapport moteur/PdF, comme le boitier 540E/1000E d'un vrai tracteur.
    if type(motor.ptoMotorRpmRatio) == "number" then
        if s.basePtoRatio == nil then
            s.basePtoRatio = motor.ptoMotorRpmRatio
        end
        local wantedRatio = s.basePtoRatio
        if s.active and s.ptoEco then
            wantedRatio = s.basePtoRatio * FlowDrive.PTO_ECO_FACTOR
        end
        if motor.ptoMotorRpmRatio ~= wantedRatio then
            motor.ptoMotorRpmRatio = wantedRatio
        end
    end

    -- 0.5.0 : temperatures, prechauffage, moteur froid (avant le reste : le moteur peut etre arrete)
    local motorOn = self.getIsMotorStarted ~= nil and self:getIsMotorStarted()
    if s.coldTest then
        if s.coldTestTemp == nil then
            s.coldTestTemp = FlowDrive.COLDTEST_AMBIENT
        end
        if motorOn then
            local loadNow = clamp(safeCall(self, "getMotorLoadPercentage") or 0, 0, 1)
            s.coldTestTemp = math.min(90, s.coldTestTemp + FlowDrive.COLDTEST_WARM_RATE * (0.3 + loadNow) * dt / 1000)
        else
            s.coldTestTemp = math.max(FlowDrive.COLDTEST_AMBIENT, s.coldTestTemp - 0.05 * dt / 1000)
        end
    end
    s.ambientTemp = FlowDriveSpec.getAmbientTemperature(s)
    s.engineTemp = FlowDriveSpec.getEngineTemperature(self, s)
    if motorOn then
        s.wasMotorOn = true
        s.preheatDone = true
        s.preheatTimer = 0
    else
        -- moteur coupe : au prochain demarrage, nouveau prechauffage s'il fait froid et si le moteur
        -- est retombe sous PREHEAT_ENGINE_MAX (updatePreheatNeed le verifie)
        if s.wasMotorOn then
            s.wasMotorOn = false
            s.preheatDone = false
        end
        if s.preheatTimer > 0 then
            if not isPlayerControlled(self) then
                -- le joueur est descendu : prechauffage abandonne
                s.preheatTimer = 0
                s.startRequested = false
            else
                s.preheatTimer = s.preheatTimer - dt
                if s.preheatTimer <= 0 then
                    s.preheatTimer = 0
                    s.preheatDone = true
                    if s.startRequested and self.startMotor ~= nil then
                        notify(FlowDrive.t("fd_msg_preheatDoneStart"))
                        pcall(self.startMotor, self)
                    else
                        notify(FlowDrive.t("fd_msg_preheatDone"))
                    end
                    s.startRequested = false
                end
            end
        end
    end
    -- moteur froid : seuil d'ADS s'il est la, avec un peu d'hysteresis
    local coldLimit = self.spec_AdvancedDamageSystem ~= nil and FlowDrive.COLD_TEMP_ADS or FlowDrive.COLD_TEMP_DEFAULT
    if s.engineTemp ~= nil and FlowDrive.settings.coldProtect then
        if s.cold and s.engineTemp >= coldLimit + FlowDrive.COLD_HYSTERESIS then
            s.cold = false
            if motorOn and s.active then
                notify(FlowDrive.t("fd_msg_warm"))
            end
        elseif not s.cold and s.engineTemp < coldLimit then
            s.cold = true
            s.coldNotified = false
        end
    else
        s.cold = false
    end
    s.coldLimit = coldLimit
    local baseRamp = FlowDriveSpec.getBaseRamp(s)
    s.rampEff = s.cold and math.min(baseRamp, FlowDrive.COLD_MAX_RAMP) or baseRamp
    s.coldCap = nil
    if s.cold and s.ratedRpm ~= nil and s.idleRpm ~= nil then
        s.coldCap = math.max(s.ratedRpm * FlowDrive.COLD_RPM_SHARE, s.idleRpm + 200)
    end
    FlowDriveSpec.updateDbl(self, s)
    if s.cold and motorOn and s.active and not s.coldNotified then
        s.coldNotified = true
        notify(FlowDrive.tf("fd_msg_cold", math.floor((s.engineTemp or 0) + 0.5), math.floor((s.coldCap or 0) + 0.5),
            coldLimit + FlowDrive.COLD_HYSTERESIS))
    end

    if not s.active or (self.getIsMotorStarted ~= nil and not self:getIsMotorStarted()) then
        s.rpmCap = nil
        s.overrunMinRpm = nil
        s.fixedRpm = nil
        s.extraMinRpm = nil
        s.inchMinRatio = nil
        s.inchSpeed = nil
        s.hydLevel = 0
        s.flowMinRatio = nil
        s.flowSpeed = nil
        s.flowLimited = false
        s.mode = s.active and "moteur arrete" or "inactif"
        FlowDriveSpec.updateDisplay(self, s, motor, dt, nil)
        return
    end

    -- Mesures
    local speed = safeCall(self, "getLastSpeed") or 0
    local rpm = safeCall(motor, "getLastModulatedMotorRpm") or motor.lastMotorRpm or 0
    local load = clamp(safeCall(self, "getMotorLoadPercentage") or 0, 0, 1)
    local pedal = motor.lastAcceleratorPedal or 0
    local rated, idle = s.ratedRpm or motor.maxRpm, s.idleRpm or motor.minRpm

    s.loadSmooth = s.loadSmooth + (load - s.loadSmooth) * math.min(1, dt / 300)
    local speedMs = speed / 3.6
    if s.lastSpeed ~= nil and dt > 0 then
        local accel = (speedMs - s.lastSpeed) / (dt / 1000)
        s.accelSmooth = s.accelSmooth + (accel - s.accelSmooth) * math.min(1, dt / 400)
    end
    s.lastSpeed = speedMs

    -- Calibrage de la constante de vitesse, sur route et sans forte charge
    local gearRatio = motor.gearRatio
    if speed > 8 and type(gearRatio) == "number" and gearRatio > 0 and rpm > 0 and s.work == "transport" and s.loadSmooth < 0.85 then
        local kNow = speed * gearRatio / rpm
        if kNow > 0.1 and kNow < 1.5 then
            s.k = s.k + (kNow - s.k) * math.min(1, dt / 5000)
            s.kCalibrated = true
        end
    end

    -- Gamme
    s.rangeActive = s.range == FlowDrive.RANGE_FIELD and FlowDrive.RANGE_FIELD or FlowDrive.RANGE_ROAD
    -- 0.4.0 : moissonneuse en gamme auto : gamme recolte des que la machine est en marche
    if s.range == FlowDrive.RANGE_AUTO and getProfile(s).autoField and s.turnedOn then
        s.rangeActive = FlowDrive.RANGE_FIELD
    end
    s.fieldMinRatio = (s.k ~= nil and s.fieldSpeed ~= nil and s.fieldSpeed > 0) and s.k * rated / s.fieldSpeed or nil

    -- Vitesse visee : vitesse maxi de la gamme, ou celle du regulateur
    local targetSpeed = s.rangeActive == FlowDrive.RANGE_FIELD and s.fieldSpeed or s.vmax
    local cruiseState = safeCall(self, "getCruiseControlState") or 0
    if cruiseState ~= 0 then
        local cruiseSpeed = safeCall(self, "getCruiseControlSpeed")
        if type(cruiseSpeed) == "number" and cruiseSpeed > 0 then
            targetSpeed = math.min(targetSpeed, cruiseSpeed)
        end
    end
    s.targetSpeed = targetSpeed
    local wantsMore = pedal > 0.85 and speed < targetSpeed - 1.5

    -- 0.3.0 : regime hydraulique. Un verin qui bouge (ou l'automotrice en marche) fait monter le regime,
    -- tenu HYD_HOLD ms apres le mouvement, puis il redescend sur HYD_FALL ms.
    s.hydCommand = FlowDrive.settings.hydraulic and getHydraulicCommand(self) or 0
    if s.hydCommand > FlowDrive.HYD_COMMAND_MIN then
        s.hydLevel = 1
        s.hydHold = FlowDrive.HYD_HOLD
    elseif s.hydHold > 0 then
        s.hydHold = s.hydHold - dt
    else
        s.hydLevel = math.max(0, s.hydLevel - dt / FlowDrive.HYD_FALL)
    end
    local hydFloor = nil
    if s.hydLevel > 0 and s.hydRpm ~= nil then
        hydFloor = idle + (s.hydRpm - idle) * s.hydLevel
    end
    -- 0.4.0 : machine en marche (melange, battage) : regime de travail du profil, sauf si une PdF
    -- impose deja son regime (Oxbo 6030 : la PdF definie par le constructeur reste prioritaire)
    local turnOnFloor = nil
    if FlowDrive.settings.hydraulic and s.turnedOn and s.work ~= "pto" and s.turnOnRpm ~= nil then
        turnOnFloor = s.turnOnRpm
    end

    -- 0.3.0 : approche lente (touche tenue) : la vitesse maxi baisse de INCH_RATE km/h par seconde,
    -- le regime reste celui du debut de l'approche (pour garder un hydraulique rapide)
    s.inchMinRatio = nil
    if s.inchHeld and s.k ~= nil and s.k > 0 then
        if s.inchSpeed == nil then
            s.inchSpeed = math.max(speed, FlowDrive.INCH_MIN_SPEED)
            s.inchRpm = clamp(math.max(rpm, hydFloor or 0), idle, rated)
        end
        s.inchSpeed = math.max(FlowDrive.INCH_MIN_SPEED, s.inchSpeed - FlowDrive.INCH_RATE * dt / 1000)
        s.inchMinRatio = s.k * s.inchRpm / s.inchSpeed
    else
        s.inchSpeed = nil
        s.inchRpm = nil
    end
    s.extraMinRpm = hydFloor
    if turnOnFloor ~= nil then
        s.extraMinRpm = math.max(s.extraMinRpm or 0, turnOnFloor)
    end
    if s.inchRpm ~= nil then
        s.extraMinRpm = math.max(s.extraMinRpm or 0, s.inchRpm)
    end

    -- 0.4.0 : regulation de debit (moissonneuse en marche) : la vitesse visee baisse quand la charge
    -- moteur depasse FLOW_LOAD_HIGH, remonte sous FLOW_LOAD_LOW, sans depasser la consigne
    -- (vitesse du regulateur, ou maxi de la gamme). Appliquee par le rapport mini (comme l'approche lente).
    s.flowLoad = s.flowLoad + (load - s.flowLoad) * math.min(1, dt / FlowDrive.FLOW_LOAD_TIME)
    s.flowMinRatio = nil
    if s.profile == "harvester" and s.flowEnabled and s.turnedOn and s.k ~= nil and s.k > 0 then
        local setpoint = targetSpeed
        -- flowSpeed = vitesse maxi imposee par la regulation. 0.4.1 : elle ne bride QUE apres une vraie
        -- surcharge (flowLimited). Avant, un changement de consigne (regulateur monte ou coupe) etait pris
        -- pour une bride et la vitesse ne remontait qu'a 0,4 km/h par seconde.
        if not s.flowLimited or s.flowSpeed == nil then
            s.flowSpeed = setpoint
        end
        if s.flowLoad > FlowDrive.FLOW_LOAD_HIGH and speed > FlowDrive.FLOW_MIN_SPEED then
            -- reagit tout de suite : part de la vitesse reelle, pas d'une consigne plus haute
            s.flowLimited = true
            s.flowSpeed = math.min(s.flowSpeed, speed + 0.5) - FlowDrive.FLOW_DOWN_RATE * dt / 1000
        elseif s.flowLimited and s.flowLoad < FlowDrive.FLOW_LOAD_LOW then
            s.flowSpeed = s.flowSpeed + FlowDrive.FLOW_UP_RATE * dt / 1000
        end
        s.flowSpeed = clamp(s.flowSpeed, FlowDrive.FLOW_MIN_SPEED, math.max(FlowDrive.FLOW_MIN_SPEED, setpoint))
        if s.flowLimited and s.flowSpeed >= setpoint - 0.2 then
            s.flowLimited = false
        end
        if s.flowLimited then
            s.flowMinRatio = s.k * clamp(rpm, idle, rated) / s.flowSpeed
        end
    else
        s.flowSpeed = nil
        s.flowLimited = false
    end

    -- 0.5.0 : consommation reelle (l/h) : baisse du niveau de gasoil sur FUEL_WINDOW ms.
    -- (lastFuelUsage du jeu a des pics : le jeu retire le gasoil par paquets)
    local consumers = motorized.consumersByFillTypeName
    local diesel = type(consumers) == "table" and consumers.DIESEL or nil
    if diesel ~= nil and diesel.fillUnitIndex ~= nil then
        local level = safeCall(self, "getFillUnitFillLevel", diesel.fillUnitIndex)
        -- 0.6.1 : le jeu cumule la consommation dans consumer.fillLevelToChange avant de la retirer
        -- du reservoir par paquets : on la compte tout de suite (niveau "reel")
        if type(level) == "number" and type(diesel.fillLevelToChange) == "number" then
            level = level - math.abs(diesel.fillLevelToChange)
        end
        -- 0.6.1 : avec le niveau "reel" (paquets en attente compris), une simple fenetre de
        -- FUEL_WINDOW ms suffit : consommation = baisse du niveau / temps.
        if type(level) == "number" then
            if s.fuelRefLevel == nil or level > s.fuelRefLevel + 0.5 then
                -- debut de mesure, ou plein refait
                s.fuelRefLevel = level
                s.fuelWinTime = 0
            else
                s.fuelWinTime = s.fuelWinTime + dt
                if s.fuelWinTime >= FlowDrive.FUEL_WINDOW then
                    s.fuelSmooth = math.max(0, s.fuelRefLevel - level) / (s.fuelWinTime / 3600000)
                    s.fuelRefLevel = level
                    s.fuelWinTime = 0
                end
            end
        end
    end

    -- Limite de charge : pleine charge prolongee sans accelerer
    if s.loadSmooth > FlowDrive.DROOP_LOAD_ON and s.accelSmooth < 0.1 and speed > 1 then
        s.droopTimer = s.droopTimer + dt
    elseif s.loadSmooth < FlowDrive.DROOP_LOAD_OFF or s.accelSmooth > 0.3 then
        s.droopTimer = 0
    end
    s.droopActive = s.droopTimer > FlowDrive.DROOP_DELAY

    -- Regime maxi autorise
    local ecoMin = idle + (rated - idle) * FlowDrive.ECO_MIN_SHARE
    local target
    s.overrunMinRpm = nil
    s.fixedRpm = nil
    if s.memory > 0 and s.memRpm[s.memory] ~= nil then
        -- 0.2.0 : regime memorise (accelerateur a main) : le moteur tient ce regime,
        -- la vitesse se regle au regulateur ou a la pedale, par le rapport
        s.fixedRpm = clamp(s.memRpm[s.memory], idle, rated)
        target = s.fixedRpm
        s.mode = "regime memorise " .. tostring(s.memory)
    elseif s.work == "pto" then
        -- 0.2.0 : le moteur tient le regime de PdF (normal ou eco) ; sous la charge, c'est l'avancement qui cede
        -- 0.2.1 : requiredMinRpm est deja le regime eco (rapport PdF modifie plus haut)
        local ptoRpm = s.requiredMinRpm or rated
        target = clamp(ptoRpm * FlowDrive.PTO_RPM_MARGIN, idle, rated)
        s.mode = s.ptoEco and "prise de force eco" or "prise de force"
    elseif pedal < 0.05 then
        target = ecoMin
        s.mode = "pied leve"
        -- 0.1.3 : frein moteur selon la rampe, par un regime mini que la boite doit tenir
        local rampEntry = FlowDrive.RAMPS[s.rampEff or s.ramp] or FlowDrive.RAMPS[FlowDrive.DEFAULT_RAMP]
        local share = rampEntry.overrunRpmShare or 0
        if share > 0 and speed > FlowDrive.OVERRUN_MIN_SPEED then
            s.overrunMinRpm = idle + (rated - idle) * share
            target = math.max(target, s.overrunMinRpm)
        end
    elseif s.droopActive then
        local droop = FlowDrive.DROOP[s.work] or FlowDrive.DROOP.transport
        target = math.max(rated * (1 - droop), s.droopFloorRpm or s.peakTorqueRpm or 0, ecoMin)
        s.mode = "limite de charge"
    elseif wantsMore then
        -- 0.1.1 : le regime monte selon le besoin reel (rampe douce = regime bas)
        -- 0.1.2 : avec un regime mini par rampe (rampe 4 = regime nominal, comme en 0.1.0)
        local rampEntry = FlowDrive.RAMPS[s.rampEff or s.ramp] or FlowDrive.RAMPS[FlowDrive.DEFAULT_RAMP]
        local rampRpm = idle + (rated - idle) * (rampEntry.accelRpmShare or 1)
        target = clamp(math.max(rpm * s.loadSmooth / FlowDrive.ACCEL_TARGET_LOAD, rampRpm), ecoMin, rated)
        s.mode = "acceleration"
    else
        target = clamp(rpm * s.loadSmooth / FlowDrive.ECO_TARGET_LOAD, ecoMin, rated)
        s.mode = "eco"
    end
    -- 0.1.1 : jamais sous le regime necessaire pour tenir la vitesse au rapport mini autorise
    if s.work ~= "pto" and s.k ~= nil and s.k > 0 and type(s.ratioIn) == "number" and s.ratioIn > 0 then
        local minRatio = s.ratioIn
        if s.rangeActive == FlowDrive.RANGE_FIELD and s.fieldMinRatio ~= nil then
            minRatio = math.max(minRatio or 0, s.fieldMinRatio)
        end
        if type(minRatio) == "number" and minRatio > 0 then
            local rpmNeeded = speed * minRatio / s.k * FlowDrive.RPM_FLOOR_MARGIN
            target = math.max(target, math.min(rpmNeeded, rated))
        end
    end
    -- 0.3.0 : le plafond ne descend jamais sous le regime hydraulique ou d'approche
    if s.extraMinRpm ~= nil and s.extraMinRpm > target then
        target = math.min(s.extraMinRpm, rated)
        if s.inchRpm ~= nil then
            s.mode = s.mode .. " + approche"
        elseif turnOnFloor ~= nil and turnOnFloor >= (hydFloor or 0) then
            s.mode = s.mode .. " + en marche"
        else
            s.mode = s.mode .. " + hydraulique"
        end
    end
    if s.flowMinRatio ~= nil then
        s.mode = s.mode .. " + debit"
    end
    -- 0.5.0 : moteur froid : plafond de regime, y compris pour les regimes hydraulique, memorise, d'approche
    -- (le regime de PdF reste impose par le jeu et l'outil)
    if s.coldCap ~= nil then
        if target > s.coldCap then
            target = s.coldCap
            s.mode = s.mode .. " + froid"
        end
        if s.extraMinRpm ~= nil then
            s.extraMinRpm = math.min(s.extraMinRpm, s.coldCap)
        end
        if s.fixedRpm ~= nil then
            s.fixedRpm = math.min(s.fixedRpm, s.coldCap)
        end
    end
    -- 0.3.1 : boite au neutre (vehicule pas encore parti depuis qu'on est monte) : le jeu ignore alors le
    -- regime mini demande et prend max(lastPtoRpm, minRpm) (VehicleMotor:update). On releve donc aussi
    -- lastPtoRpm, comme le fait une prise de force ; le jeu le fait redescendre seul ensuite.
    local holdRpm = math.max(s.extraMinRpm or 0, s.fixedRpm or 0)
    if holdRpm > idle + 50 and type(motor.lastPtoRpm) == "number" and motor.lastPtoRpm < holdRpm then
        motor.lastPtoRpm = math.min(holdRpm, rated)
    end
    if s.rpmCap == nil then
        s.rpmCap = rated
    end
    local tau = target > s.rpmCap and FlowDrive.CAP_RISE_TIME or FlowDrive.CAP_FALL_TIME
    s.rpmCap = s.rpmCap + (target - s.rpmCap) * math.min(1, dt / tau)

    FlowDriveSpec.updateDisplay(self, s, motor, dt, {speed = speed, rpm = rpm, pedal = pedal, gearRatio = gearRatio, ecoMin = ecoMin})
end

------------------------------------------------------------------------------------------
-- Panneau de reglage et journal
------------------------------------------------------------------------------------------

function FlowDriveSpec.updateDisplay(vehicle, s, motor, dt, m)
    if not s.debug then
        return
    end
    local ramp = FlowDrive.RAMPS[s.rampEff or FlowDriveSpec.getBaseRamp(s)] or FlowDrive.RAMPS[FlowDrive.DEFAULT_RAMP]
    local status = s.active and "actif" or ("inactif" .. (s.reason ~= "" and (" : " .. s.reason) or (s.enabled and "" or " (coupe a la main)")))
    s.displayLines = {
        string.format("FlowDrive %s - %s", FlowDrive.VERSION, status),
        string.format("profil %s   rampe %s (%s m/s2)   gamme %s -> %s (%s %s km/h)   travail : %s",
            getProfile(s).label, FlowDriveSpec.getRampLabel(s), num(ramp.accel, 1), rangeName(s, s.range), rangeName(s, s.rangeActive),
            getProfile(s).fieldName, num(s.fieldSpeed), FlowDrive.WORK_NAMES[s.work] or s.work)
    }
    if m ~= nil then
        table.insert(s.displayLines, string.format("mode %s   regime %s / plafond %s (nominal %s, eco mini %s, couple maxi %s)",
            s.mode, num(m.rpm), num(s.rpmCap), num(s.ratedRpm), num(m.ecoMin), num(s.peakTorqueRpm)))
        table.insert(s.displayLines, string.format("vitesse %s / visee %s km/h   accel %s m/s2   charge %s %%   pedale %s",
            num(m.speed, 1), num(s.targetSpeed, 1), num(s.accelSmooth, 2), num(s.loadSmooth * 100), num(m.pedal, 2)))
        table.insert(s.displayLines, string.format("rapport %s (mini jeu %s, mini champ %s)   k %s %s   frein moteur %s",
            num(m.gearRatio, 2), num(s.ratioIn, 2), num(s.fieldMinRatio, 1), num(s.k, 3), s.kCalibrated and "calibre" or "estime",
            num(motor.lowBrakeForceScale, 3)))
        table.insert(s.displayLines, string.format("PdF eco %s (PdF demande %s tr/min)   memoire %s (M1 %s, M2 %s)   boost %s%s",
            s.ptoEco and "oui" or "non", num(s.requiredMinRpm), s.memory > 0 and tostring(s.memory) or "non",
            num(s.memRpm[1]), num(s.memRpm[2]),
            s.boostEnabled and string.format("%d %% %s, couple x%.3f", s.boostPct or 0, s.boostIncluded and "inclus" or "en plus", s.torqueFactor or 1) or "coupe",
            s.boostApplied and " (ACTIF)" or ""))
        table.insert(s.displayLines, string.format("hydraulique %s (commande %s, regime %s)   approche %s   conso %s l/h",
            s.hydLevel > 0 and "ACTIF" or "repos", num(s.hydCommand, 2), num(s.hydRpm),
            s.inchSpeed ~= nil and (num(s.inchSpeed, 1) .. " km/h") or "non", num(s.fuelSmooth, 1)))
        table.insert(s.displayLines, string.format("moteur %s degres (%s)   air %s degres   froid %s (seuil %s, plafond %s tr/min, rampe maxi %d)%s",
            num(s.engineTemp, 1), s.engineTempSource, num(s.ambientTemp, 1), s.cold and "OUI" or "non", num(s.coldLimit),
            num(s.coldCap), FlowDrive.COLD_MAX_RAMP, s.coldTest and "   ESSAI FROID" or ""))
        if s.profile == "harvester" then
            table.insert(s.displayLines, string.format("machine %s (regime travail %s)   debit auto %s   charge %s %%   vitesse visee %s km/h%s",
                s.turnedOn and "en marche" or "arretee", num(s.turnOnRpm), s.flowEnabled and "oui" or "non",
                num(s.flowLoad * 100), num(s.flowSpeed, 1), s.flowMinRatio ~= nil and " (BRIDE)" or ""))
        end
    else
        table.insert(s.displayLines, "mode " .. tostring(s.mode))
    end

    s.logTimer = s.logTimer - dt
    if s.logTimer <= 0 and m ~= nil then
        s.logTimer = LOG_INTERVAL
        local powerShare = getPowerShare(vehicle, s, s.rpmCap)
        print(string.format("[FlowDrive] %s | R%s%s %s/%s %s | mode=%s v=%s/%s a=%s rpm=%s cap=%s load=%s ped=%s ratio=%s k=%s brake=%s pw=%s",
            tostring(safeCall(vehicle, "getFullName") or "?"), tostring(s.rampEff or FlowDriveSpec.getBaseRamp(s)),
            s.ramp == FlowDrive.RAMP_AUTO and "a" or "", rangeName(s, s.range),
            rangeName(s, s.rangeActive), s.work, s.mode, num(m.speed, 1), num(s.targetSpeed, 1),
            num(s.accelSmooth, 2), num(m.rpm), num(s.rpmCap), num(s.loadSmooth * 100), num(m.pedal, 2),
            num(m.gearRatio, 2), num(s.k, 3), num(motor.lowBrakeForceScale, 3),
            num(type(powerShare) == "number" and powerShare * 100 or nil)) .. " ovr=" .. num(s.overrunMinRpm)
            .. string.format(" ptoReq=%s eco=%d mem=%d fix=%s boost=%d tq=%.3f mass=%s", num(s.requiredMinRpm), s.ptoEco and 1 or 0,
                s.memory, num(s.fixedRpm), s.boostApplied and 1 or 0, s.torqueFactor or 1, num(s.rampAutoMass, 2))
            .. string.format(" prof=%s hyd=%s cmd=%s floor=%s inch=%s fuel=%s", s.profile, num(s.hydLevel, 2),
                num(s.hydCommand, 2), num(s.extraMinRpm), num(s.inchSpeed, 1), num(s.fuelSmooth, 1))
            .. string.format(" neutre=%s lastPto=%s", tostring(safeCall(motor, "getIsInNeutral")), num(motor.lastPtoRpm))
            .. string.format(" on=%d flow=%d fload=%s fspd=%s", s.turnedOn and 1 or 0, s.flowEnabled and 1 or 0,
                num(s.flowLoad * 100), num(s.flowSpeed, 1))
            .. string.format(" eng=%s src=%s air=%s cold=%d ccap=%s reff=%s test=%d", num(s.engineTemp, 1), s.engineTempSource,
                num(s.ambientTemp, 1), s.cold and 1 or 0, num(s.coldCap), tostring(s.rampEff), s.coldTest and 1 or 0))
    end
end

function FlowDriveSpec:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    -- 0.6.0 : affichage FlowDrive (reglage general)
    if FlowDrive.settings.hud and isActiveForInputIgnoreSelection then
        FlowDriveSpec.drawHud(self, s)
    end
    -- 0.5.0 : voyant de prechauffage, toujours visible
    if s.preheatTimer > 0 then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(1, 0.6, 0.1, 1)
        renderText(0.5, 0.2, 0.022, string.format("PRECHAUFFAGE  %d s", math.ceil(s.preheatTimer / 1000)))
        setTextBold(false)
        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
    end
    if not s.debug or #s.displayLines == 0 then
        return
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    local x, y, size, step = 0.55, 0.62, 0.013, 0.017
    for index, line in ipairs(s.displayLines) do
        renderText(x, y - (index - 1) * step, size, line)
    end
    setTextColor(1, 1, 1, 1)
end

------------------------------------------------------------------------------------------
-- Touches (provisoires jusqu'au menu de l'etape 6)
------------------------------------------------------------------------------------------

function FlowDriveSpec:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    self:clearActionEventsTable(s.actionEvents)
    s.inchHeld = false
    if not isActiveForInputIgnoreSelection then
        return
    end
    local actions = {
        {"FLOWDRIVE_MENU", FlowDriveSpec.actionMenu},
        {"FLOWDRIVE_TOGGLE", FlowDriveSpec.actionToggle},
        {"FLOWDRIVE_RAMP", FlowDriveSpec.actionRamp},
        {"FLOWDRIVE_RANGE", FlowDriveSpec.actionRange},
        {"FLOWDRIVE_DEBUG", FlowDriveSpec.actionDebug},
        {"FLOWDRIVE_PTO_ECO", FlowDriveSpec.actionPtoEco},
        {"FLOWDRIVE_MEMORY", FlowDriveSpec.actionMemory},
        {"FLOWDRIVE_RPM_UP", FlowDriveSpec.actionRpmUp},
        {"FLOWDRIVE_RPM_DOWN", FlowDriveSpec.actionRpmDown},
        {"FLOWDRIVE_BOOST", FlowDriveSpec.actionBoost},
        {"FLOWDRIVE_FLOW", FlowDriveSpec.actionFlow},
        {"FLOWDRIVE_COLDTEST", FlowDriveSpec.actionColdTest}
    }
    for _, entry in ipairs(actions) do
        local _, actionEventId = self:addActionEvent(s.actionEvents, entry[1], self, entry[2], false, true, false, true, nil)
        local priority = GS_PRIO_VERY_LOW or GS_PRIO_LOW
        if actionEventId ~= nil and priority ~= nil then
            g_inputBinding:setActionEventTextPriority(actionEventId, priority)
        end
    end
    -- 0.3.0 : approche lente, touche tenue (appel a l'appui et au relachement), sans raccourci par defaut
    local _, inchEventId = self:addActionEvent(s.actionEvents, "FLOWDRIVE_INCHING", self, FlowDriveSpec.actionInching, true, true, false, true, nil)
    if inchEventId ~= nil then
        g_inputBinding:setActionEventTextVisibility(inchEventId, false)
    end
end

-- 0.5.0 : essai froid (touche provisoire, pour tester sans attendre l'hiver) : air a -15 degres,
-- moteur simule froid qui chauffe en roulant. Le prechauffage se declenche au prochain demarrage.
function FlowDriveSpec.actionColdTest(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    s.coldTest = not s.coldTest
    s.coldTestTemp = nil
    s.preheatDone = false
    s.preheatTimer = 0
    if s.coldTest then
        local motorOn = self.getIsMotorStarted ~= nil and self:getIsMotorStarted()
        notify(FlowDrive.t(motorOn and "fd_msg_coldTestRunning" or "fd_msg_coldTestOn"))
    else
        notify(FlowDrive.t("fd_msg_coldTestOff"))
    end
end

function FlowDriveSpec.actionFlow(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    if s.profile ~= "harvester" then
        notify(FlowDrive.t("fd_msg_flowOnlyHarvester"))
        return
    end
    s.flowEnabled = not s.flowEnabled
    notify(FlowDrive.t(s.flowEnabled and "fd_msg_flowOn" or "fd_msg_flowOff"))
end

function FlowDriveSpec.actionInching(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    s.inchHeld = (inputValue or 0) > 0
end

-- 0.7.0 : changement de gamme refuse au-dessus de RANGE_CHANGE_MAX_SPEED (avec un message)
function FlowDriveSpec.canChangeRange(vehicle, s)
    local speed = safeCall(vehicle, "getLastSpeed") or 0
    if speed > FlowDrive.RANGE_CHANGE_MAX_SPEED then
        notify(FlowDrive.tf("fd_msg_rangeRefused", FlowDrive.RANGE_CHANGE_MAX_SPEED))
        return false
    end
    return true
end

-- 0.6.0 : menu de reglages
function FlowDriveSpec.actionMenu(self, actionName, inputValue, callbackState, isAnalog)
    if self.spec_flowDrive ~= nil and FlowDriveMenu ~= nil and FlowDriveMenu.show ~= nil then
        scan(self, self.spec_flowDrive)
        FlowDriveMenu.show(self)
    end
end

-- Appele par le menu apres OK
function FlowDriveSpec.onSettingsChanged(vehicle)
    local s = vehicle.spec_flowDrive
    if s == nil then
        return
    end
    s.rpmCap = nil
    s.preheatDone = s.preheatDone or not FlowDrive.settings.preheat
    scan(vehicle, s)
end

function FlowDriveSpec.actionToggle(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    if not s.eligible then
        notify(FlowDrive.tf("fd_msg_notAvailable", FlowDriveSpec.getReasonText(s)))
        return
    end
    s.enabled = not s.enabled
    scan(self, s)
    notify(FlowDrive.t(s.enabled and "fd_msg_on" or "fd_msg_off"))
end

function FlowDriveSpec.actionRamp(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    -- 0.8.0 : auto -> 1 -> 2 -> 3 -> 4 -> auto
    s.ramp = (s.ramp + 1) % (#FlowDrive.RAMPS + 1)
    if s.ramp == FlowDrive.RAMP_AUTO then
        notify(FlowDrive.t("fd_msg_rampAuto"))
    else
        local ramp = FlowDrive.RAMPS[s.ramp]
        notify(FlowDrive.tf("fd_msg_ramp", s.ramp, num(ramp.accel, 1)))
    end
end

function FlowDriveSpec.actionRange(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    if not FlowDriveSpec.canChangeRange(self, s) then
        return
    end
    s.range = (s.range + 1) % 3
    if s.range == FlowDrive.RANGE_FIELD and s.fieldSpeed ~= nil then
        notify(FlowDrive.tf("fd_msg_rangeSpeed", FlowDriveSpec.getRangeLabel(s, s.range), s.fieldSpeed))
    else
        notify(FlowDrive.tf("fd_msg_range", FlowDriveSpec.getRangeLabel(s, s.range)))
    end
end

function FlowDriveSpec.actionDebug(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    s.debug = not s.debug
    s.displayLines = {}
    s.logTimer = 0
    scan(self, s)
    if s.debug then
        print(string.format("[FlowDrive] reglage ouvert : %s | actif=%s eligible=%s (%s) rampe=%d gamme=%s | vmax=%s champ=%s regime %s-%s couple maxi %s plancher limite %s k=%s frein moteur d'origine %s",
            tostring(safeCall(self, "getFullName") or "?"), tostring(s.active), tostring(s.eligible), s.reason, s.ramp,
            rangeName(s, s.range), num(s.vmax, 1), num(s.fieldSpeed),
            num(s.idleRpm), num(s.ratedRpm), num(s.peakTorqueRpm), num(s.droopFloorRpm), num(s.k, 3), num(s.originalBrakeScale, 3)))
        local motorized = self.spec_motorized
        local motor = motorized ~= nil and motorized.motor or nil
        print(string.format("[FlowDrive] etape 2 : PdF eco=%s rapport PdF %s (origine %s) M1=%s M2=%s boost=%s %s %% %s (couple x%.3f) puissance maxi %s ch",
            tostring(s.ptoEco), num(motor ~= nil and motor.ptoMotorRpmRatio or nil, 3), num(s.basePtoRatio, 3),
            num(s.memRpm[1]), num(s.memRpm[2]), tostring(s.boostEnabled), tostring(s.boostPct),
            s.boostIncluded and "inclus" or "en plus", s.torqueFactor or 1,
            num(s.peakPower ~= nil and s.peakPower * math.pi / 30 * 1.3596 or nil)))
        local consumers = motorized ~= nil and motorized.consumersByFillTypeName or nil
        local fuels = {}
        if type(consumers) == "table" then
            for name in pairs(consumers) do
                table.insert(fuels, tostring(name))
            end
            table.sort(fuels)
        end
        print(string.format("[FlowDrive] etape 3 : profil=%s categorie=%s regime hydraulique=%s frein pied leve x%s carburants=%s",
            s.profile, tostring(s.category), num(s.hydRpm), num(getProfile(s).brakeMult, 1),
            #fuels > 0 and table.concat(fuels, ",") or "?"))
        local ptoRpmXml = self.spec_powerConsumer ~= nil and self.spec_powerConsumer.ptoRpm or nil
        print(string.format("[FlowDrive] etape 4 : regime en marche=%s debit auto=%s PdF propre=%s rapports AV %s-%s limite travail=%s",
            num(s.turnOnRpm), tostring(s.flowEnabled), num(ptoRpmXml), num(motor ~= nil and motor.minForwardGearRatio or nil, 1),
            num(motor ~= nil and motor.maxForwardGearRatio or nil, 0), num(self.speedLimit, 1)))
        print(string.format("[FlowDrive] etape 5 : types avec prechauffage=%s sans=%s", tostring(FlowDrive.preheatTypes),
            tostring(FlowDrive.preheatMissing)))
        print(string.format("[FlowDrive] etape 5 : ADS=%s moteur %s degres (%s) air %s degres froid=%s seuil %s plafond %s prechauffage fait=%s auto-demarrage jeu=%s",
            tostring(self.spec_AdvancedDamageSystem ~= nil), num(s.engineTemp, 1), s.engineTempSource, num(s.ambientTemp, 1),
            tostring(s.cold), num(s.coldLimit), num(s.coldCap), tostring(s.preheatDone),
            tostring(g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.automaticMotorStartEnabled)))
    end
end

------------------------------------------------------------------------------------------
-- 0.2.0 : prise de force eco, regime memorise, boost
------------------------------------------------------------------------------------------

function FlowDriveSpec.actionPtoEco(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    s.ptoEco = not s.ptoEco
    notify(FlowDrive.t(s.ptoEco and "fd_msg_ptoEcoOn" or "fd_msg_ptoEcoOff"))
end

function FlowDriveSpec.actionMemory(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    s.memory = (s.memory + 1) % 3
    if s.memory == 0 then
        notify(FlowDrive.t("fd_msg_memOff"))
    else
        notify(FlowDrive.tf("fd_msg_memOn", s.memory, math.floor((s.memRpm[s.memory] or 0) + 0.5)))
    end
end

local function adjustMemory(vehicle, delta)
    local s = vehicle.spec_flowDrive
    if s == nil then
        return
    end
    if s.memory == 0 or s.memRpm[s.memory] == nil then
        notify(FlowDrive.t("fd_msg_memNeed"))
        return
    end
    local minRpm = (s.idleRpm or 800) + 100
    local maxRpm = s.ratedRpm or 2200
    s.memRpm[s.memory] = clamp(s.memRpm[s.memory] + delta, minRpm, maxRpm)
    notify(FlowDrive.tf("fd_msg_memSet", s.memory, math.floor((s.memRpm[s.memory] or 0) + 0.5)))
end

function FlowDriveSpec.actionRpmUp(self, actionName, inputValue, callbackState, isAnalog)
    adjustMemory(self, FlowDrive.MEMORY_STEP)
end

function FlowDriveSpec.actionRpmDown(self, actionName, inputValue, callbackState, isAnalog)
    adjustMemory(self, -FlowDrive.MEMORY_STEP)
end

function FlowDriveSpec.actionBoost(self, actionName, inputValue, callbackState, isAnalog)
    local s = self.spec_flowDrive
    if s == nil then
        return
    end
    s.boostEnabled = not s.boostEnabled
    scan(self, s)
    notify(s.boostEnabled and FlowDrive.tf("fd_msg_boostOn", s.boostPct or FlowDrive.BOOST_DEFAULT_PCT,
        FlowDrive.t(s.boostIncluded and "fd_boost_included" or "fd_boost_added"))
        or FlowDrive.t("fd_msg_boostOff"))
end
