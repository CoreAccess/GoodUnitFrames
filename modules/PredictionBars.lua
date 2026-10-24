local _, GUF = ...
local unpack = unpack or table.unpack
local kinds = { "incAbsorb", "incHeal", "healAbsorb" }
local nativeKeys = { "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar",
    "OverAbsorbGlow", "OverHealAbsorbGlow", "overAbsorbGlow", "overHealAbsorbGlow",
    "myHealPrediction", "otherHealPrediction", "healAbsorbBar", "totalAbsorb" }

local fullHealthCurve, missingHealthCurve
local function healthAlphas(unit, maximum)
    -- Let the client evaluate the full-health threshold, then pass the resulting
    -- alpha straight to the renderer. Health may be secret during combat.
    if UnitHealthPercent and C_CurveUtil and C_CurveUtil.CreateCurve
        and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        if not fullHealthCurve then
            fullHealthCurve = C_CurveUtil.CreateCurve()
            fullHealthCurve:SetType(Enum.LuaCurveType.Step)
            fullHealthCurve:AddPoint(0, 0)
            fullHealthCurve:AddPoint(1, 1)
            missingHealthCurve = C_CurveUtil.CreateCurve()
            missingHealthCurve:SetType(Enum.LuaCurveType.Step)
            missingHealthCurve:AddPoint(0, 1)
            missingHealthCurve:AddPoint(1, 0)
        end
        local fullOK, full = pcall(UnitHealthPercent, unit, false, fullHealthCurve)
        local missingOK, missing = pcall(UnitHealthPercent, unit, false, missingHealthCurve)
        if fullOK and missingOK then return full, missing end
    end
    local current = UnitHealth(unit, false)
    if not GUF.Secret(current) and not GUF.Secret(maximum) and maximum > 0 then
        if current >= maximum then return 1, 0 end
        return 0, 1
    end
    return 0, 0
end

local function createBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.goodUnitFramesOwned = true
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetDrawLayer("ARTWORK")
    bar:Hide()
    return bar
end

local function createClip(parent)
    local clip = CreateFrame("Frame", nil, parent)
    clip.goodUnitFramesOwned = true
    clip:SetClipsChildren(true)
    return clip
end

local function predictionTexture(health)
    local source = health and health:GetStatusBarTexture()
    local file = source and source:GetTexture()
    local atlas = source and source.GetAtlas and source:GetAtlas()
    if GUF.Secret(file) or not file then file = "Interface\\TargetingFrame\\UI-StatusBar" end
    if GUF.Secret(atlas) then atlas = nil end
    return file, atlas
end

local function styleBar(bar, cfg, health)
    -- Copy artwork only from the actual visible Health bar. This also inherits
    -- stock atlases and layout/provider fallbacks without a second media choice.
    local file, atlas = predictionTexture(health)
    bar:SetStatusBarTexture(file)
    local fill = bar:GetStatusBarTexture()
    if atlas then fill:SetAtlas(atlas) else fill:SetTexCoord(0, 1, 0, 1) end
    fill:SetDesaturated(true)
    fill:SetDrawLayer("ARTWORK")
    bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3], cfg.opacity)
end

GUF.StylePredictionBar = styleBar

local function publicNumber(value)
    return not GUF.Secret(value) and type(value) == "number"
end

local function maskPresentation(source, fill, health)
    -- Read the static mask only, never the amount-driven Health fill's size/UVs.
    local width, height = source:GetSize()
    if not publicNumber(width) or not publicNumber(height) or width <= 0 or height <= 0 then return end
    local points = GUF.ReadPoints(source)
    if not points or #points == 0 then return end
    for _, point in ipairs(points) do
        if not publicNumber(point[4]) or not publicNumber(point[5]) then return end
        -- Fill-relative masks must describe the complete Health shape, even
        -- while a prediction bar slides along the current Health edge.
        if point[2] == fill then point[2] = health end
    end
    local file, coords = source:GetTexture(), { source:GetTexCoord() }
    if GUF.Secret(file) or not file or (#coords ~= 4 and #coords ~= 8) then return end
    for _, value in ipairs(coords) do if not publicNumber(value) then return end end
    return { width = width, height = height, file = file, coords = coords, points = points }
end

local function sameMask(a, b)
    if not a or a.width ~= b.width or a.height ~= b.height or a.file ~= b.file
        or #a.coords ~= #b.coords or #a.points ~= #b.points then return false end
    for i, value in ipairs(b.coords) do if a.coords[i] ~= value then return false end end
    for i, point in ipairs(b.points) do
        for j = 1, 5 do if a.points[i][j] ~= point[j] then return false end end
    end
    return true
end

local function applyMasks(bar, sources)
    local fill = bar:GetStatusBarTexture()
    local records = bar.goodUnitFramesPredictionMasks or {}
    bar.goodUnitFramesPredictionMasks = records
    for source, presentation in pairs(sources) do
        local record = records[source]
        if presentation ~= false then
            if not record then
                local mask = bar:CreateMaskTexture(nil, "ARTWORK")
                mask.goodUnitFramesOwned = true
                record = { mask = mask }; records[source] = record
            end
            if not sameMask(record.presentation, presentation) then
                record.mask:SetTexture(presentation.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
                record.mask:SetTexCoord(unpack(presentation.coords))
                record.mask:SetSize(presentation.width, presentation.height)
                record.mask:ClearAllPoints()
                for _, point in ipairs(presentation.points) do record.mask:SetPoint(unpack(point)) end
                record.presentation = presentation
            end
            if record.target ~= fill then
                if record.target then record.target:RemoveMaskTexture(record.mask) end
                fill:AddMaskTexture(record.mask); record.target = fill
            end
        end
    end
    for source, record in pairs(records) do
        if sources[source] == nil and record.target then
            record.target:RemoveMaskTexture(record.mask); record.target = nil
        end
    end
end

local function refreshMasks(state, health)
    -- Geometry/media writes and new regions wait for the existing public
    -- refresh tick after combat/Edit Mode. Amount updates keep their renderer.
    if GUF.Restricted() or GUF.editing then return end
    local fill = health:GetStatusBarTexture()
    if not fill then return end
    local count = 0
    if fill.GetNumMaskTextures and fill.GetMaskTexture then count = fill:GetNumMaskTextures() end
    if not publicNumber(count) then return end
    local sources = {}
    for i = 1, count do
        local source = fill:GetMaskTexture(i)
        if not GUF.Secret(source) and source and not source.goodUnitFramesOwned then
            -- An unreadable attachment is not a removed attachment. Preserve
            -- its last public copy until geometry becomes available again.
            sources[source] = maskPresentation(source, fill, health) or false
        end
    end
    for _, item in pairs(state.bars) do
        applyMasks(item.bar, sources)
        if item.fullBar then applyMasks(item.fullBar, sources) end
    end
end

local function createPrediction(entry)
    local state = { bars = {}, native = {} }
    entry.predictions = state
    local health = GUF.ArtisticBarHost(entry, "health")
    state.textLayer = CreateFrame("Frame", nil, health ~= entry.health and entry.frame or entry.health)
    state.textLayer.goodUnitFramesOwned = true
    state.textLayer:SetAllPoints(GUF.ArtisticBarHost(entry, "health"))
    state.textHost = health
    if CreateUnitHealPredictionCalculator then
        state.calc = CreateUnitHealPredictionCalculator()
        state.calc:SetHealAbsorbMode(1)
    end
    for _, kind in ipairs(kinds) do
        local clip = createClip(entry.frame)
        local item = { clip = clip, bar = createBar(clip) }
        if kind == "incAbsorb" then
            item.fullClip = createClip(entry.frame)
            item.fullBar = createBar(item.fullClip)
        end
        state.bars[kind] = item
    end
    entry.health:HookScript("OnSizeChanged", function() state.dirty = true end)
    hooksecurefunc(entry.health, "SetStatusBarTexture", function() state.dirty = true end)
    hooksecurefunc(entry.health, "SetFrameLevel", function() state.dirty = true end)
    return state
end

function GUF.LayerHealthText(entry, text)
    local state = entry.predictions
    if not state or not text or not text.SetParent then return end
    local current = text:GetParent()
    local parent = state.textLayer
    if not parent or current == parent then return end
    -- Parent changes are applied with the rest of the options outside combat.
    if GUF.Restricted() then GUF.pending = true; return end
    text:SetParent(parent)
end

local function layout(entry)
    local state, health = entry.predictions, GUF.ArtisticBarHost(entry, "health")
    local level = health:GetFrameLevel()
    if GUF.Secret(level) then return false end
    local strata = health:GetFrameStrata()
    if GUF.Secret(strata) then return false end
    local parent = health ~= entry.health and entry.frame or entry.health
    local changedHost = state.textHost ~= health or state.textLayer:GetParent() ~= parent
    if changedHost then
        if GUF.Restricted() or GUF.editing then GUF.pending = true; return false end
        state.textLayer:SetParent(parent)
        -- Follow the renderer through engine anchors, without reading its
        -- possibly opaque dimensions. Prediction sizing may defer separately.
        state.textLayer:ClearAllPoints()
        state.textLayer:SetAllPoints(health)
        state.textHost = health
    end
    -- SetParent can reset inherited ordering during a layout switch. The
    -- final text level must be assigned after its parent has been reconciled.
    if changedHost or state.textStrata ~= strata or state.textLevel ~= level then
        if GUF.Restricted() or GUF.editing then GUF.pending = true; return false end
        state.textLayer:SetFrameStrata(strata)
        state.textLayer:SetFrameLevel(level + #kinds + 1)
        state.textStrata, state.textLevel = strata, level
    end
    local width, height = health:GetWidth(), health:GetHeight()
    if GUF.Secret(width) or GUF.Secret(height) or width <= 0 or height <= 0 then return false end
    local fill = health:GetStatusBarTexture()
    if not fill then return false end
    local reverse = health:GetReverseFill()
    if GUF.Secret(reverse) then return false end
    for i, kind in ipairs(kinds) do
        local cfg, item = GUF.db.frames[entry.unit].bars[kind], state.bars[kind]
        local bar, clip = item.bar, item.clip
        local overlay = kind == "healAbsorb"
        -- Prediction frames must sit above the native fill, not share its
        -- background level. Keep the text layer above every prediction.
        clip:SetFrameLevel(level + i)
        bar:SetFrameLevel(level + i)
        clip:ClearAllPoints()
        clip:SetPoint("TOP", health, "TOP")
        clip:SetHeight(height)
        local edge, opposite = reverse and "LEFT" or "RIGHT", reverse and "RIGHT" or "LEFT"
        if overlay then
            clip:SetPoint("LEFT", fill, "LEFT")
            clip:SetPoint("RIGHT", fill, "RIGHT")
        else
            clip:SetPoint(opposite, fill, edge)
            clip:SetPoint(edge, health, edge)
        end
        bar:ClearAllPoints()
        bar:SetWidth(width)
        bar:SetPoint("TOP", clip, "TOP")
        bar:SetPoint("BOTTOM", clip, "BOTTOM")
        if overlay then
            bar:SetPoint(edge, fill, edge)
            bar:SetReverseFill(not reverse)
        else
            bar:SetPoint(opposite, clip, opposite)
            bar:SetReverseFill(reverse)
        end
        styleBar(bar, cfg, health)
        if item.fullClip then
            item.fullClip:SetFrameLevel(level + i)
            item.fullClip:ClearAllPoints()
            item.fullClip:SetAllPoints(health)
            item.fullBar:SetFrameLevel(level + i)
            item.fullBar:ClearAllPoints()
            item.fullBar:SetAllPoints(health)
            item.fullBar:SetReverseFill(not reverse)
            styleBar(item.fullBar, cfg, health)
        end
    end
    state.healthTexture, state.healthAtlas = predictionTexture(health)
    state.dirty = nil
    return true
end

local function hideBars(state)
    for _, item in pairs(state.bars) do
        item.clip:Hide()
        if item.fullClip then item.fullClip:Hide() end
    end
end

function GUF.UpdatePredictionBars(entry)
    local state = entry.predictions
    if not state then return end
    local unit = entry.frame.unit or entry.unit
    if not UnitExists(unit) then hideBars(state); return end
    local health = GUF.ArtisticBarHost(entry, "health")
    local texture, atlas = predictionTexture(health)
    if texture ~= state.healthTexture or atlas ~= state.healthAtlas then state.dirty = true end
    if state.dirty and not layout(entry) then hideBars(state); return end
    -- Native primary masks can settle/change independently of Health media.
    -- Keep all three overlays, including the full-health shield, in that shape.
    refreshMasks(state, health)
    local calc, amounts, maximum = state.calc, {}, UnitHealthMax(unit)
    if calc and UnitGetDetailedHealPrediction and pcall(UnitGetDetailedHealPrediction, unit, "player", calc) then
        maximum = calc:GetMaximumHealth()
        amounts.incHeal = calc:GetTotalIncomingHeals()
        amounts.incAbsorb = calc:GetTotalDamageAbsorbs()
        amounts.healAbsorb = calc:GetTotalHealAbsorbs()
    else
        amounts.incHeal, amounts.incAbsorb, amounts.healAbsorb = 0, 0, 0
        if UnitGetIncomingHeals then amounts.incHeal = UnitGetIncomingHeals(unit) end
        if UnitGetTotalAbsorbs then amounts.incAbsorb = UnitGetTotalAbsorbs(unit) end
        if UnitGetTotalHealAbsorbs then amounts.healAbsorb = UnitGetTotalHealAbsorbs(unit) end
        for _, key in ipairs(kinds) do
            if not GUF.Secret(amounts[key]) and amounts[key] == nil then amounts[key] = 0 end
        end
    end
    local full, missing = healthAlphas(unit, maximum)
    for _, kind in ipairs(kinds) do
        local cfg, item, amount = GUF.db.frames[entry.unit].bars[kind], state.bars[kind], amounts[kind]
        local visible = cfg.enabled
        if not GUF.Secret(amount) then visible = visible and amount > 0 end
        if not GUF.Secret(maximum) then visible = visible and maximum > 0 end
        item.clip:SetShown(visible)
        if kind == "healAbsorb" then
            item.clip:SetAlpha(1)
        else
            item.clip:SetAlpha(missing)
        end
        if item.fullClip then
            -- Empty-space fill clips at the bar's edge. Its companion overlay
            -- appears only at full health, when there is no empty space to fill.
            item.fullClip:SetAlpha(full)
            item.fullClip:SetShown(visible and cfg.showAtFullHealth)
        end
        if visible then
            item.bar:SetMinMaxValues(0, maximum)
            item.bar:SetValue(amount)
            item.bar:Show()
            if item.fullBar then
                item.fullBar:SetMinMaxValues(0, maximum)
                item.fullBar:SetValue(amount)
                item.fullBar:Show()
            end
        end
    end
end

function GUF.ApplyPredictionBars(entry)
    if not entry.health then return end
    local state = entry.predictions or createPrediction(entry)
    state.dirty = true
    for _, owner in ipairs({ entry.health, entry.healthArea, entry.frame }) do
        for _, key in ipairs(nativeKeys) do
            local region = owner[key]
            if region and region.SetAlpha then state.native[region] = true end
        end
    end
    -- Individual Show options own visibility. Keep Blizzard's duplicate artwork
    -- suppressed even when all three addon overlays are turned off.
    for region in pairs(state.native) do GUF.RegionAlpha(region, 0) end
    GUF.UpdatePredictionBars(entry)
    if not state.events then
        state.events = CreateFrame("Frame")
        for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
            "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }) do
            state.events:RegisterUnitEvent(event, entry.unit)
        end
        for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
            state.events:RegisterEvent(event)
        end
        state.events:SetScript("OnEvent", function() GUF.UpdatePredictionBars(entry) end)
        local elapsed = 0
        state.events:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + delta
            if elapsed < .2 then return end
            elapsed = 0
            GUF.UpdatePredictionBars(entry)
        end)
    end
end
