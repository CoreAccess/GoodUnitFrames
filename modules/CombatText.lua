local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "CombatText")
end
local fadeIn, hold, fadeOut = .15, 1.15, .7
local duration = fadeIn + hold + fadeOut
local feedbackLevel = 55

function GUF.CombatFeedbackFontSize(cfg)
    local size = cfg.fontSize
    for _, kind in ipairs({ "health", "power" }) do
        if cfg.text[kind].custom then size = math.max(size, cfg.text[kind].size) end
    end
    return math.max(24, math.floor(size * 1.75 + .5))
end

local function clearFeedback(frame)
    frame.feedbackPreview = nil
    frame.feedbackStartTime = nil
    frame.feedbackElapsed = 0
    frame.feedbackText:SetText("")
    frame.feedbackText:SetAlpha(0)
    frame.feedbackText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame:SetScript("OnUpdate", nil)
end

local function updateFeedback(frame, elapsed)
    if frame.runtimeEntry and not GUF.Runtime.IsBinding(frame.runtimeBinding, "combatText", frame.runtimeEntry) then
        clearFeedback(frame); return
    end
    -- The formatter owns the opaque combat message. This owned renderer owns
    -- its lifetime, alpha and motion using public elapsed time only.
    frame.feedbackElapsed = frame.feedbackElapsed + elapsed
    local age = frame.feedbackElapsed
    if age >= duration then clearFeedback(frame); return end
    local alpha = age < fadeIn and age / fadeIn
        or age < fadeIn + hold and 1 or (duration - age) / fadeOut
    frame.feedbackText:SetAlpha(alpha)
    local progress = age / duration
    frame.feedbackText:SetPoint("CENTER", frame, "CENTER", 0, frame.feedbackRise * progress)
end

local function feedbackEvent(entry, self, action, ...)
    local cfg = GUF.Runtime.Settings("combatText", entry).frames[entry.unit]
    if not cfg.combatText.enabled or not self:IsVisible() then return end
    -- Opaque combat values go directly to Blizzard's supported text renderer.
    CombatFeedback_OnCombatEvent(self, action, ...)
    self.feedbackElapsed = 0
    self.feedbackText:SetAlpha(0)
    self.feedbackText:SetPoint("CENTER", self, "CENTER", 0, 0)
    self:SetScript("OnUpdate", updateFeedback)
end

local function createFeedback(entry)
    local frame = GUF.Runtime.CreateFrame("Frame", nil, entry.frame)
    frame.goodUnitFramesOwned = true
    frame:SetSize(1, 1)
    frame:SetFrameLevel(entry.frame:GetFrameLevel() + feedbackLevel)
    -- Cleanup can run before custom styling, so the font must exist at creation.
    frame.feedbackText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.feedbackText.goodUnitFramesOwned = true
    frame.feedbackText:SetPoint("CENTER")
    frame:SetScript("OnHide", clearFeedback)
    frame:SetScript("OnEvent", function(self, event, _, action, ...)
        if event ~= "UNIT_COMBAT" then clearFeedback(self); return end
        if not GUF.Runtime.IsBinding(self.runtimeBinding, "combatText", entry) then return end
        GUF.Runtime.Refresh(entry, "combatText", feedbackEvent, entry, self, action, ...)
    end)
    frame.created = true
    GUF.Runtime.Constructed()
    return frame
end

local function styleFeedback(entry, frame)
    local cfg = GUF.Runtime.Settings("combatText", entry).frames[entry.unit]
    local settings, style = cfg.combatText, cfg.indicators.feedback
    -- Reapplying geometry/style must not discard an in-flight message.
    -- Float above the unit's aura/cooldown hosts and resting artwork.
    frame:SetFrameLevel(entry.frame:GetFrameLevel() + feedbackLevel)
    frame.feedbackFontHeight = GUF.CombatFeedbackFontSize(cfg)
    frame.feedbackText:SetFont(GUF.Font(cfg.font), frame.feedbackFontHeight, "THICKOUTLINE")
    frame.feedbackText:SetShadowColor(0, 0, 0, 1)
    frame.feedbackText:SetShadowOffset(1, -1)
    frame.feedbackText:SetJustifyH("CENTER")
    local height = entry.frame:GetHeight()
    if GUF.Secret(height) or type(height) ~= "number" then height = 0 end
    -- Reach above the frame in its own coordinates, independently of the text scale.
    frame.feedbackRise = math.max(64, height / 2 + 24) / style.scale
    frame:SetAlpha(style.alpha)
    frame:SetScale(style.scale)
    frame:ClearAllPoints()
    -- Anchor to the health bar; keep offsets consistent when the text scale changes.
    frame:SetPoint("CENTER", GUF.Presentation.Role(entry, "health") or entry.health or entry.frame, settings.point, settings.x / style.scale, settings.y / style.scale)
end

local function startPreviewFeedback(frame)
    frame.feedbackElapsed = 0
    frame.feedbackText:SetText("-1,250")
    frame.feedbackText:SetTextColor(1, .15, .15)
    frame.feedbackText:SetAlpha(0)
    frame.feedbackText:SetPoint("CENTER", frame, "CENTER", 0, 0)
end

local function updatePreviewFeedback(frame, elapsed)
    if frame.feedbackElapsed + elapsed >= duration then
        startPreviewFeedback(frame)
    else
        updateFeedback(frame, elapsed)
    end
end

function GUF.PreviewCombatText(entry, shown)
    -- Interactive specimens only: never register events or touch native feedback.
    if not entry.optionsPreview then return end
    local frame = entry.combatText
    if not shown or not GUF.Runtime.Settings("combatText", entry).frames[entry.unit].combatText.enabled then
        if frame then frame:Hide(); clearFeedback(frame) end
        return
    end
    if not frame then frame = createFeedback(entry); entry.combatText = frame end
    styleFeedback(entry, frame)
    -- Reserve the whole public animation path, keeping preview bounds stable
    -- while offsets, font and scale are adjusted at any point in the cycle.
    if not frame.previewBounds then
        frame.previewBounds = GUF.Runtime.CreateFrame("Frame", nil, frame)
        frame.previewBounds.goodUnitFramesOwned = true
    end
    frame.previewBounds:ClearAllPoints()
    frame.previewBounds:SetPoint("BOTTOM", frame, "CENTER", 0, -frame.feedbackFontHeight)
    frame.previewBounds:SetSize(frame.feedbackFontHeight * 6, frame.feedbackRise + frame.feedbackFontHeight * 2)
    frame:Show()
    if not frame.feedbackPreview then
        frame.feedbackPreview = true
        startPreviewFeedback(frame)
        frame:SetScript("OnUpdate", updatePreviewFeedback)
    end
end

function GUF.ApplyCombatText(entry)
    if entry.optionsPreview or not CombatFeedback_OnCombatEvent then return end
    local cfg = GUF.Runtime.Settings("combatText", entry).frames[entry.unit]
    -- The single enable toggle owns feedback visibility. Native controllers
    -- continue running while their duplicate text is cosmetically suppressed.
    for _, region in pairs(entry.feedbackRegions) do leaseAlpha(region, 0) end
    local enabled = cfg.combatText.enabled
    local frame = entry.combatText
    if enabled and (not frame or not frame.created) then frame = createFeedback(entry); entry.combatText = frame end
    if not frame then return end
    frame.runtimeEntry, frame.runtimeBinding = entry, GUF.Runtime.Binding("combatText", entry)
    frame:UnregisterAllEvents()
    if not enabled then frame:Hide(); clearFeedback(frame); return end
    styleFeedback(entry, frame)
    frame:RegisterUnitEvent("UNIT_COMBAT", entry.unit)
    if entry.unit == "target" or entry.unit == "targettarget" then frame:RegisterEvent("PLAYER_TARGET_CHANGED") end
    if entry.unit == "targettarget" then frame:RegisterUnitEvent("UNIT_TARGET", "target") end
    if entry.unit == "pet" then frame:RegisterUnitEvent("UNIT_PET", "player") end
    frame:Show()
end
