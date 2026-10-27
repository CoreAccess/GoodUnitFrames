local _, GUF = ...


local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function GUF.LayoutTargetComboStack(entry, force)
    return GUF.Presentation.Feature(entry, "layoutResources", force)
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
        row:SetScript("OnUpdate", nil)
    end
    visible(entry, false)
    GUF.UpdateNativeResourceOwnership(entry, false)
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

local function prepare(entry, maximum, kind)
    if not entry.configurationPreview and GUF.editing then GUF.DeferRuntime("native-readiness"); return end
    if not entry.comboRow then
        if not entry.configurationPreview and (GUF.Restricted() or GUF.editing) then GUF.DeferRuntime("native-readiness"); return end
        local row = GUF.Runtime.CreateFrame("Frame", nil, entry.frame)
        row.goodUnitFramesOwned = true
        row:EnableMouse(false)
        row.slots = {}
        row.integrated = true
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints(); row.background:SetColorTexture(0, 0, 0, 1)
        if GUF.isRetail then
            row.aux = GUF.Runtime.CreateFrame("Frame", nil, row)
            row.aux.goodUnitFramesOwned = true
            row.aux.fill = GUF.Runtime.CreateFrame("StatusBar", nil, row.aux)
            row.aux.fill.goodUnitFramesOwned = true
            row.aux.fill:SetPoint("TOPLEFT", 0, -1); row.aux.fill:SetPoint("BOTTOMRIGHT")
            row.aux:Hide()
            row.animate = function()
                if entry.comboRow ~= row then row:SetScript("OnUpdate", nil); return end
                GUF.AnimateRetailResourceRow(entry, row)
                if not GUF.ResourceRowNeedsAnimation(row) then row:SetScript("OnUpdate", nil) end
            end
        end
        row:Hide()
        entry.comboRow = row
        GUF.Runtime.Constructed()
    end
    local row, state = entry.comboRow, GUF.Presentation.Role(entry, "resourceGeometry")
    if not state then return end
    if not entry.configurationPreview and GUF.Restricted() then
        local protected = row:IsProtected()
        if GUF.Secret(protected) or protected then GUF.DeferRuntime("native-readiness"); return end
    end
    if #row.slots < maximum and not entry.configurationPreview and (GUF.Restricted() or GUF.editing) then
        GUF.DeferRuntime("native-readiness")
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
        local bars = { health = GUF.Presentation.Role(entry, "health") }
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
    row.baseY = state.bottom + cfg.y
    -- Prepare the supported pool outside combat. A public capacity change can
    -- then repartition the same owned frames immediately (five, six, etc.).
    local pool = entry.configurationPreview or not GUF.Restricted() and not GUF.editing
    for i = 1, pool and 10 or maximum do
        local slot = row.slots[i]
        if not slot then
            slot = GUF.Runtime.CreateFrame("Frame", nil, row)
            slot.goodUnitFramesOwned = true
            slot.edge = slot:CreateTexture(nil, "BACKGROUND")
            slot.edge:SetAllPoints(); slot.edge:SetColorTexture(.43, .34, .19, 1)
            slot.back = slot:CreateTexture(nil, "BORDER")
            slot.back:SetPoint("TOPLEFT", 1, -1); slot.back:SetPoint("BOTTOMRIGHT", -1, 1)
            slot.back:SetColorTexture(.10, .085, .055, 1)
            slot.left = slot:CreateTexture(nil, "OVERLAY")
            slot.left:SetPoint("TOPLEFT"); slot.left:SetPoint("BOTTOMLEFT")
            slot.fill = GUF.Runtime.CreateFrame("StatusBar", nil, slot)
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
        GUF.DeferRuntime("native-readiness")
        return row.bounds
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", row.baseX, row.baseY)
    local stack = row.integrated and GUF.Presentation.Role(entry, "resourceBounds")
    local rect
    if stack then
        rect = stack
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
    local gap = GUF.Presentation.Role(entry, "featureGap") or 6
    row.bounds = { left = rect.left - gap, right = rect.right + gap, bottom = rect.bottom - gap, top = rect.top + gap }
    return row.bounds
end

function GUF.LayoutComboPoints(entry)
    local kind = GUF.SegmentedResourceSource(entry.unit)
    -- Prepare Cat's other forms, every Target and potential Retail Player
    -- resources even before a specialization is known/eligible. A placeholder
    -- only allocates hidden slots; live capacity still comes from its reader.
    local maximum = GUF.SegmentedResourceCapacity(true, entry)
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
    if entry.configurationPreview or not GUF.Presentation.Role(entry, "resources") then return end
    local maximum = GUF.SegmentedResourceCapacity(false, entry)
    local row = entry.comboRow
    -- Late spec detection can occur after the initial layout skipped this row.
    -- Recover a missing row too; prepare defers creation under restrictions.
    if maximum and (not row or row.capacity ~= maximum or row.kind ~= kind) then
        row = prepare(entry, maximum, kind)
    end
    local ready = maximum and row and row.capacity == maximum and row.kind == kind and not GUF.editing
    local ok, points, progress, sample
    local retail = GUF.RetailResourceDefinition(kind)
    if ready then ok, points, progress, sample = GUF.ReadSegmentedResource(kind, source, entry, maximum) end
    ready = ready and ok and (GUF.Secret(points) or number(points))
    if ready and (kind == "runes" or kind == "essence") then
        if source ~= "player" and GUF.Secret(points) then ready = false
        elseif not GUF.Secret(points) then
            ready = points >= 0 and points <= maximum and points == math.floor(points)
        end
    end
    if maximum and (not row or row.capacity ~= maximum or row.kind ~= kind) then GUF.DeferRuntime("native-readiness") end
    local cfg = GUF.Runtime.Settings("layout", entry).frames[entry.unit]
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
            local nativeShown = GUF.NativeResourceVisible(entry, kind, source)
            if nativeShown ~= nil then shown = nativeShown
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
    GUF.UpdateNativeResourceOwnership(entry, ready or auxReady)
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
    if row then
        GUF.AnimateRetailResourceRow(entry, row)
        row:SetScript("OnUpdate", GUF.ResourceRowNeedsAnimation(row) and row.animate or nil)
    end
    GUF.ComboAuraBounds(entry)
end

function GUF.PreviewComboPoints(entry, shown)
    local kind = GUF.SegmentedResourceSource(entry.unit, true)
    if not kind or not GUF.Presentation.Role(entry, "resources") then
        visible(entry, false)
        return false
    end
    if entry.unit == "target" and (kind ~= "combo" or GUF.isRetail) and entry.previewClassification
        and entry.previewClassification ~= "player" then
        visible(entry, false)
        return true
    end
    local retail = GUF.RetailResourceDefinition(kind)
    -- Synthetic topology stays independent of live amounts and reader caches.
    local maximum = retail and (retail.meter and 1 or retail.sample) or kind == "runes" and 6 or 5
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
    row.primaryShown = not not (shown and GUF.Runtime.Settings("layout", entry).frames[entry.unit].indicators.resource.alpha > 0)
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

-- Sample eligibility and geometry use the same class/resource presenter as
-- live frames. Layouts without the role allocate no substitute resource art.
function GUF.RenderResourceSample(entry, scenario)
    local capabilities = entry.presentationContext.definition.capabilities(entry.unit)
    local cfg = GUF.PresentationFrameSettings(entry)
    local shown = capabilities.classResources and GUF.Presentation.Role(entry, "resources") ~= nil
        and (GUF.ComboPointUnit() == entry.unit or not cfg.hide.resource or scenario.showAll)
    return GUF.PreviewComboPoints(entry, shown)
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
        .. "; forever=" .. value(GUF.isForever) .. "; layout=" .. value(GUF.Runtime.Settings("layout", entry).general.frameStyle) }
    for _, unit in ipairs({ "player", "target" }) do
        local kind, source = GUF.SegmentedResourceSource(unit)
        local entry = GUF.frames and GUF.frames[unit]
        local row = entry and entry.comboRow
        local _, class = UnitClass(unit)
        lines[#lines + 1] = "\n" .. unit .. ": exists=" .. read(UnitExists, unit)
            .. "; player=" .. read(UnitIsPlayer, unit) .. "; class=" .. value(class)
            .. "; powerType=" .. read(UnitPowerType, unit)
        lines[#lines + 1] = "selected=" .. value(kind) .. "; source=" .. value(source)
            .. "; active=" .. value(entry and GUF.Presentation.Role(entry, "resources") ~= nil)
            .. "; displayed=" .. value(row and row.displayed)
            .. "; rowKind=" .. value(row and row.kind) .. "; capacity=" .. value(row and row.capacity)
        lines[#lines + 1] = "cachedKey=" .. value(entry and entry.segmentedCapacityKey)
            .. "; cachedCapacity=" .. value(entry and entry.segmentedCapacity)
        for _, pool in ipairs({ "combo", "shards", "runes", "holy", "chi", "arcane", "essence", "shadowmana" }) do
            if GUF.isRetail or pool == "combo" or pool == "shards" then
                local power = GUF.SegmentedResourcePowerType(pool)
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

-- Animation uses only cached public timing. Resource queries remain on existing
-- events/quarter-second state updates; hidden specimens never drive live state.
function GUF.AnimateRetailResourceRow(entry, row)
    if entry.configurationPreview or not row.displayed then return end
    local now, progress = GetTime(), row.progress
    if row.primaryShown and progress then
        if progress.kind == "runes" then
            for i, rune in ipairs(progress.runes) do
                local value = rune.value
                if rune.start then value = math.min(.999, math.max(0, (now - rune.start) / rune.duration)) end
                row.slots[i].fill:SetValue(value)
            end
        elseif progress.kind == "essence" then
            local value = progress.count + math.min(.999, progress.partial + math.max(0, now - progress.time) * progress.rate)
            for i = 1, row.capacity do row.slots[i].fill:SetValue(value) end
        end
    end
    if row.auxShown and row.ebonExpiration then
        row.aux.fill:SetValue(math.max(0, row.ebonExpiration - now))
    end
end


-- Only validated public recharge timing is an animation source. Full/static
-- resource rows keep their event/fallback updates without a frame-rate driver.
function GUF.ResourceRowNeedsAnimation(row)
    if not row.displayed then return false end
    local now, progress = GetTime(), row.progress
    if row.auxShown and row.ebonExpiration and row.ebonExpiration > now then return true end
    if row.primaryShown and progress then
        if progress.kind == "runes" then
            for _, rune in ipairs(progress.runes) do
                if rune.start and now < rune.start + rune.duration then return true end
            end
        elseif progress.kind == "essence" then
            return progress.rate > 0 and progress.count < row.capacity
                and progress.partial + math.max(0, now - progress.time) * progress.rate < 1
        end
    end
    return false
end
