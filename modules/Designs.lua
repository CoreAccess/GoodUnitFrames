local _, GUF = ...

local catalogGeneration = 20261019
GUF.portraitDesigns = GUF.portraitDesigns or {}
local retailPortraitClasses = { DEATHKNIGHT = true, DEMONHUNTER = true, MONK = true, EVOKER = true }

-- One choice per class in the profile/layout's Player design map. Both live
-- Player and player Targets use that same choice; never an NPC's UnitClass.
function GUF.PlayerDesignClass()
    local _, class = UnitClass("player")
    if not GUF.Secret(class) and type(class) == "string" then return class end
end

function GUF.ClassPortraitDesign(class, id)
    local first
    for _, source in ipairs(GUF.portraitDesigns) do
        if source.class == class then
            first = first or source
            if source.id == id then return source end
        end
    end
    return first
end

function GUF.PortraitDesignForClass(class)
    local player = GUF.Runtime.Settings("layout", "player").frames.player
    local selections = player.design.portraits
    return class and GUF.ClassPortraitDesign(class, selections and selections[class])
end

local creatureRanks = { normal = "normal", trivial = "normal", minus = "normal",
    elite = "elite", worldboss = "elite", rareelite = "rareelite", rare = "rare" }

GUF.monsterTypes = { { "humanoid", "Humanoid" }, { "beast", "Beast" }, { "dragonkin", "Dragonkin" },
    { "undead", "Undead" }, { "elemental", "Elemental" }, { "demon", "Demon" },
    { "mechanical", "Mechanical" }, { "giant", "Giant" }, { "aberration", "Aberration" }, { "critter", "Critter" },
    { "unknown", "Unknown" } }
-- Select complete families with independent Normal/Rare/Elite/Rare Elite art.
-- Family choices retain their normal-source IDs for saved compatibility.
GUF.monsterPortraitDesigns = GUF.monsterPortraitDesigns or {}
for _, kind in ipairs(GUF.monsterTypes) do
    local ranks = GUF.creaturePortraitDesigns and GUF.creaturePortraitDesigns[kind[1]]
    if ranks and ranks.normal then
        local choices = GUF.monsterPortraitDesigns[kind[1]] or {}
        GUF.monsterPortraitDesigns[kind[1]] = choices
        local found
        for _, choice in ipairs(choices) do if choice.id == ranks.normal.id then found = true end end
        if not found then choices[#choices + 1] = { id = ranks.normal.id, name = kind[2], ranks = ranks } end
    end
end

function GUF.MonsterPortraitDesign(family, id)
    local choices = family and GUF.monsterPortraitDesigns[family]
    for _, choice in ipairs(choices or {}) do if choice.id == id then return choice end end
    return choices and choices[1]
end

function GUF.CreaturePortraitDesign(identity, classification)
    if GUF.Secret(identity) then return nil, "creature-identity-restricted" end
    if GUF.Secret(classification) then return nil, "creature-rank-restricted" end
    if type(classification) ~= "string" then return nil, "creature-rank-unavailable" end
    local family = type(identity) == "string" and identity:match("^creature%-(%l+)$")
    if not family then return nil, "creature-type-unavailable" end
    local target = GUF.db and GUF.Runtime.Settings("layout", "target").frames.target
    local selections = target and target.design.creatures
    local choice = GUF.MonsterPortraitDesign(family, selections and selections[family])
    local rank = creatureRanks[classification]
    if not choice then return nil, "creature-design-unavailable" end
    if not rank then return nil, "creature-rank-unsupported" end
    local source = choice.ranks[rank]
    return source, source and "selected" or "creature-artwork-unavailable"
end

-- Public rank is independent of creature family. An unavailable rank uses the
-- neutral Normal painting; never branch on, index with or retain a secret rank.
function GUF.UnknownPortraitDesign(classification)
    local rank = "normal"
    if not GUF.Secret(classification) and type(classification) == "string" then rank = creatureRanks[classification] or rank end
    local source = GUF.CreaturePortraitDesign("creature-unknown", rank)
    return source
end

function GUF.SelectedPortraitDesign(unit, liveUnit, sampleIdentity)
    if not GUF.LayeredDesignSettings(unit) then return nil, "layered-design-inactive" end
    local class
    if sampleIdentity then
        -- Synthetic preview identity is explicit; a creature sample must never
        -- fall through to the local player's class or the current live target.
        if unit == "target" and sampleIdentity:match("^creature%-%l+") then
            local identity, rank = sampleIdentity:match("^(creature%-%l+):(%l+)$")
            return GUF.CreaturePortraitDesign(identity or sampleIdentity, rank or "normal")
        end
        class = sampleIdentity:match("^class%-(%l+)$")
        if class then class = class:upper() end
    elseif unit == "player" then class = GUF.PlayerDesignClass()
    else
        liveUnit = liveUnit or (GUF.frames.target and GUF.frames.target.frame.unit) or "target"
        local exists, player = UnitExists(liveUnit), UnitIsPlayer(liveUnit)
        if GUF.Secret(exists) then return nil, "unit-existence-restricted" end
        if not exists then return nil, "unit-missing" end
        if GUF.Secret(player) then return nil, "player-type-restricted" end
        if not player then
            if unit ~= "target" then return nil, "unsupported-unit" end
            local identity, reason = GUF.ArtisticPortraitIdentity(unit, liveUnit)
            local classification = UnitClassification(liveUnit)
            if not identity then return GUF.UnknownPortraitDesign(classification), reason end
            local source, selectionReason = GUF.CreaturePortraitDesign(identity, classification)
            return source or GUF.UnknownPortraitDesign(classification), selectionReason
        end
        local _, token = UnitClass(liveUnit)
        if not GUF.Secret(token) and type(token) == "string" then class = token end
    end
    local source = GUF.PortraitDesignForClass(class)
    return source, source and "selected" or "class-design-unavailable"
end

function GUF.NormalizeDesignSettings(frames)
    for unit, cfg in pairs(type(frames) == "table" and frames or {}) do
        if type(cfg) == "table" then
            if type(cfg.design) ~= "table" then cfg.design = {} end
            local design = cfg.design
            if type(design.layered) ~= "table" then design.layered = {} end
            local layered = design.layered
            -- Retire artwork selections without resetting profiles or unrelated
            -- typography, scales, visibility and indicator angles.
            if design.catalogGeneration ~= catalogGeneration then
                design.ornaments = nil
                layered.ring, layered.ornament = nil, nil
                design.catalogGeneration = catalogGeneration
            end
            -- The old independent ring/ornament IDs are intentionally retired.
            -- Keep every class's new choice in inactive profiles/layouts too.
            design.ornaments, layered.ring, layered.ornament = nil, nil, nil
            if type(design.portraits) ~= "table" then design.portraits = {} end
            for class, id in pairs(design.portraits) do
                -- A shared profile may travel back to Forever, where Retail's
                -- catalog is deliberately absent. Retain its dormant choices.
                if GUF.isRetail or not retailPortraitClasses[class] or type(id) ~= "string" then
                    local source = GUF.ClassPortraitDesign(class, id)
                    design.portraits[class] = source and source.id or nil
                end
            end
            if type(design.creatures) ~= "table" then design.creatures = {} end
            for family, id in pairs(design.creatures) do
                local choice = unit == "target" and GUF.MonsterPortraitDesign(family, id)
                design.creatures[family] = choice and choice.id or nil
            end
            -- Custom bar surrounds are paused. Normalize inactive layouts and
            -- profiles too, so an old selection cannot return after switching.
            layered.bar = "blizzard"
            -- Level is permanently part of Artistic presentation. Retire
            -- the old opt-out without changing native Blizzard visibility.
            if type(cfg.hide) == "table" then cfg.hide.level = nil end
            if type(cfg.indicators) == "table" then
                -- Compact units still consume this internal presentation record,
                -- but retired opacity/placement preferences cannot hide Level.
                cfg.indicators.level = { scale = 1, x = 0, y = 0, alpha = 1,
                    point = "DEFAULT", anchor = "frame", size = 0 }
            end
            layered.enabled, layered.level = true, nil
            if type(layered.angles) ~= "table" then layered.angles = {} end
            layered.angles.level = nil
            -- Combat/resting are automatic presentation now, not adjustable
            -- badges. Keep neutral internal records for compact/native consumers.
            for _, kind in ipairs({ "combat", "resting" }) do
                layered.angles[kind] = nil
                if type(cfg.hide) == "table" then cfg.hide[kind] = nil end
                if type(cfg.indicators) == "table" then
                    cfg.indicators[kind] = { scale = 1, x = 0, y = 0, alpha = 1,
                        point = "DEFAULT", anchor = "frame", size = 0 }
                end
            end
            -- Automatic native overlays ignore retired badge preferences.
            for _, kind in ipairs({ "raid", "status", "resurrect" }) do
                layered.angles[kind] = nil
                if type(cfg.hide) == "table" then cfg.hide[kind] = nil end
                if type(cfg.indicators) == "table" then cfg.indicators[kind] = nil end
            end
            if type(cfg.artistic) == "table" then
                cfg.artistic.raidMarker = nil
                local geometry = cfg.artistic.playerGeometry
                if type(geometry) == "table" then
                    local header = geometry.header
                    geometry.header = type(header) == "number" and header == header and math.abs(header) ~= math.huge
                        and math.max(8, math.min(100, header)) or 16
                end
                GUF.NormalizeArtisticPortraitSizing(unit, cfg)
                for _, key in ipairs({ "classTrim", "ornamentStyle", "ornamentFamily", "ornamentSide",
                    "targetOrnamentSide", "hunterOrnament", "hunterOrnamentArt", "hunterTightWrap" }) do
                    cfg.artistic[key] = nil
                end
            end
        end
    end
    -- A single class preference serves both Player and Target. Keep any valid
    -- early Target map only when Player has no choice; Player remains final.
    local player = type(frames) == "table" and frames.player
    local target = type(frames) == "table" and frames.target
    if type(player) == "table" and type(target) == "table" then
        local selections = player.design.portraits
        for class, id in pairs(target.design.portraits) do
            if selections[class] == nil then selections[class] = id end
        end
        target.design.portraits = {}
    end
end

function GUF.LayoutDesignLevel(entry, sampleLevel)
    GUF.LayoutLayeredDesign(entry, sampleLevel)
end
