local _, GUF = ...
local nativeOwners, suppressed = {}, {}

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

local function resourcePowerType(kind)
    local types = Enum and Enum.PowerType
    local retail = GUF.RetailResourcePowerType(kind)
    if retail then return retail end
    if kind == "runes" then return types and types.Runes or 5 end
    if kind == "shards" then return types and types.SoulShards or 7 end
    return types and types.ComboPoints or 4
end

-- GetRuneCooldown has no unit argument. Only use it for our own six runes,
-- including a confirmed self-target; never substitute these for another DK.
local function readyRunes(maximum)
    return GUF.ReadRetailRunes(maximum)
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

local function legacyTargetCombo(unit, kind, source)
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

local function nativeFrames(entry)
    if entry.unit == "target" then
        local kind, source = GUF.SegmentedResourceSource("target")
        -- Only Forever's observer-owned Rogue combo row owns native combo art.
        -- Retail self/foreign Target rows never own the observer's controllers.
        if not legacyTargetCombo(entry.unit, kind, source) then return {} end
    end
    if entry.comboRow and GUF.RetailResourceDefinition(entry.comboRow.kind) then
        if entry.unit ~= "player" then return {} end
        local row, frames = entry.comboRow, {}
        if row.nativeMainReady then frames = GUF.RetailResourceNativeFrames(row.kind) end
        if row.nativeAuxReady then
            for _, frame in ipairs(GUF.RetailResourceNativeFrames("ebon")) do frames[#frames + 1] = frame end
        end
        return frames
    end
    if entry.comboRow and entry.comboRow.kind == "runes" then
        return entry.unit == "player" and { RuneFrame } or {}
    end
    if entry.comboRow and entry.comboRow.kind == "shards" then
        -- Observing a Target must never claim the player's native controllers.
        return entry.unit == "player" and { WarlockPowerFrame, ShardBarFrame } or {}
    end
    return { ComboFrame, RogueComboPointBarFrame, DruidComboPointBarFrame }
end

local function updateNativeOwnership(entry, owns)
    nativeOwners[entry] = owns and nativeFrames(entry) or nil
    local desired = {}
    for _, frames in pairs(nativeOwners) do
        for _, frame in pairs(frames) do desired[frame] = true end
    end
    for frame in pairs(suppressed) do
        if not desired[frame] then
            GUF.RegionAlpha(frame, nil)
            suppressed[frame] = nil
        end
    end
    for frame in pairs(desired) do
        suppressed[frame] = true
        GUF.RegionAlpha(frame, 0)
    end
end

function GUF.OwnsNativeComboPoints(frame)
    return suppressed[frame] == true
end

local function visible(entry, shown)
    local row = entry.comboRow
    if not row then return end
    if row.displayed ~= shown or row.layoutPrimary ~= row.primaryShown or row.layoutAux ~= row.auxShown then
        row.displayed = shown
        row.layoutPrimary, row.layoutAux = row.primaryShown, row.auxShown
        row:SetShown(shown)
        if row.integrated then GUF.LayoutTargetComboStack(entry) end
        if not entry.configurationPreview then GUF.QueueCastAuraPositions(entry) end
    end
end

function GUF.RestoreComboPoints(entry)
    if entry.comboRow then
        local row = entry.comboRow
        row.primaryShown, row.auxShown, row.progress, row.ebonExpiration = false, false, nil, nil
        row.nativeMainReady, row.nativeAuxReady = false, false
    end
    visible(entry, false)
    updateNativeOwnership(entry, false)
end

function GUF.ResetTargetResources()
    local entry = GUF.frames and GUF.frames.target
    if not entry then return end
    entry.retailSample, entry.retailLimits = nil, nil
    -- Player-owned resource capacity remains valid across retargets.
    -- Only a foreign unit's capacity must be discarded on identity change.
    if entry.segmentedCapacitySource == "target" then
        entry.segmentedCapacity, entry.segmentedCapacityKey, entry.segmentedCapacitySource = nil, nil, nil
    end
    GUF.RestoreComboPoints(entry)
end

local function capacity(otherForms, entry, preview)
    local kind, source = GUF.SegmentedResourceSource(entry.unit, preview)
    if not kind then return end
    local retail = GUF.RetailResourceDefinition(kind)
    local runes = kind == "runes"
    local ownRunes = runes and source == "player"
    if ownRunes then
        if not GetRuneCooldown then return end
    elseif not retail and not UnitPowerMax then return end
    local targetCombo = legacyTargetCombo(entry.unit, kind, source)
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
    local powerType = resourcePowerType(kind)
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

-- Reserve an internal row using configured dimensions only. Never change the
-- secure root, native bars, saved heights or portrait/Level geometry.
function GUF.LayoutTargetComboStack(entry, force)
    local state, row = entry.artisticLayout, entry.comboRow
    if not GUF.IsManagedUnit(entry.unit) then return end
    if not state or not row then return end
    if not state.active then state.targetComboStack = nil; return end
    local bars = state.renderBars or entry.configurationPreview and { health = entry.health, power = entry.power }
    if not bars then return end
    if not entry.configurationPreview and GUF.editing then GUF.pending = true; return end
    local shown = row.displayed == true
    local previous = state.targetComboStack
    local lanes = shown and ((row.primaryShown ~= false and 1 or 0) + (row.auxShown and 1 or 0)) or 1
    lanes = math.max(1, lanes)
    if not force and previous and previous.shown == shown and previous.noPower == state.noPower
        and previous.lanes == lanes and previous.primary == row.primaryShown then return end
    local scale = state.scale
    local bottom = state.healthY - state.healthRowHeight - state.powerRowHeight
    local baseHealth = state.noPower and state.healthRowHeight + state.powerRowHeight - state.healthTopInset - 2 * scale
        or state.healthFillHeight
    local basePower = state.noPower and 0 or state.powerFillHeight
    local total = baseHealth + basePower
    local cfg = GUF.PresentationFrameSettings(entry).indicators.resource
    local reserve = shown and math.min((8 * cfg.scale + 1) * scale * lanes, total * (lanes > 1 and .45 or .3)) or 0
    local factor = (total - reserve) / total
    local healthHeight, powerHeight = baseHealth * factor, basePower * factor
    local powerY = state.powerY + baseHealth - healthHeight
    local stack = { shown = shown, noPower = state.noPower, powerY = powerY, lanes = lanes, primary = row.primaryShown,
        comboY = bottom + 2 * scale + reserve, height = reserve,
        healthHeight = healthHeight, powerHeight = powerHeight }
    state.targetComboStack = stack
    local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
    entry.layoutWriting, GUF.geometryWriting = true, true
    local inset = 1.5 * scale
    local x, width = state.housingX + inset, state.housingWidth - 2 * inset
    stack.x, stack.width = x, width
    for _, kind in ipairs({ "health", "power" }) do
        local bar = bars[kind]
        local y = kind == "health" and state.healthY - state.healthTopInset or powerY - state.dividerHeight
        local height = kind == "health" and healthHeight or math.max(1, powerHeight)
        if state.renderBars then GUF.LayoutArtisticRenderedBar(entry, kind, x, y, width, height)
        else
            bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", x, y)
            bar:SetSize(width, height)
        end
        local area = state.textAreas[kind]
        area:ClearAllPoints(); area:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", state.barX + 4 * scale, y)
        area:SetSize(state.barWidth - 8 * scale, height)
        local shell = kind == "health" and state.healthShell or state.powerShell
        if shell then
            shell:ClearAllPoints(); shell:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", x, y)
            shell:SetSize(width, height)
        end
    end
    bars.power:SetShown(not state.noPower)
    if row.integrated then
        row.baseX, row.baseY = x, stack.comboY
        row:SetSize(width, math.max(state.dividerHeight, reserve))
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", row.baseX, row.baseY)
        -- Divide the visible span at the portrait's curved edge, rather than
        -- assigning its entire exposed underlap to the final point. All inputs
        -- are configured geometry; no portrait pixels or live fill bounds.
        local visibleWidth, hiddenLeft = width, 0
        local radiusX, radiusY = state.portraitWidth / 2 + scale, state.portraitHeight / 2 + scale
        local dy = (stack.comboY - reserve / 2 - state.py) / radiusY
        if math.abs(dy) < 1 then
            local reach = radiusX * math.sqrt(math.max(0, 1 - dy * dy))
            if entry.unit == "player" then
                hiddenLeft = math.max(0, math.min(width - 1, state.px + reach - x))
                visibleWidth = width - hiddenLeft
            else
                local portraitEdge = state.px - reach
                visibleWidth = math.max(1, math.min(width, portraitEdge - x))
            end
        end
        local segment = math.max(1, visibleWidth / row.capacity)
        for i = 1, row.capacity do
            local slot = row.slots[i]
            local start = hiddenLeft + (i - 1) * segment
            if entry.unit == "player" and i == 1 then start = 0 end
            slot:ClearAllPoints(); slot:SetPoint("TOPLEFT", row, "TOPLEFT", start, 0)
            local underlap = entry.unit == "player" and i == 1 and hiddenLeft
                or entry.unit == "target" and i == row.capacity and math.max(0, width - visibleWidth) or 0
            slot:SetSize(segment + underlap, math.max(1, reserve / lanes))
            slot:SetShown(row.primaryShown ~= false)
        end
        if row.aux then
            local offset = row.primaryShown and reserve / lanes or 0
            row.aux:ClearAllPoints(); row.aux:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -offset)
            row.aux:SetSize(width, math.max(1, reserve / lanes))
            row.aux:SetShown(row.auxShown == true)
        end
    end
    GUF.LayoutArtisticBarDividers(entry)
    if entry.predictions then entry.predictions.dirty = true end
    entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
    if entry.predictions then GUF.UpdatePredictionBars(entry) end
end

local function prepare(entry, maximum, kind)
    if not entry.configurationPreview and GUF.editing then GUF.pending = true; return end
    if not entry.comboRow then
        if not entry.configurationPreview and (GUF.Restricted() or GUF.editing) then GUF.pending = true; return end
        local row = CreateFrame("Frame", nil, entry.frame)
        row.goodUnitFramesOwned = true
        row:EnableMouse(false)
        row.slots = {}
        row.integrated = true
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints(); row.background:SetColorTexture(0, 0, 0, 1)
        if GUF.isRetail then
            row.aux = CreateFrame("Frame", nil, row)
            row.aux.goodUnitFramesOwned = true
            row.aux.fill = CreateFrame("StatusBar", nil, row.aux)
            row.aux.fill.goodUnitFramesOwned = true
            row.aux.fill:SetPoint("TOPLEFT", 0, -1); row.aux.fill:SetPoint("BOTTOMRIGHT")
            row.aux:Hide()
            row:SetScript("OnUpdate", function() GUF.AnimateRetailResourceRow(entry, row) end)
        end
        row:Hide()
        entry.comboRow = row
    end
    local row, state = entry.comboRow, entry.artisticLayout
    if not entry.configurationPreview and GUF.Restricted() then
        local protected = row:IsProtected()
        if GUF.Secret(protected) or protected then GUF.pending = true; return end
    end
    if #row.slots < maximum and not entry.configurationPreview and (GUF.Restricted() or GUF.editing) then
        GUF.pending = true
        return
    end
    row.kind = kind or "combo"
    row.currentColor = nil
    local cfg = GUF.PresentationFrameSettings(entry).indicators.resource
    local scale = state.scale
    local effectiveScale = row:GetEffectiveScale()
    local separator = number(effectiveScale) and effectiveScale > 0 and 1 / effectiveScale or 1
    row:SetFrameLevel(entry.frame:GetFrameLevel() + 12)
    if row.integrated then
        local bars = state.renderBars or { health = entry.health }
        row:SetFrameLevel(bars.health:GetFrameLevel())
    end
    row.background:SetShown(row.integrated)
    -- Span the visible bar rails at the default scale, flush below their
    -- lowest border. Smaller resource scales keep the row centered.
    local width = math.max(1, state.barWidth * math.min(cfg.scale, 1))
    local height = 8 * scale * cfg.scale
    local segment = math.max(1, width / maximum)
    row:SetSize(width, height)
    row:SetAlpha(cfg.alpha)
    row.baseX = state.barX + state.barWidth / 2 - width / 2 + cfg.x
    row.baseY = state.healthY - state.healthRowHeight - state.powerRowHeight + cfg.y
    -- Prepare the supported pool outside combat. A public capacity change can
    -- then repartition the same owned frames immediately (five, six, etc.).
    local pool = entry.configurationPreview or not GUF.Restricted() and not GUF.editing
    for i = 1, pool and 10 or maximum do
        local slot = row.slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, row)
            slot.goodUnitFramesOwned = true
            slot.edge = slot:CreateTexture(nil, "BACKGROUND")
            slot.edge:SetAllPoints(); slot.edge:SetColorTexture(.43, .34, .19, 1)
            slot.back = slot:CreateTexture(nil, "BORDER")
            slot.back:SetPoint("TOPLEFT", 1, -1); slot.back:SetPoint("BOTTOMRIGHT", -1, 1)
            slot.back:SetColorTexture(.10, .085, .055, 1)
            slot.left = slot:CreateTexture(nil, "OVERLAY")
            slot.left:SetPoint("TOPLEFT"); slot.left:SetPoint("BOTTOMLEFT")
            slot.fill = CreateFrame("StatusBar", nil, slot)
            slot.fill.goodUnitFramesOwned = true
            slot.fill:SetPoint("TOPLEFT", 1, -1); slot.fill:SetPoint("BOTTOMRIGHT", -1, 1)
            row.slots[i] = slot
        end
        local color = GUF.ResourceRowColor(row.kind)
        if row.kind == "runes" then slot.fill:SetMinMaxValues(0, 1)
        else slot.fill:SetMinMaxValues(i - 1, i) end
        GUF.StyleClassResourceFill(entry, slot.fill, color)
        slot.edge:SetShown(not row.integrated); slot.back:SetShown(not row.integrated)
        slot.left:SetShown(row.integrated and i > 1)
        slot.fill:ClearAllPoints()
        if row.integrated then
            slot.left:SetColorTexture(0, 0, 0, 1)
            if slot.left.SetSnapToPixelGrid then slot.left:SetSnapToPixelGrid(true) end
            if slot.left.SetTexelSnappingBias then slot.left:SetTexelSnappingBias(0) end
            slot.left:SetWidth(separator)
            slot.left:SetShown(i > 1)
            slot.fill:SetPoint("TOPLEFT", i > 1 and separator or 0, 0)
            slot.fill:SetPoint("BOTTOMRIGHT")
        else
            slot.fill:SetPoint("TOPLEFT", 1, -1); slot.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        end
        slot:ClearAllPoints(); slot:SetPoint("LEFT", row, "LEFT", (i - 1) * segment, 0)
        slot:SetSize(segment, height); slot:Show()
    end
    for i = maximum + 1, #row.slots do row.slots[i]:Hide() end
    row.capacity = maximum
    if row.aux then GUF.StyleClassResourceFill(entry, row.aux.fill, { .85, .65, .25 }) end
    if row.integrated then GUF.LayoutTargetComboStack(entry, true) end
    return row
end

function GUF.RefreshClassResourceTexture(entry)
    local row = entry.comboRow
    if not row then return end
    local color = row.currentColor or GUF.ResourceRowColor(row.kind)
    for _, slot in ipairs(row.slots) do GUF.StyleClassResourceFill(entry, slot.fill, color) end
    if row.aux then GUF.StyleClassResourceFill(entry, row.aux.fill, { .85, .65, .25 }) end
end

-- Only the plain row/slot wrappers participate in geometry. A StatusBar that
-- receives an opaque combo amount must never become a geometry/count source.
function GUF.ComboAuraBounds(entry)
    local row = entry.comboRow
    if not row or not row.displayed then return end
    if not entry.configurationPreview and GUF.editing then return end
    local protected = row:IsProtected()
    if not entry.configurationPreview and GUF.Restricted() and (GUF.Secret(protected) or protected) then
        GUF.pending = true
        return row.bounds
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", row.baseX, row.baseY)
    local stack = row.integrated and entry.artisticLayout.targetComboStack
    local rect
    if stack then
        local top = entry.artisticLayout.height + stack.comboY
        rect = { left = stack.x, right = stack.x + stack.width, bottom = top - stack.height, top = top }
    else rect = GUF.FrameRectInUnit(entry, row) end
    if not rect then return end
    local cast = not row.integrated and GUF.CastAuraBounds(entry)
    if cast and rect.left < cast.right and rect.right > cast.left and rect.bottom < cast.top and rect.top > cast.bottom then
        -- Move our row beneath a visible cast (including its icon and gap).
        -- Native cast anchors/controllers and saved offsets remain untouched.
        local shift = cast.bottom - rect.top
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", row.baseX, row.baseY + shift)
        rect.bottom, rect.top = rect.bottom + shift, rect.top + shift
    end
    local gap = 6 * entry.artisticLayout.scale
    row.bounds = { left = rect.left - gap, right = rect.right + gap, bottom = rect.bottom - gap, top = rect.top + gap }
    return row.bounds
end

function GUF.LayoutComboPoints(entry)
    local kind = GUF.SegmentedResourceSource(entry.unit)
    -- Prepare Cat's other forms, every Target and potential Retail Player
    -- resources even before a specialization is known/eligible. A placeholder
    -- only allocates hidden slots; live capacity still comes from its reader.
    local maximum = capacity(true, entry)
    local retail = GUF.RetailResourceDefinition(kind)
    local potential = entry.unit == "player" and GUF.HasRetailResourceClass("player")
    if maximum or entry.unit == "target" or retail or potential then
        prepare(entry, maximum or (retail and retail.meter and 1 or 5), kind)
    end
    if not kind then GUF.RestoreComboPoints(entry); return end
    GUF.UpdateComboPoints(entry)
end

function GUF.UpdateComboPoints(entry)
    local kind, source = GUF.SegmentedResourceSource(entry.unit)
    if not kind then GUF.RestoreComboPoints(entry); return end
    local state = entry.artisticLayout
    if entry.configurationPreview or not state or not state.active then return end
    local maximum = capacity(false, entry)
    local row = entry.comboRow
    -- Late spec detection can occur after the initial layout skipped this row.
    -- Recover a missing row too; prepare defers creation under restrictions.
    if maximum and (not row or row.capacity ~= maximum or row.kind ~= kind) then
        row = prepare(entry, maximum, kind)
    end
    local ready = maximum and row and row.capacity == maximum and row.kind == kind and not GUF.editing
    local ok, points, progress, sample
    local retail = GUF.RetailResourceDefinition(kind)
    if ready then
        if retail then
            sample = GUF.ReadRetailResource(kind, source, entry, maximum)
            ok, points = sample ~= nil, sample and sample.value
            progress = sample and sample.progress
        elseif kind == "runes" and source == "player" then ok, points, progress = readyRunes(maximum)
        elseif not legacyTargetCombo(entry.unit, kind, source) then
            ok, points = pcall(UnitPower, source, resourcePowerType(kind))
        else ok, points = pcall(GetComboPoints, "player", "target") end
    end
    ready = ready and ok and (GUF.Secret(points) or number(points))
    if ready and (kind == "runes" or kind == "essence") then
        if source ~= "player" and GUF.Secret(points) then ready = false
        elseif not GUF.Secret(points) then
            ready = points >= 0 and points <= maximum and points == math.floor(points)
        end
    end
    if maximum and (not row or row.capacity ~= maximum or row.kind ~= kind) then GUF.pending = true end
    local cfg = GUF.db.frames[entry.unit]
    local exists = UnitExists(entry.unit)
    local enabled = entry.unit == "target" or kind == "combo" or not cfg.hide.resource
    local shown = ready and not GUF.Secret(exists) and exists and enabled and cfg.indicators.resource.alpha > 0
    if shown then
        -- Recharge rows and continuous secondary Mana remain visible at zero.
        -- Missing/invalid data still hides; foreign timing is never inferred.
        if not GUF.Secret(points) then shown = kind == "runes" or kind == "essence" or kind == "shadowmana" or points > 0
        elseif source ~= "player" then
            -- No native Target visibility authority exists for these resources.
            -- Never borrow the observer's icons/counts for a foreign target.
            shown = false
        else
            -- Follow only a public native resource-indicator visibility decision;
            -- never inspect its secret amount or borrow another bar's value.
            local native
            if retail then native = GUF.RetailResourceNativeFrames(kind)[1]
            elseif kind == "shards" then native = ShardBarFrame or WarlockPowerFrame
            elseif kind == "runes" then native = RuneFrame
            elseif kind == "combo" and not legacyTargetCombo(entry.unit, kind, source) then
                local _, class = UnitClass("player")
                native = not GUF.Secret(class) and (class == "DRUID" and DruidComboPointBarFrame
                    or class == "ROGUE" and RogueComboPointBarFrame) or nil
                native = native or ComboFrame
            else native = ComboFrame end
            local nativeShown = native and native:IsShown()
            if not GUF.Secret(nativeShown) and type(nativeShown) == "boolean" then shown = nativeShown
            else shown = row.primaryShown == true end
        end
    end
    local aux = maximum and row and row.aux and kind == "essence" and not GUF.editing
        and GUF.ReadRetailEbonMight(source)
    local auxReady = aux and number(aux.value) and number(aux.maximum) and aux.maximum > 0
    local auxShown = auxReady and enabled and not GUF.Secret(exists) and exists and aux.value > 0
        and cfg.indicators.resource.alpha > 0
    if row then
        row.nativeMainReady, row.nativeAuxReady = not not ready, not not auxReady
        row.progress = ready and progress or nil
        row.primaryShown, row.auxShown = not not shown, not not auxShown
        row.ebonExpiration = auxReady and aux.expiration or nil
        if auxReady then
            row.aux.fill:SetMinMaxValues(0, aux.maximum); row.aux.fill:SetValue(aux.value)
        end
        local color = sample and sample.color or GUF.ResourceRowColor(kind)
        local previous = row.currentColor
        if not previous or previous[1] ~= color[1] or previous[2] ~= color[2] or previous[3] ~= color[3] then
            row.currentColor = color
            GUF.RefreshClassResourceTexture(entry)
        end
    end
    updateNativeOwnership(entry, ready or auxReady)
    if ready then
        for i = 1, maximum do
            local fill = row.slots[i].fill
            if retail and retail.meter then fill:SetMinMaxValues(0, sample.maximum); fill:SetValue(points)
            elseif kind == "runes" then
                local value = progress and progress.runes[i].value or (i <= points and 1 or 0)
                fill:SetValue(value)
            else fill:SetValue(points) end
        end
    end
    visible(entry, not not (shown or auxShown))
    if row and row.aux then row.aux:SetShown(row.auxShown) end
    if row then GUF.AnimateRetailResourceRow(entry, row) end
    GUF.ComboAuraBounds(entry)
end

function GUF.PreviewComboPoints(entry, shown)
    local kind = GUF.SegmentedResourceSource(entry.unit, true)
    if not kind or GUF.db.general.frameStyle ~= "artistic" then
        visible(entry, false)
        return false
    end
    if entry.unit == "target" and (kind ~= "combo" or GUF.isRetail) and entry.previewClassification
        and entry.previewClassification ~= "player" then
        visible(entry, false)
        return true
    end
    local retail = GUF.RetailResourceDefinition(kind)
    local maximum = capacity(true, entry, true) or (retail and (retail.meter and 1 or retail.sample) or kind == "runes" and 6 or 5)
    local row = prepare(entry, maximum, kind)
    if not row then return false end
    row.progress, row.ebonExpiration = nil, nil
    row.currentColor = GUF.ResourceRowColor(kind)
    for i = 1, maximum do
        local fill = row.slots[i].fill
        if retail and retail.meter then fill:SetMinMaxValues(0, retail.sample); fill:SetValue(retail.sample * .55)
        elseif kind == "runes" then fill:SetValue(i <= 3 and 1 or .4)
        else fill:SetValue(math.min(3, maximum)) end
    end
    row.primaryShown = not not (shown and GUF.db.frames[entry.unit].indicators.resource.alpha > 0)
    row.auxShown = row.primaryShown and kind == "essence" and GUF.RetailResourceKind("player") == "essence"
        and GUF.RetailEbonPreview()
    if row.auxShown then row.aux.fill:SetMinMaxValues(0, 20); row.aux.fill:SetValue(12) end
    GUF.RefreshClassResourceTexture(entry)
    entry.resource = row
    visible(entry, row.primaryShown or not not row.auxShown)
    if row.aux then row.aux:SetShown(not not row.auxShown) end
    GUF.ComboAuraBounds(entry)
    return true
end

-- Manual snapshot only: never stringify opaque values or change live caches,
-- request inspections, read native amounts, or start a diagnostic update loop.
function GUF.ShowResourceReport()
    if GUF.editing or GUF.Restricted() then
        GUF.Print("Open diagnostic reports outside combat and Edit Mode."); return
    end
    local function value(item)
        if GUF.Secret(item) then return "<restricted>" end
        if item == nil then return "<unavailable>" end
        local kind = type(item)
        if kind == "string" or kind == "boolean" or number(item) then return tostring(item) end
        return "<unsupported>"
    end
    local function read(fn, ...)
        if type(fn) ~= "function" then return "<unsupported API>" end
        local ok, item = pcall(fn, ...)
        if not ok then return "<API error>" end
        return value(item)
    end
    local lines = { "Class resource report v1; retail=" .. value(GUF.isRetail)
        .. "; forever=" .. value(GUF.isForever) .. "; layout=" .. value(GUF.db.general.frameStyle) }
    for _, unit in ipairs({ "player", "target" }) do
        local kind, source = GUF.SegmentedResourceSource(unit)
        local entry = GUF.frames and GUF.frames[unit]
        local row = entry and entry.comboRow
        local _, class = UnitClass(unit)
        lines[#lines + 1] = "\n" .. unit .. ": exists=" .. read(UnitExists, unit)
            .. "; player=" .. read(UnitIsPlayer, unit) .. "; class=" .. value(class)
            .. "; powerType=" .. read(UnitPowerType, unit)
        lines[#lines + 1] = "selected=" .. value(kind) .. "; source=" .. value(source)
            .. "; active=" .. value(entry and entry.artisticLayout and entry.artisticLayout.active)
            .. "; displayed=" .. value(row and row.displayed)
            .. "; rowKind=" .. value(row and row.kind) .. "; capacity=" .. value(row and row.capacity)
        lines[#lines + 1] = "cachedKey=" .. value(entry and entry.segmentedCapacityKey)
            .. "; cachedCapacity=" .. value(entry and entry.segmentedCapacity)
        for _, pool in ipairs({ "combo", "shards", "runes", "holy", "chi", "arcane", "essence", "shadowmana" }) do
            if GUF.isRetail or pool == "combo" or pool == "shards" then
                local power = resourcePowerType(pool)
                if pool == "combo" or pool == "shards" or pool == "runes" or GUF.RetailResourcePowerType(pool) then
                    lines[#lines + 1] = pool .. ": count=" .. read(UnitPower, unit, power, pool == "arcane")
                        .. "; maximum=" .. read(UnitPowerMax, unit, power, pool == "arcane")
                end
            end
        end
        if GUF.isRetail then
            lines[#lines + 1] = "stagger=" .. read(UnitStagger, unit) .. "; healthMax=" .. read(UnitHealthMax, unit)
            local ids = Constants and Constants.UnitPowerSpellIDs
            for _, spell in ipairs({ 344179, 395296, ids and ids.DARK_HEART_SPELL_ID,
                ids and ids.SILENCE_THE_WHISPERS_SPELL_ID }) do
                local api = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
                local ok, info
                if api then ok, info = pcall(api, unit, spell) end
                local detail = "<unsupported API>"
                if ok then
                    if GUF.Secret(info) then detail = "<restricted>"
                    elseif info == nil then detail = "<absent>"
                    elseif type(info) == "table" then
                        detail = "applications=" .. value(info.applications) .. "; expiration=" .. value(info.expirationTime)
                    end
                elseif api then detail = "<API error>" end
                lines[#lines + 1] = "aura " .. value(spell) .. ": " .. detail
            end
        end
    end
    lines[#lines + 1] = "\nForeign rows use only exposed Target data; zero need not prove generation is observable."
    lines[#lines + 1] = "Foreign Maelstrom Weapon/Devourer maxima and rune recharge timing are unavailable through local-only APIs."
    GUF.ShowDiagnosticReport("Class resources", table.concat(lines, "\n"))
end
