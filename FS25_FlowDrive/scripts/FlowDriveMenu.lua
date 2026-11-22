-- FlowDrive settings window (Left Shift + Left Alt + T). 0.8.0: auto ramp, boost entered in %.
-- Same method as ADS: class derived from MessageDialog, loaded on first display (g_gui:loadGui),
-- XML layout with the FS25 profiles already used by CVT Addon.
-- Choices are only applied with OK; Back (or Escape) changes nothing.

FlowDriveMenu = FlowDriveMenu or {}
local FlowDriveMenu_mt = Class(FlowDriveMenu, MessageDialog)

local function yesNo()
    return {FlowDrive.t("fd_no"), FlowDrive.t("fd_yes")}
end

local function boolState(value)
    return value and 2 or 1
end

local function stateBool(option)
    return option ~= nil and option:getState() == 2
end

function FlowDriveMenu.new(target, customMt)
    local self = MessageDialog.new(target, customMt or FlowDriveMenu_mt)
    self.vehicle = nil
    self.memValues = {}
    return self
end

function FlowDriveMenu.register()
    local dialog = FlowDriveMenu.new()
    g_gui:loadGui(FlowDrive.MOD_DIR .. "gui/FlowDriveMenu.xml", "FlowDriveMenu", dialog)
    rawset(FlowDriveMenu, "INSTANCE", dialog)
end

function FlowDriveMenu.show(vehicle)
    if g_gui == nil or vehicle == nil or vehicle.spec_flowDrive == nil then
        return
    end
    if rawget(FlowDriveMenu, "INSTANCE") == nil then
        local ok, err = pcall(FlowDriveMenu.register)
        if not ok then
            print("[FlowDrive] ERREUR : menu non charge : " .. tostring(err))
            return
        end
    end
    local dialog = rawget(FlowDriveMenu, "INSTANCE")
    dialog.vehicle = vehicle
    local ok, err = pcall(dialog.updateContent, dialog)
    if not ok then
        print("[FlowDrive] ERREUR : menu : " .. tostring(err))
        return
    end
    g_gui:showDialog("FlowDriveMenu")
end

function FlowDriveMenu:onOpen()
    FlowDriveMenu:superClass().onOpen(self)
end

function FlowDriveMenu:onClose()
    self.vehicle = nil
    FlowDriveMenu:superClass().onClose(self)
end

-- List of engine speeds that can be memorised: idle + 100 up to rated, in steps of FlowDrive.MEMORY_STEP
local function buildRpmList(s)
    local values, texts = {}, {}
    local idle = s.idleRpm or 800
    local rated = s.ratedRpm or 2200
    local rpm = math.ceil((idle + 100) / FlowDrive.MEMORY_STEP) * FlowDrive.MEMORY_STEP
    while rpm <= rated do
        table.insert(values, rpm)
        table.insert(texts, FlowDrive.tf("fd_rpm", rpm))
        rpm = rpm + FlowDrive.MEMORY_STEP
    end
    if #values == 0 then
        values, texts = {rated}, {FlowDrive.tf("fd_rpm", rated)}
    end
    return values, texts
end

local function nearestIndex(values, value)
    local best, bestDiff = 1, math.huge
    for index, v in ipairs(values) do
        local diff = math.abs(v - (value or 0))
        if diff < bestDiff then
            best, bestDiff = index, diff
        end
    end
    return best
end

function FlowDriveMenu:updateContent()
    local vehicle = self.vehicle
    local s = vehicle.spec_flowDrive
    local settings = FlowDrive.settings

    local name = vehicle.getFullName ~= nil and vehicle:getFullName() or "?"
    self.guiTitle:setText(FlowDrive.t("fd_menu_title") .. " " .. FlowDrive.t("fd_menu_for") .. " " .. name)
    self.guiVersion:setText("FlowDrive " .. tostring(FlowDrive.VERSION))

    -- This vehicle
    self.optEnabled:setTexts(yesNo())
    self.optEnabled:setState(boolState(s.enabled))

    -- 0.8.0: first choice = Auto
    local rampTexts = {FlowDrive.t("fd_ramp_auto")}
    for index, ramp in ipairs(FlowDrive.RAMPS) do
        rampTexts[index + 1] = FlowDrive.tf("fd_ramp_value", index, string.format("%.1f", ramp.accel))
    end
    self.optRamp:setTexts(rampTexts)
    self.optRamp:setState((s.ramp or FlowDrive.RAMP_AUTO) + 1)

    self.optRange:setTexts({
        FlowDriveSpec.getRangeLabel(s, FlowDrive.RANGE_AUTO),
        FlowDriveSpec.getRangeLabel(s, FlowDrive.RANGE_FIELD),
        FlowDriveSpec.getRangeLabel(s, FlowDrive.RANGE_ROAD)
    })
    self.optRange:setState((s.range or 0) + 1)

    self.optPtoEco:setTexts(yesNo())
    self.optPtoEco:setState(boolState(s.ptoEco))

    self.optMemory:setTexts({FlowDrive.t("fd_off"), "1", "2"})
    self.optMemory:setState((s.memory or 0) + 1)

    local values, texts = buildRpmList(s)
    self.memValues = values
    self.optMem1:setTexts(texts)
    self.optMem1:setState(nearestIndex(values, s.memRpm[1]))
    self.optMem2:setTexts(texts)
    self.optMem2:setState(nearestIndex(values, s.memRpm[2]))

    -- 0.8.0: boost "Off / X %", X entered with the bottom button; included / added mode
    self.boostPct = s.boostPct or FlowDrive.BOOST_DEFAULT_PCT
    self:updateBoostTexts(s.boostEnabled)

    -- 1.0.2: the row title shows the game power, to compare with the real spec sheet
    if self.titleBoostMode ~= nil then
        if s.gameHp ~= nil then
            self.titleBoostMode:setText(FlowDrive.tf("fd_opt_boostModeHp", s.gameHp))
        else
            self.titleBoostMode:setText(FlowDrive.t("fd_opt_boostMode"))
        end
    end
    self.optBoostMode:setTexts({FlowDrive.t("fd_boost_included"), FlowDrive.t("fd_boost_added")})
    self.optBoostMode:setState(s.boostIncluded ~= false and 1 or 2)

    self.optFlow:setTexts(yesNo())
    self.optFlow:setState(boolState(s.flowEnabled))

    -- Vehicle settings greyed out when it is not handled; crop flow only on a harvester
    local eligible = s.eligible == true
    for _, option in ipairs({self.optEnabled, self.optRamp, self.optRange, self.optPtoEco, self.optMemory,
        self.optMem1, self.optMem2, self.optBoost, self.optBoostMode}) do
        option:setDisabled(not eligible)
    end
    if self.boostButton ~= nil then
        self.boostButton:setDisabled(not eligible)
    end
    self.optFlow:setDisabled(not eligible or s.profile ~= "harvester")
    if not eligible and self.ttEnabled ~= nil then
        self.ttEnabled:setText(FlowDrive.tf("fd_not_available", FlowDriveSpec.getReasonText(s)))
    elseif self.ttEnabled ~= nil then
        self.ttEnabled:setText(FlowDrive.t("fd_opt_enabled_tt"))
    end

    -- General settings
    self.optHydraulic:setTexts(yesNo())
    self.optHydraulic:setState(boolState(settings.hydraulic))
    self.optPreheat:setTexts(yesNo())
    self.optPreheat:setState(boolState(settings.preheat))
    self.optCold:setTexts(yesNo())
    self.optCold:setState(boolState(settings.coldProtect))
    self.optHud:setTexts(yesNo())
    self.optHud:setState(boolState(settings.hud))
    self.optHudPos:setTexts({FlowDrive.t("fd_right"), FlowDrive.t("fd_left")})
    self.optHudPos:setState(settings.hudPos == 2 and 2 or 1)
    self.optDbl:setTexts(yesNo())
    self.optDbl:setState(boolState(settings.dbl))
end

-- 0.8.0: boost row: 1 = off, 2 = current percentage
function FlowDriveMenu:updateBoostTexts(enabled)
    self.optBoost:setTexts({FlowDrive.t("fd_off"), FlowDrive.tf("fd_boost_pct", self.boostPct)})
    self.optBoost:setState(enabled and 2 or 1)
end

-- 0.8.0: free entry of the percentage with the game's text input dialog (same call as FS25_ShopSearch)
function FlowDriveMenu:onClickBoostInput()
    if TextInputDialog == nil or TextInputDialog.createFromExistingGui == nil then
        print("[FlowDrive] ATTENTION : boite de saisie du jeu introuvable")
        return
    end
    local menu = self
    local ok, err = pcall(TextInputDialog.createFromExistingGui, {
        onTextEntered = function(text, clickOk)
            if not clickOk then
                return
            end
            local value = tonumber((tostring(text or ""):gsub(",", ".")))
            if value == nil or value < 0 or value > FlowDrive.BOOST_MAX_PCT then
                print("[FlowDrive] menu : boost saisi refuse : " .. tostring(text))
                if g_currentMission ~= nil and g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil then
                    g_currentMission.hud:addSideNotification({1, 0.6, 0.2, 1}, FlowDrive.tf("fd_msg_boostInvalid", FlowDrive.BOOST_MAX_PCT), 3000)
                end
                return
            end
            value = math.floor(value + 0.5)
            print("[FlowDrive] menu : boost saisi " .. tostring(value) .. " %")
            if value == 0 then
                menu:updateBoostTexts(false)
            else
                menu.boostPct = value
                menu:updateBoostTexts(true)
            end
        end,
        target = nil,
        defaultText = tostring(self.boostPct or FlowDrive.BOOST_DEFAULT_PCT),
        dialogPrompt = FlowDrive.tf("fd_boost_prompt", FlowDrive.BOOST_MAX_PCT),
        imePrompt = "",
        maxCharacters = 4,
        confirmText = g_i18n:getText("button_ok"),
        inputText = tostring(self.boostPct or FlowDrive.BOOST_DEFAULT_PCT),
        applyTextFilter = false
    })
    if not ok then
        print("[FlowDrive] ERREUR : boite de saisie : " .. tostring(err))
        return
    end
    if TextInputDialog.INSTANCE ~= nil and TextInputDialog.INSTANCE.textElement ~= nil then
        TextInputDialog.INSTANCE.textElement.applyProfanityFilter = false
    end
end

function FlowDriveMenu:onClickApply()
    local vehicle = self.vehicle
    local s = vehicle ~= nil and vehicle.spec_flowDrive or nil
    if s ~= nil and s.eligible then
        s.enabled = stateBool(self.optEnabled)
        s.ramp = math.max(0, math.min(#FlowDrive.RAMPS, self.optRamp:getState() - 1))
        local wantedRange = math.max(0, math.min(2, self.optRange:getState() - 1))
        if wantedRange ~= s.range and FlowDriveSpec.canChangeRange(vehicle, s) then
            s.range = wantedRange
        end
        s.ptoEco = stateBool(self.optPtoEco)
        s.memory = math.max(0, math.min(2, self.optMemory:getState() - 1))
        s.memRpm[1] = self.memValues[self.optMem1:getState()] or s.memRpm[1]
        s.memRpm[2] = self.memValues[self.optMem2:getState()] or s.memRpm[2]
        s.boostEnabled = stateBool(self.optBoost)
        s.boostPct = self.boostPct or s.boostPct
        s.boostIncluded = self.optBoostMode:getState() ~= 2
        if s.profile == "harvester" then
            s.flowEnabled = stateBool(self.optFlow)
        end
        if FlowDriveSpec.onSettingsChanged ~= nil then
            FlowDriveSpec.onSettingsChanged(vehicle)
        end
    end

    local settings = FlowDrive.settings
    settings.hydraulic = stateBool(self.optHydraulic)
    settings.preheat = stateBool(self.optPreheat)
    settings.coldProtect = stateBool(self.optCold)
    settings.hud = stateBool(self.optHud)
    settings.hudPos = self.optHudPos:getState() == 2 and 2 or 1
    settings.dbl = stateBool(self.optDbl)
    pcall(FlowDrive.saveSettings)

    print(string.format("[FlowDrive] menu : enregistre | actif=%s rampe=%s gamme=%s pdfEco=%s memoire=%s M1=%s M2=%s boost=%s %s%% inclus=%s puissance jeu=%s ch debit=%s | hydraulique=%s prechauffage=%s froid=%s affichage=%s position=%s dbl=%s",
        tostring(s ~= nil and s.enabled), tostring(s ~= nil and s.ramp), tostring(s ~= nil and s.range),
        tostring(s ~= nil and s.ptoEco), tostring(s ~= nil and s.memory), tostring(s ~= nil and s.memRpm[1]),
        tostring(s ~= nil and s.memRpm[2]), tostring(s ~= nil and s.boostEnabled), tostring(s ~= nil and s.boostPct),
        tostring(s ~= nil and s.boostIncluded), tostring(s ~= nil and s.gameHp), tostring(s ~= nil and s.flowEnabled),
        tostring(settings.hydraulic), tostring(settings.preheat), tostring(settings.coldProtect), tostring(settings.hud),
        tostring(settings.hudPos), tostring(settings.dbl)))
    if g_currentMission ~= nil and g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil then
        g_currentMission.hud:addSideNotification({1, 1, 1, 1}, FlowDrive.t("fd_msg_saved"), 2500)
    end
    self:close()
end

function FlowDriveMenu:onClickBack()
    self:close()
end
