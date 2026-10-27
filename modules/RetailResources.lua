local _, GUF = ...

-- Retail adapters provide data/presentation only. Native controllers keep their
-- events and values; no native amount, fill geometry or animation is inspected.
local definitions = {
    holy = { class = "PALADIN", power = "HolyPower", color = { 1, .85, .30 }, sample = 5 },
    chi = { class = "MONK", spec = 269, power = "Chi", color = { .35, 1, .72 }, sample = 5 },
    arcane = { class = "MAGE", spec = 62, power = "ArcaneCharges", color = { .55, .45, 1 }, sample = 4 },
    essence = { class = "EVOKER", power = "Essence", color = { .35, .85, .85 }, sample = 5 },
    maelstrom = { class = "SHAMAN", spec = 263, color = { .25, .60, 1 }, sample = 10 },
    fragments = { class = "DEMONHUNTER", spec = 1480, color = { .70, .35, 1 }, meter = true, sample = 40 },
    stagger = { class = "MONK", spec = 268, color = { .35, .85, .35 }, meter = true, sample = 100 },
    shadowmana = { class = "PRIEST", power = "Mana", color = GUF.powerColors.MANA, meter = true, sample = 100 },
}
local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function specialization(unit)
    local api = C_SpecializationInfo
    local ok, spec
    if unit == "player" then
        local valid, index = call(api and api.GetSpecialization or GetSpecialization)
        if not valid or not number(index) or index < 1 then return end
        ok, spec = call(api and api.GetSpecializationInfo or GetSpecializationInfo, index)
    else
        -- Read only already exposed inspection information; never initiate an
        -- inspect request or borrow the observer's specialization/talents.
        ok, spec = call(api and api.GetInspectSpecialization or GetInspectSpecialization, unit)
    end
    if ok and number(spec) and spec > 0 then return spec end
end
local function aura(unit, spell)
    if not number(spell) then return false end
    local api = C_UnitAuras
    local ok, info
    if unit == "player" and api and api.GetPlayerAuraBySpellID then
        ok, info = call(api.GetPlayerAuraBySpellID, spell)
    else ok, info = call(api and api.GetUnitAuraBySpellID, unit, spell) end
    if not ok or GUF.Secret(info) then return false end
    if info == nil then return true end
    if type(info) == "table" then return true, info end
    return false
end
local function spellMaximum(spell)
    local ok, maximum = call(C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications, spell)
    if ok and GUF.Secret(maximum) then return nil, true end
    if ok and number(maximum) and maximum > 0 then return maximum end
end

function GUF.RetailResourceDefinition(kind)
    return GUF.isRetail and definitions[kind] or nil
end
function GUF.RetailResourcePowerType(kind)
    local def = GUF.RetailResourceDefinition(kind)
    return def and def.power and Enum and Enum.PowerType and Enum.PowerType[def.power]
end
function GUF.HasRetailResourceClass(unit)
    if not GUF.isRetail then return false end
    local _, class = UnitClass(unit)
    if GUF.Secret(class) or type(class) ~= "string" then return false end
    -- Layout hosts must exist before a specialization is known or changes.
    -- Actual resource eligibility/counts still belong to RetailResourceKind.
    for _, def in pairs(definitions) do
        if def.class == class then return true end
    end
    return false
end
function GUF.RetailResourceKind(unit)
    if not GUF.isRetail then return end
    if unit ~= "player" then
        local player = UnitIsPlayer(unit)
        if GUF.Secret(player) or not player then return end
    end
    local _, class = UnitClass(unit)
    if GUF.Secret(class) or type(class) ~= "string" then return end
    if class == "PRIEST" then
        -- Match Blizzard's secondary-Mana rule using the actual primary pool,
        -- not a spell/aura assumption or cached inspection specialization.
        local valid, primary = call(UnitPowerType, unit)
        local insanity = Enum and Enum.PowerType and Enum.PowerType.Insanity
        if valid and number(primary) and insanity and primary == insanity then return "shadowmana" end
        return
    end
    local spec = specialization(unit)
    if class == "PALADIN" then return "holy" end
    if class == "EVOKER" then return "essence" end
    for _, kind in ipairs({ "chi", "arcane", "maelstrom", "fragments", "stagger" }) do
        local def = definitions[kind]
        if def.class == class then
            if spec == def.spec then return kind end
            -- Unknown foreign specs can expose an actual class-power pool.
            -- Aura/talent-dependent maxima cannot use local spell/talent data.
            if unit ~= "player" and not spec and def.power then
                local power = GUF.RetailResourcePowerType(kind)
                local ok, maximum = call(UnitPowerMax, unit, power)
                if power and ok and number(maximum) and maximum > 0 then return kind end
            end
        end
    end
    if unit ~= "player" and not spec and class == "MONK" then
        local ok, amount = call(UnitStagger, unit)
        if ok and number(amount) and amount > 0 then return "stagger" end
    end
end

GUF.RetailResourceNativeFrames = GUF.Client.ResolveResourceFrames

local function playerCache(unit, entry)
    if unit ~= "player" or entry.unit ~= "target" then return end
    local player = GUF.frames and GUF.frames.player
    if player and player.segmentedCapacityKey == entry.segmentedCapacityKey then return player end
end

-- Returns handled, topology. Continuous meter ranges remain separate from the
-- number of prepared slots. Custom aura maxima are never guessed for Targets.
function GUF.RetailResourceCapacity(kind, unit, entry)
    local def = GUF.RetailResourceDefinition(kind)
    if not def then return false end
    entry.retailSample = nil
    -- One continuous meter, independent of the possibly opaque Mana maximum.
    -- The reader validates the actual range before replacing native visuals.
    if kind == "shadowmana" then return true, 1 end
    if def.power then
        local power = GUF.RetailResourcePowerType(kind)
        if not power then return true end
        local ok, maximum = call(UnitPowerMax, unit, power)
        if ok and GUF.Secret(maximum) then
            local player = playerCache(unit, entry)
            return true, entry.segmentedCapacity or player and player.segmentedCapacity
        end
        if ok and number(maximum) and maximum >= 1 and maximum <= 10 then
            return true, math.floor(maximum)
        end
        return true
    end
    if kind == "stagger" then return true, 1 end
    if unit ~= "player" then return true end
    if kind == "maelstrom" then
        local maximum, opaque = spellMaximum(344179)
        if opaque then
            local player = playerCache(unit, entry)
            maximum = entry.segmentedCapacity or player and player.segmentedCapacity
        end
        if maximum and maximum >= 1 and maximum <= 10 then return true, math.floor(maximum) end
        return true
    end
    local ids = Constants and Constants.UnitPowerSpellIDs
    if not ids then return true end
    local readable, meta = aura(unit, ids.VOID_METAMORPHOSIS_SPELL_ID)
    if not readable then return true end
    local spell = meta and ids.SILENCE_THE_WHISPERS_SPELL_ID or ids.DARK_HEART_SPELL_ID
    local ok, info = aura(unit, spell)
    if not ok then return true end
    local maximum, opaque
    local phase = meta and "star" or "heart"
    entry.retailLimits = entry.retailLimits or {}
    if meta then
        local valid, cost = call(GetCollapsingStarCost)
        if valid and GUF.Secret(cost) then opaque = true
        elseif valid and number(cost) and cost > 0 then maximum = cost end
    else maximum, opaque = spellMaximum(spell) end
    if opaque then
        maximum = entry.retailLimits[phase]
        local player = playerCache(unit, entry)
        if not maximum and player and player.retailLimits then maximum = player.retailLimits[phase] end
    else entry.retailLimits[phase] = maximum end
    if not maximum then return true end
    local count = 0
    if info then count = info.applications end
    if not GUF.Secret(count) and (not number(count) or count < 0) then return true end
    entry.retailSample = { value = count, maximum = maximum,
        color = meta and { .45, .65, 1 } or def.color }
    return true, 1
end

function GUF.ReadRetailResource(kind, unit, entry, maximum)
    local def = GUF.RetailResourceDefinition(kind)
    if not def then return end
    if kind == "shadowmana" then
        local power = GUF.RetailResourcePowerType(kind)
        if power == nil then return end
        local ok, value = call(UnitPower, unit, power)
        local valid, limit = call(UnitPowerMax, unit, power)
        if not ok or not valid or (not GUF.Secret(value) and (not number(value) or value < 0))
            or (not GUF.Secret(limit) and (not number(limit) or limit <= 0)) then return end
        if number(value) and number(limit) and value > limit then return end
        return { value = value, maximum = limit, color = def.color }
    end
    if kind == "fragments" then return entry.retailSample end
    if kind == "stagger" then
        local ok, value = call(UnitStagger, unit)
        local valid, limit = call(UnitHealthMax, unit)
        if not ok or not valid or (not GUF.Secret(value) and not number(value))
            or (not GUF.Secret(limit) and (not number(limit) or limit <= 0)) then return end
        local color = def.color
        if number(value) and number(limit) then
            local fraction = value / limit
            color = fraction >= .6 and { 1, .25, .20 } or fraction >= .3 and { 1, .80, .20 } or color
        end
        return { value = value, maximum = limit, color = color }
    end
    if kind == "maelstrom" then
        local ok, info = aura(unit, 344179)
        if not ok then return end
        local value = 0
        if info then value = info.applications end
        if not number(value) or value < 0 or value > maximum then return end
        return { value = value, maximum = maximum, color = def.color }
    end
    local power = GUF.RetailResourcePowerType(kind)
    local ok, value = call(UnitPower, unit, power, kind == "arcane")
    if not ok or (not GUF.Secret(value) and not number(value)) then return end
    local sample = { value = value, maximum = maximum, color = def.color }
    if kind == "essence" and unit == "player" and number(value) and value < maximum then
        local valid, partial = call(UnitPartialPower, unit, power)
        local available, rate = call(GetPowerRegenForPowerType, power)
        if valid and number(partial) and partial >= 0 and partial < 1000 then
            sample.progress = { kind = "essence", count = value, partial = partial / 1000,
                rate = available and number(rate) and math.max(0, rate) or 0, time = GetTime() }
        end
    end
    return sample
end

function GUF.ReadRetailRunes(maximum)
    local count, runes = 0, {}
    for i = 1, maximum do
        local ok, start, duration, ready = call(GetRuneCooldown, i)
        if not ok or GUF.Secret(ready) or type(ready) ~= "boolean" then return false end
        if ready then count = count + 1; runes[#runes + 1] = { ready = true, value = 1 }
        else
            local rune = { value = 0 }
            if number(start) and start > 0 and number(duration) and duration > 0 then
                rune.start, rune.duration = start, duration
                rune.value = math.min(.999, math.max(0, (GetTime() - start) / duration))
            end
            runes[#runes + 1] = rune
        end
    end
    table.sort(runes, function(a, b) return a.value > b.value end)
    return true, count, { kind = "runes", runes = runes }
end

function GUF.ReadRetailEbonMight(unit)
    if not GUF.isRetail then return end
    local _, class = UnitClass(unit)
    if GUF.Secret(class) or class ~= "EVOKER" then return end
    local spec = specialization(unit)
    if spec and spec ~= 1473 then return end
    local ok, info = aura(unit, 395296) -- Self Ebon Might, never the recipient buff.
    if not ok then return end
    if not info then return { value = 0, maximum = 20 } end
    local expiration = info.expirationTime
    if not number(expiration) then return end
    return { value = math.max(0, expiration - GetTime()), maximum = 20, expiration = expiration }
end

function GUF.RetailEbonPreview()
    return GUF.isRetail and specialization("player") == 1473
end

function GUF.ResourceRowColor(kind)
    local def = GUF.RetailResourceDefinition(kind)
    return def and def.color or kind == "runes" and GUF.powerColors.RUNES
        or kind == "shards" and GUF.powerColors.SOULSHARDS or GUF.powerColors.COMBOPOINTS
end

function GUF.ResetRetailResourceCaches()
    if not GUF.isRetail then return end
    for _, entry in pairs(GUF.frames or {}) do
        entry.segmentedCapacity, entry.segmentedCapacityKey, entry.segmentedCapacitySource = nil, nil, nil
        entry.retailSample, entry.retailLimits = nil, nil
        GUF.RestoreComboPoints(entry)
    end
end
