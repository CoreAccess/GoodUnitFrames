local _, GUF = ...

local function publicNumber(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Prepare public meter geometry during guarded layout. Native Name is bound
-- to both edges of an owned area here; only that area changes during combat.
function GUF.LayoutArtisticThreatName(entry)
    -- Geometry belongs to the layout attempt, before the separate threat
    -- family acknowledges its visibility/text settings later in that request.
    local state, cfg = entry.artisticLayout, GUF.Runtime.Settings("layout", entry).threat
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

function GUF.PositionArtisticThreat(entry, frame)
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
    return true
end


function GUF.SetArtisticThreatVisible(entry, frame, show)
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
    return true
end


function GUF.RenderArtisticThreatSample(entry, previewShown)
    if entry.unit ~= "target" then return end
    local state, cfg = entry.artisticLayout, GUF.Runtime.Settings("threat").threat
    local frame = state.threatPreview
    if not frame then
        frame = GUF.CreateArtisticThreatPlaque(entry.frame)
        state.threatPreview = frame
        local handle = GUF.Runtime.CreateFrame("Frame", nil, frame)
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
    GUF.PositionArtisticThreat(entry, frame)
    frame.dragHandle:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.text:SetText("100%")
    frame.background:SetVertexColor(.78, .10, .10, cfg.alpha)
    local show = entry.optionsPreview and ((cfg.enabled and entry.previewCombat) or entry.configurationShowAll) or not entry.optionsPreview and (cfg.enabled or GUF.configurationShowAll)
    if entry.optionsPreview and previewShown ~= nil then show = cfg.enabled and previewShown end
    GUF.SetArtisticThreatVisible(entry, frame, show and state.threatGeometry ~= nil)
end

