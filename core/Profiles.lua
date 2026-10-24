local _, GUF = ...

-- User-authorized clean start. This account marker makes the reset happen once,
-- not on every reload. No character variables or pre-reset imports are retained.
local resetGeneration = 20261014

local function migrateAddonName()
    -- New storage is authoritative. Compatibility addons load account variables
    -- only; neither legacy name registers frames, commands or runtime handlers.
    if type(GoodUnitFramesProfiles) == "table" then return end
    for _, legacy in ipairs({
        { addon = "GoldheartUnitFrames", storage = "GoldheartUnitFramesProfiles" },
        { addon = "ForeverOptions", storage = "ForeverOptionsProfiles" },
    }) do
        if type(_G[legacy.storage]) ~= "table" and C_AddOns.DoesAddOnExist(legacy.addon) then
            local loaded, reason = C_AddOns.LoadAddOn(legacy.addon)
            if not loaded then
                error("Good Unit Frames could not load the legacy profile migration addon "
                    .. legacy.addon .. " (" .. tostring(reason)
                    .. "). Enable its profile migration entry and restart the game.")
            end
        end
        local storage = _G[legacy.storage]
        if type(storage) == "table" and storage.resetGeneration == resetGeneration then
            GoodUnitFramesProfiles = storage
            _G[legacy.storage] = nil
            return
        end
    end
end

function GUF.ValidateProfileName(name)
    if type(name) ~= "string" or not name:match("%S") then return false, "Enter a profile name." end
    if #name > 64 or name:find("[%c]") then return false, "Use a profile name of at most 64 characters without control characters." end
    return true
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
                position[key] = math.max(-150, math.min(150, value))
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
                cast[key] = math.max(key == "width" and 100 or 10, math.min(key == "width" and 250 or 30, value))
            end
        end
    end
end

function GUF.AttachProfile()
    migrateAddonName()
    if type(GoodUnitFramesProfiles) ~= "table" or GoodUnitFramesProfiles.resetGeneration ~= resetGeneration then
        GoodUnitFramesProfiles = { version = 2, resetGeneration = resetGeneration,
            selectedProfile = "Default", profiles = { Default = GUF.Copy(GUF.factoryDefaults) } }
    end
    local storage = GoodUnitFramesProfiles
    if type(storage.profiles) ~= "table" then storage.profiles = {} end
    storage.profileKeys = nil
    if type(storage.profiles.Default) ~= "table" then storage.profiles.Default = GUF.Copy(GUF.factoryDefaults) end
    -- Layout selection now owns every supported unit. Remove old opt-outs from
    -- inactive profiles and style snapshots too, without resetting preferences.
    for _, profile in pairs(storage.profiles) do
        if type(profile) == "table" then
            GUF.NormalizeLayouts(profile)
            retireUnitSwitches(profile.frames)
            normalizeNameDisplays(profile.frames)
            GUF.NormalizeResourceIndicators(profile.frames)
            GUF.NormalizeNameText(profile.frames)
            GUF.NormalizeThreatText(profile.frames, profile.threat, profile.general and profile.general.frameStyle)
            GUF.NormalizeRankText(profile.frames)
            GUF.NormalizeDesignSettings(profile.frames)
            GUF.NormalizeFrameScales(profile.frames, profile.general and profile.general.frameStyle or "blizzard")
            GUF.NormalizeTextEditors(profile.frames)
            GUF.NormalizeAuraOptions(profile.frames)
            retirePredictionSettings(profile.frames)
            normalizeCombatText(profile.frames)
            GUF.NormalizeCastSettings(profile.frames, profile.general and profile.general.frameStyle or "blizzard")
            if type(profile.layouts) == "table" then
                for style, layout in pairs(profile.layouts) do
                    if type(layout) == "table" then
                        retireUnitSwitches(layout.frames)
                        normalizeNameDisplays(layout.frames)
                        GUF.NormalizeResourceIndicators(layout.frames)
                        GUF.NormalizeNameText(layout.frames)
                        GUF.NormalizeThreatText(layout.frames, layout.threat, style)
                        GUF.NormalizeRankText(layout.frames)
                        GUF.NormalizeDesignSettings(layout.frames)
                        GUF.NormalizeFrameScales(layout.frames, style)
                        GUF.NormalizeTextEditors(layout.frames)
                        GUF.NormalizeAuraOptions(layout.frames)
                        retirePredictionSettings(layout.frames)
                        normalizeCombatText(layout.frames)
                        GUF.NormalizeCastSettings(layout.frames, style)
                    end
                end
            end
        end
    end
    local name = storage.selectedProfile
    if type(name) ~= "string" or type(storage.profiles[name]) ~= "table" then
        name = "Default"
    end
    storage.version, storage.selectedProfile = 2, name
    GUF.profileStorage, GUF.profileName = storage, name
    return storage.profiles[name]
end

function GUF.ProfileNames(excludeCurrent)
    local names = {}
    for name in pairs(GUF.profileStorage and GUF.profileStorage.profiles or {}) do
        if not excludeCurrent or name ~= GUF.profileName then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

local function available()
    if GUF.Restricted() or GUF.editing then GUF.Print("Change profiles outside combat and Blizzard Edit Mode."); return false end
    if not GUF.profileStorage then GUF.Print("Profiles are not initialized yet."); return false end
    if GUF.options and GUF.options.content then GUF.options.content:Hide() end
    return true
end

local function applyProfile()
    GUF.InitializeDB()
    GUF.RequestApply()
    GUF.ApplyPanelScale(true)
    if GUF.options then GUF.BuildOptions() end
end

function GUF.SelectProfile(name)
    if not GUF.profileStorage or type(GUF.profileStorage.profiles[name]) ~= "table" or name == GUF.profileName then return end
    if not available() then return end
    GUF.profileStorage.selectedProfile = name
    applyProfile()
end

function GUF.CreateProfile(name, useDefaults)
    local ok, message = GUF.ValidateProfileName(name)
    if not ok then GUF.Print(message); return end
    name = name:match("^%s*(.-)%s*$")
    if GUF.profileStorage and GUF.profileStorage.profiles[name] then GUF.Print("A profile with that name already exists."); return end
    if not available() then return end
    GUF.profileStorage.profiles[name] = GUF.Copy(useDefaults and GUF.factoryDefaults or GUF.db)
    GUF.profileStorage.selectedProfile = name
    applyProfile()
    return true
end

function GUF.CopyProfile(source)
    if not GUF.profileStorage or source == GUF.profileName or not GUF.profileStorage.profiles[source] then return end
    if not available() then return end
    GUF.profileStorage.profiles[GUF.profileName] = GUF.Copy(GUF.profileStorage.profiles[source])
    applyProfile()
end

function GUF.ResetCurrentProfile()
    if not available() then return end
    GUF.profileStorage.profiles[GUF.profileName] = GUF.Copy(GUF.factoryDefaults)
    applyProfile()
    return true
end

function GUF.DeleteProfile(name)
    if not GUF.profileStorage or name == GUF.profileName or name == "Default" or not GUF.profileStorage.profiles[name] then return end
    if not available() then return end
    GUF.profileStorage.profiles[name] = nil
    if GUF.options then GUF.BuildOptions() end
end
