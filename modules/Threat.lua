local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "Threat")
end
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

function GUF.CreateArtisticThreatPlaque(parent)
    local frame = GUF.Runtime.CreateFrame("Frame", nil, parent)
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
    if not GUF.Presentation.Feature(entry, "threatVisibility", frame, show) then frame:SetShown(show) end
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
    if GUF.Presentation.Role(entry, "threatHost") then
        return GUF.Presentation.Feature(entry, "positionThreat", frame)
    end
    -- Keep the vertical binding on Blizzard's name area. Horizontal alignment
    -- uses native coordinates only while all geometry inputs are public.
    local topRegion = entry.nameBackground
        or (not GUF.Runtime.Settings("threat", "target").frames.target.hide.name and entry.name) or entry.health
    local barCenter = entry.health:GetCenter()
    local regionCenter = topRegion:GetCenter()
    local barScale = entry.health:GetEffectiveScale()
    local regionScale = topRegion:GetParent():GetEffectiveScale()
    local frameScale = frame:GetEffectiveScale()
    -- Native geometry can be opaque outside combat too. Truthiness does not
    -- make a coordinate public; defer the panel until every input is usable.
    if not publicNumber(barCenter) or not publicNumber(regionCenter)
        or not publicNumber(barScale) or not publicNumber(regionScale) or not publicNumber(frameScale)
        or barScale <= 0 or regionScale <= 0 or frameScale <= 0 then return false end
    local x = cfg.x + (barCenter * barScale - regionCenter * regionScale) / frameScale
    if frame.anchorRegion ~= topRegion or frame.anchorX ~= x or frame.anchorY ~= cfg.y then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", topRegion, "TOP", x, cfg.y)
        frame.anchorRegion, frame.anchorX, frame.anchorY = topRegion, x, cfg.y
    end
    return true
end

function GUF.RenderConfigurationThreat(entry, previewShown)
    return GUF.Presentation.Feature(entry, "renderThreatSample", previewShown)
end

function GUF.ApplyThreat()
    local entry = GUF.frames.target
    if not entry or not entry.health then return end
    if not GUF.threat or not GUF.threat.created then
        local frame = GUF.threat or GUF.Runtime.CreateFrame("Frame", "GoodUnitFramesThreat", entry.frame, "BackdropTemplate")
        GUF.threat = frame
        frame:Hide()
        frame:SetFrameLevel(entry.frame:GetFrameLevel() + 8)
        frame:EnableMouse(false)
        frame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        frame:SetBackdropBorderColor(.70, .70, .70, 1)
        frame.background = frame.background or frame:CreateTexture(nil, "BACKGROUND")
        -- Clear the angled top corners and fill down to the bottom border.
        frame.background:SetPoint("TOPLEFT", 4, -4)
        frame.background:SetPoint("BOTTOMRIGHT", -4, 1)
        frame.text = frame.text or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.text:SetPoint("CENTER")
        GUF.threat = frame
        GUF.NativeProperties.HookScript("Threat:script:1", entry.frame, "OnShow", function()
            if GUF.Restricted() then GUF.DeferRuntime("native-readiness") else GUF.ApplyThreat() end
        end)
        frame.created = true
        GUF.Runtime.Constructed()
    end
    local cfg = GUF.Runtime.Settings("threat").threat
    local artistic = GUF.Presentation.Role(entry, "threatHost") ~= nil
    if artistic and not GUF.artisticThreat then
        GUF.artisticThreat = GUF.CreateArtisticThreatPlaque(entry.frame)
    end
    local native = getNativeThreat(entry)
    applyBorder(GUF.threat, native)
    if native and not (native.IsForbidden and native:IsForbidden()) then
        -- Show one numerical threat display and restore the stock one when disabled.
        leaseAlpha(native, (artistic or cfg.enabled) and 0 or nil)
    end
    local frame = artistic and GUF.artisticThreat or GUF.threat
    if artistic then
        GUF.threat:Hide()
    else
        frame:SetSize(cfg.width, cfg.height)
        if GUF.artisticThreat then GUF.artisticThreat:Hide() end
    end
    if not cfg.enabled then threatVisible(frame, entry, false); return end
    if not artistic then GUF.StyleThreatText(entry, frame, cfg.width, cfg.height) end
    if not positionThreat(frame, entry, cfg) then threatVisible(frame, entry, false); return end
    GUF.UpdateThreat()
end

function GUF.UpdateThreat()
    local entry = GUF.frames.target
    local artistic = entry and GUF.Presentation.Role(entry, "threatHost") ~= nil
    local frame, cfg = artistic and GUF.artisticThreat or GUF.threat, GUF.db and GUF.Runtime.Settings("threat").threat
    if not frame or not cfg then return end
    if not cfg.enabled then threatVisible(frame, entry, false); return end
    local rootShown = entry.frame:IsVisible()
    if not GUF.Secret(rootShown) and not rootShown then threatVisible(frame, entry, false); return end
    local exists, hostile = UnitExists("target"), UnitCanAttack("player", "target")
    if not cfg.enabled or GUF.Secret(exists) or not exists
        or GUF.Secret(hostile) or not hostile or not UnitDetailedThreatSituation then
        threatVisible(frame, entry, false); return
    end
    if artistic then
        if not GUF.Presentation.Role(entry, "threatGeometry") then
            -- Enabling in combat waits for the guarded Name-area binding.
            GUF.DeferRuntime("native-readiness")
            threatVisible(frame, entry, false); return
        end
        local playerCombat, targetCombat = UnitAffectingCombat("player"), UnitAffectingCombat("target")
        if GUF.Secret(playerCombat) or not playerCombat or GUF.Secret(targetCombat) or not targetCombat then
            threatVisible(frame, entry, false); return
        end
    end
    -- Use the captured Name-row placement; Blizzard's separate panel still
    -- follows its native name area as that layout settles.
    -- The existing periodic update retries deferred placement; do not force a
    -- full addon reapply or reuse offsets computed for another native layout.
    if not positionThreat(frame, entry, cfg) then threatVisible(frame, entry, false); return end
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
