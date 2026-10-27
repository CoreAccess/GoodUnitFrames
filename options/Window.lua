local _, GUF = ...
local UI = GUF.OptionsUI

function GUF.ApplyPanelScale(preservePosition)
    local window = GUF.options
    if not window then return end
    local requested = tonumber(GUF.db.general.panelScale) or 1
    if requested ~= requested then requested = 1 end
    requested = math.max(.75, math.min(1.5, requested))
    local scale = math.min(requested, UI.PanelScaleLimit(window, preservePosition))
    local left, top
    if preservePosition and window:IsShown() then
        local previous = window:GetScale()
        left, top = window:GetLeft(), window:GetTop()
        if left and top then left, top = left * previous, top * previous end
    end
    window:SetScale(math.max(.4, scale))
    if left and top then window:ClearAllPoints(); window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / window:GetScale(), top / window:GetScale()) end
    if window.panelScale then window.panelScale.Refresh() end
    GUF.UpdateOptionsPreview()
end

function UI.LayoutOptionsContent(window)
    local preview = window.page == "units"
    local top = 0
    local right = preview and UI.layout.previewWidth + 20 or 8
    window.headingOffset = top
    window.heading:SetShown(not preview)
    window.heading:ClearAllPoints(); window.heading:SetPoint("TOPLEFT", window.pane, "TOPLEFT", 0, -top)
    window.headingRule:ClearAllPoints()
    window.headingRule:SetPoint("TOPLEFT", window.pane, "TOPLEFT", 0, -top - 36)
    window.headingRule:SetPoint("TOPRIGHT", window.pane, "TOPRIGHT", preview and -right or 0, -top - 36)
    window.editor:ClearAllPoints()
    window.editor:SetPoint("TOPLEFT", window.pane, "TOPLEFT", 0, -top - 56)
    window.editor:SetPoint("BOTTOMRIGHT", window.pane, "BOTTOMRIGHT", -right, 0)
    window.preview.section:SetShown(preview)
    window.preview.viewport:SetShown(preview)
    UI.UpdateTabs(window)
    UI.QueueScrollUpdate(window)
end

function GUF.UpdateConfigurationButton()
    local window = GUF.options
    if not window then return end
    window.resetButton:SetEnabled(not GUF.Restricted() and not GUF.editing)
    window.profile:SetEnabled(not GUF.Restricted() and not GUF.editing)
    if window.frameMoverButton then
        window.frameMoverButton:SetText(GUF.frameMoversUnlocked and "Lock Frames" or "Unlock Frames")
        window.frameMoverButton:SetEnabled(not GUF.Restricted() and not GUF.editing)
    end
end

local function selectContent(window)
    local key = window.page == "units" and (window.unit .. ":" .. window.tab) or window.page
    if window.page == "units" then key = key .. ":" .. (UI.SelectedCategory(window) or "") end
    if window.tab == "auras" and window.page == "units" then key = key .. ":" .. (window.auraTab or "general") end
    if window.scroll.ScrollBar.goodUnitFramesScrollInput then window.scroll.ScrollBar.goodUnitFramesScrollInput.Stop() end
    if window.content then
        window.content.scrollOffset = window.scroll.ScrollBar:GetValue()
        if window.content.fixedHeader then
            UI.CancelControlFocus(window.content.fixedHeader); window.content.fixedHeader:Hide()
        end
        UI.CancelControlFocus(window.content); window.content:Hide()
    end
    local content = window.contentPages[key]
    if not content then
        content = CreateFrame("Frame", nil, window.scrollContent)
        content:SetPoint("TOPLEFT"); content:SetPoint("TOPRIGHT"); content:SetHeight(1)
        content.rows, content.groups = {}, {}
        content:HookScript("OnSizeChanged", function() if window.content == content then UI.QueueScrollUpdate(window) end end)
        window.contentPages[key] = content
    end
    window.content, window.rows, window.groups = content, content.rows, content.groups
end

function GUF.BuildOptions(unit, page)
    local window = GUF.options
    if not window then return end
    window.buildingOptions = true; window.refreshFrameScale = nil
    if window.confirmation then window.confirmation:Hide() end
    window.buildGeneration = (window.buildGeneration or 0) + 1
    if unit and not GUF.IsManagedUnit(unit) then unit = "player" end
    window.unit = unit or window.unit or "player"
    if not GUF.IsManagedUnit(window.unit) then window.unit = "player" end
    window.page = page or (unit and "units") or window.page or "panel"
    window.tab = window.tab or "general"
    if window.tab == "design" and not UI.LayoutCapabilities(window.unit).design then window.tab = "frame" end
    GUF.SyncOptionsPreviewSubject(window)
    if unit then window.unitsExpanded = true end
    if window.auraKind == "bossDebuffs" and window.unit ~= "player" then window.auraKind = "buffs" end
    local preview = window.page == "units"
    window.preview:SetShown(preview)
    if not preview then
        if GUF.optionsPreviewEntry then GUF.optionsPreviewEntry.frame:Hide() end
        GUF.optionsPreviewEntry = nil; window.preview.positionPending = nil
    end
    UI.LayoutOptionsContent(window)
    UI.UpdateNavigation(window)
    UI.UpdateElementNavigation(window); UI.UpdateBarNavigation(window); UI.UpdateAuraNavigation(window)
    selectContent(window)
    for _, row in ipairs(window.rows) do row:Hide() end
    for _, group in ipairs(window.groups) do group:Hide() end
    window.heading:SetText(window.page ~= "units" and UI.pageLabels[window.page] or "")
    if window.page == "panel" then window.heading:SetText("Choose your look") end
    if window.page == "profiles" then
        window.heading:SetFormattedText('Profile - "%s" is currently active', GUF.profileName or "Default")
    end
    local categories = window.page == "units" and (window.tab == "bars" or window.tab == "auras" or window.tab == "indicators" or window.tab == "text")
    window.scroll:ClearAllPoints()
    window.scroll:SetPoint("TOPLEFT", window.editor, "TOPLEFT", categories and UI.layout.categoryWidth or 0, 0)
    window.scroll:SetPoint("BOTTOMRIGHT", window.editor, "BOTTOMRIGHT", -24, 0)
    window.resetButton:SetText(window.page == "panel" and "Reset panel scale" or window.page == "hideBlizzard" and "Reset visibility" or window.page == "profiles" and "Reset profile" or "Reset " .. GUF.labels[window.unit])
    window.layoutLabel:SetText("Layout: " .. UI.LayoutName())
    window.panelScale.Refresh()
    window.profile:SetDefaultText(GUF.profileName or "Default")
    window.profile:GenerateMenu()
    local cfg, context
    if window.page == "units" then cfg, context = UI.UnitContext(window)
    elseif window.page == "panel" then cfg = GUF.db.general
    elseif window.page == "hideBlizzard" then cfg = GUF.db.hideBlizzard
    elseif window.page == "profiles" then cfg = GUF.profileDraft
    end
    local builder = UI.CreateBuilder(window, cfg, context)
    if window.page == "units" then UI.pages[window.tab](builder, window.unit, window)
    else UI.pages[window.page](builder, window.unit, window) end
    builder.Finish(); GUF.UpdateConfigurationButton(); GUF.UpdateOptionsPreview()
end

local function reset(window)
    local page, unit = window.page, window.unit
    if page == "panel" then GUF.db.general.panelScale = GUF.factoryDefaults.general.panelScale; GUF.ApplyPanelScale(true); GUF.BuildOptions(); return end
    local label = page == "profiles" and "profile " .. GUF.profileName or page == "hideBlizzard" and "Blizzard visibility settings" or GUF.labels[unit] .. " settings"
    UI.ConfirmProfileAction("Reset " .. label .. " to defaults?", function()
        if page == "profiles" then GUF.ResetCurrentProfile(); return end
        if page == "hideBlizzard" then GUF.db.hideBlizzard = GUF.Copy(GUF.GetLayoutDefaults(GUF.db.general.frameStyle).hideBlizzard)
        else
            GUF.Settings.ResetUnit(GUF.db, unit)
        end
        GUF.RequestApply(nil, nil, "reset"); GUF.BuildOptions()
    end)
end

function GUF.CreateOptions()
    if GUF.options then return GUF.options end
    local window = CreateFrame("Frame", "GoodUnitFramesWindow", UIParent, "PortraitFrameTemplate")
    GUF.options = window
    window:SetSize(UI.layout.windowWidth, UI.layout.windowHeight); window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG"); window:SetClampedToScreen(true); window:SetMovable(true)
    UI.WindowShell(window)
    local title = window.TitleContainer and window.TitleContainer.TitleText or window.TitleText
    if title then
        title:SetText(GUF.title)
        -- Lower the native title into the new shell header, preserving its
        -- horizontal anchors, width and font.
        local anchors = {}
        for i = 1, title:GetNumPoints() do anchors[i] = { title:GetPoint(i) } end
        title:ClearAllPoints()
        for _, point in ipairs(anchors) do
            title:SetPoint(point[1], point[2], point[3], point[4], point[5] - 5)
        end
    end
    local drag = CreateFrame("Frame", nil, window)
    drag:SetPoint("TOPLEFT", 80, -2); drag:SetPoint("TOPRIGHT", -38, -2); drag:SetHeight(24)
    drag:EnableMouse(true)
    local function stopDragging()
        local wasMoving = window.moving
        window:StopMovingOrSizing()
        window.moving = nil
        drag:SetScript("OnUpdate", nil)
        if wasMoving then GUF.UpdateOptionsPreviewBounds(GUF.optionsPreviewEntry) end
    end
    drag:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        -- Capture the grab point on press instead of waiting for OnDragStart.
        window.moving = true; window:StartMoving()
        self:SetScript("OnUpdate", function()
            -- Also finish if release occurs outside the title-bar hit region.
            if not IsMouseButtonDown("LeftButton") then stopDragging() end
        end)
    end)
    drag:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then stopDragging() end
    end)
    drag:SetScript("OnHide", stopDragging)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", UI.layout.paneLeft - 12, -76); page:SetPoint("BOTTOMRIGHT", -8, 42); UI.Parchment(page)
    window.parchment = page
    window.layoutLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.CreatePanelScale(window)
    local profileLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileLabel:SetPoint("TOPRIGHT", -266, -47); profileLabel:SetText("Profile")
    window.profile = UI.Dropdown(window, function() return GUF.ProfileNames() end, function() return GUF.profileName end, GUF.SelectProfile)
    window.profile:SetSize(220, 24); window.profile:SetPoint("TOPRIGHT", -24, -39)
    window.sidebar = CreateFrame("Frame", nil, window, "BackdropTemplate")
    window.sidebar:SetPoint("TOPLEFT", 16, -86); window.sidebar:SetPoint("BOTTOMLEFT", 16, 54); window.sidebar:SetWidth(UI.layout.sidebarWidth)
    -- The shell supplies continuous leather and its brass sidebar divider.
    window.pane = CreateFrame("Frame", nil, window)
    window.pane:SetPoint("TOPLEFT", UI.layout.paneLeft + 8, -92); window.pane:SetPoint("BOTTOMRIGHT", -30, 62)
    window.editor = CreateFrame("Frame", nil, window.pane)
    window.heading = window.pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    window.heading:SetPoint("TOPLEFT", 0, 0); UI.Heading(window.heading, 26)
    local divider = UI.Rule(window.pane, -36)
    window.headingRule = divider
    window.unit, window.contentPages = "player", {}
    UI.CreateNavigation(window); UI.CreateTabs(window)
    window.scroll = CreateFrame("ScrollFrame", nil, window.editor)
    window.scrollContent = CreateFrame("Frame", nil, window.scroll)
    window.scrollContent:SetPoint("TOPLEFT"); window.scrollContent:SetPoint("TOPRIGHT"); window.scrollContent:SetHeight(1)
    window.scroll:SetScrollChild(window.scrollContent)
    local scrollbar = CreateFrame("Slider", "GoodUnitFramesScrollBar", window.scroll, "UIPanelScrollBarTemplate")
    window.scroll.ScrollBar = scrollbar
    scrollbar:SetWidth(16); scrollbar:SetPoint("TOPLEFT", window.scroll, "TOPRIGHT", 6, -16); scrollbar:SetPoint("BOTTOMLEFT", window.scroll, "BOTTOMRIGHT", 6, 16)
    scrollbar:SetMinMaxValues(0, 0); scrollbar:SetValueStep(1); scrollbar:SetObeyStepOnDrag(true); scrollbar:SetValue(0)
    for _, item in ipairs({ { scrollbar.ScrollUpButton, "BOTTOM", "TOP", -36 }, { scrollbar.ScrollDownButton, "TOP", "BOTTOM", 36 } }) do
        if item[1] then
            item[1]:ClearAllPoints(); item[1]:SetPoint(item[2], scrollbar, item[3]); item[1]:SetSize(16, 16)
            local step = item[4]; item[1]:SetScript("OnClick", function() scrollbar:SetValue(scrollbar:GetValue() + step) end)
        end
    end
    UI.BindScrollBar(window)
    UI.StyleScrollBar(scrollbar)
    scrollbar:SetScript("OnValueChanged", function(_, value) UI.SetScroll(window, value); UI.UpdateScroll(window) end)
    window.scroll:EnableMouseWheel(true)
    window.scroll:SetScript("OnMouseWheel", function(_, delta) scrollbar:SetValue(scrollbar:GetValue() - delta * 36) end)
    window.scroll:SetScript("OnSizeChanged", function() UI.QueueScrollUpdate(window) end)
    window.scroll:SetScript("OnShow", function() UI.QueueScrollUpdate(window) end)
    UI.CreateOptionsPreview(window)
    window.resetButton = UI.Button(window, "Reset", 170, function() reset(window) end)
    window.resetButton:SetPoint("BOTTOMLEFT", 20, 14)
    local close = UI.Button(window, "Close", 110, function() window:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -24, 14)
    window.layoutLabel:SetPoint("RIGHT", close, "LEFT", -16, 0)
    window:SetScript("OnHide", function()
        stopDragging()
        window.controlSession = (window.controlSession or 0) + 1
        UI.CancelControlFocus(window)
        window.panelScale.Stop()
        if window.confirmation then window.confirmation:Hide() end
        GUF.SetMovers(false)
        if GUF.optionsPreviewEntry then GUF.optionsPreviewEntry.frame:Hide() end
        GUF.optionsPreviewEntry = nil
    end)
    window:SetScript("OnShow", function()
        window.panelScale.Refresh(); UI.QueueScrollUpdate(window)
        if window.page == "panel" and window.rows[2] and window.rows[2].QueueLayout then window.rows[2].QueueLayout() end
        GUF.UpdateOptionsPreview()
    end)
    window:Hide(); GUF.ApplyPanelScale()
    tinsert(UISpecialFrames, "GoodUnitFramesWindow")
    return window
end

function GUF.OpenOptions(unit)
    local window = GUF.CreateOptions()
    GUF.ApplyPanelScale(); window:ClearAllPoints(); window:SetPoint("CENTER")
    GUF.BuildOptions(unit); window:Show()
end
