local _, GUF = ...
local Settings = {}
GUF.Settings = Settings

-- One preparation order for active profiles and saved layouts. These helpers
-- change configuration only; native discovery, live data and apply stay outside.

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

local function retireUnitSwitches(frames)
    if type(frames) ~= "table" then return end
    for _, settings in pairs(frames) do
        if type(settings) == "table" then settings.enabled = nil end
    end
end

local function normalizeNameDisplays(frames)
    if type(frames) ~= "table" then return end
    for _, unit in ipairs(GUF.order) do
        local cfg = frames[unit]
        if type(cfg) == "table" then
            if unit == "pet" then cfg.nameDisplay = nil
            elseif cfg.nameDisplay ~= "first" and cfg.nameDisplay ~= "last" and cfg.nameDisplay ~= "full" then cfg.nameDisplay = "full" end
        end
    end
end

local function retirePredictionSettings(frames)
    if type(frames) ~= "table" then return end
    for _, cfg in pairs(frames) do
        local bars = type(cfg) == "table" and cfg.bars
        if type(bars) == "table" then
            bars.nativePredictions = nil
            for _, key in ipairs({ "incHeal", "incAbsorb", "healAbsorb" }) do
                if type(bars[key]) == "table" then bars[key].texture = nil end
            end
        end
    end
end

local function normalizeCombatText(frames)
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        if type(cfg) == "table" then
            if type(cfg.combatText) == "table" then cfg.combatText.native = nil end
            local feedback = type(cfg.indicators) == "table" and cfg.indicators.feedback
            if type(feedback) == "table" then
                local scale = feedback.scale
                if type(scale) ~= "number" or scale ~= scale or scale == math.huge or scale == -math.huge then scale = 1 end
                -- Retain the renderer multiplier; snap old choices to the
                -- new control's half-unit steps without repeat conversion.
                feedback.scale = math.max(.5, math.min(2, math.floor(scale * 4 + .5) / 4))
            end
        end
    end
end

local castPoints = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local castOutlines = { [""] = true, OUTLINE = true, THICKOUTLINE = true, ["MONOCHROME,OUTLINE"] = true }

function GUF.NormalizeCastSettings(frames, style)
    local defaults = GUF.defaults.frames.player.bars.cast
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        local cast = type(cfg) == "table" and cfg.bars and cfg.bars.cast
        if type(cast) == "table" then
            cast.native = nil
            cast.autoHide = nil -- Empty cast bars always hide; retire the old preference.
            for _, kind in ipairs({ "name", "time" }) do
                local label = cast[kind]
                if type(label) == "table" and (type(label.outline) ~= "string" or not castOutlines[label.outline]) then
                    -- Retire the old inherited choice in every profile/layout.
                    label.outline = style == "blizzard" and "" or (castOutlines[cfg.outline or ""] and cfg.outline or "OUTLINE")
                end
            end
            cast.avoidAuras = nil -- Cast/aura avoidance is always active.
            if cast.icon == "BLIZZARD" then cast.icon = "LEFT" end
            if type(cast.position) ~= "table" then cast.position = {} end
            local position = cast.position
            local legacyDefault = position.point == "DEFAULT"
            if type(position.point) ~= "string" or not castPoints[position.point] then
                position.point = legacyDefault and "TOPLEFT" or defaults.position.point
            end
            if type(position.relativePoint) ~= "string" or not castPoints[position.relativePoint] then
                position.relativePoint = legacyDefault and "BOTTOMLEFT" or defaults.position.relativePoint
            end
            for _, key in ipairs({ "x", "y" }) do
                local value = position[key]
                if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
                    value = legacyDefault and 0 or defaults.position[key]
                end
                if legacyDefault and key == "y" then value = value - 6 end
                local definition = Settings.controls["cast.position." .. key]
                position[key] = math.max(definition.minimum, math.min(definition.maximum, value))
            end
            if cast.font == "Blizzard" then cast.font = "Default" end
            if type(cast.font) ~= "string" or cast.font == "" then
                cast.font = style == "blizzard" and "Default" or cfg.font or "Default"
            end
            for _, key in ipairs({ "width", "height" }) do
                local value = cast[key]
                if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value <= 0 then
                    value = defaults[key]
                end
                local definition = Settings.controls["cast." .. key]
                cast[key] = math.max(definition.minimum, math.min(definition.maximum, value))
            end
        end
    end
end

local function merge(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            -- A composition is an ordered list, including intentionally empty
            -- lists. Never merge default pieces into a user's shorter format.
            if key == "parts" then
                if type(target[key]) ~= "table" then target[key] = GUF.Copy(value) end
            else
                if type(target[key]) ~= "table" then target[key] = {} end
                merge(target[key], value)
            end
        elseif type(target[key]) ~= type(value) then target[key] = value end
    end
end

-- Repair invalid schema types without adding missing fields yet. Legacy text,
-- aura and appearance migrations must see what was actually saved before merge.
-- Ordered text compositions are atomic, including an intentionally empty list.
local function repairTypes(target, defaults)
    for key, value in pairs(defaults) do
        local saved = target[key]
        if saved ~= nil then
            if type(saved) ~= type(value) then target[key] = nil
            elseif type(value) == "table" and key ~= "parts" then repairTypes(saved, value)
            elseif type(value) == "number" and (saved ~= saved or math.abs(saved) == math.huge) then
                target[key] = nil
            end
        end
    end
end

local function schemaVersion(value)
    local version = tonumber(value)
    return version and version == version and math.abs(version) ~= math.huge and math.max(0, version) or 0
end

local layoutSchema = { frames = GUF.defaults.frames, threat = GUF.defaults.threat,
    hideBlizzard = GUF.defaults.hideBlizzard }

local function normalizeExisting(database, style)
    local frames = database.frames
    retireUnitSwitches(frames)
    normalizeNameDisplays(frames)
    GUF.NormalizeResourceIndicators(frames)
    GUF.NormalizeNameText(frames)
    GUF.NormalizeThreatText(frames, database.threat, style)
    GUF.NormalizeRankText(frames)
    GUF.NormalizeDesignSettings(frames, style)
    GUF.NormalizeFrameScales(frames, style)
    GUF.NormalizeTextEditors(frames)
    GUF.NormalizeAuraOptions(frames)
    retirePredictionSettings(frames)
    normalizeCombatText(frames)
    GUF.NormalizeCastSettings(frames, style)
end

-- sourceVersion supplies the owning profile's version for old unversioned
-- snapshots. Never guess that a snapshot is version zero and replay historical
-- geometry/fading conversions over an already customized modern layout.
function Settings.PrepareLayout(database, style, sourceVersion)
    local version = schemaVersion(database.version == nil and sourceVersion or database.version)
    repairTypes(database, layoutSchema)
    normalizeExisting(database, style)
    if version < 2 then
        -- Update previous default geometry while retaining customized settings.
        local threat = database.threat
        if type(threat) == "table" then
            if threat.width == 100 then threat.width = GUF.defaults.threat.width end
            if threat.y == 6 then threat.y = GUF.defaults.threat.y end
        end
    end
    if version < 3 then
        -- Align the badge with the name background; preserve custom offsets.
        local threat = database.threat
        if type(threat) == "table" and threat.y == 2 then threat.y = GUF.defaults.threat.y end
    end
    -- Seed independent formats from the saved abbreviation preference.
    for _, cfg in pairs(database.frames or {}) do
        if type(cfg) == "table" and not cfg.combatText then
            local feedback = cfg.indicators and cfg.indicators.feedback
            cfg.combatText = { enabled = false, point = "CENTER",
                x = feedback and feedback.x or 0, y = feedback and feedback.y or 0 }
        end
        if type(cfg) == "table" and not cfg.text then
            cfg.text = GUF.Copy(GUF.defaults.frames.player.text)
            cfg.text.health.abbreviate = cfg.abbreviate ~= false
            cfg.text.power.abbreviate = cfg.abbreviate ~= false
        end
    end
    for _, cfg in pairs(database.frames or {}) do
        if type(cfg) == "table" then GUF.MigrateAuras(cfg.auras) end
    end
    if version < 11 and type(database.hideBlizzard) ~= "table" then
        -- Preserve the previous effective Player replacement preference.
        local player = database.frames and database.frames.player
        local auras = player and player.auras
        local buffs, debuffs = false, false
        if player and auras and auras.replaceDefault ~= false then
            for _, cfg in ipairs(auras.buffs or {}) do if cfg.enabled then buffs = true; break end end
            for _, cfg in ipairs(auras.debuffs or {}) do if cfg.enabled then debuffs = true; break end end
        end
        database.hideBlizzard = { buffs = buffs and debuffs, debuffs = buffs and debuffs }
    end
    -- Seed from existing formats BEFORE merge; new defaults must not replace custom text.
    for unit, cfg in pairs(database.frames or {}) do
        if type(cfg) == "table" and cfg.text then
            local automatic = unit == "player" and cfg.healthText == "currentmax" and cfg.powerText == "currentmax"
                and cfg.text.health and not cfg.text.health.split and cfg.text.health.abbreviate ~= false
                and cfg.text.power and not cfg.text.power.split
            for _, kind in ipairs({ "health", "power" }) do
                if cfg.text[kind] then
                    GUF.SeedTextFields(cfg, kind, automatic)
                    if cfg.text[kind].fieldLayout == nil then
                        cfg.text[kind].fieldLayout = unit == "player" and (automatic or cfg[kind .. "Text"] ~= "blizzard")
                    end
                end
            end
        end
    end
    GUF.NormalizeThreatText(database.frames, database.threat, style)
    merge(database, layoutSchema)
    GUF.NormalizeResourceIndicators(database.frames)
    GUF.NormalizeNameText(database.frames)
    GUF.NormalizeThreatText(database.frames, database.threat, style)
    GUF.NormalizeRankText(database.frames)
    GUF.NormalizeFrameScales(database.frames, style)
    GUF.NormalizeDesignSettings(database.frames, style)
    GUF.NormalizeTextEditors(database.frames)
    GUF.NormalizeAuraOptions(database.frames)
    for _, unit in ipairs(GUF.order) do
        local bars = database.frames[unit].bars
        if bars.width < 0 then
            local width = GUF.ArtisticLegacyBarSize(unit, "health", database.frames[unit])
            -- Accommodate interim separate-width fields without retaining two owners.
            if type(bars.healthSize.width) == "number" and bars.healthSize.width >= 0 then width = bars.healthSize.width end
            bars.width = width
        end
        bars.healthSize.width, bars.powerSize.width = nil, nil
    end
    if version < 12 then
        -- Preserve the current Artistic live-bar sizes when moving controls out of Frame.
        -- Keep old frame dimensions stored for other layouts and legacy fallback.
        for _, unit in ipairs(GUF.order) do
            for _, kind in ipairs({ "health", "power" }) do
                local _, height = GUF.ArtisticLegacyBarSize(unit, kind, database.frames[unit])
                local settings = database.frames[unit].bars[kind .. "Size"]
                if settings.height < 0 then settings.height = height end
            end
        end
    end
    for _, unit in ipairs(GUF.order) do
        local cfg = database.frames[unit]
        -- Retire the experimental 50-200% range when loading/selecting profiles.
        cfg.artistic.portraitScale = math.max(1, math.min(1.5, cfg.artistic.portraitScale))
        if unit ~= "target" then cfg.auras.replaceDefault = nil end
        if unit == "pet" then cfg.nameDisplay = nil
        elseif cfg.nameDisplay ~= "first" and cfg.nameDisplay ~= "last" and cfg.nameDisplay ~= "full" then cfg.nameDisplay = "full" end
        if version < 4 then
            -- Preserve the old effective fading percentages when retiring normal opacity.
            local alpha = type(cfg.alpha) == "number" and cfg.alpha or 1
            cfg.fading.combat = math.max(0, math.min(1, cfg.fading.combat * alpha))
            cfg.fading.inactive = math.max(0, math.min(1, cfg.fading.inactive * alpha))
        end
        if cfg.healthColor == "gradient" then cfg.healthColor = "percent"
        elseif cfg.healthColor == "custom" then cfg.healthColor = "static"
        elseif cfg.healthColor ~= "class" and cfg.healthColor ~= "percent" and cfg.healthColor ~= "static" and cfg.healthColor ~= "blizzard" then
            cfg.healthColor = "class"
        end
        if cfg.bars.powerMode ~= "class" and cfg.bars.powerMode ~= "blizzard" then cfg.bars.powerMode = "type" end
        for _, key in ipairs({ "incAbsorb", "incHeal", "healAbsorb" }) do
            local prediction = cfg.bars[key]
            -- Prediction artwork always inherits the visible Health bar.
            prediction.texture = nil
            prediction.opacity = math.max(0, math.min(1, prediction.opacity))
            -- Placement follows the effect's meaning; retain enablement and appearance choices.
            prediction.display = nil
            prediction.anchorMode, prediction.frameEdge, prediction.cap = nil, nil, nil
            prediction.barSize, prediction.barAlign = nil, nil
            if key ~= "incAbsorb" then prediction.showAtFullHealth = nil end
        end
        cfg.powerColor, cfg.hide.power = nil, nil
        cfg.bars.customPower, cfg.bars.healthBackground, cfg.bars.powerBackground = nil, nil, nil
        cfg.bars.healthBackgroundColor, cfg.bars.powerBackgroundColor, cfg.bars.backgroundAlpha = nil, nil, nil
        cfg.alpha = nil
        cfg.artwork = nil
        cfg.hide.feedback = nil
        cfg.indicators.feedback.x, cfg.indicators.feedback.y = nil, nil
        cfg.hide.portrait, cfg.hide.name, cfg.hide.border = nil, nil, nil
        cfg.fading.duration, cfg.fading.mouseover, cfg.fading.delay = nil, nil, nil
    end
    if style == "flat" then GUF.NormalizeFlatSettings(database.frames) end
    database.version = math.max(version, GUF.defaults.version)
    return database
end

local function supportedLayout(style)
    return GUF.Layouts.IsAvailable(style)
end

function Settings.PrepareProfile(profile)
    GUF.NormalizeLayouts(profile)
    local version = schemaVersion(profile.version)
    local generalSchema = { general = GUF.defaults.general }
    repairTypes(profile, generalSchema)
    merge(profile, generalSchema)
    local style = profile.general.frameStyle
    if not supportedLayout(style) then
        style = GUF.defaults.general.frameStyle
        profile.general.frameStyle = style
    end
    -- Prepare snapshots before advancing their owner's version. Unknown layout
    -- data stays dormant and intact; a future definition can own its migration.
    for savedStyle, layout in pairs(type(profile.layouts) == "table" and profile.layouts or {}) do
        if type(layout) == "table" and supportedLayout(savedStyle) then
            Settings.PrepareLayout(layout, savedStyle, version)
        end
    end
    Settings.PrepareLayout(profile, style, version)
    profile.general.globalUnits = nil
    profile.editMode = nil
    return profile
end

-- Active tables stay authoritative. Missing snapshots use a private copy of the
-- factory template; inspecting a card never switches or snapshots the profile.
function Settings.GetLayout(profile, style)
    if not supportedLayout(style) then return end
    if profile.general.frameStyle == style then return profile end
    local saved = type(profile.layouts) == "table" and profile.layouts[style]
    if type(saved) == "table" then return Settings.PrepareLayout(saved, style, profile.version) end
    local defaults = GUF.GetLayoutDefaults(style)
    if defaults then return Settings.PrepareLayout(GUF.Copy(defaults), style, GUF.defaults.version) end
end

function Settings.CaptureLayout(profile)
    return { version = profile.version, frames = GUF.Copy(profile.frames),
        threat = GUF.Copy(profile.threat), hideBlizzard = GUF.Copy(profile.hideBlizzard) }
end
