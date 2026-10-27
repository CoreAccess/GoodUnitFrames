local _, GUF = ...

-- Permitted unit data and public topology only; no frame creation or writes.
local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function GUF.UsesComboPoints(unit)
    unit = unit or "player"
    if unit ~= "player" then
        if not GUF.isRetail then return false end
        local player = UnitIsPlayer(unit)
        if GUF.Secret(player) or not player then return false end
    end
    local class
    if UnitClassBase then class = UnitClassBase(unit)
    else local _, token = UnitClass(unit); class = token end
    return not GUF.Secret(class) and (class == "ROGUE" or class == "DRUID")
end

function GUF.UsesSoulShards(unit)
    local _, class = UnitClass(unit or "player")
    return not GUF.Secret(class) and class == "WARLOCK"
end

function GUF.UsesRunes(unit)
    if not GUF.isRetail then return false end
    unit = unit or "player"
    if unit == "target" then
        local player = UnitIsPlayer("target")
        if GUF.Secret(player) or not player then return false end
    end
    local _, class = UnitClass(unit)
    return not GUF.Secret(class) and class == "DEATHKNIGHT"
end

function GUF.SegmentedResourcePowerType(kind)
    local types = Enum and Enum.PowerType
    local retail = GUF.RetailResourcePowerType(kind)
    if retail then return retail end
    if kind == "runes" then return types and types.Runes or 5 end
    if kind == "shards" then return types and types.SoulShards or 7 end
    return types and types.ComboPoints or 4
end

function GUF.ComboPointUnit()
    local class
    if UnitClassBase then class = UnitClassBase("player")
    else local _, token = UnitClass("player"); class = token end
    if GUF.Secret(class) then return end
    if class == "DRUID" then return "player" end
    if class == "ROGUE" then
        if GUF.isRetail then return "player" end
        if GUF.isForever then return "target" end
    end
end

function GUF.LegacyTargetCombo(unit, kind, source)
    return GUF.isForever and unit == "target" and kind == "combo" and source == "player"
end

function GUF.SegmentedResourceSource(unit, preview)
    local comboUnit = GUF.ComboPointUnit()
    -- Forever Rogue combos retain the Target row even against a Warlock.
    if comboUnit ~= nil and unit == comboUnit then return "combo", "player" end
    if unit == "player" or (preview and unit == "target") then
        if GUF.isRetail and GUF.UsesComboPoints() then return "combo", "player" end
        if GUF.UsesSoulShards() then return "shards", "player" end
        if GUF.UsesRunes() then return "runes", "player" end
        local retail = GUF.RetailResourceKind("player")
        if retail then return retail, "player" end
    elseif unit == "target" then
        local same = UnitIsUnit and UnitIsUnit("target", "player")
        if GUF.isRetail then
            if not GUF.Secret(same) and same == true and GUF.UsesComboPoints() then return "combo", "player" end
            if GUF.UsesComboPoints("target") then return "combo", "target" end
        end
        if not GUF.Secret(same) and same == true and GUF.UsesSoulShards() then return "shards", "player" end
        if not GUF.Secret(same) and same == true and GUF.UsesRunes() then return "runes", "player" end
        if GUF.UsesSoulShards("target") then return "shards", "target" end
        if GUF.UsesRunes("target") then return "runes", "target" end
        if not GUF.Secret(same) and same == true then
            local retail = GUF.RetailResourceKind("player")
            if retail then return retail, "player" end
        else
            local retail = GUF.RetailResourceKind("target")
            if retail then return retail, "target" end
        end
    end
end

function GUF.UsesSegmentedResources(unit, preview)
    return GUF.SegmentedResourceSource(unit, preview) ~= nil
end


function GUF.SegmentedResourceCapacity(otherForms, entry, preview)
    local kind, source = GUF.SegmentedResourceSource(entry.unit, preview)
    if not kind then return end
    local retail = GUF.RetailResourceDefinition(kind)
    local runes = kind == "runes"
    local ownRunes = runes and source == "player"
    if ownRunes then
        if not GetRuneCooldown then return end
    elseif not retail and not UnitPowerMax then return end
    local targetCombo = GUF.LegacyTargetCombo(entry.unit, kind, source)
    if (targetCombo and not GetComboPoints) or (not targetCombo and not ownRunes and not UnitPower) then return end
    -- Vehicle resources keep their native controller/display. Never guess its
    -- unit, capacity or self-target exceptions from the player's last points.
    if UnitHasVehicleUI then
        local vehicle = UnitHasVehicleUI(source)
        if GUF.Secret(vehicle) or vehicle then return end
    end
    local class = retail and retail.class or runes and "DEATHKNIGHT" or "WARLOCK"
    if kind == "combo" then
        if UnitClassBase then class = UnitClassBase(source)
        else local _, token = UnitClass(source); class = token end
    end
    if GUF.Secret(class) or type(class) ~= "string" then return end
    local key = kind .. ":" .. source .. ":" .. class
    if entry.segmentedCapacityKey ~= key then
        entry.segmentedCapacityKey, entry.segmentedCapacity = key, nil
    end
    entry.segmentedCapacitySource = source
    if retail then
        local _, maximum = GUF.RetailResourceCapacity(kind, source, entry)
        entry.segmentedCapacity = maximum
        return maximum
    end
    -- Retail DK topology is always six. Other units still require their own
    -- public UnitPowerMax; never manufacture a foreign capacity/count.
    if ownRunes then entry.segmentedCapacity = 6; return 6 end
    if kind == "combo" and class == "DRUID" and not otherForms then
        local powerType = UnitPowerType(source)
        local energy = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
        if GUF.Secret(powerType) or powerType ~= energy then return end
    end
    local powerType = GUF.SegmentedResourcePowerType(kind)
    local ok, maximum = pcall(UnitPowerMax, source, powerType)
    if not ok then entry.segmentedCapacity = nil; return end
    -- Retain only previously public topology if combat makes the maximum
    -- opaque. A public zero/unsupported maximum invalidates that cache.
    if GUF.Secret(maximum) then
        if not entry.segmentedCapacity and source == "player" and entry.unit == "target" then
            local player = GUF.frames and GUF.frames.player
            if player and player.segmentedCapacityKey == key then return player.segmentedCapacity end
        end
        return entry.segmentedCapacity
    end
    if number(maximum) and maximum >= 1 and maximum <= 10 and (not runes or maximum == 6) then
        entry.segmentedCapacity = math.floor(maximum)
        return entry.segmentedCapacity
    end
    entry.segmentedCapacity = nil
end


-- Amounts may be opaque. The caller forwards them to owned renderers and
-- performs only its existing guarded eligibility/visibility decisions.
function GUF.ReadSegmentedResource(kind, source, entry, maximum)
    if GUF.RetailResourceDefinition(kind) then
        local sample = GUF.ReadRetailResource(kind, source, entry, maximum)
        return sample ~= nil, sample and sample.value, sample and sample.progress, sample
    end
    -- GetRuneCooldown has no unit argument; foreign DKs never borrow it.
    if kind == "runes" and source == "player" then return GUF.ReadRetailRunes(maximum) end
    if GUF.LegacyTargetCombo(entry.unit, kind, source) then return pcall(GetComboPoints, "player", "target") end
    return pcall(UnitPower, source, GUF.SegmentedResourcePowerType(kind))
end
