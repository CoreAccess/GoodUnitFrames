local _, GUF = ...
local unpack = unpack or table.unpack
local states = { { "normal", "Normal" }, { "combat", "Combat" }, { "pvp", "PvP" }, { "resting", "Resting" },
    { "casting", "Casting" }, { "channel", "Channeling" }, { "ready", "Ready" }, { "notready", "Not ready" },
    { "waiting", "Ready: waiting" }, { "dead", "Dead" }, { "ghost", "Ghost" }, { "resurrect", "Resurrection" },
    { "offline", "Offline" }, { "feign", "Feign death" } }
GUF.configurationStates = states

function GUF.PreviewPlayerLevel()
    local level = UnitLevel("player")
    if GUF.Secret(level) or type(level) ~= "number" or level < 1 then return 15 end
    return level
end

-- Legacy mode callers share the whole-frame mover. Specimens are display-only;
-- detailed component changes belong to the existing settings controls.
function GUF.SetConfigurationMode(enabled)
    if GUF.auraPreviewUnit and GUF.SetConfigurationAuraPreview then GUF.SetConfigurationAuraPreview(false) end
    GUF.SetFrameMovers(enabled)
end
