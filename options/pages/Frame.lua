local _, GUF = ...
local UI = GUF.OptionsUI

UI.RegisterPage("frame", "Frame", function(builder, unit)
    UI.BuildFrameSize(builder, unit)
    if UI.LayoutCapabilities(unit).flat then
        builder.Group("Size")
        builder.Slider("Frame width", 120, 800, 1, false, "bars", "width")
        builder.Slider("Health height", 10, 160, 1, false, "bars", "healthSize", "height")
        builder.Slider("Power height", 5, 80, 1, false, "bars", "powerSize", "height")
        builder.Group("Portrait")
        builder.Setting("flat.portrait")
        builder.Setting("flat.backgroundAlpha")
    end
    if UI.LayoutCapabilities(unit).artwork then
        builder.Group("Portrait Scale")
        local minimum, maximum = GUF.ArtisticPortraitScaleLimits(unit)
        builder.Slider("Portrait scale", minimum, maximum, .01, true, "artistic", "portraitScale")
        if UI.LayoutCapabilities(unit).classification then builder.Check("Show classification dragons", "artistic", "dragons") end
    end
    UI.BuildManualPosition(builder, unit)
end)
