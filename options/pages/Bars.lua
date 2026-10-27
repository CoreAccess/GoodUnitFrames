local _, GUF = ...
local UI = GUF.OptionsUI

local textAnchors = { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } }
local castOutlines = { { "", "None" }, { "OUTLINE", "Outline" },
    { "THICKOUTLINE", "Thick outline" }, { "MONOCHROME,OUTLINE", "Monochrome outline" } }

local function prediction(builder, key, label, description)
    builder.Group()
    local host, check = builder.Setting(key .. ".enabled")
    if description then
        UI.Tooltip(host, label, description)
        UI.Tooltip(check, label, description)
    end
    if key == "incAbsorb" then
        local fullHost, fullCheck = builder.Setting("incAbsorb.showAtFullHealth")
        local explanation = "Below full health, shields fill the empty space after current health. Enable this to also show an overlay at full health; otherwise shields are hidden at full health. Shields always stay within the health bar."
        UI.Tooltip(fullHost, "Show at Full Health", explanation)
        UI.Tooltip(fullCheck, "Show at Full Health", explanation)
    end
    local opacityHost, opacitySlider = builder.Setting(key .. ".opacity")
    if key == "healAbsorb" then
        local explanation = "Lower opacity blends the healing absorb with the health bar and any overlapping damage shield. Use 100% for a distinct color."
        UI.Tooltip(opacityHost, "Healing absorb opacity", explanation)
        UI.Tooltip(opacitySlider, "Healing absorb opacity", explanation)
    end
    builder.Setting(key .. ".color")
end

UI.RegisterPage("bars", "Bars", function(builder, unit, window)
    local category = window.barCategory or "power"
    if category == "name" and UI.LayoutCapabilities(unit).artwork then
        builder.Group()
        UI.BuildBarSize(builder, unit, "name")
        builder.Slider("Background opacity", 0, 1, .01, true, "artistic", "nameBackgroundAlpha")
    elseif category == "power" then
        builder.Group()
        UI.BuildBarSize(builder, unit, "power")
        builder.Select("Color power by", { { "blizzard", "Blizzard" }, { "class", "Class" }, { "type", "Power Type" } }, "bars", "powerMode")
        builder.Select("Power texture", UI.TextureChoices, "bars", "powerTexture")
    elseif category == "health" then
        builder.Group()
        UI.BuildBarSize(builder, unit, "health")
        builder.Select("Color health by", { { "blizzard", "Blizzard" }, { "class", "Class" }, { "percent", "Health percent" }, { "static", "Static" } }, "healthColor")
        if builder.Read({ "healthColor" }) == "static" then builder.Color("Static health color", "customHealth") end
        builder.Select("Health texture", UI.TextureChoices, "bars", "healthTexture")
    elseif category == "cast" then
        local defaults = builder.Default({ "bars", "cast" })
        builder.Group()
        builder.Setting("cast.enabled")
        builder.Setting("cast.icon")
        builder.Setting("cast.font")
        builder.Group("Cast bar position")
        local columns = UI.CompactColumns(builder, "castPositionAnchors", 66, 2)
        for i, spec in ipairs({ { "Anchor point", "point", "The point on the cast bar that attaches to the unit frame." },
            { "Relative point", "relativePoint", "The point on the unit frame where the selected cast bar anchor attaches." } }) do
            local column, key = columns[i], spec[2]
            column.caption:ClearAllPoints(); column.caption:SetPoint("TOP")
            column.caption:SetJustifyH("CENTER"); column.caption:SetText(spec[1])
            column.dropdown = UI.Dropdown(column, UI.pointChoices,
                function() return builder.Read({ "bars", "cast", "position", key }) end,
                function(value) builder.Change({ "bars", "cast", "position", key }, value) end, column.dropdown)
            column.dropdown:ClearAllPoints()
            column.dropdown:SetPoint("TOPLEFT", 0, -22); column.dropdown:SetPoint("TOPRIGHT", 0, -22)
            UI.Tooltip(column.dropdown, spec[1], spec[3])
        end
        builder.Setting("cast.position.x")
        builder.Setting("cast.position.y")
        local positionRow = builder.Row("")
        positionRow.castPositionReset = positionRow.castPositionReset or UI.Button(positionRow, "Reset position", 170)
        positionRow.castPositionReset:ClearAllPoints(); positionRow.castPositionReset:SetPoint("RIGHT", -5, 0)
        positionRow.castPositionReset:SetScript("OnClick", function()
            builder.Change({ "bars", "cast", "position" }, GUF.Copy(defaults.position))
            GUF.BuildOptions()
        end)
        positionRow.castPositionReset:Show()
        builder.Group("Cast bar size")
        builder.Setting("cast.width")
        builder.Setting("cast.height")
        local sizeRow = builder.Row("")
        sizeRow.castSizeReset = sizeRow.castSizeReset or UI.Button(sizeRow, "Reset size", 170)
        sizeRow.castSizeReset:ClearAllPoints(); sizeRow.castSizeReset:SetPoint("RIGHT", -5, 0)
        sizeRow.castSizeReset:SetScript("OnClick", function()
            builder.Change({ "bars", "cast", "width" }, defaults.width)
            builder.Change({ "bars", "cast", "height" }, defaults.height)
            GUF.BuildOptions()
        end)
        sizeRow.castSizeReset:Show()
        for _, kind in ipairs({ "name", "time" }) do
            builder.Group(kind == "name" and "Cast bar name" or "Cast bar time")
            builder.Check("Show cast " .. kind, "bars", "cast", kind, "enabled")
            builder.Select("Anchor point", textAnchors, "bars", "cast", kind, "point")
            builder.Select("Font outline", castOutlines, "bars", "cast", kind, "outline")
            builder.Slider("Size adjustment", -10, 10, 1, false, "bars", "cast", kind, "size")
            builder.Slider("X Offset", -20, 20, 1, false, "bars", "cast", kind, "x")
            builder.Slider("Y Offset", -20, 20, 1, false, "bars", "cast", kind, "y")
        end
    else
        for _, item in ipairs(UI.barCategories) do
            if item[1] == category then prediction(builder, category, item[2], item[3]); break end
        end
    end
end)
