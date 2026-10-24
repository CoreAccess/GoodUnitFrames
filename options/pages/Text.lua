local _, GUF = ...
local UI = GUF.OptionsUI

local outlines = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" }, { "MONOCHROME,OUTLINE", "Monochrome outline" } }
local alignments = { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } }
UI.RegisterPage("text", "Text", function(builder, unit, window)
    local category = window.textCategory
    if category == "level" then
        if GUF.db.general.frameStyle ~= "blizzard" or (unit ~= "player" and unit ~= "target") then return end
        builder.Group("Position")
        builder.Slider("X offset", -200, 200, 1, false, "text", "level", "x")
        builder.Slider("Y offset", -200, 200, 1, false, "text", "level", "y")
        builder.Group("Appearance")
        builder.Slider("Font size", 6, 40, 1, false, "text", "level", "size")
        builder.Select("Font", UI.FontChoices, "text", "level", "font")
        builder.Select("Font outline", outlines, "text", "level", "outline")
        builder.ColorSwatch("Text color", "text", "level", "color")
        return
    end
    if category == "health" or category == "power" then
        UI.BarTextEditor(builder, unit, category, window)
        return
    end
    if category == "name" or (category == "threat" or category == "rank") and unit == "target" then
        builder.Group("Position")
        builder.Slider("X offset", -30, 30, 1, false, "text", category, "x")
        builder.Slider("Y offset", -10, 30, 1, false, "text", category, "y")
        builder.Group("Appearance")
        builder.Slider("Font size", 6, 16, 1, false, "text", category, "size")
        builder.Select("Font", UI.FontChoices, "text", category, "font")
        builder.Select("Font outline", outlines, "text", category, "outline")
        if category == "threat" or category == "rank" then return end
        builder.Select("Alignment", alignments, "text", category, "align")
        local choices = { { "class", "Class" } }
        local help = unit == "player" and "Class uses your class color."
            or "Class uses class colors for players and reaction colors for NPCs."
        if unit ~= "player" then
            choices[#choices + 1] = { "reaction", "Reaction" }
            help = help .. " Reaction colors everyone's name by attitude toward you: green for friendly, yellow for neutral and red for hostile."
        end
        choices[#choices + 1] = { "custom", "Custom" }
        local host, control = builder.Select("Name color", choices, "nameColor")
        help = help .. " Custom uses your selected color. The preview uses a friendly player/pet or a hostile Target creature."
        UI.Tooltip(host, "Name color", help); UI.Tooltip(control, "Name color", help)
        if builder.Read({ "nameColor" }) == "custom" then builder.ColorSwatch("Text color", "customName") end
        return
    end
end)
