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
        return key and "class-" .. key
    end
    if frameUnit ~= "target" and frameUnit ~= "pet" and frameUnit ~= "targettarget" then return end
    liveUnit = liveUnit or frameUnit
    local exists = UnitExists(liveUnit)
    if GUF.Secret(exists) or not exists then return end
    local player = UnitIsPlayer(liveUnit)
    if GUF.Secret(player) then return end
    if player then
        local key = classKey(liveUnit)
        return key and "class-" .. key
    end
    -- NPC UnitClass is not their visual identity; use public creature type.
    local name, id = UnitCreatureType(liveUnit)
    local key = not GUF.Secret(id) and type(id) == "number" and creatureIDs[id]
    if not key and not GUF.Secret(name) and type(name) == "string" then key = creatureNames[name] end
    return key and "creature-" .. key
end


function GUF.SelectArtisticPortraitArtwork(frameUnit, liveUnit, sampleIdentity)
    return GUF.SelectedPortraitDesign(frameUnit, liveUnit, sampleIdentity) or GUF.BlizzardRingArtwork(frameUnit)
end
