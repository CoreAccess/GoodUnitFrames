local _, GUF = ...
-- Public class/creature identities remain useful to the preview and future art.
local classes = { DRUID = "druid", HUNTER = "hunter", MAGE = "mage", PALADIN = "paladin",
    PRIEST = "priest", ROGUE = "rogue", SHAMAN = "shaman", WARLOCK = "warlock", WARRIOR = "warrior" }
if GUF.isRetail then
    classes.DEATHKNIGHT, classes.DEMONHUNTER = "deathknight", "demonhunter"
    classes.MONK, classes.EVOKER = "monk", "evoker"
end
-- CreatureType table IDs returned by UnitCreatureType; not localized labels.
local creatureIDs = { [1] = "beast", [2] = "dragonkin", [3] = "demon", [4] = "elemental",
    [5] = "giant", [6] = "undead", [7] = "humanoid", [8] = "critter", [9] = "mechanical", [15] = "aberration" }
local creatureNames = { Aberration = "aberration", Beast = "beast", Demon = "demon", Dragonkin = "dragonkin",
    Elemental = "elemental", Giant = "giant", Humanoid = "humanoid", Mechanical = "mechanical",
    Undead = "undead", Critter = "critter" }

local function classKey(unit)
    local _, class = UnitClass(unit)
    return not GUF.Secret(class) and type(class) == "string" and classes[class]
end

function GUF.ArtisticPortraitIdentity(frameUnit, liveUnit)
    if frameUnit == "player" then
        local key = classKey("player")
        return key and "class-" .. key, key and "selected" or "class-unavailable"
    end
    if frameUnit ~= "target" and frameUnit ~= "pet" and frameUnit ~= "targettarget" then return nil, "unsupported-unit" end
    liveUnit = liveUnit or frameUnit
    local exists = UnitExists(liveUnit)
    if GUF.Secret(exists) then return nil, "unit-existence-restricted" end
    if not exists then return nil, "unit-missing" end
    local player = UnitIsPlayer(liveUnit)
    if GUF.Secret(player) then return nil, "player-type-restricted" end
    if player then
        local key = classKey(liveUnit)
        return key and "class-" .. key, key and "selected" or "class-unavailable"
    end
    -- NPC UnitClass is not their visual identity; use public creature type.
    local name, id = UnitCreatureType(liveUnit)
    local key = not GUF.Secret(id) and type(id) == "number" and creatureIDs[id]
    if not key and not GUF.Secret(name) and type(name) == "string" then key = creatureNames[name] end
    if key then return "creature-" .. key, "selected" end
    if GUF.Secret(id) or GUF.Secret(name) then return nil, "creature-type-restricted" end
    if name == nil and id == nil then return nil, "creature-type-unavailable" end
    return nil, "creature-type-unsupported"
end


function GUF.SelectArtisticPortraitArtwork(frameUnit, liveUnit, sampleIdentity)
    local source, reason = GUF.SelectedPortraitDesign(frameUnit, liveUnit, sampleIdentity)
    return source or GUF.BlizzardRingArtwork(frameUnit), reason
end

-- Retain one public failure reason for a live entry, not a unit identity or a
-- selection cache. Recovery, clearing Target and leaving Artistic preserve it
-- until another meaningful fallback or reload. Specimens never contribute.
function GUF.RememberPortraitArtworkFallback(entry, source, reason)
    if GUF.frames[entry.unit] ~= entry or not source or not (source.native or source.unknown) or not reason
        or reason == "selected" or reason == "unit-missing" or reason == "layered-design-inactive" then return end
    entry.lastPortraitFallbackReason = reason
end

-- On-demand selection metadata only. This can diagnose a restricted-map
-- fallback without opening the geometry report or logging unit payloads.
function GUF.PrintPortraitArtworkStatus()
    if not GUF.db then GUF.Print("Portrait settings are not initialized yet."); return end
    local function public(value)
        if GUF.Secret(value) then return "<restricted>" end
        return tostring(value)
    end
    GUF.Print("Portrait selection v3; interface=" .. public(GUF.clientInterface)
        .. "; layout=" .. public(GUF.db.general.frameStyle))
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if not entry then
            GUF.Print(unit .. ": frame-unavailable")
        else
            local state = entry.artisticLayout
            local liveUnit = entry.frame.unit or unit
            local candidate, reason
            if GUF.Secret(liveUnit) then reason = "unit-token-restricted"
            else candidate, reason = GUF.SelectedPortraitDesign(unit, liveUnit) end
            local rendered = state and state.rim and state.rim.source
            GUF.Print(unit .. ": candidate=" .. public(candidate and candidate.id or "native-fallback")
                .. "; rendered=" .. public(rendered and rendered.id or "unattached")
                .. "; reason=" .. public(reason) .. "; active=" .. public(state and state.active or false))
            GUF.Print(unit .. ".lastFallback=" .. public(entry.lastPortraitFallbackReason or "none-recorded")
                .. " (since reload; may precede current target)")
        end
    end
end
