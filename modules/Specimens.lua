local _, GUF = ...
local Presentation = GUF.Presentation
local unpack = unpack or table.unpack

local function font(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text.goodUnitFramesOwned = true
    text:SetWordWrap(false)
    return text
end

-- Shared primitive sample regions only. The selected layout creates its own
-- housing, portrait, indicators and geometry; Blizzard allocates no Artistic art.
function GUF.CreateSpecimenBase(unit, parent, style)
    local frame = CreateFrame("Frame", nil, parent or UIParent)
    frame.goodUnitFramesOwned = true
    frame:EnableMouse(false)
    frame:SetFrameStrata(parent and parent:GetFrameStrata() or "HIGH")
    frame:SetFrameLevel(parent and parent:GetFrameLevel() + 4 or 30)
    frame:Hide()
    local entry = { unit = unit, frame = frame, configurationPreview = true,
        healthSlots = {}, powerSlots = {}, specimenStyle = style }
    local state = { unit = unit, active = false, scale = 1, badges = {}, textAreas = {} }
    entry.specimenState = state
    local nameLayer = CreateFrame("Frame", nil, frame)
    nameLayer.goodUnitFramesOwned = true
    nameLayer:SetFrameLevel(48)
    entry.name = font(nameLayer)
    entry.name:SetPoint("CENTER")
    for _, kind in ipairs({ "health", "power" }) do
        local bar = CreateFrame("StatusBar", nil, frame)
        bar.goodUnitFramesOwned = true
        bar:SetFrameLevel(32)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        entry[kind], entry[kind .. "Text"] = bar, font(bar)
        bar.background = bar:CreateTexture(nil, "BACKGROUND")
        bar.background.goodUnitFramesOwned = true
        bar.background:SetAllPoints(); bar.background:SetColorTexture(.025, .025, .03, 1)
        state.textAreas[kind] = CreateFrame("Frame", nil, bar)
        state.textAreas[kind].goodUnitFramesOwned = true
        for _, side in ipairs({ "left", "center", "right" }) do entry[kind .. "Slots"][side] = font(bar) end
    end
    entry.castBar = GUF.CreateCastBarPresentation(frame)
    entry.castBar.managed = true
    entry.castBar.icon:SetTexture("Interface\\Icons\\INV_Spear_07")
    return entry
end

function Presentation.SampleData(entry, options)
    local states = options.states or {}
    local status = ({ dead = "Dead", ghost = "Ghost", offline = "Offline" })[options.state]
        or (states.resurrect and "Dead" or states.feign and "Feign death" or "")
    local health = options.health == nil and 55 or options.health
    if GUF.Secret(health) or type(health) ~= "number" or health ~= health then health = 55 end
    health = math.max(0, math.min(100, health))
    if status == "Dead" or status == "Ghost" then health = 0 end
    local name = options.subject == "player" and GUF.PreviewPlayerName() or "Beary"
    local cfg = GUF.PresentationFrameSettings(entry)
    name = GUF.UnitNamePart(name, cfg.nameDisplay)
    entry.sampleState, entry.previewClassification = options.state, options.subject
    entry.previewCombat = states.combat == true
    entry.configurationShowAll = options.showAll
    entry.previewData = { health = health * 100, healthMax = 10000, healthPercent = health,
        power = 100, powerMax = 100, powerPercent = 100, level = GUF.PreviewPlayerLevel(), name = name, status = status }
    return entry.previewData
end

function Presentation.StyleSampleBars(entry, options)
    local cfg, data = GUF.PresentationFrameSettings(entry), entry.previewData
    local stock = entry.presentationContext.definition.presentation.nativeBarColors
    local offline = data.status == "Offline"
    if not stock or cfg.healthColor ~= "blizzard" or offline then
        if stock then entry.health:GetStatusBarTexture():SetDesaturated(true) end
        GUF.TintPresentationBar(entry.health, GUF.PreviewHealthColor(entry, options.subject, data.healthPercent, offline))
    end
    if not stock or cfg.bars.powerMode ~= "blizzard" or offline or data.status == "Dead" or data.status == "Ghost" then
        local r, g, b
        if offline or data.status == "Dead" or data.status == "Ghost" then r, g, b = unpack(GUF.colors.offline)
        elseif cfg.bars.powerMode == "class" then r, g, b = GUF.ClassColor("player")
        else
            local color = GUF.powerColors[options.powerToken]
            if color then r, g, b = unpack(color)
            else
                local powerType, token, red, green, blue = UnitPowerType("player")
                local native = not GUF.Secret(powerType) and type(powerType) == "number" and PowerBarColor and PowerBarColor[powerType]
                local function public(value) return not GUF.Secret(value) and type(value) == "number" end
                if not GUF.Secret(token) and token == options.powerToken and native
                    and public(native.r) and public(native.g) and public(native.b) then r, g, b = native.r, native.g, native.b
                elseif not GUF.Secret(token) and token == options.powerToken and public(red) and public(green) and public(blue) then
                    r, g, b = red, green, blue
                else r, g, b = unpack(GUF.powerColors.MANA) end
            end
        end
        if stock then entry.power:GetStatusBarTexture():SetDesaturated(true) end
        GUF.TintPresentationBar(entry.power, r, g, b)
    end
    entry.name:SetTextColor(GUF.PreviewNameColor(entry, options.subject))
end

function GUF.CreateFrameSpecimen(unit, parent, style)
    if not GUF.IsManagedUnit(unit) then return end
    style = style or GUF.db.general.frameStyle
    local definition = GUF.Layouts.Get(style)
    if not definition then return end
    return definition.presentation.createSample(unit, parent)
end

function GUF.RenderFrameSpecimen(entry, native, options)
    options = options or {}
    local style = options.style or entry.specimenStyle
    if style ~= entry.specimenStyle then error("A specimen cannot change its registered layout.") end
    local source = options.settings or GUF.Settings.GetLayout(GUF.db, style)
    -- Inactive layout snapshots deliberately contain no General table. Build a
    -- private presentation snapshot; never stamp advertised style into storage.
    local settings = { general = GUF.Copy(GUF.db.general), frames = GUF.Copy(source.frames),
        threat = GUF.Copy(source.threat), hideBlizzard = GUF.Copy(source.hideBlizzard) }
    settings.general.frameStyle = style
    local scenario = {}
    for key, value in pairs(options) do scenario[key] = value end
    scenario.style, scenario.config = style, settings.frames[entry.unit]
    scenario.state, scenario.subject = scenario.state or "normal", scenario.subject or "player"
    scenario.states = scenario.states and GUF.Copy(scenario.states) or { [scenario.state] = true }
    scenario.groups = scenario.groups and GUF.Copy(scenario.groups) or nil
    scenario.group = scenario.group or "solo"
    if not scenario.powerToken then
        local _, token = UnitPowerType("player")
        scenario.powerToken = not GUF.Secret(token) and token or "MANA"
    end
    local context = Presentation.New(style, entry.unit, settings, scenario.layoutCard and "card" or "interactive",
        entry, scenario, options.generation)
    entry.presentationContext = context
    entry.presentationConfig, entry.presentationStyle = scenario.config, style
    entry.presentationStatus, entry.presentationReason = "rendering", nil
    return Presentation.With(context, function()
        Presentation.SampleData(entry, scenario)
        local status, reason = context.definition.presentation.renderSample(entry, scenario, context)
        if status == "unavailable" or status == "deferred" then
            entry.presentationStatus, entry.presentationReason = status, reason
            entry.frame:Hide(); return status, reason
        end
        Presentation.StyleSampleBars(entry, scenario)
        Presentation.SampleFeatures(entry, scenario)
        entry.presentationStatus, entry.presentationReason = "applied", nil
        return "applied"
    end)
end

-- Bounds are measured only from owned synthetic regions. Live layouts expose
-- their public root footprint instead of sampling live status-bar fill geometry.
function Presentation.OwnedBounds(context)
    local entry = context.view
    local frame = entry.frame
    local frameHeight = frame:GetHeight()
    local left, right, bottom, top = 0, frame:GetWidth(), -frameHeight, 0
    local function include(region)
        if region:GetObjectType() == "MaskTexture" then return end
        local rect = GUF.FrameRectInUnit(entry, region)
        if not rect then return end
        local upper, lower = rect.top - frameHeight, rect.bottom - frameHeight
        local paintTop, paintBottom = Presentation.Feature(entry, "paintedBounds", region)
        if paintTop then upper, lower = paintTop, paintBottom end
        left, right = math.min(left, rect.left), math.max(right, rect.right)
        bottom, top = math.min(bottom, lower), math.max(top, upper)
    end
    local function collect(host)
        for _, region in ipairs({ host:GetRegions() }) do if region:IsShown() then include(region) end end
        for _, child in ipairs({ host:GetChildren() }) do
            if child:IsShown() then include(child); collect(child) end
        end
    end
    collect(frame)
    return { left = left, right = right, bottom = bottom, top = top }
end

function Presentation.Bounds(entry)
    local context = Presentation.ForEntry(entry)
    return context.definition.presentation.bounds(context)
end

function Presentation.FitCard(entry, parent, paddingY)
    local frame = entry.frame
    frame:SetScale(1)
    local bounds = Presentation.Bounds(entry)
    local width, height = math.max(1, bounds.right - bounds.left), math.max(1, bounds.top - bounds.bottom)
    local scale = math.max(.1, math.min(1, (parent:GetWidth() - 12) / width,
        (parent:GetHeight() - (paddingY or 12)) / height))
    frame:SetScale(scale); frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", (parent:GetWidth() - width * scale) / (2 * scale) - bounds.left,
        -(parent:GetHeight() - height * scale) / (2 * scale) - bounds.top)
end

-- Feature presenters consume the same layout snapshot and host roles as the
-- frame presenter. Cards deliberately omit the interactive diagnostic layers.
function Presentation.SampleFeatures(entry, scenario)
    if scenario.layoutCard then return end
    local cfg = GUF.PresentationFrameSettings(entry)
    GUF.RenderResourceSample(entry, scenario)
    GUF.RenderPredictionSample(entry, cfg, entry.previewData.healthPercent, scenario.showAll, scenario.prediction)
    if entry.unit == "target" and scenario.subject ~= "player" then
        local presentation = entry.blizzardPresentation
        for _, kind in ipairs({ "pvp", "pvpBackground", "leader", "role", "loot" }) do
            local badge = Presentation.Role(entry, "indicator:" .. kind)
            if badge then badge:Hide() end
            local record = presentation and presentation.indicators and presentation.indicators[kind]
            if record then record.frame:Hide() end
        end
    end
    GUF.PreviewCombatText(entry, scenario.combatText)
    GUF.RefreshAuraPreview(entry)
end
