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
    for _, profile in pairs(storage.profiles) do
        if type(profile) == "table" then GUF.Settings.PrepareProfile(profile) end
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
    GUF.RequestApply(nil, nil, "profile")
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
