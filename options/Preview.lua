local _, GUF = ...
local UI = GUF.OptionsUI
local specimens = {}
local sampleHealthGap = 24
local _, playerClass = UnitClass("player")
local canFeignDeath = not GUF.Secret(playerClass) and playerClass == "HUNTER"
local stateChoices = {}
for _, choice in ipairs(GUF.configurationStates) do
    if choice[1] ~= "normal" and choice[1] ~= "channel" and (choice[1] ~= "feign" or canFeignDeath) then
        stateChoices[#stateChoices + 1] = { choice[1], choice[1] == "combat" and "In combat" or choice[2] }
    end
end
local groupChoices = { { "solo", "Solo" }, { "raid", "Party/Raid" } }
local subjectChoices = { { "player", "Player" }, { "beast", "Normal mob" },
    { "rare", "Rare" }, { "elite", "Elite mob" }, { "rareelite", "Rare elite" } }
local stateConflicts = {
    combat = { "resting", "dead", "ghost", "resurrect" },
    resting = { "combat", "dead", "ghost", "resurrect" },
    dead = { "ghost", "ready", "notready", "waiting", "feign", "casting", "combat", "resting" },
    ghost = { "dead", "ready", "notready", "waiting", "feign", "casting", "combat", "resting" },
    resurrect = { "ready", "notready", "waiting", "feign", "casting", "combat", "resting" },
    feign = { "dead", "ghost", "resurrect", "casting" },
    casting = { "dead", "ghost", "resurrect", "feign" },
    ready = { "notready", "waiting", "dead", "ghost", "resurrect" },
    notready = { "ready", "waiting", "dead", "ghost", "resurrect" },
    waiting = { "ready", "notready", "dead", "ghost", "resurrect" },
}
local function sampleChecks(window)
    window.sampleChecks = window.sampleChecks or { states = { resting = true }, groups = { solo = true }, subjects = { player = true } }
    window.sampleChecks.states = window.sampleChecks.states or { resting = true }
    window.sampleChecks.groups = window.sampleChecks.groups or { solo = true }
    window.sampleChecks.subjects = window.sampleChecks.subjects or { player = true }
    return window.sampleChecks
end

-- Target Design can choose a monster for its artwork without overwriting the
-- subject the user was inspecting elsewhere. Capture once, restore on exit.
function GUF.SyncOptionsPreviewSubject(window)
    local checked = sampleChecks(window)
    local design = window.page == "units" and window.unit == "target" and window.tab == "design"
    if design then
        if not window.targetDesignSubjectSnapshot then
            window.targetDesignSubjectSnapshot = { subjects = GUF.Copy(checked.subjects), current = window.sampleSubject }
        end
    elseif window.targetDesignSubjectSnapshot then
        local previous = window.targetDesignSubjectSnapshot
        checked.subjects, window.sampleSubject = previous.subjects, previous.current
        window.targetDesignSubjectSnapshot = nil
    end
end

local function representative(checked, current, choices, fallback)
    if current and checked[current] then return current end
    for _, choice in ipairs(choices) do if checked[choice[1]] then return choice[1] end end
    return fallback
end

local function setCondition(window, section, scalar, key, enabled)
    if section == "subjects" and window.unit ~= "target" then return end
    local checked = sampleChecks(window)
    if section ~= "states" then
        -- Checking another choice replaces the selection; clicking the current one keeps it selected.
        checked[section] = { [key] = true }
        window[scalar] = key
        return
    end
    local states = checked.states
    if enabled then
        if key == "offline" then
            checked.states = { offline = true }
        else
            states.offline = nil
            for _, other in ipairs(stateConflicts[key] or {}) do states[other] = nil end
            states[key] = true
        end
        window.sampleState = key
    else
        states[key] = nil
        if not next(states) then states.resting = true end
        if window.sampleState == key then window.sampleState = nil end
    end
end

local function primaryState(window, states)
    -- Health/status must keep reflecting death/disconnection when another sample is selected.
    for _, key in ipairs({ "offline", "ghost", "dead", "feign", "waiting", "notready", "ready" }) do
        if states[key] then return key end
    end
    return representative(states, window.sampleState, stateChoices, "resting")
end

local function refreshConditions(window)
    local rail, checked = window.preview, sampleChecks(window)
    local target = window.unit == "target"
    for _, control in ipairs(rail.conditions) do
        control:SetChecked(checked[control.sampleSection][control.sampleKey] == true)
        if control.sampleSection == "subjects" then control:SetShown(target) end
    end
    if rail.subjectVisible ~= target then
        rail.subjectVisible = target
        rail.subjectHeading:SetShown(target)
        local y = target and rail.subjectBottom or rail.groupBottom
        rail.health:ClearAllPoints()
        rail.health:SetPoint("TOPLEFT", 14, y - sampleHealthGap); rail.health:SetPoint("TOPRIGHT", -14, y - sampleHealthGap)
    end
end

local function label(parent, text, x, y, small)
    local region = parent:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontNormal")
    region:SetPoint("TOPLEFT", x, y); region:SetText(text); UI.Ink(region)
    return region
end

local function positionPreview(window, entry)
    local frame, rail = entry.frame, window.preview
    local viewport, panel = rail.viewport, rail.section
    if entry.presentationStatus ~= "applied" or not panel:IsShown() or panel.moving or window.moving then return false end
    -- Match the configured UIParent scale even when the options window is scaled.
    local requested = GUF.PresentationFrameSettings(entry).scale * UIParent:GetEffectiveScale() / viewport:GetEffectiveScale()
    frame:SetScale(requested)
    local bounds = GUF.Presentation.Bounds(entry)
    local minimumX, maximumX, minimumY, maximumY = bounds.left, bounds.right, bounds.bottom, bounds.top
    local width, height = maximumX - minimumX, maximumY - minimumY
    local desiredWidth = math.max(360, math.ceil(width * requested + 48))
    local desiredHeight = math.max(180, math.ceil(height * requested + 80))
    local screenScale = UIParent:GetEffectiveScale() / panel:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
    local left, top
    if not panel.detached then
        -- Reserve the preview's width before capping it at the screen edge.
        -- Both windows are measured in preview coordinates, including scale.
        local windowLeft, windowRight, windowTop = window:GetLeft(), window:GetRight(), window:GetTop()
        if not windowLeft or not windowRight or not windowTop then return false end
        local windowRatio = window:GetEffectiveScale() / panel:GetEffectiveScale()
        windowLeft, windowRight, windowTop = windowLeft * windowRatio, windowRight * windowRatio, windowTop * windowRatio
        local dockWidth = math.max(96, math.min(desiredWidth, screenWidth - 32))
        local shift = math.min(math.max(0, windowRight + 8 + dockWidth + 16 - screenWidth), math.max(0, windowLeft - 16))
        if shift > .01 then
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (windowLeft - shift) / windowRatio, windowTop / windowRatio)
            -- Let the client's new options position settle before docking;
            -- do not cap the preview using the previous screen rectangle.
            return false
        end
        -- If the pair cannot fit side by side, keep both windows on screen
        -- and overlap the options instead of squeezing the preview to a strip.
        left = math.max(16, math.min(windowRight + 8, screenWidth - dockWidth - 16))
        top = math.min(windowTop, screenHeight - 16)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", window, "TOPRIGHT", left - windowRight, top - windowTop)
    else
        left, top = panel:GetLeft(), panel:GetTop()
    end
    if not left or not top then return false end
    -- A single TOPLEFT anchor keeps growth directed right/down. Limit the
    -- viewport at the screen edge, never change the specimen's actual scale.
    local panelWidth = math.max(96, math.min(desiredWidth, screenWidth - left - 16))
    local panelHeight = math.max(96, math.min(desiredHeight, top - 16))
    if math.abs(panel:GetWidth() - panelWidth) > .01 or math.abs(panel:GetHeight() - panelHeight) > .01 then
        panel:SetSize(panelWidth, panelHeight)
    end
    local previewWidth, previewHeight = panelWidth - 24, panelHeight - 56
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", viewport, "TOPLEFT",
        (previewWidth - width * requested) / (2 * requested) - minimumX,
        -(previewHeight - height * requested) / (2 * requested) - maximumY)
    frame:Show()
    return true
end

local function combatTextSelected(window, entry)
    return entry ~= nil and window:IsShown() and window.preview.section:IsShown()
        and window.page == "units" and window.unit == entry.unit
        and window.tab == "indicators" and window.indicatorCategory == "feedback"
        and GUF.db.frames[entry.unit].combatText.enabled
end

local function renderPreview(window)
    local rail, unit = window.preview, window.unit
    if window.page ~= "units" or not window:IsShown() or not rail.section:IsShown() then return end
    if rail.section.moving or window.moving then rail.dirty = true; return end
    local style = GUF.db.general.frameStyle
    local specimenKey = style .. ":" .. unit
    for key, entry in pairs(specimens) do if key ~= specimenKey then entry.frame:Hide() end end
    local entry = specimens[specimenKey]
    if not entry then
        entry = GUF.CreateFrameSpecimen(unit, rail.viewport, style)
        entry.optionsPreview, entry.previewStarted = true, GetTime()
        specimens[specimenKey] = entry
    end
    GUF.optionsPreviewEntry = entry
    local checked = sampleChecks(window)
    local subject = unit == "target" and representative(checked.subjects, window.sampleSubject, subjectChoices, "player")
        or unit == "pet" and "beast" or "player"
    local portraitClass = unit == "player" and window.tab == "design" and window.playerPortraitClass or GUF.PlayerDesignClass()
    local monsterType = unit == "target" and window.targetMonsterType or "beast"
    if not GUF.MonsterPortraitDesign(monsterType) then monsterType = "beast" end
    local creatureRank = subject == "elite" and "elite"
        or subject == "rareelite" and "rareelite" or subject == "rare" and "rare" or "normal"
    entry.previewIdentity = subject ~= "player" and "creature-" .. monsterType .. ":" .. creatureRank
        or portraitClass and "class-" .. portraitClass:lower() or "class-hunter"
    local options = { style = style, settings = GUF.Settings.GetLayout(GUF.db, style),
        state = primaryState(window, checked.states),
        group = representative(checked.groups, window.sampleGroup, groupChoices, "solo"),
        states = checked.states, groups = checked.groups,
        showAll = false, subject = subject, health = window.sampleHealth or 55 }
    options.enabledIndicators = unit ~= "target" or subject == "player"
    options.previewThreat = unit == "target" and subject ~= "player"
    local _, powerToken = UnitPowerType("player")
    options.powerToken = not GUF.Secret(powerToken) and powerToken or "MANA"
    options.prediction = window.tab == "bars" and window.barCategory or nil
    options.combatText = combatTextSelected(window, entry)
    local cfg = options.settings.frames[unit]
    entry.frame:SetScale(cfg.scale * UIParent:GetEffectiveScale() / rail.viewport:GetEffectiveScale())
    if GUF.RenderFrameSpecimen(entry, nil, options) ~= "applied" then
        rail.positionPending = nil
        rail.presentationAttempts = (rail.presentationAttempts or 0) + 1
        if rail.presentationAttempts < 20 then rail.presentationRetryAt = GetTime() + .1 end
        return
    end
    rail.presentationAttempts, rail.presentationRetryAt = nil, nil
    rail.BindWindowDrag(entry.frame)
    refreshConditions(window)
    rail.positionPending = entry
    -- Center in this refresh; continuous slider updates must not postpone it.
    if not positionPreview(window, entry) then entry.frame:Hide() end
end

local function render(window)
    return GUF.Runtime.Sample(renderPreview, window)
end

function GUF.UpdateOptionsPreview()
    local window = GUF.options
    if window and window.preview then
        window.preview.dirty = true
        window.preview.presentationAttempts, window.preview.presentationRetryAt = nil, nil
    end
end

local function enablePreviewCondition(unit, section, scalar, key)
    local window = GUF.options
    if not window or window.page ~= "units" or window.unit ~= unit then return end
    if not sampleChecks(window)[section][key] then
        setCondition(window, section, scalar, key, true)
        GUF.UpdateOptionsPreview()
    end
end

function GUF.EnableOptionsCastingPreview(unit)
    enablePreviewCondition(unit, "states", "sampleState", "casting")
end

function GUF.EnableOptionsRankPreview(unit)
    enablePreviewCondition(unit, "subjects", "sampleSubject", "elite")
end

function GUF.EnableOptionsIndicatorPreview(unit, category)
    if category == "combat" or category == "resting" then
        enablePreviewCondition(unit, "states", "sampleState", category)
    end
end

function GUF.UpdateOptionsPreviewBounds(entry)
    local window = GUF.options
    if entry and entry.presentationStatus == "applied" and window and window.preview
        and window.page == "units" and entry == GUF.optionsPreviewEntry then
        window.preview.positionPending = entry
    end
end

function UI.CreateOptionsPreview(window)
    local rail = CreateFrame("Frame", nil, window.pane)
    window.preview = rail
    rail:RegisterEvent("CVAR_UPDATE")
    rail:RegisterEvent("UNIT_FACTION")
    rail:RegisterEvent("DISPLAY_SIZE_CHANGED")
    rail:RegisterEvent("UI_SCALE_CHANGED")
    rail:RegisterEvent("PLAYER_LEVEL_UP")
    rail:RegisterEvent("PLAYER_REGEN_ENABLED")
    rail:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_REGEN_ENABLED" and window.page == "units" and window.unit == "target"
            or event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" or event == "PLAYER_LEVEL_UP"
            or event == "UNIT_FACTION" and name == "player"
            or event == "CVAR_UPDATE" and (name == "statusTextDisplay" or name == "statusText") then
            GUF.UpdateOptionsPreview()
            if event == "PLAYER_LEVEL_UP" and window.page == "panel" and window.rows[2] and window.rows[2].QueueLayout then
                window.rows[2].QueueLayout()
            end
        end
    end)
    rail:SetPoint("TOPRIGHT", 0, 0); rail:SetPoint("BOTTOMRIGHT", 0, 0); rail:SetWidth(UI.layout.previewWidth)
    local rule = rail:CreateTexture(nil, "BACKGROUND"); rule:SetColorTexture(.43, .28, .12, .35)
    rule:SetWidth(1); rule:SetPoint("TOPLEFT", -10, 0); rule:SetPoint("BOTTOMLEFT", -10, 0)
    rail.title = label(rail, "Preview Settings", 8, -2)
    UI.Heading(rail.title, 20); UI.Rule(rail, -35)
    local panel = CreateFrame("Frame", "GoodUnitFramesPreviewWindow", window, "PortraitFrameTemplate")
    rail.section = panel
    panel.goodUnitFramesOwned = true
    panel:SetSize(360, 180); panel:SetPoint("TOPLEFT", window, "TOPRIGHT", 8, 0)
    panel:SetFrameStrata("FULLSCREEN_DIALOG"); panel:SetToplevel(true)
    panel:SetMovable(true); panel:EnableMouse(true)
    UI.WindowShell(panel, true)
    rail.reopen = UI.Button(rail, "Show Interactive Preview", UI.layout.previewWidth - 28, function()
        if window:IsShown() and window.page == "units" then panel:Show() end
    end)
    rail.reopen:SetPoint("BOTTOM", rail, "BOTTOM", 0, 8)
    rail.reopen:Hide()
    local title = panel.TitleContainer and panel.TitleContainer.TitleText or panel.TitleText
    if title then
        title:SetText("Interactive Preview")
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -7)
        title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -7); title:SetHeight(20)
    end
    local function stopDragging()
        if panel.moving then
            panel:StopMovingOrSizing(); panel.moving = nil
            -- Native moving can leave a CENTER anchor; normalize before the
            -- next automatic resize so the user's new top-left stays fixed.
            local left, top = panel:GetLeft(), panel:GetTop()
            if left and top then
                panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            panel:SetClampedToScreen(false)
            GUF.UpdateOptionsPreview()
        end
        panel:SetScript("OnUpdate", nil)
    end
    local function startDragging(_, button)
        if button ~= "LeftButton" or panel.moving then return end
        panel:SetClampedToScreen(true); panel.moving = true; panel.detached = true
        panel:StartMoving()
        panel:SetScript("OnUpdate", function() if not IsMouseButtonDown("LeftButton") then stopDragging() end end)
    end
    local function releaseDragging(_, button)
        if button == "LeftButton" then stopDragging() end
    end
    local function bindWindowDrag(host)
        -- Mouse-disabled artwork falls through to the panel. Sample buttons
        -- (including newly created auras) forward presses without losing hover
        -- tooltips; the native close button keeps its normal click behavior.
        if host == panel.CloseButton or host == panel.Close then return end
        if host:IsMouseEnabled() and not host.goodUnitFramesWindowDragBound then
            host.goodUnitFramesWindowDragBound = true
            host:HookScript("OnMouseDown", startDragging)
            host:HookScript("OnMouseUp", releaseDragging)
        end
        for _, child in ipairs({ host:GetChildren() }) do bindWindowDrag(child) end
    end
    rail.BindWindowDrag = bindWindowDrag
    panel:SetScript("OnHide", function()
        stopDragging()
        if GUF.optionsPreviewEntry then GUF.optionsPreviewEntry.frame:Hide() end
        rail.positionPending = nil
        rail.reopen:SetShown(window:IsShown() and window.page == "units")
    end)
    panel:SetScript("OnShow", function()
        rail.reopen:Hide()
        GUF.UpdateOptionsPreview()
    end)
    local paper = CreateFrame("Frame", nil, panel)
    paper:SetPoint("TOPLEFT", 8, -30); paper:SetPoint("BOTTOMRIGHT", -8, 8); UI.Parchment(paper)
    rail.viewport = CreateFrame("Frame", nil, paper)
    rail.viewport:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -40)
    rail.viewport:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 16)
    rail.viewport:SetClipsChildren(true)
    bindWindowDrag(panel)
    rail.conditions = {}
    local y = -50
    local function section(title, choices, key, scalar)
        local heading = label(rail, title, 8, y); UI.Heading(heading, 17)
        y = y - 24
        for i, choice in ipairs(choices) do
            local value, caption = choice[1], choice[2]
            local control = CreateFrame("CheckButton", nil, rail, "UICheckButtonTemplate")
            control:SetSize(24, 24)
            control:SetPoint("TOPLEFT", 8 + (i - 1) % 2 * (UI.layout.previewWidth / 2), y - math.floor((i - 1) / 2) * 28)
            control.sampleSection, control.sampleKey = key, value
            control.caption = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            control.caption:SetFont(GUF.Font("Default"), 12, "")
            control.caption:SetPoint("LEFT", control, "RIGHT", 0, 0)
            control.caption:SetSize(UI.layout.previewWidth / 2 - 34, 26)
            control.caption:SetJustifyH("LEFT"); control.caption:SetText(caption); UI.Ink(control.caption)
            control:SetHitRectInsets(0, -(UI.layout.previewWidth / 2 - 26), 0, 0)
            control:SetScript("OnClick", function(self)
                setCondition(window, key, scalar, value, self:GetChecked())
                refreshConditions(window); GUF.UpdateOptionsPreview()
            end)
            UI.Tooltip(control, caption, value == "pvp"
                and "Show your character's Horde or Alliance banner. Combine with In combat to preview PvP combat. This does not flag you for PvP."
                or key == "states"
                and "Simulate this state. In combat/Resting, Dead/Ghost and Ready/Not ready/Waiting exclude one another. In combat, Resting, ready-check states and Feign death also exclude Dead, Ghost and Resurrection. Casting excludes Dead, Ghost, Resurrection and Feign death. Offline clears every other state. This does not change gameplay."
                or "Select one option in this section. This does not change gameplay.")
            rail.conditions[#rail.conditions + 1] = control
        end
        y = y - math.ceil(#choices / 2) * 28 - 12
        return heading
    end
    section("State", stateChoices, "states", "sampleState")
    section("Group", groupChoices, "groups", "sampleGroup")
    rail.groupBottom = y
    rail.subjectHeading = section("Subject", subjectChoices, "subjects", "sampleSubject")
    rail.subjectBottom = y
    y = y - sampleHealthGap
    rail.health = CreateFrame("Slider", nil, rail, "OptionsSliderTemplate")
    rail.health:SetPoint("TOPLEFT", 14, y); rail.health:SetPoint("TOPRIGHT", -14, y); rail.health:SetHeight(16)
    rail.health:SetMinMaxValues(0, 100); rail.health:SetValueStep(1); rail.health:SetObeyStepOnDrag(true); rail.health:SetValue(55)
    rail.health.Low:SetText("0%"); rail.health.High:SetText("100%"); rail.health.Text:SetText("Sample health: 55%")
    UI.SkinSlider(rail.health)
    rail.health:SetScript("OnValueChanged", function(self, value)
        window.sampleHealth = math.floor(value + .5); self.Text:SetFormattedText("Sample health: %.0f%%", value); GUF.UpdateOptionsPreview()
    end)
    refreshConditions(window)
    local elapsed = 0
    rail:SetScript("OnUpdate", function(_, delta)
        -- Settle the previous layout before rendering the next slider value.
        -- Neither placement nor its follow-up can be starved by dirty refreshes.
        if rail.positionPending then
            local entry = rail.positionPending
            rail.positionPending = nil
            -- Clear before measuring so a resize callback can queue its own
            -- follow-up without being discarded after this pass.
            if not positionPreview(window, entry) then rail.positionPending = entry end
        end
        if rail.presentationRetryAt and GetTime() >= rail.presentationRetryAt then
            rail.presentationRetryAt, rail.dirty = nil, true
        end
        if rail.dirty then rail.dirty = nil; render(window) end
        local entry = GUF.optionsPreviewEntry
        if entry then
            local shown = combatTextSelected(window, entry) and entry.frame:IsVisible()
            local running = entry.combatText and entry.combatText.feedbackPreview or false
            -- Stop even if a drag defers rendering; resume after deferred
            -- preview positioning hides/shows the specimen during layout.
            if shown ~= running then GUF.PreviewCombatText(entry, shown) end
        end
        elapsed = elapsed + delta
        if window.page ~= "units" or not rail.section:IsShown() then return end
        if elapsed >= .1 then elapsed = 0; if GUF.optionsPreviewEntry then GUF.TickSpecimenAuras(GUF.optionsPreviewEntry) end end
    end)
    rail.viewport:SetScript("OnSizeChanged", function() GUF.UpdateOptionsPreviewBounds(GUF.optionsPreviewEntry) end)
end
