local _, GUF = ...
local UI = GUF.OptionsUI

UI.RegisterPage("general", "General", function(builder, unit)
    if unit ~= "pet" and not GUF.isRetail then
        builder.Select("Name Display", { { "full", "Full Name" }, { "first", "First Name" }, { "last", "Last Name" } }, "nameDisplay")
        builder.Row("", 32, true):Hide()
    end
    builder.Group("Combat fader")
    builder.CombatFader()
    UI.BuildCopySettings(builder, unit)
end)
