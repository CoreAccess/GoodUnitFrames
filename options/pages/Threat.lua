local _, GUF = ...
local UI = GUF.OptionsUI

function UI.BuildThreat(builder)
    builder.Group()
    local artistic = GUF.db.general.frameStyle == "artistic"
    builder.Check(artistic and "Show Target threat meter" or "Show Target threat panel", "threat", "enabled")
end
