local _, GUF = ...
local UI = GUF.OptionsUI
function UI.UpdateAuraNavigation(window)
    local visible = window.page == "units" and window.tab == "auras"
    if not window.auraNavigation and visible then
        local nav = UI.CreateCategoryPanel(window)
        window.auraNavigation = nav
        for i, item in ipairs({ { "buffs", "Buffs" }, { "debuffs", "Debuffs" }, { "bossDebuffs", "Boss debuffs" } }) do
            local key = item[1]
            local button = UI.CategoryButton(nav, item[2], UI.layout.categoryWidth - 18)
            button:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
            button:SetScript("OnClick", function() window.auraKind = key; GUF.BuildOptions() end)
            nav.buttons[key] = button
        end
    end
    local nav = window.auraNavigation
    if not nav then return end
    nav:SetShown(visible)
    if not visible then return end
    window.auraKind, window.auraTab = window.auraKind or "buffs", window.auraTab or "general"
    window.auraIndex = window.auraKind == "bossDebuffs" and 1 or UI.PrimaryAuraIndex(window.unit, window.auraKind)
    for key, button in pairs(nav.buttons) do
        button:SetShown(key ~= "bossDebuffs" or UI.LayoutCapabilities(window.unit).bossAuras)
        UI.SelectCategoryButton(button, window.auraKind == key)
    end
end
