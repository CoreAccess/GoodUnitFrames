local _, GUF = ...
local unpack = unpack or table.unpack
local castColor = CreateColor(1, .7, 0)
local channelColor = CreateColor(0, 1, 0)
local lockedColor = CreateColor(.5, .5, .5)
local untintedColor = CreateColor(1, 1, 1)
local atlasAvailability = {}

local function hasAtlas(atlas)
    if atlasAvailability[atlas] == nil then
        atlasAvailability[atlas] = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil or false
    end
    return atlasAvailability[atlas]
end

local function styleFill(bar)
    local atlas = bar.channel and "ui-castingbar-filling-channel" or "ui-castingbar-filling-standard"
    bar.atlasFill = hasAtlas(atlas)
    local asset = bar.atlasFill and atlas or "Interface\\TargetingFrame\\UI-StatusBar"
    if bar.fillAsset ~= asset then
        bar:SetStatusBarTexture(bar.atlasFill and "Interface\\Buttons\\WHITE8X8" or asset)
        if bar.atlasFill then bar:GetStatusBarTexture():SetAtlas(atlas) end
        bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
        bar.fillAsset = asset
    end
end

local function durationFor(func, unit, ...)
    if not func then return end
    local ok, duration = pcall(func, unit, ...)
    if ok then return duration end
end

local function nativeCastBar(entry)
    if entry.unit == "player" then return PlayerCastingBarFrame or CastingBarFrame end
    if entry.unit == "pet" then return PetCastingBarFrame end
    local live = entry.configurationPreview and GUF.frames[entry.unit]
    local frame = live and live.frame or entry.frame
    if entry.unit == "target" then return frame.spellbar or frame.SpellBar or TargetFrameSpellBar end
end

GUF.NativeCastBar = nativeCastBar

function GUF.UsesNativeCastBar(entry)
    return GUF.db.general.frameStyle == "blizzard" and nativeCastBar(entry) ~= nil
end

function GUF.CastSourceText(entry)
    local native = nativeCastBar(entry)
    if not native then
        local player = GUF.frames.player
        native = player and nativeCastBar(player)
    end
    if not native then return end
    local prefix = native:GetName()
    return native.Text or native.TextString or prefix and _G[prefix .. "Text"]
end

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Callers guard protected geometry. Always anchor from saved unit-relative
-- coordinates, never from the bar's previously offset points.
function GUF.AnchorCastBar(entry, bar, position)
    position = position or GUF.db.frames[entry.unit].bars.cast.position
    bar:ClearAllPoints()
    bar:SetPoint(position.point, entry.frame, position.relativePoint, position.x, position.y)
    bar.goodUnitFramesComboCastOffset = 0
end

local verticalPoint = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = .5, CENTER = .5,
    RIGHT = .5, BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
local horizontalPoint = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = .5, CENTER = .5,
    BOTTOM = .5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
GUF.CastAnchorX, GUF.CastAnchorY = horizontalPoint, verticalPoint

-- Resolve public anchor constraints in unit coordinates. Screen rectangles can
-- belong to different layout passes while the preview is resized/recentered.
local function anchoredRect(entry, region, rootScale, visiting, depth, geometry)
    local kind = type(region)
    if (kind ~= "table" and kind ~= "userdata") or depth > 24
        or not region.GetSize or not region.GetEffectiveScale or (region.IsForbidden and region:IsForbidden()) then return end
    local cached = visiting[region]
    if cached then if cached ~= true then return cached end; return end
    local saved = geometry and geometry[region]
    if geometry and not saved then return end
    local width, height = saved and saved.width, saved and saved.height
    if not saved then width, height = region:GetSize() end
    if not number(width) or not number(height) or width < 0 or height < 0 then return end
    if region == entry.frame then
        if width > 0 and height > 0 then return { left = 0, bottom = 0, right = width, top = height } end
        return
    end
    local scale = region:GetEffectiveScale()
    if not number(scale) or scale <= 0 or not region.GetNumPoints then return end
    local points = saved and saved.points or GUF.ReadPoints(region)
    if not points or #points == 0 then return end
    local ratio = scale / rootScale
    width, height = width * ratio, height * ratio
    visiting[region] = true
    local firstX, firstY, firstAnchorX, firstAnchorY, solvedX, solvedY
    for _, point in ipairs(points) do
        local x, y = horizontalPoint[point[1]], verticalPoint[point[1]]
        local relativeX, relativeY = horizontalPoint[point[3]], verticalPoint[point[3]]
        if x == nil or y == nil or relativeX == nil or relativeY == nil or not number(point[4]) or not number(point[5]) then
            visiting[region] = nil; return
        end
        local relative = point[2] or region:GetParent()
        if type(relative) == "string" then relative = _G[relative] end
        local parent = anchoredRect(entry, relative, rootScale, visiting, depth + 1, geometry)
        if not parent then visiting[region] = nil; return end
        local anchorX = parent.left + (parent.right - parent.left) * relativeX + point[4] * ratio
        local anchorY = parent.bottom + (parent.top - parent.bottom) * relativeY + point[5] * ratio
        if firstX == nil then
            firstX, firstY, firstAnchorX, firstAnchorY = x, y, anchorX, anchorY
        else
            -- Opposing anchors determine stretched artwork immediately, even
            -- before its GetSize has caught up to the current layout pass.
            if not solvedX and x ~= firstX then width = (anchorX - firstAnchorX) / (x - firstX); solvedX = true end
            if not solvedY and y ~= firstY then height = (anchorY - firstAnchorY) / (y - firstY); solvedY = true end
        end
    end
    if not number(width) or not number(height) or width < 0 or height < 0 then visiting[region] = nil; return end
    local left, bottom = firstAnchorX - width * firstX, firstAnchorY - height * firstY
    local rect = { left = left, bottom = bottom, right = left + width, top = bottom + height }
    visiting[region] = rect
    return rect
end

-- Call only for cast/owned presentation or static pre-layout artwork bounds;
-- never native aura containers or amount-driven StatusBar fill textures.
function GUF.FrameRectInUnit(entry, region, geometry)
    local rootScale = entry.frame:GetEffectiveScale()
    if not number(rootScale) or rootScale <= 0 then return end
    return anchoredRect(entry, region, rootScale, {}, 0, geometry)
end

-- Cache only the last applied public position, for restricted native rectangles.
function GUF.CacheCastAuraGeometry(entry, bar, width, height)
    local root = GUF.FrameRectInUnit(entry, entry.frame)
    local scale, rootScale = bar:GetEffectiveScale(), entry.frame:GetEffectiveScale()
    if not root or not number(width) or not number(height) or not number(scale) or not number(rootScale)
        or width <= 0 or height <= 0 or scale <= 0 or rootScale <= 0 then return end
    local position = GUF.db.frames[entry.unit].bars.cast.position
    local ratio = scale / rootScale
    local left = root.right * horizontalPoint[position.relativePoint] + position.x * ratio - width * ratio * horizontalPoint[position.point]
    local bottom = root.top * verticalPoint[position.relativePoint] + position.y * ratio - height * ratio * verticalPoint[position.point]
    local state = entry.artisticLayout
    local inset = state and state.active and state.castBorderInset or 2 * ratio
    local horizontal, above, below = inset, inset, inset
    if bar.goodUnitFramesOwned and not bar.nativeCastPresentation and bar.castBorderPadding then
        horizontal, above, below = bar.castBorderPadding.x * ratio,
            bar.castBorderPadding.top * ratio, bar.castBorderPadding.bottom * ratio
    end
    bar.goodUnitFramesCastBounds = { left = left - horizontal, bottom = bottom - below,
        right = left + width * ratio + horizontal, top = bottom + height * ratio + above }
    bar.goodUnitFramesCastIconBounds = nil
    local cfg = GUF.db.frames[entry.unit].bars.cast
    local prefix = bar:GetName()
    local icon = bar.Icon or bar.icon or prefix and _G[prefix .. "Icon"]
    if icon and (cfg.icon == "LEFT" or cfg.icon == "RIGHT") then
        local iconWidth, iconHeight = icon:GetSize()
        local iconScale = icon:GetEffectiveScale()
        if number(iconWidth) and number(iconHeight) and number(iconScale) and iconWidth > 0 and iconHeight > 0 and iconScale > 0 then
            iconWidth, iconHeight = iconWidth * iconScale / rootScale, iconHeight * iconScale / rootScale
            local iconLeft = cfg.icon == "LEFT" and left - 4 * ratio - iconWidth or left + (width + 4) * ratio
            local iconBottom = bottom + height * ratio / 2 - iconHeight / 2
            bar.goodUnitFramesCastIconBounds = { left = iconLeft, bottom = iconBottom,
                right = iconLeft + iconWidth, top = iconBottom + iconHeight }
        end
    end
end

local function unionRect(rect, other)
    if not other then return rect end
    return { left = math.min(rect.left, other.left), bottom = math.min(rect.bottom, other.bottom),
        right = math.max(rect.right, other.right), top = math.max(rect.top, other.top) }
end

-- Internal combo/shard rows stay inside their housing. If the configured
-- owned cast intersects it, move only that cosmetic cast beneath the row.
function GUF.AdjustTargetComboCast(entry)
    if entry.unit ~= "target" and not (entry.unit == "player" and entry.comboRow and entry.comboRow.integrated) then return end
    local bar, row, state = entry.castBar, entry.comboRow, entry.artisticLayout
    if not bar or not bar.goodUnitFramesOwned or bar.nativeCastPresentation then return end
    local offset = 0
    local bounds = bar.goodUnitFramesCastBounds
    if bounds and row and row.integrated and row.displayed and state and state.active then
        local shown = bar:IsShown()
        local combo = GUF.ComboAuraBounds(entry)
        local rect = unionRect(bounds, bar.goodUnitFramesCastIconBounds)
        if not GUF.Secret(shown) and shown and combo
            and rect.left < combo.right and rect.right > combo.left
            and rect.bottom < combo.top and rect.top > combo.bottom then
            offset = combo.bottom - rect.top
        end
    end
    if (bar.goodUnitFramesComboCastOffset or 0) == offset then return end
    if not entry.configurationPreview and (GUF.Restricted() or GUF.editing) then
        local protected = bar:IsProtected()
        if GUF.editing or GUF.Secret(protected) or protected then GUF.pending = true; return end
    end
    local scale, rootScale = bar:GetEffectiveScale(), entry.frame:GetEffectiveScale()
    if not number(scale) or not number(rootScale) or scale <= 0 or rootScale <= 0 then return end
    local position = GUF.PresentationFrameSettings(entry).bars.cast.position
    bar:ClearAllPoints()
    bar:SetPoint(position.point, entry.frame, position.relativePoint, position.x, position.y + offset * rootScale / scale)
    bar.goodUnitFramesComboCastOffset = offset
end

local function shiftedCastRect(bar, rect)
    if not rect then return end
    local offset = bar.goodUnitFramesComboCastOffset or 0
    return { left = rect.left, right = rect.right, bottom = rect.bottom + offset, top = rect.top + offset }
end

function GUF.CastAuraBounds(entry)
    local cfg = GUF.db.frames[entry.unit].bars.cast
    if not cfg.enabled and not (entry.optionsPreview and entry.previewCasting) then return end
    local sample = entry.configurationPreview
    local nativeDisplay = nativeCastBar(entry)
    local bar = sample and entry.castBar or GUF.UsesNativeCastBar(entry) and nativeDisplay or entry.castBar
    if not bar or (bar.IsForbidden and bar:IsForbidden()) then return end
    if not sample and GUF.UsesNativeCastBar(entry) and (entry.unit == "player" or entry.unit == "pet") and GUF.db.hideBlizzard.cast then return end
    local shown = bar:IsShown()
    if GUF.Secret(shown) or not shown then return end
    local prefix = bar:GetName()
    local border = bar.Border or bar.border or prefix and _G[prefix .. "Border"]
    local borderShown = border and border.GetBottom and border:IsShown()
    local region = not GUF.Secret(borderShown) and borderShown and border or bar
    local rect = GUF.FrameRectInUnit(entry, region) or shiftedCastRect(bar, bar.goodUnitFramesCastBounds)
    if not rect then return end
    local icon = bar.Icon or bar.icon or prefix and _G[prefix .. "Icon"]
    if cfg.icon ~= "HIDE" and icon then
        local iconShown = icon:IsShown()
        if not GUF.Secret(iconShown) and iconShown then
            rect = unionRect(rect, GUF.FrameRectInUnit(entry, icon) or shiftedCastRect(bar, bar.goodUnitFramesCastIconBounds))
        end
    end
    local state = entry.artisticLayout
    local gap = 6 * (state and (state.active or sample) and state.scale or 1)
    return { left = rect.left - gap, bottom = rect.bottom - gap, right = rect.right + gap, top = rect.top + gap }
end

local castAuraPending = {}
local castAuraDriver = CreateFrame("Frame")
castAuraDriver:Hide()
local function queueCastAuras(entry)
    castAuraPending[entry] = true
    castAuraDriver:Show()
end
GUF.QueueCastAuraPositions = queueCastAuras
castAuraDriver:SetScript("OnUpdate", function()
    castAuraDriver:Hide()
    for entry in pairs(castAuraPending) do
        castAuraPending[entry] = nil
        if GUF.RefreshCastAuraPositions then GUF.RefreshCastAuraPositions(entry) end
    end
end)

local function watchNativeCastBar(entry)
    local bar = nativeCastBar(entry)
    if not bar or (bar.IsForbidden and bar:IsForbidden()) then return end
    entry.castAuraHooks = entry.castAuraHooks or {}
    if not entry.castAuraHooks[bar] then
        entry.castAuraHooks[bar] = true
        local function refresh()
            if entry.nativeCastStyle and entry.nativeCastStyle.writing then return end
            queueCastAuras(entry)
            if GUF.QueueNativeCastRefresh then GUF.QueueNativeCastRefresh(entry) end
        end
        -- Observe native controllers; all resulting writes target owned aura proxies.
        for _, script in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do bar:HookScript(script, refresh) end
        for _, method in ipairs({ "SetPoint", "SetScale", "SetParent" }) do hooksecurefunc(bar, method, refresh) end
    end
    return bar
end

local function clearEmpowerStages(bar)
    bar.empowerFractions, bar.empowerWidth, bar.empowerHeight, bar.empowerScale = nil, nil, nil, nil
    bar:GetStatusBarTexture():SetAlpha(1)
    for _, stage in ipairs(bar.empowerStages or {}) do stage.pip:Hide() end
end

local function readEmpowerFractions(unit)
    if not GUF.isRetail or not UnitEmpoweredStagePercentages then return end
    -- Query actual empowerment, never a spell-name/ID whitelist. The final
    -- fraction is hold-at-max, matching the empowered duration's true option.
    local ok, fractions = pcall(UnitEmpoweredStagePercentages, unit, true)
    if not ok or GUF.Secret(fractions) or type(fractions) ~= "table"
        or #fractions < 2 or #fractions > 10 then return end
    local total = 0
    for _, fraction in ipairs(fractions) do
        if not number(fraction) or fraction < 0 or fraction > 1 then return end
        total = total + fraction
    end
    if math.abs(total - 1) <= .001 then return fractions end
end

local function updateEmpowerStages(bar, fractions)
    if not bar.empowered or not fractions or not bar.empowerStages then clearEmpowerStages(bar); return end
    local same = bar.empowerFractions and #bar.empowerFractions == #fractions
    for i, fraction in ipairs(fractions) do
        if same and bar.empowerFractions[i] ~= fraction then same = false end
    end
    local width, height = bar:GetSize()
    local scale = bar:GetEffectiveScale()
    if not number(width) or not number(height) or not number(scale) or width <= 0 or height <= 0 or scale <= 0 then
        clearEmpowerStages(bar); return
    end
    if same and bar.empowerWidth == width and bar.empowerHeight == height and bar.empowerScale == scale then return end
    if GUF.Restricted() then
        local protected = bar:IsProtected()
        if GUF.Secret(protected) or protected then GUF.pending = true; clearEmpowerStages(bar); return end
    end
    local offset = 0
    for i, stage in ipairs(bar.empowerStages) do
        local fraction = fractions[i]
        if fraction then
            offset = math.min(1, offset + fraction)
            stage.pip:ClearAllPoints()
            stage.pip:SetPoint("TOP", bar, "TOPLEFT", width * offset, 0)
            stage.pip:SetPoint("BOTTOM", bar, "BOTTOMLEFT", width * offset, 0)
            stage.pip:SetWidth(2 / scale)
            stage.pip:SetShown(i < #fractions and offset > 0 and offset < 1)
        else stage.pip:Hide() end
    end
    bar.empowerFractions = {}
    for i, fraction in ipairs(fractions) do bar.empowerFractions[i] = fraction end
    bar.empowerWidth, bar.empowerHeight, bar.empowerScale = width, height, scale
end

local function clearCast(entry)
    local bar = entry.castBar
    bar.empowered = nil
    clearEmpowerStages(bar)
    bar.duration, bar.startTime, bar.endTime = nil, nil, nil
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.name:SetText("")
    bar.time:SetText("")
    bar.icon:Hide()
    bar.spark:Hide()
    bar:Hide()
end

local function updateTime(entry)
    local bar, cfg = entry.castBar, GUF.db.frames[entry.unit].bars.cast
    if bar.duration then
        if cfg.time.enabled then bar.time:SetFormattedText("%.1f", bar.duration:GetRemainingDuration()) end
    elseif bar.startTime then
        local now = GetTime()
        local remaining = math.max(0, bar.endTime - now)
        bar:SetValue(bar.channel and remaining or math.max(0, now - bar.startTime))
        if cfg.time.enabled then bar.time:SetFormattedText("%.1f", remaining) end
    end
end

local function updateCast(entry)
    local bar, root = entry.castBar, GUF.db.frames[entry.unit]
    if GUF.UsesNativeCastBar(entry) or not root.bars.cast.enabled then clearCast(entry); return end
    local cfg, unit = root.bars.cast, entry.frame.unit or entry.unit
    if not UnitExists(unit) then clearCast(entry); return end
    local fractions = readEmpowerFractions(unit)
    local ok, name, _, texture, startTime, endTime, _, _, notInterruptible = pcall(UnitCastingInfo, unit)
    if not ok then name = nil end
    local present = ok and (GUF.Secret(name) or name ~= nil)
    local channel, empowered = false, false
    -- Retail empowerment is channel metadata even if a casting record is
    -- present. Probe it independently for every spell, including healing casts.
    if GUF.isRetail or not present then
        local valid, channelName, _, channelTexture, channelStart, channelEnd, _, channelLocked, _, isEmpowered, stages = pcall(UnitChannelInfo, unit)
        local channelPresent = valid and (GUF.Secret(channelName) or channelName ~= nil)
        local channelEmpowered = (not GUF.Secret(isEmpowered) and isEmpowered == true)
            or (not GUF.Secret(stages) and type(stages) == "number" and stages > 0)
        if channelPresent and (not present or channelEmpowered or fractions ~= nil) then
            name, texture, startTime, endTime, notInterruptible = channelName, channelTexture, channelStart, channelEnd, channelLocked
            present, channel, empowered = true, true, channelEmpowered
        end
    end
    if not present then clearCast(entry); return end
    if fractions then channel, empowered = true, true end
    bar.channel, bar.empowered = channel and not empowered, empowered
    bar.duration = nil
    if channel then
        if empowered then bar.duration = durationFor(UnitEmpoweredChannelDuration, unit, true)
        else bar.duration = durationFor(UnitChannelDuration, unit) end
    else bar.duration = durationFor(UnitCastingDuration, unit) end
    if bar.duration and bar.SetTimerDuration then
        bar.startTime, bar.endTime = nil, nil
        bar:SetMinMaxValues(0, 1)
        bar:SetTimerDuration(bar.duration, Enum.StatusBarInterpolation.Immediate,
            bar.channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    elseif not GUF.Secret(startTime) and not GUF.Secret(endTime) and type(startTime) == "number" and type(endTime) == "number" then
        if empowered then
            local valid, hold
            if GetUnitEmpowerHoldAtMaxTime then valid, hold = pcall(GetUnitEmpowerHoldAtMaxTime, unit) end
            if not valid or not number(hold) or hold < 0 then clearCast(entry); return end
            endTime = endTime + hold
        end
        bar.duration = nil
        bar.startTime, bar.endTime = startTime / 1000, endTime / 1000
        bar:SetMinMaxValues(0, math.max(.001, bar.endTime - bar.startTime))
    else
        clearCast(entry)
        return
    end
    bar.name:SetText(name)
    bar.icon:SetTexture(texture)
    bar.icon:SetShown(cfg.icon ~= "HIDE")
    bar:SetStatusBarColor(1, 1, 1)
    styleFill(bar)
    local fill, base = bar:GetStatusBarTexture(), bar.atlasFill and untintedColor or (bar.channel and channelColor or castColor)
    if not GUF.Secret(notInterruptible) and notInterruptible == nil then notInterruptible = false end
    if fill.SetVertexColorFromBoolean then
        fill:SetVertexColorFromBoolean(notInterruptible, lockedColor, base)
    elseif not GUF.Secret(notInterruptible) and notInterruptible then fill:SetVertexColor(lockedColor:GetRGB())
    else fill:SetVertexColor(base:GetRGB()) end
    bar.spark:Show()
    bar:Show()
    updateEmpowerStages(bar, fractions)
    updateTime(entry)
end

local function styleCastSurfaces(bar)
    bar.background:ClearAllPoints()
    bar.background:SetAllPoints()
    if hasAtlas("ui-castingbar-background") then
        bar.background:SetTexture(nil, "CLAMP", "CLAMP", "LINEAR")
        bar.background:SetAtlas("ui-castingbar-background")
    else bar.background:SetColorTexture(.08, .08, .08, .9) end
    bar.border:ClearAllPoints()
    if hasAtlas("ui-castingbar-frame") then
        bar.border:SetTexture(nil, "CLAMP", "CLAMP", "LINEAR")
        bar.border:SetAtlas("ui-castingbar-frame")
        bar.border:SetPoint("TOPLEFT", -2, 2)
        bar.border:SetPoint("BOTTOMRIGHT", 2, -2)
        bar.castBorderPadding = { x = 2, top = 2, bottom = 2 }
    else
        -- Legacy clients without the slim atlas retain their native file.
        bar.border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border", "CLAMP", "CLAMP", "LINEAR")
        bar.border:SetTexCoord(0, 1, 0, 1)
        bar.border:SetPoint("TOPLEFT", -30.5, 28)
        bar.border:SetPoint("BOTTOMRIGHT", 30.5, -23)
        bar.castBorderPadding = { x = 30.5, top = 28, bottom = 23 }
    end
end

-- Artwork-only factory shared with public specimens; no unit events or timers.
function GUF.CreateCastBarPresentation(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.goodUnitFramesOwned = true
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetHeight(16)
    bar.layoutHeight = 16
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.border = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    styleCastSurfaces(bar)
    if GUF.isRetail then
        -- Plain dividers keep a consistent physical width at any bar size.
        -- No fixed-aspect tier artwork is stretched into custom stage spans.
        bar.empowerStages = {}
        for i = 1, 10 do
            local pip = bar:CreateTexture(nil, "ARTWORK", nil, 2)
            pip.goodUnitFramesOwned = true
            pip:SetColorTexture(1, .9, .55, .95); pip:Hide()
            bar.empowerStages[i] = { pip = pip }
        end
    end
    bar.spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    if hasAtlas("ui-castingbar-pip") then bar.spark:SetAtlas("ui-castingbar-pip")
    else
        bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        bar.spark:SetBlendMode("ADD")
    end
    bar.spark:SetSize(6, 20)
    -- The texture edge tracks native timer values, including restricted casts.
    bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
    bar.spark:Hide()
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(16, 16)
    for _, kind in ipairs({ "name", "time" }) do
        bar[kind] = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar[kind]:SetFont(GUF.Font("Default"), 12, "OUTLINE")
    end
    bar:Hide()
    return bar
end

function GUF.StyleCastBarPresentation(bar, state, channel)
    styleCastSurfaces(bar)
    bar.nativeCastPresentation = nil
    bar.artisticStyle = state and state.active or false
    bar.channel = channel
    bar.border:Show()
    styleFill(bar)
    bar:SetStatusBarColor(1, 1, 1)
    local color = bar.atlasFill and untintedColor or channel and channelColor or castColor
    bar:GetStatusBarTexture():SetVertexColor(color:GetRGB())
end

local function nativeSurface(source, target, native, bar)
    if not source or not source.GetTexture then return end
    local atlas, file = source.GetAtlas and source:GetAtlas(), source:GetTexture()
    if not GUF.Secret(atlas) and atlas and hasAtlas(atlas) then target:SetAtlas(atlas)
    elseif not GUF.Secret(file) and file then
        target:SetTexture(file, "CLAMP", "CLAMP", "LINEAR")
        local coords, readable = { source:GetTexCoord() }, true
        for _, value in ipairs(coords) do if not number(value) then readable = false end end
        if readable then target:SetTexCoord(unpack(coords)) end
    end
    local points = GUF.ReadPoints(source)
    if not points or #points == 0 then return end
    for _, point in ipairs(points) do
        if point[2] ~= native or not number(point[4]) or not number(point[5]) then return end
    end
    local width, height = source:GetSize()
    if number(width) and number(height) and width > 0 and height > 0 then target:SetSize(width, height) end
    target:ClearAllPoints()
    for _, point in ipairs(points) do target:SetPoint(point[1], bar, point[3], point[4], point[5]) end
end

-- Copy public native presentation only. Specimens keep synthetic spell/value
-- data and never inherit a native cast controller, timer, script or mask.
function GUF.CopyNativeCastPresentation(entry, bar)
    local native = nativeCastBar(entry)
    if not native and GUF.frames.player then native = nativeCastBar(GUF.frames.player) end
    if not native or (native.IsForbidden and native:IsForbidden()) then return end
    bar.nativeCastPresentation = true
    local prefix = native:GetName()
    nativeSurface(native.Background or native.background or prefix and _G[prefix .. "Background"], bar.background, native, bar)
    nativeSurface(native.Border or native.border or prefix and _G[prefix .. "Border"], bar.border, native, bar)
    local text = native.Text or native.TextString or prefix and _G[prefix .. "Text"]
    local icon = native.Icon or native.icon or prefix and _G[prefix .. "Icon"]
    return text, icon, native
end

function GUF.StyleNativeCastSpecimen(entry, options)
    local cfg, bar = GUF.db.frames[entry.unit].bars.cast, entry.castBar
    local width, height = GUF.CastBarDimensions(entry.unit)
    bar:SetSize(width, height); bar.layoutHeight = height
    bar:SetScale(1)
    local source, live = nativeCastBar(entry), GUF.frames[entry.unit]
    if source and live then
        local ancestor, inherits = source:GetParent(), false
        while ancestor do
            if ancestor == live.frame then inherits = true; break end
            ancestor = ancestor:GetParent()
        end
        local effective = source:GetEffectiveScale()
        local denominator = inherits and live.frame:GetEffectiveScale() or GUF.db.frames[entry.unit].scale * UIParent:GetEffectiveScale()
        if number(effective) and number(denominator) and denominator > 0 then bar:SetScale(effective / denominator) end
    end
    GUF.AnchorCastBar(entry, bar)
    local text, icon = GUF.CopyNativeCastPresentation(entry, bar)
    GUF.LayoutCastLabels(entry, bar, bar.name, bar.time, text)
    GUF.PositionCastIcon(entry, bar, icon)
    GUF.CacheCastAuraGeometry(entry, bar, width, height)
    bar.icon:SetShown(cfg.icon ~= "HIDE" and (options.states.casting == true or options.states.channel == true))
end

function GUF.PositionCastIcon(entry, bar, icon)
    local cfg = GUF.db.frames[entry.unit].bars.cast
    local gap = GUF.db.general.frameStyle == "blizzard" and 4 or 3
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint(cfg.icon == "RIGHT" and "LEFT" or "RIGHT", bar,
        cfg.icon == "RIGHT" and "RIGHT" or "LEFT", cfg.icon == "RIGHT" and gap or -gap, 0)
    if icon then
        local width, iconHeight = icon:GetSize()
        if number(width) and number(iconHeight) and width > 0 and iconHeight > 0 then bar.icon:SetSize(width, iconHeight) end
    end
end

local function createCastBar(entry)
    local bar = GUF.CreateCastBarPresentation(entry.frame)
    entry.castBar = bar
    local function auraClearance()
        if GUF.RefreshCastAuraPositions then GUF.RefreshCastAuraPositions(entry) end
    end
    bar:HookScript("OnShow", auraClearance)
    bar:HookScript("OnHide", auraClearance)
    local events = CreateFrame("Frame")
    bar.events = events
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
        "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do events:RegisterUnitEvent(event, entry.unit) end
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function() updateCast(entry) end)
    -- Poll the displayed unit too: Target of Target has no native casting-bar controller.
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, delta)
        if not bar.managed then return end
        elapsed = elapsed + delta
        if elapsed >= .1 then elapsed = 0; updateCast(entry) end
        if bar:IsShown() then updateTime(entry) end
    end)
    return bar
end

function GUF.PositionCastBar(entry)
    local bar = entry.castBar
    if not bar then return end
    local state = entry.artisticLayout
    local anchor = state and state.active and state.noPower and entry.health or entry.power or entry.health or entry.frame
    if state and state.active then
        anchor = state.fullWidthCast or state.castAreas[state.noPower and "health" or "power"] or anchor
    end
    if GUF.Restricted() then
        local ok, protected = pcall(bar.IsProtected, bar)
        if not ok or GUF.Secret(protected) or protected then GUF.pending = true; return bar.anchorRegion or anchor end
    end
    local width, height = GUF.CastBarDimensions(entry.unit)
    bar:SetSize(width, height); bar.layoutHeight = height
    GUF.AnchorCastBar(entry, bar)
    GUF.CacheCastAuraGeometry(entry, bar, width, height)
    bar.anchorRegion = anchor
    if GUF.RefreshCastAuraPositions then GUF.RefreshCastAuraPositions(entry) end
    return anchor
end

function GUF.ApplyCastBar(entry)
    local root, bar = GUF.db.frames[entry.unit], entry.castBar
    local native = watchNativeCastBar(entry)
    queueCastAuras(entry)
    if GUF.UsesNativeCastBar(entry) then
        if bar then bar.managed = false; clearCast(entry) end
        GUF.ApplyNativeCastBar(entry)
        return
    end
    GUF.ReleaseNativeCastBar(entry)
    bar = bar or createCastBar(entry)
    bar.managed = true
    if native then
        -- The separate player bar is hidden only by Hide Blizzard > Cast.
        -- Target's attached source is replaced only while its addon cast is on.
        local replacingTarget = entry.unit ~= "player" and root.bars.cast.enabled
        GUF.RegionAlpha(native, replacingTarget and 0 or nil)
    end
    GUF.StyleCastBarPresentation(bar, entry.artisticLayout, bar.channel)
    GUF.PositionCastBar(entry)
    local icon
    if GUF.db.general.frameStyle == "blizzard" then
        local text
        text, icon = GUF.CopyNativeCastPresentation(entry, bar)
    end
    GUF.PositionCastIcon(entry, bar, icon)
    GUF.LayoutCastLabels(entry, bar, bar.name, bar.time, GUF.CastSourceText(entry))
    GUF.CacheCastAuraGeometry(entry, bar, GUF.CastBarDimensions(entry.unit))
    if not bar.sizeHooked then
        local function resized()
            if not bar.managed then return end
            GUF.PositionCastBar(entry)
            GUF.LayoutCastLabels(entry, bar, bar.name, bar.time, GUF.CastSourceText(entry))
        end
        for _, region in pairs({ entry.health, entry.power }) do
            if region.HookScript then region:HookScript("OnSizeChanged", resized) end
        end
        bar.sizeHooked = true
    end
    updateCast(entry)
end
