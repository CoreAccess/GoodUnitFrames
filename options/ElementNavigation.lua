local _, GUF = ...
local UI = GUF.OptionsUI

function UI.IndicatorCategories(unit)
    local capabilities = UI.LayoutCapabilities(unit)
    local artistic = capabilities.artwork
    local categories = { { "pvp", "PvP flag" } }
    categories[#categories + 1] = { "leader", "Leader / assistant" }
    if capabilities.roleIndicator then categories[#categories + 1] = { "role", artistic and "Class role" or "Role icon" } end
    if artistic then categories[#categories + 1] = { "loot", "Master loot" } end
    categories[#categories + 1] = { "feedback", "Combat text" }
    if unit == "player" and GUF.SupportsClassResources() and capabilities.classResources then categories[#categories + 1] = { "resource", "Class resources" } end
    if capabilities.threat then categories[#categories + 1] = { "threat", "Threat" } end
    return categories
end

UI.textCategories = { { "name", "Name" }, { "health", "Health text" }, { "power", "Power text" } }

function UI.TextCategories(unit)
    local capabilities = UI.LayoutCapabilities(unit)
    local categories = GUF.Copy(UI.textCategories)
    if capabilities.levelText then
        table.insert(categories, 2, { "level", "Level" })
    end
    if capabilities.threat then categories[#categories + 1] = { "threat", "Threat" } end
    return categories
end

function UI.UpdateElementNavigation(window)
    local indicators = window.page == "units" and window.tab == "indicators"
    if not indicators or not window:IsShown() then
        window.indicatorPreviewUnit, window.indicatorPreviewCategory = nil, nil
    end
    if window.page ~= "units" or window.tab ~= "text" or not window:IsShown() then
        window.threatTextPreviewUnit, window.rankTextPreview = nil, nil
    end
    local visible = window.page == "units" and (window.tab == "indicators" or window.tab == "text")
    if not window.elementNavigation and visible then
        local nav = UI.CreateCategoryPanel(window)
        window.elementNavigation = nav
    end
    local nav = window.elementNavigation
    if not nav then return end
    nav:SetShown(visible)
    if not visible then return end
    local categories = window.tab == "indicators" and UI.IndicatorCategories(window.unit) or UI.TextCategories(window.unit)
    local field = window.tab == "indicators" and "indicatorCategory" or "textCategory"
    if window.tab == "text" then
        local kind, side = (window[field] or ""):match("^(health)(Left)$")
        if not kind then kind, side = (window[field] or ""):match("^(health)(Right)$") end
        if not kind then kind, side = (window[field] or ""):match("^(power)(Left)$") end
        if not kind then kind, side = (window[field] or ""):match("^(power)(Right)$") end
        if not kind then kind, side = (window[field] or ""):match("^(health)(Center)$") end
        if not kind then kind, side = (window[field] or ""):match("^(power)(Center)$") end
        if kind then
            window.barTextPosition = window.barTextPosition or {}
            window.barTextPosition[kind], window[field] = side:lower(), kind
        end
    end
    local found
    for _, item in ipairs(categories) do if item[1] == window[field] then found = true end end
    if not found then window[field] = categories[1][1] end
    if window.tab == "text" and window.unit == "target" and window[field] == "threat" then
        if window.threatTextPreviewUnit ~= window.unit then GUF.EnableOptionsIndicatorPreview(window.unit, "threat") end
        window.threatTextPreviewUnit = window.unit
    else window.threatTextPreviewUnit = nil end
    if window.tab == "text" and window.unit == "target" and window[field] == "rank" then
        if not window.rankTextPreview then GUF.EnableOptionsRankPreview(window.unit) end
        window.rankTextPreview = true
    else window.rankTextPreview = nil end
    -- Selecting a section (including tab/unit entry) chooses its useful sample
    -- once. Settings rebuilds must not undo a user's manual preview choices.
    if indicators and (window.indicatorPreviewUnit ~= window.unit or window.indicatorPreviewCategory ~= window[field]) then
        window.indicatorPreviewUnit, window.indicatorPreviewCategory = window.unit, window[field]
        GUF.EnableOptionsIndicatorPreview(window.unit, window[field])
    end
    for _, button in ipairs(nav.buttons) do button:Hide() end
    for i, item in ipairs(categories) do
        local key = item[1]
        local button = nav.buttons[i] or UI.CategoryButton(nav, item[2], UI.barNavigationWidth - 23)
        nav.buttons[i] = button
        button.text:SetText(item[2])
        button.text:ClearAllPoints()
        button.text:SetPoint("LEFT", 5, 0)
        button.text:SetPoint("RIGHT", -6, 0)
        button.text:SetJustifyH("LEFT")
        button.text:SetWordWrap(false)
        button:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
        button:SetScript("OnClick", function()
            window[field] = key
            GUF.BuildOptions()
        end)
        UI.SelectCategoryButton(button, window[field] == key)
        button:Show()
    end
end
