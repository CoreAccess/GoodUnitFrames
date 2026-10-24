local _, GUF = ...
local UI = GUF.OptionsUI

UI.RegisterPage("frame", "Frame", function(builder, unit)
    UI.BuildFrameSize(builder, unit)
    if UI.LayoutCapabilities(unit).artwork then
        builder.Group("Portrait Scale")
        local minimum, maximum = GUF.ArtisticPortraitScaleLimits(unit)
        builder.Slider("Portrait scale", minimum, maximum, .01, true, "artistic", "portraitScale")
        if UI.LayoutCapabilities(unit).classification then builder.Check("Show classification dragons", "artistic", "dragons") end
    end
    UI.BuildManualPosition(builder, unit)
end)
