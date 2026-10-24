local _, GUF = ...
local UI = GUF.OptionsUI
UI.barNavigationWidth = UI.layout.categoryWidth
UI.barCategories = {
    { "name", "Name" },
    { "health", "Health bar" }, { "power", "Power bar" },
    { "healAbsorb", "Healing absorbs", "Effects that absorb incoming healing before it can restore health. Healing clears this amount first; any remaining healing restores health. Displayed over the filled health bar, including at full health." },
    { "incHeal", "Incoming heals", "Expected healing fills the missing-health space after current health, stopping at maximum health. Hidden at full health." },
    { "incAbsorb", "Damage shields", "Shields such as Power Word: Shield absorb incoming damage before it reduces health. Includes shields cast by you or other players." },
    { "cast", "Cast bar" },
}

function UI.CategoryButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 26)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("LEFT", 5, 0)
    button.text:SetFont(GUF.Font("Default"), 12, "")
    button.text:SetShadowColor(0, 0, 0, 0)
    button.text:SetText(label)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    button.selection = button:CreateTexture(nil, "BACKGROUND")
    button.selection:SetAllPoints()
    button.selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    button.selection:SetVertexColor(.55, .32, .08)
    button.selection:SetBlendMode("ADD")
    button.selectionBorder = UI.Selection(button)
    return button
end

function UI.SelectCategoryButton(button, selected, enabled)
    button:SetEnabled(not selected)
    button.selection:SetShown(selected)
    button.selectionBorder:SetShown(selected)
    if selected then button.text:SetTextColor(.35, .16, .03)
    elseif enabled == false then button.text:SetTextColor(.5, .5, .5)
    else UI.Ink(button.text) end
end

function UI.UpdateBarNavigation(window)
    local visible = window.page == "units" and window.tab == "bars"
    if not window.barNavigation and visible then
        local nav = UI.CreateCategoryPanel(window)
        window.barNavigation = nav
        for i, category in ipairs(UI.barCategories) do
            local key, label = category[1], category[2]
            local button = UI.CategoryButton(nav, label, UI.barNavigationWidth - 23)
            nav.buttons[key] = button
            if category[3] then UI.Tooltip(button, label, category[3]) end
            button:SetScript("OnClick", function()
                if window.barCategory == key then return end
                window.barCategory = key
                if key == "cast" then GUF.EnableOptionsCastingPreview(window.unit) end
                GUF.BuildOptions()
            end)
        end
    end
    if not window.barNavigation then return end
    window.barNavigation:SetShown(visible)
    if not visible then return end
    window.barCategory = window.barCategory or "health"
    local artwork = UI.LayoutCapabilities(window.unit).artwork
    if window.barCategory == "name" and not artwork then window.barCategory = "health" end
    local index = 0
    for _, category in ipairs(UI.barCategories) do
        local button = window.barNavigation.buttons[category[1]]
        local shown = category[1] ~= "name" or artwork
        button:SetShown(shown)
        if shown then
            button:ClearAllPoints(); button:SetPoint("TOPLEFT", 0, -index * 28)
            index = index + 1
        end
    end
    for key, button in pairs(window.barNavigation.buttons) do
        local selected = key == window.barCategory
        UI.SelectCategoryButton(button, selected)
    end
end
