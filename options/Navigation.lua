local _, GUF = ...
local UI = GUF.OptionsUI

local function navigationButton(window, label, indent, callback)
    local button = CreateFrame("Button", nil, window.sidebar, "OptionsListButtonTemplate")
    button:SetSize(UI.layout.sidebarWidth - 14, 26)
    if button.toggle then button.toggle:Hide() end
    button.text = button.text or button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", 5 + indent, 0)
    button.text:SetWidth(UI.layout.sidebarWidth - 28 - indent)
    button.text:SetHeight(20)
    button.text:SetFont(GUF.Font("Default"), 13, "")
    button.text:SetJustifyH("LEFT")
    button.text:SetText(label)
    -- Disabled buttons suppress hover highlights; keep selection artwork independent.
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetVertexColor(.65, .44, .12, .45) end
    button.selection = button:CreateTexture(nil, "BACKGROUND")
    button.selection:SetAllPoints(button)
    button.selection:SetTexture(highlight and highlight:GetTexture() or "Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if highlight then button.selection:SetTexCoord(highlight:GetTexCoord()) end
    button.selection:SetVertexColor(.8, .55, .16)
    button.selection:SetBlendMode("ADD")
    button.selection:Hide()
    button.selectionBorder = UI.Selection(button, true)
    button:SetScript("OnClick", callback)
    button:SetScript("OnDoubleClick", nil)
    return button
end

function UI.CreateNavigation(window)
    window.navigation = {}
    window.navigation.profiles = navigationButton(window, "Profiles", 0, function() GUF.BuildOptions(nil, "profiles") end)
    window.navigation.panel = navigationButton(window, "General", 0, function()
        if window.page == "panel" then return end
        GUF.BuildOptions(nil, "panel")
    end)
    window.navigation.hideBlizzard = navigationButton(window, "Hide Blizzard", 0, function()
        if window.page == "hideBlizzard" then return end
        GUF.BuildOptions(nil, "hideBlizzard")
    end)
    local units = navigationButton(window, "Unit Configuration", 0, function()
        window.unitsExpanded = not window.unitsExpanded
        UI.UpdateNavigation(window)
    end)
    window.navigation.units = units
    units.toggleIcon = units:CreateTexture(nil, "OVERLAY")
    units.toggleIcon:SetSize(14, 14)
    units.toggleIcon:SetPoint("RIGHT", -2, 0)
    units.text:SetWidth(UI.layout.sidebarWidth - 44)
    window.unitsExpanded = true
    for _, unit in ipairs(UI.unitOrder) do
        window.navigation[unit] = navigationButton(window, GUF.labels[unit], 12, function()
            if window.page == "units" and window.unit == unit then return end
            window.unitsExpanded = true
            GUF.BuildOptions(unit, "units")
        end)
    end
end

function UI.UpdateNavigation(window)
    local keys = { "panel", "profiles", "units" }
    if window.unitsExpanded then
        for _, unit in ipairs(UI.unitOrder) do
            keys[#keys + 1] = unit
        end
    end
    keys[#keys + 1] = "hideBlizzard"
    for _, button in pairs(window.navigation) do button:Hide() end
    for i, key in ipairs(keys) do
        local button = window.navigation[key]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 7, -8 - (i - 1) * 26)
        local selected = (key ~= "units" and key == window.page) or (window.page == "units" and key == window.unit)
        button:SetEnabled(not selected)
        button:UnlockHighlight()
        button.selection:SetShown(selected)
        button.selectionBorder:SetShown(selected)
        local white = selected or GUF.labels[key] ~= nil
        button.text:SetTextColor(1, white and 1 or .82, white and 1 or 0)
        button:Show()
    end
    window.navigation.units.toggleIcon:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    window.navigation.units.toggleIcon:SetVertexColor(1, .78, .25)
    window.navigation.units.toggleIcon:SetRotation(window.unitsExpanded and 0 or math.pi / 2)
end

function UI.CreateTabs(window)
    window.tabs = {}
    local previous
    for _, key in ipairs(UI.unitTabs) do
        local button = CreateFrame("Button", nil, window.pane)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.label:SetFont(GUF.Font("Default"), 13, "")
        button.label:SetText(UI.pageLabels[key])
        button.label:SetPoint("CENTER")
        -- Real tab faces replace the stock transparent end caps. A two-unit gap
        -- keeps the measured gold/bronze rims separate without overlap.
        button:SetSize(math.max(88, math.ceil(button.label:GetStringWidth()) + 24), 32)
        button.tabWidth = button:GetWidth()
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else button:SetPoint("TOPLEFT", window.pane, "TOPLEFT", 0, 0) end
        UI.SkinTab(button)
        button:SetScript("OnClick", function()
            if window.tab == key then return end
            window.tab = key
            GUF.BuildOptions()
        end)
        window.tabs[key] = button
        previous = button
    end
end

function UI.UpdateTabs(window)
    local design = UI.LayoutCapabilities(window.unit).design
    local total, count = 0, 0
    for _, key in ipairs(UI.unitTabs) do
        if key ~= "design" or design then total = total + window.tabs[key].tabWidth; count = count + 1 end
    end
    local available = window.pane:GetWidth() - UI.layout.previewWidth - 20 - (count - 1) * 2
    local factor = design and available > 0 and math.min(1, available / total) or 1
    local previous
    for _, key in ipairs(UI.unitTabs) do
        local button = window.tabs[key]
        local visible = key ~= "design" or UI.LayoutCapabilities(window.unit).design
        button:SetWidth(button.tabWidth * factor)
        button:SetShown(window.page == "units" and visible)
        button:ClearAllPoints()
        if visible then
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else button:SetPoint("TOPLEFT", window.pane, "TOPLEFT", 0, -(window.headingOffset or 0)) end
            previous = button
        end
        button.label:SetText(UI.pageLabels[key])
        UI.SelectTab(button, key == window.tab)
    end
end
