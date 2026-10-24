local _, GUF = ...
-- Feature module for the existing Blizzard unit frames.

local function publicNumber(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Style only the owned percentage label, never its backing or native text.
function GUF.StyleThreatText(entry, frame, width, height, scale)
    local cfg = GUF.PresentationFrameSettings(entry)
    local options, text = cfg.text.threat, frame.text
    local font, size, outline = GUF.Font(options.font), options.size, options.outline
    local changed = frame.threatFont ~= font or frame.threatFontSize ~= size or frame.threatOutline ~= outline
    local value
    if changed then
        -- The percentage often stays identical between edits. Invalidate its
        -- glyph layout rather than relying on another identical SetText call.
        -- Opaque live text is forwarded unchanged, never inspected.
        value = text:GetText()
        text:SetText(nil)
    end
    scale = scale or 1
    -- Threat always owns its font; legacy general-text opt-ins do not apply.
    text:SetFont(font, size, outline)
    text:SetShadowColor(0, 0, 0, 0)
    text:SetShadowOffset(0, 0)
    text:ClearAllPoints()
    text:SetWidth(0)
    text:SetPoint("LEFT", frame, "LEFT", 4 * scale + options.x, options.y)
    text:SetPoint("RIGHT", frame, "LEFT", width - 4 * scale + options.x, options.y)
    text:SetHeight(math.max(height, options.size + 4))
    text:SetJustifyH(options.align); text:SetJustifyV("MIDDLE")
    text:SetTextColor(1, 1, 1, 1)
    text:SetWordWrap(false); text:SetNonSpaceWrap(false); text:SetMaxLines(1)
    if changed then text:SetText(value) end
    frame.threatFont, frame.threatFontSize, frame.threatOutline = font, size, outline
end

-- Prepare public meter geometry during guarded layout. Native Name is bound
-- to both edges of an owned area here; only that area changes during combat.
function GUF.LayoutArtisticThreatName(entry)
    local state, cfg = entry.artisticLayout, GUF.db.threat
    state.threatGeometry, state.threatNameInset = nil, nil
    if entry.unit ~= "target" or not state.active or not (cfg.enabled or entry.configurationShowAll) then return end
    local scale = state.scale
    local height = state.headerTop - state.healthY
    local options = GUF.PresentationFrameSettings(entry).text.threat
    local font, size = GUF.Font(options.font), options.size
    if not state.threatMeasure then
        state.threatMeasure = state.nameStrip:CreateFontString(nil, "OVERLAY")
        state.threatMeasure.goodUnitFramesOwned = true
        state.threatMeasure:SetAlpha(0)
        state.threatMeasure:Hide()
    end
    local sample = "100%"
    -- Measure only a public configuration sample, never the live percentage.
    state.threatMeasure:SetFont(font, size, options.outline)
    state.threatMeasure:SetText(sample)
    local measured = state.threatMeasure:GetStringWidth()
    local textWidth = publicNumber(measured) and measured > 0 and measured or size * .65 * #sample
    -- Trim four scaled units from the former span, keeping the portrait end
    -- fixed and retaining eight units of padding around the public sample.
    local width = math.min(math.max(((cfg.artisticWidth or 52) - 4) * scale, textWidth + 8 * scale),
        math.max(scale, state.barWidth - 32 * scale))
    local right = state.barX + state.barWidth - 4 * scale
    local left = right - width
    state.threatGeometry = { left = left, top = state.headerTop, height = height,
        width = state.px + state.barOffset - left, textWidth = width,
        scale = scale }
end

local function fitArtisticThreat(frame, entry)
    local state = entry.artisticLayout
    local geometry = state.threatGeometry
    if not geometry then return end
    local scale = geometry.scale
    local edge = math.min(3 * scale, geometry.height / 3)
    -- Like Health/Power, the backing continues underneath the circular face.
    -- Keep the entire meter behind the portrait and its painted surround.
    frame:SetFrameLevel(state.nameStrip:GetFrameLevel() + 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", geometry.left, geometry.top)
    frame:SetSize(geometry.width, geometry.height)
    frame.background:ClearAllPoints()
    -- Preserve the Name row's existing top chrome, not a separate plaque rim.
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", edge, -edge)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    -- Reuse the Target stack's left rail, stopping below the Name top chrome.
    frame.leftBorder:ClearAllPoints()
    frame.leftBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -edge)
    frame.leftBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    frame.leftBorder:SetWidth(edge)
    GUF.PaintBlizzardStackSlice(frame.leftBorder, "target", 2, 1)
    GUF.StyleThreatText(entry, frame, geometry.textWidth, geometry.height, scale)
end

function GUF.CreateArtisticThreatPlaque(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.goodUnitFramesOwned = true
    frame:EnableMouse(false)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background.goodUnitFramesOwned = true
    frame.background:SetColorTexture(1, 1, 1, 1)
    frame.leftBorder = frame:CreateTexture(nil, "OVERLAY")
    frame.leftBorder.goodUnitFramesOwned = true
    if frame.leftBorder.SetSnapToPixelGrid then frame.leftBorder:SetSnapToPixelGrid(false) end
    if frame.leftBorder.SetTexelSnappingBias then frame.leftBorder:SetTexelSnappingBias(0) end
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text.goodUnitFramesOwned = true
    frame.text:SetJustifyH("CENTER"); frame.text:SetJustifyV("MIDDLE")
    frame.text:SetWordWrap(false); frame.text:SetNonSpaceWrap(false); frame.text:SetMaxLines(1)
    frame:Hide()
    return frame
end

local function threatVisible(frame, entry, show)
    local state = entry.artisticLayout
    if entry.unit == "target" and state and state.active then
        local geometry, scale = state.threatGeometry, state.scale
        local inset = show and geometry and geometry.textWidth + 4 * scale or 0
        if state.threatNameInset ~= inset then
            -- Native Name follows these owned anchors without any native text
            -- SetPoint/SetWidth writes, including combat retarget/zero threat.
            state.nameArea:SetPoint("BOTTOMRIGHT", state.nameStrip, "BOTTOMRIGHT",
                state.barX + state.barWidth - 4 * scale - state.px - state.barOffset - inset, 0)
            state.nameTextWidth = math.max(1, state.barWidth - 16 * scale - inset)
            state.threatNameInset = inset
        end
    end
    frame:SetShown(show)
end

local function getNativeThreat(entry)
    local content = entry.frame.TargetFrameContent
    local context = content and content.TargetFrameContentContextual
    return (context and context.NumericalThreat) or entry.frame.NumericalThreat
        or _G[entry.frame:GetName() .. "NumericalThreat"]
end

local function applyBorder(frame, native)
    if frame.border or not native or (native.IsForbidden and native:IsForbidden()) then return end
    -- Reuse the client's compact numerical-threat border artwork.
    for i = 1, native:GetNumRegions() do
        local region = select(i, native:GetRegions())
        if region:IsObjectType("Texture") and region ~= native.bg and region:GetDrawLayer() == "ARTWORK" then
            local atlas = region.GetAtlas and region:GetAtlas()
            local texture = region:GetTexture()
            if atlas or texture then
                frame.border = frame:CreateTexture(nil, "ARTWORK")
                if atlas then frame.border:SetAtlas(atlas) else frame.border:SetTexture(texture) end
                frame.border:SetTexCoord(region:GetTexCoord())
                frame.border:SetVertexColor(region:GetVertexColor())
                frame.border:SetAllPoints(frame)
                frame:SetBackdrop(nil)
                return
            end
        end
    end
end

local function positionThreat(frame, entry, cfg)
    if frame == GUF.artisticThreat or entry.configurationPreview then
        fitArtisticThreat(frame, entry)
        return
    end
    -- Anchor directly so vertical placement follows Blizzard's layout even if
    -- its screen coordinates have not been calculated yet.
    local topRegion = entry.nameBackground
        or (not GUF.db.frames.target.hide.name and entry.name) or entry.health
    local x = cfg.x
    local barCenter = entry.health:GetCenter()
    local regionCenter = topRegion:GetCenter()
    if barCenter and regionCenter then
        x = x + (barCenter * entry.health:GetEffectiveScale()
            - regionCenter * topRegion:GetParent():GetEffectiveScale()) / frame:GetEffectiveScale()
    end
    if frame.anchorRegion ~= topRegion or frame.anchorX ~= x or frame.anchorY ~= cfg.y then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", topRegion, "TOP", x, cfg.y)
        frame.anchorRegion, frame.anchorX, frame.anchorY = topRegion, x, cfg.y
    end
end

function GUF.RenderConfigurationThreat(entry, previewShown)
    if entry.unit ~= "target" then return end
    local state, cfg = entry.artisticLayout, GUF.db.threat
    local frame = state.threatPreview
    if not frame then
        frame = GUF.CreateArtisticThreatPlaque(entry.frame)
        state.threatPreview = frame
        local handle = CreateFrame("Frame", nil, frame)
        handle.goodUnitFramesOwned = true
        handle:SetAllPoints(frame)
        frame.dragHandle = handle
        -- This section is fixed to the Name row; the legacy drag offset is dormant.
        handle:EnableMouse(false)
        handle:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            self.drag = nil
        end)
    end
    positionThreat(frame, entry, cfg)
    frame.dragHandle:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.text:SetText("100%")
    frame.background:SetVertexColor(.78, .10, .10, cfg.alpha)
    local show = entry.optionsPreview and ((cfg.enabled and entry.previewCombat) or entry.configurationShowAll) or not entry.optionsPreview and (cfg.enabled or GUF.configurationShowAll)
    if entry.optionsPreview and previewShown ~= nil then show = cfg.enabled and previewShown end
    threatVisible(frame, entry, show and state.threatGeometry ~= nil)
end

function GUF.ApplyThreat()
    local entry = GUF.frames.target
    if not entry or not entry.health then return end
    if not GUF.threat then
        local frame = CreateFrame("Frame", "GoodUnitFramesThreat", entry.frame, "BackdropTemplate")
        frame:SetFrameLevel(entry.frame:GetFrameLevel() + 8)
        frame:EnableMouse(false)
        frame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        frame:SetBackdropBorderColor(.70, .70, .70, 1)
        frame.background = frame:CreateTexture(nil, "BACKGROUND")
        -- Clear the angled top corners and fill down to the bottom border.
        frame.background:SetPoint("TOPLEFT", 4, -4)
        frame.background:SetPoint("BOTTOMRIGHT", -4, 1)
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.text:SetPoint("CENTER")
        GUF.threat = frame
        entry.frame:HookScript("OnShow", function()
            if GUF.Restricted() then GUF.pending = true else GUF.ApplyThreat() end
        end)
    end
    local cfg = GUF.db.threat
    local artistic = entry.artisticLayout and entry.artisticLayout.active
    if artistic and not GUF.artisticThreat then
        GUF.artisticThreat = GUF.CreateArtisticThreatPlaque(entry.frame)
    end
    local native = getNativeThreat(entry)
    applyBorder(GUF.threat, native)
    if native and not (native.IsForbidden and native:IsForbidden()) then
        -- Show one numerical threat display and restore the stock one when disabled.
        GUF.RegionAlpha(native, (artistic or cfg.enabled) and 0 or nil)
    end
    local frame = artistic and GUF.artisticThreat or GUF.threat
    if artistic then
        GUF.threat:Hide()
    else
        frame:SetSize(cfg.width, cfg.height)
        if GUF.artisticThreat then GUF.artisticThreat:Hide() end
    end
    positionThreat(frame, entry, cfg)
    if not artistic then GUF.StyleThreatText(entry, frame, cfg.width, cfg.height) end
    GUF.UpdateThreat()
end

function GUF.UpdateThreat()
    local entry = GUF.frames.target
    local artistic = entry and entry.artisticLayout and entry.artisticLayout.active
    local frame, cfg = artistic and GUF.artisticThreat or GUF.threat, GUF.db and GUF.db.threat
    if not frame or not cfg then return end
    local exists, hostile = UnitExists("target"), UnitCanAttack("player", "target")
    if not cfg.enabled or GUF.Secret(exists) or not exists
        or GUF.Secret(hostile) or not hostile or not UnitDetailedThreatSituation then
        threatVisible(frame, entry, false); return
    end
    if artistic then
        if not entry.artisticLayout.threatGeometry then
            -- Enabling in combat waits for the guarded Name-area binding.
            GUF.pending = true
            threatVisible(frame, entry, false); return
        end
        local playerCombat, targetCombat = UnitAffectingCombat("player"), UnitAffectingCombat("target")
        if GUF.Secret(playerCombat) or not playerCombat or GUF.Secret(targetCombat) or not targetCombat then
            threatVisible(frame, entry, false); return
        end
    end
    -- Use the captured Name-row placement; Blizzard's separate panel still
    -- follows its native name area as that layout settles.
    positionThreat(frame, GUF.frames.target, cfg)
    -- Always use scaled threat: 100% is the aggro threshold. Retired saved
    -- percentage/zero-display preferences must not change this policy.
    local _, status, percent = UnitDetailedThreatSituation("player", "target")
    if not GUF.Secret(percent) and (percent == nil or percent <= 0) then threatVisible(frame, entry, false); return end
    if GUF.Secret(status) then
        -- Some builds accept secret status in the native color function; others don't.
        local ok, r, g, b = pcall(GetThreatStatusColor, status)
        if not ok or (not GUF.Secret(r) and r == nil) then r, g, b = .25, .25, .25 end
        if artistic then frame.background:SetVertexColor(.32, .34, .37, cfg.alpha)
        else frame.background:SetColorTexture(r, g, b, cfg.alpha) end
        frame.text:SetFormattedText("%.0f%%", percent)
        threatVisible(frame, entry, true)
        return
    end
    if status == nil then
        threatVisible(frame, entry, false); return
    end
    local r, g, b = GetThreatStatusColor(status)
    if artistic then
        if status >= 2 then r, g, b = .78, .10, .10
        elseif status == 1 then r, g, b = .82, .61, .10
        else r, g, b = .32, .34, .37 end
        frame.background:SetVertexColor(r, g, b, cfg.alpha)
    else frame.background:SetColorTexture(r, g, b, cfg.alpha) end
    frame.text:SetFormattedText("%.0f%%", percent)
    threatVisible(frame, entry, true)
end
