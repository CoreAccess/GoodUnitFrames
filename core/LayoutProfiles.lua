local _, GUF = ...

-- Compatibility is confined here. Renderers and controls use Artistic names.
local function renameSetting(settings, old, current)
    if settings[current] == nil then settings[current] = settings[old] end
    settings[old] = nil
end

local function migrateArtisticSettings(settings)
    local frames = settings.frames
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        if type(cfg) == "table" then renameSetting(cfg, "classic", "artistic") end
    end
    local threat = settings.threat
    if type(threat) == "table" then
        for _, suffix in ipairs({ "Diameter", "Width", "Height" }) do
            renameSetting(threat, "classic" .. suffix, "artistic" .. suffix)
        end
    end
end

function GUF.NormalizeLayouts(profile)
    -- Migrate before schema normalization/default merging, across every account
    -- profile and saved layout. Existing destination snapshots stay authoritative.
    for _, retired in ipairs({ { "classic", "artistic" }, { "hunter", "artistic" },
        { "vanilla", "blizzard" }, { "custom", "blizzard" } }) do
        local key, replacement = retired[1], retired[2]
        if type(profile.general) == "table" and profile.general.frameStyle == key then
            profile.general.frameStyle = replacement
        end
        local layouts = profile.layouts
        if type(layouts) == "table" and layouts[key] ~= nil then
            -- Keep an existing supported snapshot. Otherwise retain the useful
            -- old preferences under its replacement; active frames stay authoritative.
            if type(layouts[replacement]) ~= "table" and type(layouts[key]) == "table" then
                layouts[replacement] = layouts[key]
            end
            layouts[key] = nil
        end
    end
    migrateArtisticSettings(profile)
    for _, layout in pairs(type(profile.layouts) == "table" and profile.layouts or {}) do
        if type(layout) == "table" then migrateArtisticSettings(layout) end
    end
end

function GUF.GetLayoutDefaults(style)
    return GUF.factoryLayoutDefaults[style]
end

function GUF.SelectLayout(style)
    local defaults = GUF.GetLayoutDefaults(style)
    if not defaults then return end
    local available
    for _, layout in ipairs(GUF.frameStyles) do
        if layout[1] == style and not layout.disabled then available = true; break end
    end
    if not available then return end
    local profile = GUF.db
    local current = profile.general.frameStyle
    if current == style then return end
    -- Each account profile remembers the settings for each style. The active
    -- tables remain authoritative while controls edit them; snapshot on exit.
    profile.layouts = profile.layouts or {}
    profile.layouts[current] = { frames = GUF.Copy(profile.frames), threat = GUF.Copy(profile.threat),
        hideBlizzard = GUF.Copy(profile.hideBlizzard) }
    local saved = profile.layouts[style] or defaults
    profile.frames, profile.threat = GUF.Copy(saved.frames), GUF.Copy(saved.threat)
    profile.hideBlizzard = GUF.Copy(saved.hideBlizzard)
    profile.general.frameStyle = style
    GUF.RequestApply()
end
