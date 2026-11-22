-- FlowDrive 0.1.0 - etape 1 : CVT moderne, mode pedale
-- Ce fichier : constantes, enregistrement de la specialisation, accroches du moteur.
--
-- Principe : FlowDrive ne reecrit jamais le regime, le rapport ou la charge apres coup.
-- Il repond aux questions que le jeu pose au moteur a chaque image :
--   getMinMaxGearRatio                -> rapports autorises (gamme champ)
--   getAccelerationLimit              -> acceleration maxi (rampe)
--   getMotorRotationAccelerationLimit -> vitesse de montee du regime (rampe)
--   getRequiredMotorRpmRange          -> regime maxi autorise (eco, limite de charge)
-- Chaque accroche appelle d'abord la fonction d'origine (et celles des autres mods, ADS compris),
-- puis ajuste le resultat. Sans FlowDrive actif sur le vehicule, elle ne change rien.

FlowDrive = FlowDrive or {}
FlowDrive.MOD_NAME = g_currentModName
FlowDrive.MOD_DIR = g_currentModDirectory
FlowDrive.VERSION = "1.0.1.0"
FlowDrive.SPEC_NAME = "flowDrive"

-- Rampes : acceleration maxi (m/s2), part de la montee de regime,
-- regime mini en acceleration (part de la plage ralenti-nominal, 0.1.2),
-- regime mini pied leve = frein moteur par raccourcissement du rapport (0.1.3).
-- et frein pied leve (0.1.4) : multiplicateur de lowBrakeForceScale. Le jeu freine pied leve avec
-- brakePedal = lowBrakeForceScale au-dessus de 3,6 km/h (WheelsUtil.updateWheelsPhysics).
-- Mesure 0.1.4 sur le Q305 a vide : ralentissement ~ 0,15 + 4,8 x lowBrakeForceScale (m/s2).
-- Mesure 0.1.5 a vide : 0,05 -> 0,40 m/s2 ; 0,26 -> 1,77 m/s2 (pas tout a fait lineaire).
-- 0.1.6 : facteurs recales sur ces deux points pour 0,4 / 0,7 / 1,0 / 1,4 m/s2 a vide (valeur d'origine 0,10).
FlowDrive.RAMPS = {
    {accel = 0.4, rot = 0.50, accelRpmShare = 0.35, overrunRpmShare = 0.00, brakeFactor = 0.50},
    {accel = 0.8, rot = 0.70, accelRpmShare = 0.50, overrunRpmShare = 0.20, brakeFactor = 1.00},
    {accel = 1.3, rot = 0.85, accelRpmShare = 0.75, overrunRpmShare = 0.35, brakeFactor = 1.40},
    {accel = 2.0, rot = 1.00, accelRpmShare = 1.00, overrunRpmShare = 0.50, brakeFactor = 2.05}
}
-- 0.1.5 : avec une charge attelee, le frein moteur retient moins (racine de masse propre / masse totale)
FlowDrive.BRAKE_MASS_MIN = 0.5
FlowDrive.OVERRUN_MIN_SPEED = 3        -- km/h : sous cette vitesse, plus de frein moteur impose (arret en douceur)
FlowDrive.DEFAULT_RAMP = 3

-- Gammes
FlowDrive.RANGE_AUTO = 0
FlowDrive.RANGE_FIELD = 1
FlowDrive.RANGE_ROAD = 2
FlowDrive.RANGE_NAMES = {[0] = "auto", [1] = "champ", [2] = "route"}
FlowDrive.FIELD_SPEED_SHARE = 0.55     -- gamme champ : 55 % de la vitesse maxi
FlowDrive.RANGE_CHANGE_MAX_SPEED = 10  -- km/h : 0.7.0 : au-dessus, changement de gamme refuse (question 7 : bloquer et avertir)

-- Regime eco et limite de charge
FlowDrive.ECO_TARGET_LOAD = 0.80       -- le regime eco vise une charge moteur de 80 %
FlowDrive.ACCEL_TARGET_LOAD = 0.70     -- en acceleration, le regime monte jusqu'a une charge de 70 % (0.1.1)
FlowDrive.RPM_FLOOR_MARGIN = 1.05      -- plancher : regime necessaire pour tenir la vitesse au rapport mini, + 5 % (0.1.1)
FlowDrive.DROOP_MIN_POWER = 0.90       -- la limite de charge garde au moins 90 % de la puissance maxi (0.1.1)
FlowDrive.ECO_MIN_SHARE = 0.35         -- regime eco mini : ralenti + 35 % de la plage
FlowDrive.CAP_RISE_TIME = 400          -- ms : le regime remonte vite quand on demande
FlowDrive.CAP_FALL_TIME = 2500         -- ms : il redescend doucement
FlowDrive.DROOP_LOAD_ON = 0.93         -- pleine charge
FlowDrive.DROOP_LOAD_OFF = 0.85
FlowDrive.DROOP_DELAY = 1500           -- ms de pleine charge sans accelerer avant la chute de regime
FlowDrive.DROOP = {transport = 0.15, traction = 0.25}

FlowDrive.WORK_NAMES = {transport = "transport", traction = "traction", pto = "prise de force"}

-- 0.2.0 : prise de force eco (540E / 1000E : meme regime de PdF a environ 78 % du regime moteur)
FlowDrive.PTO_ECO_FACTOR = 0.78
FlowDrive.PTO_RPM_MARGIN = 1.03        -- avec la PdF, le regime maxi autorise = regime de PdF + 3 %
-- 0.2.0 : regimes memorises par defaut (part de la plage ralenti-nominal) et pas de reglage
FlowDrive.MEMORY_SHARES = {0.65, 0.90}
FlowDrive.MEMORY_STEP = 50
-- 0.2.0 : boost (type Sigma Power / IPM) en transport et avec la PdF.
-- 0.8.0 : desactive par defaut ; pourcentage saisi par machine (0 a BOOST_MAX_PCT) ;
-- "inclus" : la puissance du jeu est deja celle avec boost (John Deere, Case IH, Valtra, Fendt 728 de base),
-- FlowDrive la retire hors boost. "en plus" : le boost s'ajoute (Massey Ferguson de base).
FlowDrive.BOOST_DEFAULT_PCT = 8
FlowDrive.BOOST_MAX_PCT = 30
FlowDrive.BOOST_SPEED_ON = 16          -- km/h
FlowDrive.BOOST_SPEED_OFF = 12         -- km/h (hysteresis)
FlowDrive.BOOST_MIN_INTERVAL = 1500    -- ms entre deux changements (chaque changement recharge la courbe moteur)

-- 0.8.0 : rampe auto (rampe 0) : 2 au travail ou tres charge, 3 a vide, 4 sur chargeuse
FlowDrive.RAMP_AUTO = 0
FlowDrive.RAMP_AUTO_HEAVY = 2.0        -- masse totale / masse du tracteur au-dela de laquelle on reste en rampe 2
FlowDrive.RAMP_AUTO_HOLD = 2000        -- ms : la situation doit durer avant de changer de rampe

-- 0.3.0 : profils de transmission. cvt = tracteurs ; hst = chargeuses, telescopiques, automotrices.
-- hydShare : regime hydraulique (part de la plage ralenti-nominal) quand un verin bouge
-- brakeMult : frein pied leve (un hydrostatique retient plus fort qu'une CVT de tracteur)
-- fieldShare / fieldName : gamme lente (champ pour un tracteur, travail pour une chargeuse)
-- 0.4.0 : turnOnShare : regime tenu quand la machine elle-meme est en marche (melange, battage) sans regime
-- de PdF defini ; autoField : la gamme auto passe en gamme lente quand la machine est en marche
FlowDrive.PROFILES = {
    cvt = {label = "CVT tracteur", hydShare = 0.50, turnOnShare = 0.50, brakeMult = 1.0, fieldShare = 0.55, fieldName = "champ", autoField = false},
    hst = {label = "HST", hydShare = 0.60, turnOnShare = 0.60, brakeMult = 1.5, fieldShare = 0.50, fieldName = "travail", autoField = false},
    harvester = {label = "moissonneuse", hydShare = 0.60, turnOnShare = 1.00, brakeMult = 1.5, fieldShare = 0.40, fieldName = "recolte", autoField = true}
}
-- 0.4.0 : regulation de debit des moissonneuses (charge moteur lissee sur FLOW_LOAD_TIME ms)
FlowDrive.FLOW_LOAD_HIGH = 0.90        -- au-dessus : la vitesse visee baisse
FlowDrive.FLOW_LOAD_LOW = 0.75         -- en dessous : elle remonte jusqu'a la consigne
FlowDrive.FLOW_DOWN_RATE = 1.0         -- km/h par seconde
FlowDrive.FLOW_UP_RATE = 0.4           -- km/h par seconde
FlowDrive.FLOW_MIN_SPEED = 1.5         -- km/h
FlowDrive.FLOW_LOAD_TIME = 1000        -- ms

-- 0.5.0 : prechauffage automatique a la mise du contact (temperature de l'air, celle du jeu)
FlowDrive.PREHEAT_AMBIENT = 5          -- degres C : en dessous, prechauffage
FlowDrive.PREHEAT_ENGINE_MAX = 30      -- degres C : moteur encore chaud au-dessus, pas de prechauffage
FlowDrive.PREHEAT_MIN = 2000           -- ms (a 5 degres)
FlowDrive.PREHEAT_MAX = 15000          -- ms (vers -20 degres)
FlowDrive.PREHEAT_PER_DEGREE = 520     -- ms par degre sous PREHEAT_AMBIENT
-- 0.5.0 : moteur froid. Seuil 50 degres comme ADS (stable et beta) ; 40 sans ADS.
-- Plafond a 72 % du regime maxi : sous l'alerte moteur froid d'ADS beta (75 %).
FlowDrive.COLD_TEMP_ADS = 50
FlowDrive.COLD_TEMP_DEFAULT = 40
FlowDrive.COLD_HYSTERESIS = 2
FlowDrive.COLD_RPM_SHARE = 0.72
FlowDrive.COLD_MAX_RAMP = 2
-- 0.5.0 : mode essai froid (touche provisoire) : air a -15 degres, moteur simule qui chauffe en roulant
FlowDrive.COLDTEST_AMBIENT = -15
FlowDrive.COLDTEST_WARM_RATE = 0.6     -- degres par seconde a pleine charge
-- 0.5.0 : consommation mesuree sur la baisse du niveau de gasoil
FlowDrive.FUEL_WINDOW = 10000          -- ms

------------------------------------------------------------------------------------------
-- 0.6.0 : textes (l10n/l10n_fr.xml, l10n_en.xml) et reglages generaux (modSettings)
------------------------------------------------------------------------------------------

-- Texte traduit. Les textes d'un mod sont dans son environnement (comme CVT Addon et ADS les lisent).
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

-- Reglages generaux, communs a tous les vehicules et a toutes les parties
FlowDrive.settings = {hydraulic = true, preheat = true, coldProtect = true, hud = true, hudPos = 1, dbl = true}
FlowDrive.SETTINGS_BOOLS = {"hydraulic", "preheat", "coldProtect", "hud", "dbl"}

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
FlowDrive.HST_CATEGORIES = {
    FRONTLOADERVEHICLES = true, TELELOADERVEHICLES = true, SKIDSTEERVEHICLES = true,
    WHEELLOADERVEHICLES = true, FORAGEMIXERS = true, FORKLIFTS = true
}
-- 0.3.0 : regime hydraulique
FlowDrive.HYD_COMMAND_MIN = 0.05       -- commande de verin mini pour compter un mouvement
FlowDrive.HYD_HOLD = 800               -- ms : le regime reste haut apres le mouvement (0.3.1 : 2000 juge trop long)
FlowDrive.HYD_FALL = 1000              -- ms : puis redescend sur cette duree (0.3.1 : 1500 avant)
-- 0.3.0 : approche lente (inching), touche optionnelle sans raccourci par defaut
FlowDrive.INCH_RATE = 5                -- km/h par seconde de touche tenue
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

-- Etat FlowDrive du moteur, ou nil si FlowDrive n'agit pas sur ce vehicule
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
    -- marche avant seulement (rapports positifs)
    if state.fieldMinRatio ~= nil and state.rangeActive == FlowDrive.RANGE_FIELD and minRatio > 0 and maxRatio > minRatio then
        minRatio = math.min(math.max(minRatio, state.fieldMinRatio), maxRatio)
    end
    -- 0.3.0 : approche lente : le rapport s'allonge pour ralentir sans baisser le regime
    if state.inchMinRatio ~= nil and minRatio > 0 and maxRatio > minRatio then
        minRatio = math.min(math.max(minRatio, state.inchMinRatio), maxRatio)
    end
    -- 0.4.0 : regulation de debit : meme principe, la vitesse maxi suit la charge moteur
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
    -- 0.5.0 : rampEff = rampe reellement appliquee (limitee moteur froid)
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
    -- regime impose par la PdF (deja reduit en PdF eco : la spec modifie motor.ptoMotorRpmRatio, 0.2.1)
    state.requiredMinRpm = minRpm
    -- 0.2.0 : regime memorise : le moteur tient ce regime
    if state.fixedRpm ~= nil then
        minRpm = math.max(minRpm, math.min(state.fixedRpm, maxRpm))
    end
    -- 0.3.0 : regime hydraulique (verin en mouvement) et regime tenu en approche lente
    if state.extraMinRpm ~= nil then
        minRpm = math.max(minRpm, math.min(state.extraMinRpm, maxRpm))
    end
    if state.rpmCap ~= nil then
        maxRpm = math.max(minRpm, math.min(maxRpm, state.rpmCap))
    end
    -- 0.1.3 : frein moteur pied leve, la boite raccourcit pour tenir ce regime
    if state.overrunMinRpm ~= nil then
        minRpm = math.max(minRpm, math.min(state.overrunMinRpm, maxRpm))
    end
    return minRpm, maxRpm
end

-- 0.2.0 : boost. Meme methode qu'ADS : la courbe de couple est multipliee ici, et la spec appelle
-- vehicle:updateMotorProperties() quand le boost change, pour que le moteur physique la relise.
-- 0.8.0 : torqueFactor est calcule par la spec (1 si FlowDrive inactif ou boost coupe) ; il peut etre
-- inferieur a 1 en mode "inclus" hors boost. Lu directement (pas getState) : la spec le remet a 1 elle-meme.
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
    -- 1.0.1 : touche de demarrage (Entree) : lance le prechauffage s'il fait froid. Remplace avant le
    -- chargement des vehicules, donc vu aussi par ADS qui rappelle Motorized.actionEventToggleMotorState.
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
    -- 0.7.0 : mods voisins detectes (compatibilite)
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
