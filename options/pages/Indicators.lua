local _, GUF = ...
local UI = GUF.OptionsUI

local anchors = { { "DEFAULT", "Layout default" } }
for _, point in ipairs(UI.pointChoices) do anchors[#anchors + 1] = point end

local function enabled(builder, kind)
    local host = builder.Row("Enable indicator")
    host.enabledIndicator = host.enabledIndicator or CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
    local check = host.enabledIndicator
    check:SetSize(26, 26)
    check:SetPoint("LEFT", 170, 0)
    check:SetChecked(not builder.Read({ "hide", kind }))
    check:SetScript("OnClick", function(self) builder.Change({ "hide", kind }, not self:GetChecked()) end)
    check:Show()
end

local function placement(builder, kind)
    builder.Group()
    enabled(builder, kind)
    local artistic = GUF.db.general.frameStyle == "artistic"
    local integratedCombo = artistic and kind == "resource" and GUF.UsesSegmentedResources(GUF.options.unit)
    local positioned = GUF.IsPortraitIndicator(kind)
    if artistic and positioned then
        builder.Group("Position")
        local columns = UI.CompactColumns(builder, "indicatorPositionAnchors", 66, 2)
        for i, spec in ipairs({ { "Anchor point", "anchorPoint", UI.pointChoices, "CENTER" },
            { "Relative point", "point", UI.pointChoices, "CENTER" } }) do
            local column, keys, fallback = columns[i], { "indicators", kind, spec[2] }, spec[4]
            column.caption:ClearAllPoints(); column.caption:SetPoint("TOP")
            column.caption:SetJustifyH("CENTER"); column.caption:SetText(spec[1])
            column.dropdown = UI.Dropdown(column, spec[3],
                function() return builder.Read(keys) or fallback end,
                function(value) builder.Change(keys, value) end, column.dropdown)
            column.dropdown:ClearAllPoints()
            column.dropdown:SetPoint("TOPLEFT", 0, -22); column.dropdown:SetPoint("TOPRIGHT", 0, -22)
        end
    elseif artistic and kind ~= "resource" then
        local columns = UI.CompactColumns(builder, "indicatorPlacement", 70, 2)
        columns[1].caption:SetPoint("TOP"); columns[1].caption:SetText("Anchor point")
        columns[1].dropdown = UI.Dropdown(columns[1], anchors,
            function() return builder.Read({ "indicators", kind, "point" }) end,
            function(value) builder.Change({ "indicators", kind, "point" }, value) end, columns[1].dropdown)
        columns[1].dropdown:ClearAllPoints()
        columns[1].dropdown:SetPoint("TOPLEFT", 0, -22); columns[1].dropdown:SetPoint("TOPRIGHT", 0, -22)
        UI.CompactSlider(builder, columns[2], "Size (0 = default)", { "indicators", kind, "size" }, 0, 64, 1)
        builder.Select("Anchor relative to", { { "frame", "Whole frame" }, { "portrait", "Portrait" }, { "bars", "Health / Power" } }, "indicators", kind, "anchor")
    end
    if not integratedCombo then
        if positioned then
            builder.Slider("X Offset", -300, 300, 1, false, "indicators", kind, "x")
            builder.Slider("Y Offset", -300, 300, 1, false, "indicators", kind, "y")
        else
            local columns = UI.CompactColumns(builder, "indicatorOffsets", 70, 2)
            UI.CompactSlider(builder, columns[1], "X offset", { "indicators", kind, "x" }, -50, 50, 1, false, true, { -300, 300 })
            UI.CompactSlider(builder, columns[2], "Y offset", { "indicators", kind, "y" }, -50, 50, 1, false, true, { -300, 300 })
        end
    end
    if kind == "resource" then return end
    if artistic and positioned then
        builder.Group("Appearance")
        builder.Slider("Size", 1, 64, 1, false, "indicators", kind, "size")
    end
    local columns = UI.CompactColumns(builder, "indicatorAppearance", 70, 2)
    UI.CompactSlider(builder, columns[1], "Opacity", { "indicators", kind, "alpha" }, 0, 1, .01, true)
    UI.CompactSlider(builder, columns[2], "Scale", { "indicators", kind, "scale" }, .5, 2.5, .05, true)
end

UI.RegisterPage("indicators", "Indicators", function(builder, unit, window)
    local kind = window.indicatorCategory
    if kind == "combat" or kind == "resting" then return end
    if kind == "threat" then UI.BuildThreat(builder); return end
    if kind == "feedback" then
        builder.Group()
        builder.Check("Enable combat text", "combatText", "enabled")
        builder.Select("Anchor point", UI.pointChoices, "combatText", "point")
        for _, axis in ipairs({ "x", "y" }) do
            local host, slider = builder.Slider(axis:upper() .. " offset", -300, 300, 1, false, "combatText", axis)
            host.sliderField:SetWidth(44)
            slider:SetPoint("RIGHT", host, "RIGHT", -58, 0)
        end
        builder.Slider("Opacity", 0, 1, .01, true, "indicators", "feedback", "alpha")
        builder.Slider("Scale", 1, 4, .5, false, "indicators", "feedback", "scale")
        return
    end
    placement(builder, kind)
    if kind == "role" and GUF.db.general.frameStyle == "blizzard" then
        builder.Row("Uses Blizzard's role visibility rules. X/Y offsets start at the bottom center of the portrait.", 48, true)
    end
end)
