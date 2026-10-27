local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "ArtisticLayout")
end
local unpack = unpack or table.unpack
local circle = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local white = "Interface\\Buttons\\WHITE8X8"
-- Measured original PNG coordinates, not the requested generation dimensions.
local portraitArt = { canvas = 1254, centerX = 626.5, centerY = 617.5, diameter = 1117,
    paintTop = 71, paintBottom = 1164 } -- alpha >=128; bottom is exclusive
-- Preserve the previous core reference independently of the fresh plain border.
local playerPortraitReference = { canvas = 1254, centerX = 626, centerY = 616.5,
    diameter = 1140, paintTop = 47, paintBottom = 1186 }
-- Height is the sizing priority; font sizes remain the user's own preference.
-- Health remains ten units taller than Power before compact/unit scaling.
local base = { barWidth = 124, healthDifference = 10, portrait = 62,
    topInset = 1, divider = 1, bottomInset = 2, housingEdge = 3, header = 15 }
function GUF.ArtisticPortraitArtwork(unit, liveUnit)
    local source, reason = GUF.SelectArtisticPortraitArtwork(unit, liveUnit)
    return source or portraitArt, reason
end

function GUF.ArtisticPortraitReferenceArtwork(unit)
    -- A fixed common reference: target identity must never change bar geometry.
    if unit == "player" or unit == "target" then return playerPortraitReference end
    return portraitArt
end

function GUF.ArtisticBarHost(entry, kind)
    return GUF.Presentation.Role(entry, kind) or entry[kind]
end

-- Owned Retail bars do not need native amount-driven geometry to be readable.
-- Keep Forever Target's existing native geometry path; Player isolation is
-- already shared by its owned resource renderers on both clients.
function GUF.ArtisticNativeBarsIsolated(entry, state)
    state = state or entry.artisticLayout
    return GUF.IsManagedUnit(entry.unit) and state ~= nil and state.renderBars ~= nil
        and (entry.unit == "player" or GUF.isRetail)
end

function GUF.BarTextHost(entry, kind)
    if kind == "health" and entry.predictions then return entry.predictions.textLayer end
    if kind == "health" and entry.configurationPreview and entry.textLayer then return entry.textLayer end
    return GUF.Presentation.Role(entry, kind .. "Text") or entry[kind]
end

function GUF.LayoutArtisticDividerLayer(entry)
    local state = entry.artisticLayout
    if not state or not state.dividerLayer then return end
    local health, power = GUF.ArtisticBarHost(entry, "health"), GUF.ArtisticBarHost(entry, "power")
    local healthLevel, powerLevel = health:GetFrameLevel(), power:GetFrameLevel()
    local strata = health:GetFrameStrata()
    if GUF.Secret(healthLevel) or GUF.Secret(powerLevel) or GUF.Secret(strata) then return end
    state.dividerLayer:SetFrameStrata(strata)
    state.dividerLayer:SetFrameLevel(math.max(healthLevel, powerLevel) + 4)
end

function GUF.LayoutArtisticRenderedBar(entry, kind, x, y, width, height)
    local state = entry.artisticLayout
    local render = state and state.renderBars and state.renderBars[kind]
    if not render then return end
    -- Player and Target use the same public base geometry. The shared header
    -- divider owns its inset; fill sizes do not compensate for border seams.
    render:ClearAllPoints()
    render:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", x, y)
    render:SetSize(width, height)
end

function GUF.LayoutArtisticRenderedLayers(entry)
    local state = entry.artisticLayout
    if not state or not state.active or not state.renderBars then return end
    local level = entry.frame:GetFrameLevel()
    local strata = entry.frame:GetFrameStrata()
    if GUF.Secret(level) or GUF.Secret(strata) then return end
    -- Keep presentation ordering independent of native classification/layout.
    -- Each owned bar carries its backing below its own fill; shell frames now
    -- retain geometry only and must not paint an opaque surface over the bar.
    state.background:SetFrameLevel(level)
    state.background:SetFrameStrata(strata)
    state.healthShell:SetFrameLevel(level + 1)
    state.powerShell:SetFrameLevel(level + 1)
    for _, kind in ipairs({ "health", "power" }) do
        state.renderBars[kind]:SetFrameLevel(level + 2)
        state.renderBars[kind]:SetFrameStrata(strata)
    end
    -- Predictions occupy fill + 1..3, and their text layer occupies fill + 4.
    state.ornaments:SetFrameLevel(level + 7)
    state.rim:SetFrameLevel(level + 8)
    state.badgeLayer:SetFrameLevel(level + 11)
    -- Keep foreground chrome in the same strata as the owned Target fills;
    -- frame levels cannot put a divider above a fill in a higher strata.
    for _, host in ipairs({ state.healthShell, state.powerShell, state.ornaments, state.rim, state.badgeLayer }) do
        host:SetFrameStrata(strata)
    end
    GUF.LayoutArtisticDividerLayer(entry)
    if entry.predictions then entry.predictions.dirty = true end
end

local function suppressNativeDecorations(entry)
    local state = entry.artisticLayout
    if not state or not state.active then return end
    local frame = entry.frame
    local container = frame.PlayerFrameContainer or frame.TargetFrameContainer or frame
    local regions = { container.Flash, container.FrameFlash, frame.flash,
        frame.threatIndicator, frame.ThreatIndicator, entry.nameBackground }
    local powerFeedback
    if entry.unit == "target" then
        -- ReputationColor carries every native reaction/tapped-grey backdrop;
        -- BossPortraitFrameTexture carries the native rank dragon.
        regions.reaction = entry.main and entry.main.ReputationColor
        regions.dragon = container.BossPortraitFrameTexture
        regions.legacyDragon = frame.BossPortraitFrameTexture
    elseif entry.unit == "player" then
        -- One native StatusTexture supplies both combat red and resting gold.
        regions.status = entry.main and entry.main.StatusTexture
        regions.legacyStatus = frame.statusTexture
        -- Some Player classes retain the native Power renderer. Suppress these
        -- cosmetic animation hosts here, before the owned-bar-only pass.
        -- Texture alpha alone does not contain a full-resource pulse.
        regions.fullPower = entry.power and entry.power.FullPowerFrame
        regions.powerFeedback = entry.power and entry.power.FeedbackFrame
        regions.powerSpark = entry.power and entry.power.Spark
        if GUF.isRetail and state.renderBars then
            -- This red damage trail is a Health sibling, not a Power effect.
            -- Its native placement can overlap the owned Artistic Power row.
            regions.healthLoss = GUF.Client.ResolvePlayerHealthLoss(entry)
            local effects = GUF.Client.ResolvePlayerPowerEffects(entry.power)
            for key, region in pairs(effects or {}) do regions[key] = region end
            powerFeedback = effects and effects.powerFeedback
        end
        local textFrame = frame.rightFrame and frame.rightFrame.textFrame
        regions.overAbsorbGlow = textFrame and textFrame.overAbsorbGlow
        regions.overHealAbsorbGlow = textFrame and textFrame.overHealAbsorbGlow
        -- Priest's native class controller paints a separate portrait glow
        -- and animated fill sibling. Suppress cosmetics, retaining its events,
        -- animations, masks and primary Insanity controller unchanged.
        local insanity = GUF.isRetail and InsanityBarFrame
        regions.insanityPortrait = insanity and insanity.PortraitGlow
        regions.insanityFill = insanity and insanity.FillOverlay
    end
    state.nativeDecorationHooks = state.nativeDecorationHooks or {}
    for _, region in pairs(regions) do
        if region and not region.goodUnitFramesOwned and region.SetAlpha
            and not (region.IsForbidden and region:IsForbidden()) then
            state.hidden[region] = true
            leaseAlpha(region, 0)
            if not state.nativeDecorationHooks[region] then
                -- Native faction/classification/status updates recolor/rebind these
                -- textures as well as showing them. Reassert appearance only;
                -- leave their controllers and numeric threat untouched.
                local function suppress()
                    if state.active then leaseAlpha(region, 0) end
                end
                for _, method in ipairs({ "Show", "SetShown", "SetVertexColor", "SetAtlas", "SetTexture" }) do
                    if type(region[method]) == "function" then GUF.NativeProperties.Hook("ArtisticLayout:1", region, method, suppress) end
                end
                state.nativeDecorationHooks[region] = true
            end
        end
    end
    if powerFeedback and not powerFeedback.goodUnitFramesOwned then
        state.powerFeedbackHooks = state.powerFeedbackHooks or {}
        local watched = state.powerFeedbackHooks[powerFeedback] or {}
        state.powerFeedbackHooks[powerFeedback] = watched
        for _, method in ipairs({ "Initialize", "StartFeedbackAnim" }) do
            if not watched[method] and type(powerFeedback[method]) == "function" then
                GUF.NativeProperties.Hook("ArtisticLayout:2", powerFeedback, method, function()
                    -- Ignore native amounts passed to the controller. Reconcile
                    -- cosmetic leases after it initializes/starts an effect;
                    -- released or replaced hosts cannot reacquire ownership.
                    if state.active and state.renderBars and entry.power
                        and entry.power.FeedbackFrame == powerFeedback then
                        GUF.SuppressArtisticNativeBars(entry)
                    end
                end)
                watched[method] = true
            end
        end
    end
end

function GUF.SuppressArtisticNativeBars(entry)
    local state = entry.artisticLayout
    if not state or not state.active or state.suppressWriting then return end
    suppressNativeDecorations(entry)
    if not state.renderBars then return end
    state.suppressWriting = true
    local function suppress(region)
        if not region or region.goodUnitFramesOwned or not region.SetAlpha then return end
        -- StatusBar-created fill textures do not inherit custom Lua markers.
        -- Exclude the presentation textures explicitly as well as their hosts.
        for _, render in pairs(state.renderBars) do
            if region == render or region == render:GetStatusBarTexture() then return end
        end
        state.hidden[region] = true
        leaseAlpha(region, 0)
    end
    local function textures(owner)
        if not owner or GUF.IsUnmanagedUnitFrame(owner) or owner.goodUnitFramesOwned then return end
        if owner.GetRegions then
            for _, region in pairs({ owner:GetRegions() }) do
                if region:GetObjectType() == "Texture" then suppress(region) end
            end
        end
        if owner.GetChildren then
            for _, child in pairs({ owner:GetChildren() }) do textures(child) end
        end
    end
    for _, kind in ipairs({ "health", "power" }) do
        local native = entry[kind]
        if native then
            -- Named XML fills and child feedback renderers can differ from the
            -- current StatusBar texture. Suppress their visuals, not controllers
            -- or FontStrings. Owned text/prediction hosts are excluded.
            suppress(native:GetStatusBarTexture())
            textures(native)
            for _, key in ipairs({ "FeedbackFrame", "HealthBarAnimatedLoss", "AnimatedLoss",
                "FullPowerFrame", "bbfSmoothOverlay", "bbfOvershieldBar" }) do suppress(native[key]) end
        end
    end
    suppress(entry.healthArea.TempMaxHealthLoss)
    suppress(entry.frame.tempMaxHealthLossBar)
    state.suppressWriting = nil
end

function GUF.SyncArtisticRenderedBar(entry, kind)
    local state = entry.artisticLayout
    local render = state and state.active and state.renderBars and state.renderBars[kind]
    if not render or state.renderWriting then return end
    state.renderWriting = true
    GUF.SuppressArtisticNativeBars(entry)
    local unit, cfg = entry.frame.unit or entry.unit, GUF.Runtime.Settings("colors", entry).frames[entry.unit]
    local exists = UnitExists(unit)
    if not GUF.Secret(exists) and not exists then
        render:Hide()
        state.renderWriting = nil
        return
    end
    -- DinoUnitFrames' model: read the unit directly on target/unit events.
    -- Hidden native bars are not a source of range, value, tint or opacity.
    local value, maximum, r, g, b
    if kind == "health" then
        value, maximum = UnitHealth(unit), UnitHealthMax(unit)
        r, g, b = GUF.HealthColor(unit, cfg)
    else
        local powerType = UnitPowerType(unit)
        value, maximum = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
        r, g, b = GUF.PowerColor(unit, cfg)
    end
    -- The new Player presentation preserves its explicitly selected native
    -- color policy using captured presentation, never native fill geometry.
    if entry.unit == "player" and ((kind == "health" and cfg.healthColor == "blizzard")
        or (kind == "power" and cfg.bars.powerMode == "blizzard")) then
        r, g, b = GUF.BlizzardTextureColor(entry, kind)
    end
    render:SetMinMaxValues(0, maximum)
    render:SetValue(value)
    -- Keep StatusBar tint neutral; pass opaque color components only to the
    -- owned texture, just as Dino's SetBlockColor does for restricted colors.
    GUF.TintPresentationBar(render, r, g, b)
    if kind == "power" then
        -- Resolve row visibility before text renders. Restricted amounts stay
        -- opaque; the native Power widget owns its zero-capacity shown state.
        GUF.SyncArtisticPowerLayout(entry, false, maximum)
    end
    render:SetShown(kind ~= "power" or not state.noPower)
    state.renderWriting = nil
end

function GUF.PrintArtisticTargetBars()
    local entry = GUF.frames.target
    local state = entry and entry.artisticLayout
    if not state or not state.active or not state.renderBars then
        GUF.Print("Target bars: Artistic owned presentation is inactive.")
        return
    end
    local function public(value)
        if GUF.Secret(value) then return "<restricted>" end
        if type(value) == "number" then return string.format("%.2f", value) end
        return tostring(value)
    end
    local unit, cfg = entry.frame.unit or entry.unit, GUF.Runtime.Settings("layout", "target").frames.target
    local _, class = UnitClass(unit)
    local powerType, powerToken = UnitPowerType(unit)
    local hasPower = "unavailable"
    if UnitHasPowerType and not GUF.Secret(powerType) and type(powerType) == "number" and powerType >= 0 then
        hasPower = UnitHasPowerType(unit, powerType)
    end
    GUF.Print("Target power API v4: unit=" .. public(unit)
        .. "; exists=" .. public(UnitExists(unit)) .. "; player=" .. public(UnitIsPlayer(unit))
        .. "; type=" .. public(powerType) .. "; token=" .. public(powerToken)
        .. "; hasPowerType=" .. public(hasPower)
        .. "; max(default)=" .. public(UnitPowerMax(unit))
        .. "; max(typed)=" .. public(UnitPowerMax(unit, powerType))
        .. "; max(raw)=" .. public(UnitPowerMax(unit, powerType, true)))
    GUF.Print("Target power layout: noPower=" .. public(state.noPower)
        .. "; reason=" .. public(state.powerCapacityReason)
        .. "; nativePowerShown=" .. public(entry.power:IsShown())
        .. "; nativeControlsShown=" .. public(entry.power.controlsShownState)
        .. "; editing=" .. public(GUF.editing) .. "; restricted=" .. public(GUF.Restricted())
        .. "; pending=" .. public(GUF.pending)
        .. "; baseHealth=" .. public(state.healthFillHeight)
        .. "; healthRow=" .. public(state.healthRowHeight) .. "; powerRow=" .. public(state.powerRowHeight))
    GUF.Print("Target color state: unit=" .. public(unit) .. "; mode=" .. public(cfg.healthColor)
        .. "; class=" .. public(class) .. "; player=" .. public(UnitIsPlayer(unit))
        .. "; connected=" .. (UnitIsConnected and public(UnitIsConnected(unit)) or "unavailable")
        .. "; AFK=" .. (UnitIsAFK and public(UnitIsAFK(unit)) or "unavailable")
        .. "; tapDenied=" .. (UnitIsTapDenied and public(UnitIsTapDenied(unit)) or "unavailable"))
    for _, kind in ipairs({ "health", "power" }) do
        for _, owner in ipairs({ "native", "owned" }) do
            local bar = owner == "native" and entry[kind] or state.renderBars[kind]
            local fill = bar:GetStatusBarTexture()
            local minimum, maximum = bar:GetMinMaxValues()
            GUF.Print("Target " .. kind .. " " .. owner .. ": " .. public(bar:GetWidth()) .. "x" .. public(bar:GetHeight())
                .. "; strata=" .. public(bar:GetFrameStrata()) .. "; level=" .. public(bar:GetFrameLevel())
                .. "; visible=" .. public(bar:IsVisible()) .. "; alpha=" .. public(bar:GetAlpha())
                .. "; fillAlpha=" .. public(fill and fill:GetAlpha())
                .. "; value=" .. public(bar:GetValue()) .. "; range=" .. public(minimum) .. ".." .. public(maximum))
            if fill then
                local r, g, b, a = fill:GetVertexColor()
                GUF.Print("Target " .. kind .. " " .. owner .. " fill: " .. public(fill:GetTexture())
                    .. "; RGBA=" .. public(r) .. "," .. public(g) .. "," .. public(b) .. "," .. public(a))
            end
        end
    end
end

function GUF.ShowTargetDividerReport()
    local entry = GUF.frames.target
    local state = entry and entry.artisticLayout
    if not state or not state.active or not state.renderBars then
        GUF.Print("Select Artistic layout with a Target first.")
        return
    end
    if GUF.editing or GUF.Restricted() then GUF.Print("Open diagnostic reports outside combat and Edit Mode."); return end
    local function public(value)
        if GUF.Secret(value) then return "<restricted>" end
        if type(value) == "number" then return string.format("%.3f", value) end
        return tostring(value)
    end
    local lines = { "Name/Health join report v5 (shared border); interface=" .. public(GUF.clientInterface) }
    local function describe(label, specimen)
        local layout = specimen.artisticLayout
        local upper = layout.headerDivider or layout.separators and layout.separators[1]
        local lower = layout.divider or layout.separators and layout.separators[2]
        local health = GUF.ArtisticBarHost(specimen, "health")
        local housing = layout.housing.border or layout.housing
        local names = { [specimen.frame] = "root", [health] = "health", [layout.nameStrip] = "name",
            [housing] = "housing", [layout.rim] = "rim" }
        if layout.background then names[layout.background] = "background" end
        if layout.dividerLayer then names[layout.dividerLayer] = "dividerLayer" end
        local function reference(region) return region and (names[region] or "other") or "nil" end
        local function frame(label, region)
            if not region then return label .. "=missing" end
            return label .. "=" .. public(region:GetFrameLevel()) .. "/" .. public(region:GetFrameStrata())
                .. "; visible=" .. public(region:IsVisible()) .. "; alpha=" .. public(region:GetAlpha())
                .. "; parent=" .. reference(region:GetParent())
        end
        local function rectangle(region)
            if region == health and not region.goodUnitFramesOwned then return "<native host; not measured>" end
            local rect = region and GUF.FrameRectInUnit(specimen, region)
            if not rect then return "<unavailable>" end
            return "[" .. public(rect.left) .. "," .. public(rect.bottom) .. "," .. public(rect.right) .. "," .. public(rect.top) .. "]"
        end
        lines[#lines + 1] = "\n" .. label .. "; rectangles are [left,bottom,right,top] in frame coordinates"
        for _, item in ipairs({ { "upper", upper }, { "lower", lower },
            { "nameBody", layout.nameStrip.body } }) do
            local region = item[2]
            if region then
                local layer, sublevel = region:GetDrawLayer()
                local override = GUF.alphaStates and GUF.alphaStates[region]
                local width, height = region:GetSize()
                local _, _, _, vertexAlpha = region:GetVertexColor()
                lines[#lines + 1] = item[1] .. ": shown=" .. public(region:IsShown()) .. "; visible=" .. public(region:IsVisible())
                    .. "; alpha=" .. public(region:GetAlpha()) .. "; vertexAlpha=" .. public(vertexAlpha)
                    .. "; override=" .. public(override and override.override) .. "; parent=" .. reference(region:GetParent())
                    .. "; draw=" .. public(layer) .. "/" .. public(sublevel) .. "; size=" .. public(width) .. "x" .. public(height)
                    .. "; rect=" .. rectangle(region)
            else lines[#lines + 1] = item[1] .. ": missing" end
        end
        for _, item in ipairs({ { "dividerLayer", layout.dividerLayer }, { "background", layout.background },
            { "health", health }, { "name", layout.nameStrip }, { "housing", housing }, { "rim", layout.rim } }) do
            lines[#lines + 1] = frame(item[1], item[2])
        end
        lines[#lines + 1] = "rects: health=" .. rectangle(health) .. "; name=" .. rectangle(layout.nameStrip)
            .. "; housing=" .. rectangle(housing)
        lines[#lines + 1] = "geometry: healthY=" .. public(layout.healthY) .. "; headerTop=" .. public(layout.headerTop)
            .. "; topInset=" .. public(layout.healthTopInset) .. "; pixelSize=" .. public(GUF.ArtisticDividerPixelSize(specimen))
            .. "; effectiveScale=" .. public(specimen.frame:GetEffectiveScale())
        lines[#lines + 1] = "Health texture setting=" .. public(GUF.Runtime.Settings("layout", specimen).frames[specimen.unit].bars.healthTexture)
    end
    local player = GUF.frames.player
    if player and player.artisticLayout and player.artisticLayout.active then describe("LIVE PLAYER", player) end
    describe("LIVE TARGET", entry)
    local preview = GUF.optionsPreviewEntry
    if preview and preview.unit == "target" and not preview.blizzardPresentation then describe("INTERACTIVE PREVIEW", preview) end
    GUF.ShowDiagnosticReport("Player/Target Name/Health join", table.concat(lines, "\n"))
end

-- Artistic owns component geometry and the optional portrait viewport. Blizzard
-- owns secure buttons, live bars and resource controllers; never stretch glyphs.
local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function yes(value)
    return not GUF.Secret(value) and (value == true or value == 1)
end

local function compact(unit)
    return unit == "pet" and .78 or unit == "targettarget" and .62 or 1
end

local function legacyDimensions(unit, cfg)
    local scale = compact(unit)
    local width = number(cfg.width) and cfg.width >= 0 and cfg.width or 260 * scale
    local height = number(cfg.height) and cfg.height >= 0 and cfg.height or 90 * scale
    return math.max(math.ceil(180 * scale), math.min(300, width)), math.max(math.ceil(80 * scale), math.min(100, height))
end

-- Legacy migration helper; the old flexible preferences remain stored.
function GUF.ArtisticLegacyBarSize(unit, kind, cfg)
    local width, height = legacyDimensions(unit, cfg)
    local scale = compact(unit)
    local budget = height - 28 * scale
    return width - 81 * scale, kind == "health" and budget * .65 - 3 * scale or budget * .35 - 4 * scale
end

-- Portrait scale is relative to the original 80-high composition, never to
-- the current bar stack. Otherwise height changes silently multiply its size.
local portraitScaleHeight, maximumStackHeight = 80, 120

function GUF.ArtisticStackHeight(cfg)
    local geometry = cfg.artistic.playerGeometry
    return geometry.header + geometry.health + geometry.power + 4
end

function GUF.ArtisticMinimumPortraitScale(cfg)
    -- The portrait slider uses whole percentages. Round upward so the stack
    -- never protrudes while its displayed percentage remains accurate.
    return math.max(1, math.min(1.5, math.ceil(GUF.ArtisticStackHeight(cfg) * 100 / portraitScaleHeight) / 100))
end

function GUF.ArtisticPortraitScaleLimits(unit)
    if unit == "player" or unit == "target" then
        return GUF.ArtisticMinimumPortraitScale(GUF.Runtime.Settings("layout", unit).frames[unit]), 1.5
    end
    return 1, 1.5
end

function GUF.NormalizeArtisticPortraitSizing(unit, cfg)
    if unit ~= "player" and unit ~= "target" then return end
    local artistic = cfg.artistic
    local geometry = artistic.playerGeometry
    if type(geometry) ~= "table" then return end
    local source = GUF.ArtisticPortraitReferenceArtwork(unit)
    local factor = source.diameter / (source.paintBottom - source.paintTop)
    local specs = { { "header", 8, 16 }, { "health", 12, 38 }, { "power", 8, 22 } }
    for _, spec in ipairs(specs) do
        local value = geometry[spec[1]]
        geometry[spec[1]] = number(value) and math.max(spec[2], math.min(100, value)) or spec[3]
    end
    local oldHeight = GUF.ArtisticStackHeight(cfg)
    local validWidth = number(geometry.width)
    local width = math.max(80, (validWidth and geometry.width or 300) - oldHeight * factor - 6)
    local scale = number(artistic.portraitScale) and artistic.portraitScale or 1
    local legacy = artistic.portraitSizingVersion ~= 1
    if legacy then scale = scale * oldHeight / portraitScaleHeight end
    if oldHeight > maximumStackHeight then
        -- Retain row proportions above their existing minima when old profiles
        -- exceed the new shared budget. No unrelated preferences are reset.
        local budget, remainder = maximumStackHeight - 32, maximumStackHeight - 32
        for i, spec in ipairs(specs) do
            local extra = i == #specs and remainder
                or math.floor((geometry[spec[1]] - spec[2]) * budget / (oldHeight - 32))
            geometry[spec[1]] = spec[2] + extra
            remainder = remainder - extra
        end
    end
    artistic.portraitScale = math.max(GUF.ArtisticMinimumPortraitScale(cfg), math.min(1.5, scale))
    artistic.portraitSizingVersion = 1
    if legacy or oldHeight > maximumStackHeight or not validWidth then
        geometry.width = width + GUF.ArtisticStackHeight(cfg) * factor + 6
        if type(cfg.bars) == "table" then
            cfg.bars.width = width
            if type(cfg.bars.healthSize) == "table" then cfg.bars.healthSize.height = geometry.health end
            if type(cfg.bars.powerSize) == "table" then cfg.bars.powerSize.height = geometry.power end
        end
    end
end

function GUF.ArtisticBarLimits(unit, kind)
    local scale = compact(unit)
    local minimum = math.ceil((kind == "health" and 12 or 8) * scale)
    local maximum = 100
    if unit == "player" or unit == "target" then
        local cfg = GUF.Runtime.Settings("layout", unit).frames[unit]
        local key = kind == "name" and "header" or kind
        maximum = math.max(minimum, math.min(maximum,
            math.floor(maximumStackHeight - GUF.ArtisticStackHeight(cfg) + cfg.artistic.playerGeometry[key])))
    end
    return math.ceil(80 * scale), 300, minimum, maximum
end

function GUF.ArtisticBarSize(unit, kind, config)
    if unit == "player" or unit == "target" then
        local geometry = (config or GUF.Runtime.Settings("layout", unit).frames[unit]).artistic.playerGeometry
        return math.max(80, geometry.width - GUF.ArtisticBasePortraitWidth(unit, config) - 6),
            kind == "health" and geometry.health or geometry.power
    end
    -- Keep flexible preferences stored; only uniform Frame Scale changes this
    -- fixed composition, so its circular artwork and faces retain proportions.
    local scale = compact(unit)
    -- Use the painted rim's vertical span, excluding its transparent margins.
    -- Header plus bar housing reaches that same top/bottom without overflow.
    local paintedHeight = base.portrait * (portraitArt.paintBottom - portraitArt.paintTop) / portraitArt.diameter
    local fillBudget = paintedHeight - base.header - base.topInset - base.divider - base.bottomInset
    local difference = kind == "health" and base.healthDifference or -base.healthDifference
    return base.barWidth * scale, (fillBudget + difference) / 2 * scale
end

function GUF.ArtisticDimensions(unit, config)
    if unit == "player" or unit == "target" then
        local geometry = (config or GUF.Runtime.Settings("layout", unit).frames[unit]).artistic.playerGeometry
        return math.max(geometry.width, GUF.ArtisticBasePortraitWidth(unit, config) + 86), geometry.header + geometry.health + geometry.power + 4
    end
    local width, healthHeight = GUF.ArtisticBarSize(unit, "health")
    local _, powerHeight = GUF.ArtisticBarSize(unit, "power")
    local scale = compact(unit)
    local diameter = GUF.ArtisticBasePortraitWidth(unit)
    local stackHeight = healthHeight + powerHeight + (base.topInset + base.divider + base.bottomInset) * scale
    return width + diameter + 10 * scale, math.max(diameter, stackHeight) + 8 * scale
end

-- The stack-fitting reference owns core placement only. The actual portrait
-- uses a fixed 100% baseline and the separately reported Portrait scale.
function GUF.ArtisticBasePortraitWidth(unit, config)
    if unit == "player" or unit == "target" then
        local geometry, source = (config or GUF.Runtime.Settings("layout", unit).frames[unit]).artistic.playerGeometry, GUF.ArtisticPortraitReferenceArtwork(unit)
        local height = geometry.header + geometry.health + geometry.power + 4
        return height * source.diameter / (source.paintBottom - source.paintTop)
    end
    return base.portrait * compact(unit)
end

function GUF.ArtisticPortraitWidth(unit, config)
    local baseline = GUF.ArtisticBasePortraitWidth(unit, config)
    if unit == "player" or unit == "target" then
        local source = GUF.ArtisticPortraitReferenceArtwork(unit)
        baseline = portraitScaleHeight * source.diameter / (source.paintBottom - source.paintTop)
    end
    return baseline * (config or GUF.Runtime.Settings("layout", unit).frames[unit]).artistic.portraitScale
end

-- Translate the joined bars by the portrait's radius change, preserving their
-- dimensions and the original spacing from its attachment-side edge.
function GUF.ArtisticBarOffset(unit, config)
    local offset = (GUF.ArtisticPortraitWidth(unit, config) - GUF.ArtisticBasePortraitWidth(unit, config)) / 2
    return unit == "target" and -offset or offset
end

function GUF.ArtisticPetOffset()
    local cfg = GUF.Runtime.Settings("layout", "player").frames.player
    local clearance = 110
    for _, aura in ipairs(cfg.auras.buffs) do
        if aura.enabled and aura.anchorPoint ~= "FREE" and aura.anchorPoint:find("BOTTOM", 1, true) then
            local rows = aura.size * aura.maxRows + aura.spacing * math.max(0, aura.maxRows - 1)
            clearance = math.max(clearance, math.max(0, -aura.y) + rows + (cfg.bars.cast.enabled and 30 or 0) + 8)
        end
    end
    return clearance
end

local function layer(entry, level)
    local frame = GUF.Runtime.CreateFrame("Frame", nil, entry.frame)
    frame.goodUnitFramesOwned = true
    frame:SetAllPoints(entry.frame)
    frame:SetFrameLevel(entry.frame:GetFrameLevel() + level)
    frame:EnableMouse(false)
    return frame
end

local function texture(parent, file, drawLayer)
    local region = parent:CreateTexture(nil, drawLayer or "ARTWORK")
    region.goodUnitFramesOwned = true
    region:SetTexture(file)
    return region
end

local function surround(parent, housing, refined, cleanPlayer, unit, stack)
    -- Eight slices of captured Blizzard bar chrome; no installed custom graphics.
    local frame = GUF.Runtime.CreateFrame("Frame", nil, parent)
    frame.goodUnitFramesOwned = true
    frame:EnableMouse(false)
    frame.edgeSize, frame.unit = 3, unit or "player"
    frame.fill = texture(frame, white, "BACKGROUND")
    frame.fill:SetPoint("TOPLEFT", 2, -2)
    frame.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.fill:SetVertexColor(.025, .025, .03, 1)
    frame.pieces = {}
    for row = 1, 3 do
        for col = 1, 3 do
            if row ~= 2 or col ~= 2 then
                local region = texture(frame, nil, "OVERLAY")
                if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
                if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
                frame.pieces[#frame.pieces + 1] = { region = region, row = row, col = col }
            end
        end
    end
    frame.LayoutBorder = function(self, width, height)
        if not number(width) or not number(height) then return end
        local edge = math.min(self.edgeSize, width / 3, height / 3)
        local widths, heights = { edge, width - 2 * edge, edge }, { edge, height - 2 * edge, edge }
        local x, y = { 0, edge, width - edge }, { 0, -edge, -height + edge }
        for _, piece in ipairs(self.pieces) do
            piece.region:ClearAllPoints()
            piece.region:SetPoint("TOPLEFT", self, "TOPLEFT", x[piece.col], y[piece.row])
            piece.region:SetSize(widths[piece.col], heights[piece.row])
            if stack then
                -- Continue the straight side through the Name/Health join.
                -- That boundary has its own divider, not another pair of caps.
                if piece.row == 1 and piece.col == 2 then piece.region:Hide()
                else GUF.PaintBlizzardStackSlice(piece.region, self.unit,
                    piece.row == 1 and 2 or piece.row, piece.col) end
            else GUF.PaintBlizzardBarSlice(piece.region, self.unit, piece.row, piece.col) end
        end
    end
    frame:SetScript("OnSizeChanged", frame.LayoutBorder)
    return frame
end

GUF.CreateArtisticSurround = surround

function GUF.CreateArtisticHousing(parent, refined, neutral, unit, stack)
    local frame = surround(parent, true, refined, neutral, unit, stack)
    frame.fill:Hide()
    return frame
end

local function circularFill(parent, drawLayer)
    local region = texture(parent, white, drawLayer)
    local mask = parent:CreateMaskTexture(nil, "ARTWORK")
    mask.goodUnitFramesOwned = true
    mask:SetTexture(circle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(region)
    region:AddMaskTexture(mask)
    return region
end

local function nameHeader(parent, unit)
    local frame = GUF.Runtime.CreateFrame("Frame", nil, parent)
    frame.goodUnitFramesOwned = true
    frame:EnableMouse(false)
    frame.body = texture(frame, white, "BACKGROUND")
    frame.side = texture(frame, white, "BACKGROUND")
    frame.corner = GUF.Runtime.CreateFrame("Frame", nil, frame)
    frame.corner.goodUnitFramesOwned = true
    frame.corner:EnableMouse(false)
    frame.corner:SetClipsChildren(true)
    frame.disc = GUF.Runtime.CreateFrame("Frame", nil, frame.corner)
    frame.disc.goodUnitFramesOwned = true
    frame.disc:EnableMouse(false)
    frame.cornerFill = texture(frame.disc, white, "BACKGROUND")
    frame.cornerFill:SetAllPoints(frame.disc)
    frame.mask = frame.disc:CreateMaskTexture(nil, "ARTWORK")
    frame.mask.goodUnitFramesOwned = true
    frame.mask:SetTexture(circle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    frame.mask:SetTexCoord(0, 1, 0, 1)
    frame.mask:SetAllPoints(frame.cornerFill)
    frame.cornerFill:AddMaskTexture(frame.mask)
    frame.cornerFill:SetDrawLayer("ARTWORK", 1)
    frame.topTrim = texture(frame, white, "ARTWORK")
    frame.sideTrim = texture(frame, white, "ARTWORK")
    frame.cornerTrim = texture(frame.disc, nil, "OVERLAY")
    frame.cornerTrim:SetAllPoints(frame.corner)
    for _, region in ipairs({ frame.topTrim, frame.sideTrim, frame.cornerTrim }) do
        if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
    for _, region in ipairs({ frame.body, frame.side, frame.cornerFill }) do
        region:SetVertexColor(.035, .035, .035)
        if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
    frame.LayoutHeader = function(self, width, height, mirrored, radius)
        local far = mirrored and "LEFT" or "RIGHT"
        -- Match the housing's three-unit native edge, including scale. The
        -- native corner supplies the contour and colors; no painted gold disc.
        radius = math.min(radius / 2, height / 3, width / 3)
        self.body:ClearAllPoints()
        self.body:SetPoint("TOPLEFT", self, "TOPLEFT", mirrored and radius or 0, 0)
        self.body:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", mirrored and 0 or -radius, 0)
        self.side:ClearAllPoints()
        self.side:SetPoint("TOP" .. far, self, "TOP" .. far, 0, -radius)
        self.side:SetPoint("BOTTOM" .. far, self, "BOTTOM" .. far, 0, 0)
        self.side:SetWidth(radius)
        self.corner:ClearAllPoints()
        self.corner:SetPoint("TOP" .. far, self, "TOP" .. far)
        self.corner:SetSize(radius, radius)
        -- Clip an entire masked disc to one quadrant. This avoids relying on
        -- cropped mask UVs and gives the far upper corner a real curved edge.
        self.disc:ClearAllPoints()
        self.disc:SetPoint("TOP" .. far, self.corner, "TOP" .. far)
        self.disc:SetSize(2 * radius, 2 * radius)
        self.cornerFill:ClearAllPoints()
        self.cornerFill:SetPoint("CENTER", self.disc, "CENTER")
        self.cornerFill:SetSize(2 * radius, 2 * radius)
        self.topTrim:ClearAllPoints()
        self.topTrim:SetPoint("TOPLEFT", self, "TOPLEFT", mirrored and radius or 0, 0)
        self.topTrim:SetPoint("TOPRIGHT", self, "TOPRIGHT", mirrored and 0 or -radius, 0)
        self.topTrim:SetHeight(radius)
        self.sideTrim:ClearAllPoints()
        self.sideTrim:SetPoint("TOP" .. far, self, "TOP" .. far, 0, -radius)
        self.sideTrim:SetPoint("BOTTOM" .. far, self, "BOTTOM" .. far)
        self.sideTrim:SetWidth(radius)
        local artUnit = unit or (mirrored and "target" or "player")
        GUF.PaintBlizzardStackSlice(self.topTrim, artUnit, 1, 2)
        GUF.PaintBlizzardStackSlice(self.sideTrim, artUnit, 2, mirrored and 1 or 3)
        GUF.PaintBlizzardStackSlice(self.cornerTrim, artUnit, 1, mirrored and 1 or 3)
    end
    return frame
end

local function circularSurround(parent, portrait, smallLevel)
    local frame = GUF.Runtime.CreateFrame("Frame", nil, parent)
    frame.goodUnitFramesOwned = true
    frame:EnableMouse(false)
    frame.fill = circularFill(frame, "BACKGROUND")
    frame.fill:SetPoint("CENTER")
    frame.fill:SetVertexColor(.025, .025, .03, 1)
    frame.chrome = GUF.Runtime.CreateFrame("Frame", nil, frame)
    frame.chrome.goodUnitFramesOwned = true
    frame.chrome:EnableMouse(false)
    frame.chrome:SetAllPoints()
    frame.art = texture(frame.chrome, nil, "OVERLAY")
    if frame.art.SetSnapToPixelGrid then frame.art:SetSnapToPixelGrid(false) end
    if frame.art.SetTexelSnappingBias then frame.art:SetTexelSnappingBias(0) end
    frame.LayoutBorder = function(self, width, height)
        -- Size callbacks can run after a badge renderer hides its decoration.
        -- Remember that choice so layout cannot repaint a bare indicator rim.
        if self.badgeChromeEnabled == false then
            self.art:Hide(); self.fill:Hide()
            return
        end
        if not number(width) or not number(height) then return end
        local diameter = math.min(width, height)
        local source = self.source or GUF.BlizzardRingArtwork()
        self.chrome:SetFrameLevel(self:GetFrameLevel() + 3)
        self.fill:SetSize(diameter * source.openingRatio, diameter * source.openingRatio)
        self.fill:SetShown(not source.combined)
        GUF.PlaceDesignTexture(self.art, source, self, diameter, self.mirrored)
    end
    frame:SetScript("OnSizeChanged", frame.LayoutBorder)
    return frame
end

GUF.CreateArtisticPortraitRim = function(parent) return circularSurround(parent, true) end
GUF.CreateArtisticNameHeader = nameHeader

-- Row boundaries belong to the current presentation geometry. The native
-- chrome strips contain no divider marks, so independent row-height changes
-- cannot leave a second junction behind. Shared by live and owned specimens.
function GUF.StyleArtisticBarDivider(region, strength)
    -- Shade the existing border material rather than making it transparent.
    -- This is the previous silver-over-dark appearance in one opaque texture.
    strength = strength or 1
    local background = .035 * (1 - strength)
    region:SetColorTexture(.66 * strength + background, .68 * strength + background,
        .71 * strength + background, 1)
end

function GUF.ArtisticDividerPixelSize(entry)
    local scale = entry.frame:GetEffectiveScale()
    if not number(scale) or scale <= 0 then return 1 end
    local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()
    if not number(factor) or factor <= 0 then factor = 1 end
    return factor / scale
end

function GUF.LayoutArtisticBarDividers(entry)
    local state = entry.artisticLayout
    GUF.LayoutArtisticDividerLayer(entry)
    local upper = state.headerDivider or state.separators[1]
    local lower = state.divider or state.separators[2]
    local inset = state.housingEdge or 3 * state.scale
    local width = math.max(1, state.housingWidth - 2 * inset)
    local powerY = state.targetComboStack and state.targetComboStack.powerY or state.powerY
    local effectiveScale = entry.frame:GetEffectiveScale()
    local pixel = not GUF.Secret(effectiveScale) and type(effectiveScale) == "number" and effectiveScale > 0
        and 1 / effectiveScale or 0
    -- Name ends at healthY and the Health fill starts healthTopInset below it.
    -- Share the Name edge directly; do not snap the divider independently from
    -- the unsnapped Name body at fractional frame scales.
    local joinInset = GUF.IsManagedUnit(entry.unit) and 1.5 * state.scale or inset
    local nameX = entry.unit == "target" and state.barX or state.px + state.barOffset
    upper:ClearAllPoints()
    upper:SetPoint("TOPLEFT", state.nameStrip, "BOTTOMLEFT", state.housingX + joinInset - nameX, 0)
    upper:SetSize(math.max(1, state.housingWidth - 2 * joinInset),
        math.max(state.healthTopInset, GUF.ArtisticDividerPixelSize(entry)))
    upper:SetDrawLayer("OVERLAY", 7)
    if upper.SetSnapToPixelGrid then upper:SetSnapToPixelGrid(false) end
    if upper.SetTexelSnappingBias then upper:SetTexelSnappingBias(0) end
    -- Retain the existing Health/Power boundary and its resource-row behavior.
    lower:ClearAllPoints()
    lower:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", state.housingX + inset, powerY)
    lower:SetSize(width, math.max(state.dividerHeight, pixel))
    lower:SetDrawLayer("OVERLAY", 7)
    if lower.SetSnapToPixelGrid then lower:SetSnapToPixelGrid(true) end
    if lower.SetTexelSnappingBias then lower:SetTexelSnappingBias(0) end
    GUF.StyleArtisticBarDivider(upper, .72)
    GUF.StyleArtisticBarDivider(lower)
    upper:Show(); lower:SetShown(not state.noPower)
end

function GUF.UpdateArtisticPortraitArtwork(entry)
    local state = entry.artisticLayout
    if not state or not state.active or not state.portraitWidth then return end
    local source, reason = GUF.ArtisticPortraitArtwork(entry.unit, entry.frame.unit or entry.unit)
    GUF.RememberPortraitArtworkFallback(entry, source, reason)
    if state.rim.source == source then return end
    -- Only owned cosmetic regions change here, including during target swaps in
    -- combat. Do not resize/anchor the secure button or native Health/Power bars.
    state.rim.source = source
    state.rim.mirrored = source.combined and not source.targetOnly and entry.unit == "target" or false
    if source.creature then
        for _, item in ipairs(state.dragon or {}) do item.region:Hide() end
    end
    state.rim:LayoutBorder(state.portraitWidth, state.portraitHeight)
    local factor = state.portraitWidth / source.diameter
    state.portraitPaintTop = state.py + (source.centerY - source.paintTop) * factor
    state.portraitPaintBottom = state.py + (source.centerY - source.paintBottom) * factor
    GUF.LayoutArtisticPortrait(entry)
end

function GUF.SetArtisticBadgeChrome(badge, shown)
    badge.rim.badgeChromeEnabled = shown
    badge.rim.art:SetShown(shown)
    badge.rim.fill:SetShown(shown)
    badge.background:SetShown(shown)
end

function GUF.CreateArtisticBadge(parent, smallLevel)
    local badge = GUF.Runtime.CreateFrame("Frame", nil, parent)
    badge.goodUnitFramesOwned = true
    badge:EnableMouse(false)
    badge.rim = circularSurround(badge, false, smallLevel)
    badge.rim:SetAllPoints()
    badge.background = circularFill(badge.rim, "ARTWORK")
    badge.background:SetPoint("CENTER")
    badge.background:SetVertexColor(.045, .045, .045, 1)
    -- Background follows a real circular alpha mask, including threat colors.
    badge:SetScript("OnSizeChanged", function(_, width, height)
        if number(width) and number(height) then
            local shortSide = math.min(width, height)
            badge.background:SetSize(shortSide * .84, shortSide * .84)
            badge.rim:LayoutBorder(shortSide, shortSide)
        end
    end)
    badge.icon = texture(badge.rim, white, "OVERLAY")
    if badge.icon.SetSnapToPixelGrid then badge.icon:SetSnapToPixelGrid(false) end
    if badge.icon.SetTexelSnappingBias then badge.icon:SetTexelSnappingBias(0) end
    badge.icon:SetPoint("CENTER")
    -- Native Level chrome includes an opaque face in a child frame. Text on
    -- the rim's own frame would sit underneath that child regardless of layer.
    badge.text = badge.rim.chrome:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.text.goodUnitFramesOwned = true
    badge.text:SetPoint("CENTER")
    badge.text:SetJustifyH("CENTER")
    badge.text:SetJustifyV("MIDDLE")
    badge:Hide()
    return badge
end

local function panel(parent, borderParent, refined, unit)
    local frame = GUF.Runtime.CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame.goodUnitFramesOwned = true
    frame:EnableMouse(false)
    -- Background below live fills, segmented border above them. A single lower
    -- backdrop lets native status bars cover the inner half of the metal edge.
    frame:SetBackdrop({ bgFile = white })
    frame:SetBackdropColor(.035, .035, .035, 1)
    if borderParent then
        frame.border = GUF.CreateArtisticHousing(borderParent, refined, true, unit, true)
        frame.border.edgeSize = 6
        frame.border:SetAllPoints(frame)
    end
    return frame
end

local function track(entry, state, region)
    if not region then return end
    if state.regions[region] then return state.regions[region] end
    local geometry
    for _, item in ipairs(entry.sizeRegions or {}) do
        if item.region == region then geometry = item; break end
    end
    if not geometry then
        local points = GUF.ReadPoints(region)
        if not points then return end
        geometry = { region = region, points = points, width = region:GetWidth(), height = region:GetHeight(), hasSize = true }
    end
    local item = { geometry = geometry, parent = region:GetParent(), width = region.GetFont and region:GetWidth(),
        justify = region.GetJustifyH and region:GetJustifyH() }
    state.regions[region] = item
    GUF.NativeProperties.Track(region, "layoutGeometry", entry, item)
    return item
end

local function transformBase(region, points, width, height)
    local transform = GUF.regionTransforms and GUF.regionTransforms[region]
    if transform then
        transform.points, transform.pointsReadable = points, true
        if width then transform.width, transform.height = width, height end
    end
end

local function place(entry, state, region, x, y, width, height, parent, point, relative)
    if region and GUF.ArtisticNativeBarsIsolated(entry, state) and (region == entry.health or region == entry.power) then
        -- Owned bars already render this geometry. Leave their native sources
        -- in place so opaque geometry cannot block or corrupt a later handoff.
        state.barGeometry = state.barGeometry or {}
        state.barGeometry[region] = { x = x, y = y, width = width, height = height }
        GUF.LayoutArtisticRenderedBar(entry, region == entry.health and "health" or "power", x, y, width, height)
        return
    end
    if not region or not track(entry, state, region) then return end
    local original = entry.textOriginals and entry.textOriginals[region]
    local writing = original and original.writing
    if original then original.writing = true end
    if parent and region.SetParent then region:SetParent(parent) end
    local points = { { point or "TOPLEFT", relative or entry.frame,
        relative and (point or "TOPLEFT") or "TOPLEFT", x, y } }
    region:ClearAllPoints()
    region:SetPoint(unpack(points[1]))
    region:SetSize(width, height)
    if region == entry.health or region == entry.power then
        state.barGeometry = state.barGeometry or {}
        state.barGeometry[region] = { x = x, y = y, width = width, height = height }
        GUF.LayoutArtisticRenderedBar(entry, region == entry.health and "health" or "power", x, y, width, height)
    end
    transformBase(region, points, width, height)
    if original then original.writing = writing end
end

function GUF.RestoreArtisticPlayerNameAnchor(entry)
    local state = entry and entry.artisticLayout
    if not GUF.isRetail or not state or not state.active or entry.unit ~= "player"
        or not state.nameArea or not entry.name then return false end
    local _, class = UnitClass("player")
    if GUF.Secret(class) or class ~= "DEMONHUNTER" then return false end
    local unit = entry.frame.unit
    if GUF.Secret(unit) or (unit ~= nil and unit ~= "player") then return false end
    if entry.layoutWriting or entry.sizeWriting or GUF.geometryWriting then return false end
    if GUF.editing or GUF.Restricted() or not number(state.scale) then GUF.DeferRuntime("native-readiness"); return false end
    local settings = GUF.Runtime.Settings("layout", "player").frames.player.text.name
    local x, y = 4 * state.scale, 0
    local points = { { "LEFT", state.nameArea, "LEFT", x, y } }
    if not settings.nativeStyle then x, y = x + settings.x, y + settings.y end
    local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
    entry.layoutWriting, GUF.geometryWriting = true, true
    -- Repair before the native name-anchor function returns to the renderer.
    -- Keep the transform's unshifted base separate from saved text offsets.
    entry.name:ClearAllPoints()
    entry.name:SetPoint("LEFT", state.nameArea, "LEFT", x, y)
    transformBase(entry.name, points)
    entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
    return true
end

function GUF.RestoreArtisticBarGeometry(entry, region)
    local state = entry.artisticLayout
    if not state or not state.active or GUF.editing then return false end
    local geometry = state.barGeometry and state.barGeometry[region]
    if region ~= entry.frame and not geometry then return false end
    local kind = region == entry.health and "health" or region == entry.power and "power"
    local render = kind and state.renderBars and state.renderBars[kind]
    if render then
        -- Native retarget/classification callbacks may reset their hidden bars.
        -- Repair only our presentation, never the native bar that invoked us.
        -- In particular, its protection/geometry must not gate owned updates.
        local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
        entry.layoutWriting, GUF.geometryWriting = true, true
        GUF.LayoutArtisticRenderedBar(entry, kind, geometry.x, geometry.y, geometry.width, geometry.height)
        entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
        if entry.comboRow then GUF.LayoutTargetComboStack(entry, true) end
        return true
    end
    if GUF.Restricted() then
        local ok, protected = pcall(region.IsProtected, region)
        if not ok or GUF.Secret(protected) or protected then return false end
    end
    local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
    entry.layoutWriting, GUF.geometryWriting = true, true
    if region == entry.frame then region:SetSize(state.width, state.height)
    else place(entry, state, region, geometry.x, geometry.y, geometry.width, geometry.height) end
    entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
    return true
end

local function layoutNativeHealthText(entry, state, text)
    if not state.active or not state.healthFillHeight then return end
    if state.renderBars and GUF.Restricted() then
        -- Owned Target text continues through UpdateBarText. Native labels can
        -- wait for the normal out-of-combat apply instead of writing anchors
        -- from inside Blizzard's combat text-layout callbacks.
        GUF.DeferRuntime("native-readiness")
        return
    end
    local point = (text == entry.health.RightText or text == entry.healthArea.RightText) and "RIGHT"
        or (text == entry.health.LeftText or text == entry.healthArea.LeftText) and "LEFT" or "CENTER"
    local cfg = GUF.Runtime.Settings("layout", entry).frames[entry.unit]
    local size = cfg.text.health.custom and cfg.text.health.size or cfg.fontSize
    local height = state.noPower and state.healthRowHeight + state.powerRowHeight - state.healthTopInset - 2 * state.scale
        or state.healthFillHeight
    local inset = point == "LEFT" and 4 * state.scale or point == "RIGHT" and -4 * state.scale or 0
    state.nativeHealthTextWriting = true
    -- Both outer labels share the readable span, with glyphs flowing inward.
    -- A Blizzard refresh may supply its old, narrower native text-box geometry.
    place(entry, state, text, inset, 0, state.barWidth - 16 * state.scale,
        math.max(height, size + 4), nil, point, state.textAreas.health)
    text:SetJustifyH(point)
    state.nativeHealthTextWriting = nil
end

local function ownNativeHealthText(entry, state, text)
    state.nativeHealthTextHooks = state.nativeHealthTextHooks or {}
    if not state.nativeHealthTextHooks[text] then
        state.nativeHealthTextHooks[text] = true
        local function refresh()
            local original = entry.textOriginals and entry.textOriginals[text]
            if not state.active or state.nativeHealthTextWriting or entry.layoutWriting or GUF.geometryWriting
                or GUF.editing or (original and original.writing) then return end
            layoutNativeHealthText(entry, state, text)
        end
        GUF.NativeProperties.Hook("ArtisticLayout:3", text, "SetPoint", refresh)
        GUF.NativeProperties.Hook("ArtisticLayout:4", text, "SetWidth", refresh)
        GUF.NativeProperties.Hook("ArtisticLayout:5", text, "SetSize", refresh)
    end
    layoutNativeHealthText(entry, state, text)
end

local function mask(entry, state, region, owner, circular)
    if not region or not track(entry, state, region) then return end
    if not state.masks[region] then
        local original = { texture = region:GetTexture(), atlas = region.GetAtlas and region:GetAtlas(),
            coords = { region:GetTexCoord() }, owner = owner, circular = circular }
        state.masks[region] = original
        GUF.NativeProperties.Track(region, "maskMedia", entry, original)
    end
    local original = state.masks[region]
    if not original.hooked then
        -- Classification changes reset masks directly, bypassing StatusBar size
        -- setters. Keep the rectangular Artistic mask even during combat.
        local function refresh()
            if not state.active or original.writing or entry.layoutWriting or GUF.editing then return end
            mask(entry, state, region, original.owner, original.circular)
        end
        GUF.NativeProperties.Hook("ArtisticLayout:6", region, "SetAtlas", function(_, atlas)
            if original.writing or not state.active or entry.layoutWriting then return end
            original.texture, original.atlas, original.coords = region:GetTexture(), atlas, { region:GetTexCoord() }
            refresh()
        end)
        GUF.NativeProperties.Hook("ArtisticLayout:7", region, "SetTexture", function()
            if original.writing or not state.active or entry.layoutWriting then return end
            original.texture, original.atlas = region:GetTexture(), region:GetAtlas()
            refresh()
        end)
        GUF.NativeProperties.Hook("ArtisticLayout:8", region, "SetTexCoord", function()
            if original.writing or not state.active or entry.layoutWriting then return end
            original.coords = { region:GetTexCoord() }
            refresh()
        end)
        for _, method in ipairs({ "SetPoint", "SetAllPoints", "SetSize", "SetWidth", "SetHeight" }) do
            GUF.NativeProperties.Hook("ArtisticLayout:9", region, method, refresh)
        end
        original.hooked = true
    end
    original.owner, original.circular, original.writing = owner, circular, true
    local geometryWriting = GUF.geometryWriting
    GUF.geometryWriting = true
    region:SetTexture(circular and circle or white, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    region:SetTexCoord(0, 1, 0, 1)
    region:ClearAllPoints()
    region:SetAllPoints(owner)
    GUF.geometryWriting = geometryWriting
    original.writing = nil
end

local function barMasks(entry, state, bar, known)
    local seen = {}
    local function apply(region)
        if region and not GUF.Secret(region) and not seen[region] then
            seen[region] = true
            mask(entry, state, region, bar)
        end
    end
    apply(known)
    local fill = bar:GetStatusBarTexture()
    if fill and fill.GetNumMaskTextures and fill.GetMaskTexture then
        local count = fill:GetNumMaskTextures()
        if number(count) then for i = 1, count do apply(fill:GetMaskTexture(i)) end end
    end
end

function GUF.RefreshArtisticBarPresentation(entry)
    local state = entry.artisticLayout
    if entry.unit ~= "target" or not state or not state.active or not state.renderBars
        or not state.barGeometry or state.presentationWriting or entry.layoutWriting or GUF.editing then
        if entry.unit == "target" and GUF.Layouts.NeedsLiveApply(entry) then GUF.DeferRuntime("native-readiness") end
        return
    end
    state.presentationWriting = true
    -- A cosmetic post-update repair, not a full secure layout application.
    -- Native classification writes fill atlases and masks after unit values.
    GUF.LayoutArtisticRenderedLayers(entry)
    GUF.SyncArtisticPowerLayout(entry)
    GUF.RestoreArtisticBarGeometry(entry, entry.health)
    GUF.RestoreArtisticBarGeometry(entry, entry.power)
    GUF.ApplyBars(entry)
    for _, kind in ipairs({ "health", "power" }) do
        local bar, geometry = entry[kind], state.barGeometry[entry[kind]]
        if bar and geometry then
            -- Only owned StatusBars receive values from addon callbacks. Native
            -- TextStatusBars run Blizzard text scripts when SetValue is called.
            GUF.SyncArtisticRenderedBar(entry, kind)
            GUF.UpdateBarText(entry, kind)
        end
    end
    if entry.predictions then entry.predictions.dirty = true; GUF.UpdatePredictionBars(entry) end
    state.presentationWriting = nil
end

local function hide(state, region)
    if not region or not region.SetAlpha or region.goodUnitFramesOwned or state.preserved[region] then return end
    state.hidden[region] = true
    leaseAlpha(region, 0)
end

local function hideTextures(state, owner, keep)
    if not owner or not owner.GetRegions then return end
    for _, region in pairs({ owner:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region ~= keep and region ~= state.portrait then hide(state, region) end
    end
end

local function create(entry)
    local container = entry.frame.PlayerFrameContainer or entry.frame.TargetFrameContainer or entry.frame
    local portrait = container.PlayerPortrait or container.Portrait or entry.frame.portrait or entry.frame.Portrait
        or _G[entry.frame:GetName() .. "Portrait"]
    if not portrait or not entry.health or not entry.power then return end
    local state = { unit = entry.unit, regions = {}, masks = {}, hidden = {}, preserved = {}, container = container, portrait = portrait,
        playerRefinement = entry.unit == "player", refinedHousing = entry.unit == "player" or entry.unit == "target" }
    entry.artisticLayout = state
    for _, region in pairs(entry.regions.resource) do state.preserved[region] = true end
    state.background, state.ornaments, state.badgeLayer = layer(entry, 0), layer(entry, 5), layer(entry, 8)
    -- Retail Health geometry may become restricted on every class. Keep the
    -- native bars in place and render Artistic in owned hosts. Resource rows
    -- still require their actual class/spec/data eligibility independently.
    if entry.unit == "target" or entry.unit == "player"
        and (GUF.isRetail or GUF.UsesSegmentedResources("player")) then
        state.renderBars = {}
        for _, kind in ipairs({ "health", "power" }) do
            local render = GUF.Runtime.CreateFrame("StatusBar", nil, state.background)
            render.goodUnitFramesOwned = true
            render:EnableMouse(false)
            -- Own a specific texture object, not a native fill or atlas.
            local fill = render:CreateTexture(nil, "ARTWORK")
            fill.goodUnitFramesOwned = true
            fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
            render:SetStatusBarTexture(fill)
            fill:SetDrawLayer("ARTWORK", 0)
            render.goodUnitFramesFill = fill
            render.background = texture(render, white, "BACKGROUND")
            render.background:SetAllPoints(render)
            render.background:SetVertexColor(.035, .035, .035, 1)
            render:SetOrientation("HORIZONTAL")
            render:SetReverseFill(false)
            state.renderBars[kind] = render
        end
    end
    state.circular = true
    state.rim = circularSurround(state.ornaments, true)
    GUF.CreateArtisticPortrait(entry, state)
    state.portraitLayer = { portrait:GetDrawLayer() }
    -- Retain the old hidden placeholder; the housing now extends under the rim.
    state.junction = texture(state.background, white, "BACKGROUND")
    state.junction:SetVertexColor(.07, .06, .035, 1)
    state.classTrim = {}
    for i = 1, 8 do
        local segment = texture(state.rim, white, "OVERLAY")
        state.classTrim[i] = segment
    end
    state.housing = panel(state.background, state.ornaments, state.refinedHousing, entry.unit)
    -- Header is a separate translucent backing above the live Health fill.
    state.housing:SetBackdropColor(0, 0, 0, 0)
    state.nameStrip = nameHeader(state.background, entry.unit)
    state.healthShell = panel(state.background)
    state.powerShell = panel(state.background)
    if state.renderBars then
        -- Dino puts backing and fill on the same StatusBar, with explicit draw
        -- layers. These geometry helpers must not add another opaque surface.
        state.healthShell:SetBackdropColor(0, 0, 0, 0)
        state.powerShell:SetBackdropColor(0, 0, 0, 0)
    end
    state.nameArea = GUF.Runtime.CreateFrame("Frame", nil, state.nameStrip)
    state.nameArea.goodUnitFramesOwned = true
    state.nameArea:EnableMouse(false)
    -- Fill extensions can run under the portrait; keep readable text/casts in
    -- the original visible bar span instead of centering them under the ring.
    state.textAreas, state.castAreas = {}, {}
    for _, kind in ipairs({ "health", "power" }) do
        local area = GUF.Runtime.CreateFrame("Frame", nil, state.renderBars and state.renderBars[kind] or entry[kind])
        area.goodUnitFramesOwned = true
        area:EnableMouse(false)
        state.textAreas[kind] = area
        local castArea = GUF.Runtime.CreateFrame("Frame", nil, state.renderBars and state.renderBars[kind] or entry[kind])
        castArea.goodUnitFramesOwned = true
        castArea:EnableMouse(false)
        state.castAreas[kind] = castArea
    end
    state.separators = {}
    state.dividerLayer = GUF.Runtime.CreateFrame("Frame", nil, state.background)
    state.dividerLayer.goodUnitFramesOwned = true
    state.dividerLayer:EnableMouse(false)
    state.dividerLayer:SetAllPoints(entry.frame)
    for i = 1, 2 do
        -- The one-unit join needs opaque coverage, not a compressed alpha crop.
        local separator = texture(state.dividerLayer, white, "OVERLAY")
        separator:SetColorTexture(.66, .68, .71, 1)
        if separator.SetSnapToPixelGrid then separator:SetSnapToPixelGrid(false) end
        if separator.SetTexelSnappingBias then separator:SetTexelSnappingBias(0) end
        state.separators[i] = separator
    end
    state.badges = {}
    for _, key in ipairs({ "level", "combat", "pvp", "leader", "loot", "role", "raid", "status", "resurrect" }) do
        state.badges[key] = GUF.CreateArtisticBadge(state.badgeLayer, state.playerRefinement and key == "level")
    end
    -- Complete monster rank paintings replace the old Blizzard dragon copies.
    -- Retain the empty record for shared cleanup paths, with no legacy artwork.
    state.dragon = {}
    state.portraitMask = container.PlayerPortraitMask or container.PortraitMask
    state.healthMask = entry.healthArea.HealthBarMask or entry.health.HealthBarMask
    state.powerMask = entry.power.ManaBarMask
    if entry.unit == "target" then
        for _, kind in ipairs({ "health", "power" }) do
            local native = entry[kind]
            GUF.NativeProperties.HookScript("ArtisticLayout:script:1", native, "OnShow", function() GUF.RefreshArtisticBarPresentation(entry) end)
            if kind == "power" then
                GUF.NativeProperties.HookScript("ArtisticLayout:script:2", native, "OnHide", function() GUF.RefreshArtisticBarPresentation(entry) end)
            end
            GUF.NativeProperties.Hook("ArtisticLayout:10", native, "SetFrameLevel", function() GUF.LayoutArtisticRenderedLayers(entry) end)
        end
        GUF.NativeProperties.Hook("ArtisticLayout:11", entry.frame, "SetFrameLevel", function() GUF.LayoutArtisticRenderedLayers(entry) end)
        for _, method in ipairs({ "Update", "CheckClassification" }) do
            if type(entry.frame[method]) == "function" then
                GUF.NativeProperties.Hook("ArtisticLayout:12", entry.frame, method, function() GUF.RefreshArtisticBarPresentation(entry) end)
            end
        end
    end
    entry.artisticLayout = state
    state.background:Hide(); state.ornaments:Hide(); state.badgeLayer:Hide()
    state.created = true
    GUF.Runtime.Constructed()
    return state
end

local function restoreGeometryReady(region, item)
    local geometry = item and item.geometry
    if not geometry or geometry.points == nil or geometry.pointsReadable == false or GUF.ReadPoints(region) == nil then return false end
    if geometry.hasSize and (not number(geometry.width) or not number(geometry.height)) then return false end
    for _, point in ipairs(geometry.points) do
        if not number(point[4]) or not number(point[5]) then return false end
    end
    return true
end

function GUF.ArtisticCleanupReady(entry)
    local state = entry.artisticLayout
    if not state or state.active then return false end
    for region in pairs(state.restorePending or {}) do
        if restoreGeometryReady(region, state.regions[region]) then return true end
    end
    return false
end

local function restore(entry, state)
    local pending = not state.active and state.restorePending or nil
    local deferred = {}
    GUF.HideLayeredDesign(entry)
    GUF.RestoreArtisticResources(entry)
    GUF.ClearArtisticPortrait(state)
    -- Release the old geometry owner before native resize/layout callbacks run.
    -- Otherwise a restore write can be repaired back to Artistic bounds.
    state.active = false
    if state.powerSuppressed then leaseAlpha(entry.power, nil) end
    state.noPower, state.powerSuppressed, state.powerCapacityReason = nil, nil, nil
    if state.renderBars then
        for _, kind in ipairs({ "health", "power" }) do
            for _, text in pairs(entry[kind .. "Slots"] or {}) do text:Hide() end
            if kind == "power" then
                entry.powerText:SetParent(entry.power)
                for _, text in pairs(entry.powerSlots or {}) do text:SetParent(entry.power) end
            end
        end
    end
    -- Applying an atlas can change its native dimensions/anchors. Restore its
    -- media first, then make the trusted captured geometry the final writes.
    for region, original in pairs(state.masks) do
        if not pending or pending[region] then
            local item = state.regions[region]
            local geometry = item and item.geometry
            if geometry and number(geometry.width) and number(geometry.height) and GUF.ReadPoints(region) then
                original.writing = true
                if original.atlas then region:SetAtlas(original.atlas)
                else region:SetTexture(original.texture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
                region:SetTexCoord(unpack(original.coords))
                original.writing = nil
            else deferred[region] = true end
        end
    end
    local restored = {}
    local function restoreRegion(region)
        if restored[region] or pending and not pending[region] then return end
        local item = state.regions[region]
        if not item then return end
        restored[region] = true
        -- Restore ancestors first: their native layout callbacks may resize
        -- children, whose captured bounds must be the final restore writes.
        restoreRegion(item.parent)
        local geometry = item.geometry
        -- A native Health controller may make its geometry opaque even outside
        -- combat. Release the skin as a whole; defer only this native region.
        -- Captured public anchors do not make its current geometry readable.
        if not restoreGeometryReady(region, item) or deferred[region] then deferred[region] = true; return end
        local original = entry.textOriginals and entry.textOriginals[region]
        local writing = original and original.writing
        if original then original.writing = true end
        if region ~= entry.frame and region.SetParent then region:SetParent(item.parent) end
        if region ~= entry.frame then
            region:ClearAllPoints()
            for _, point in ipairs(geometry.points) do region:SetPoint(unpack(point)) end
        end
        if geometry.hasSize and number(geometry.width) and number(geometry.height) then
            region:SetSize(geometry.width, geometry.height)
        elseif original and number(original.width) then region:SetWidth(original.width)
        elseif number(item.width) then region:SetWidth(item.width) end
        if item.justify then region:SetJustifyH(item.justify) end
        transformBase(region, geometry.points, geometry.width, geometry.height)
        if original then original.writing = writing end
    end
    for region in pairs(state.regions) do restoreRegion(region) end
    state.restorePending = next(deferred) and deferred or nil
    state.portrait:SetDrawLayer(unpack(state.portraitLayer))
    for region in pairs(state.hidden) do leaseAlpha(region, nil) end
    state.hidden, state.active = {}, false
    state.background:Hide(); state.ornaments:Hide(); state.badgeLayer:Hide()
end

local function noPower(entry, maximum)
    -- Player keeps the Power row as the home of level even without a resource.
    if entry.unit == "player" then return false, "player-row" end
    local unit = entry.frame.unit or entry.unit
    if not yes(UnitExists(unit)) then return false, "unit-missing-or-restricted" end
    -- All playable Forever classes have a resource. Do not expand Health for
    -- a player target's temporary zero capacity while its unit data arrives.
    if entry.unit == "target" and yes(UnitIsPlayer(unit)) then return false, "player-target" end
    if not entry.power then return true, "no-power-source" end
    local powerType = UnitPowerType(unit)
    -- Current power can be zero on a fully functional bar. Capacity, not its
    -- depleted value, is authoritative when the amount is public.
    if not GUF.Secret(maximum) and maximum == nil then
        maximum = UnitPowerMax(unit, powerType)
    end
    if number(maximum) then
        if maximum <= 0 then return true, "zero-capacity" end
        return false, "positive-capacity"
    end
    -- A primary type (and UnitHasPowerType) can describe an NPC's placeholder
    -- resource without a usable pool. Blizzard's TextStatusBar controller
    -- independently hides its own Power widget at zero maximum, and shows it
    -- for positive maximum even when depleted. Follow only that public shown
    -- flag, not ancestor visibility, native values, fill geometry or opacity.
    -- Never change the native widget's Show/Hide state ourselves.
    if entry.unit == "target" then
        local native, controller = entry.power, entry.power.controlsShownState
        local nativeUnit = native.unit
        if not GUF.Secret(controller) and controller == true
            and not GUF.Secret(nativeUnit) and nativeUnit == unit then
            local shown = native:IsShown()
            if not GUF.Secret(shown) and type(shown) == "boolean" then
                return not shown, shown and "native-power-shown" or "native-power-hidden"
            end
        end
    end
    -- If neither capacity nor the controller decision is public, retain the
    -- previous decision. Unknown is never treated as proof of no resource.
    return entry.artisticLayout.noPower == true, GUF.Secret(maximum) and "restricted-capacity" or "unavailable-capacity"
end

function GUF.SyncArtisticPowerLayout(entry, force, maximum)
    local state = entry.artisticLayout
    if not state or not state.active or not state.healthFillHeight then return end
    local absent, reason = noPower(entry, maximum)
    state.powerCapacityReason = reason
    if not force and state.noPower == absent then return end
    if GUF.editing then GUF.DeferRuntime("native-readiness"); return end
    -- An owned bar does not need its hidden native source resized when
    -- power availability changes. Keep the Dino-style renderer independent.
    local permitted = not state.renderBars
    if permitted and GUF.Restricted() then
        -- The secure button and portrait footprint do not change. A native
        -- StatusBar can resize immediately only when it is unprotected.
        local ok, protected = pcall(entry.health.IsProtected, entry.health)
        if not ok or GUF.Secret(protected) or protected then
            permitted = false
            if not state.renderBars then GUF.DeferRuntime("native-readiness"); return end
        end
    end
    local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
    entry.layoutWriting, GUF.geometryWriting = true, true
    local outerHeight = state.healthRowHeight + (absent and state.powerRowHeight or 0)
    -- Keep the top rim inset and the housing's bottom inset; the hidden
    -- inter-bar divider becomes part of the expanded health interior.
    local fillHeight = absent and outerHeight - state.healthTopInset - base.bottomInset * state.scale or state.healthFillHeight
    if permitted then entry.health:SetHeight(fillHeight) end
    if state.renderBars then
        state.renderBars.health:SetHeight(fillHeight)
        state.renderBars.power:SetShown(not absent)
        if entry.predictions then entry.predictions.dirty = true end
    end
    if state.barGeometry and state.barGeometry[entry.health] then state.barGeometry[entry.health].height = fillHeight end
    state.healthShell:SetHeight(state.refinedHousing and fillHeight or outerHeight)
    state.powerShell:SetShown(not absent)
    state.separators[2]:SetShown(not absent)
    if absent then
        leaseAlpha(entry.power, 0)
        state.powerSuppressed = true
    elseif state.powerSuppressed then
        leaseAlpha(entry.power, nil)
        state.powerSuppressed = nil
    end
    state.noPower = absent
    if entry.comboRow then GUF.LayoutTargetComboStack(entry, true) end
    GUF.LayoutBarDesign(entry)
    entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
    if not force then
        GUF.UpdateBarText(entry, "health")
        GUF.UpdateBarText(entry, "power")
        GUF.UpdatePredictionBars(entry)
        GUF.PositionCastBar(entry)
    end
end

local function fitIndicatorIcon(frame, aspect)
    local size = frame.iconSize
    if not size or not number(aspect) or aspect <= 0 then return end
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("CENTER")
    frame.icon:SetSize(size * math.min(1, aspect), size * math.min(1, 1 / aspect))
end
GUF.FitArtisticIndicatorIcon = fitIndicatorIcon

local function badge(entry, key, kind, dx, dy, diameter, file, coords, text)
    local state, cfg = entry.artisticLayout, GUF.PresentationFrameSettings(entry)
    local frame, settings = state.badges[key], cfg.indicators[kind]
    if kind ~= "level" and cfg.hide[kind] and not entry.configurationShowAll then frame:Hide(); return end
    local scale = settings.scale
    local portraitIndicator = GUF.IsPortraitIndicator(kind)
    frame:ClearAllPoints()
    if portraitIndicator then
        local relativePoint = settings.point and settings.point ~= "DEFAULT" and settings.point or "CENTER"
        frame:SetPoint(settings.anchorPoint or "CENTER", state.rim, relativePoint, settings.x, settings.y)
    else
        frame:SetPoint(settings.anchorPoint or "CENTER", entry.frame, "TOPLEFT", state.px + dx * state.scale + settings.x,
            state.py + dy * state.scale + settings.y)
        if settings.point and settings.point ~= "DEFAULT" then
            frame:ClearAllPoints()
            local anchor = settings.anchor == "bars" and state.indicatorArea or settings.anchor == "portrait" and state.rim or entry.frame
            frame:SetPoint(settings.anchorPoint or "CENTER", anchor, settings.point, settings.x, settings.y)
        end
    end
    local size = (portraitIndicator and GUF.PortraitIndicatorSize(entry.unit, kind, cfg)
        or (settings.size and settings.size > 0 and settings.size or diameter * state.scale)) * scale
    frame:SetSize(size, size)
    if kind == "level" and state.playerRefinement then
        -- Frame Scale can change without changing this holder's local size.
        frame.rim:LayoutBorder(size, size)
    end
    -- Give level text a centered area within the painted opening rather than
    -- inheriting the font template's unbounded text box/shadow positioning.
    if kind == "level" then
        frame.text:SetSize(size * .72, size * .72)
        frame.text:SetWordWrap(false)
    end
    frame:SetAlpha(entry.configurationShowAll and (cfg.hide[kind] or settings.alpha <= 0) and .25 or settings.alpha)
    -- Icon indicators use only their native artwork. Keep the rim frame alive
    -- as the icon/text parent; hide its decorative regions independently.
    local iconOnly = kind ~= "level" or file ~= nil
    GUF.SetArtisticBadgeChrome(frame, not iconOnly)
    local iconScale = iconOnly and 1 or .65
    frame.iconSize = size * iconScale
    -- These legacy sheets are square; their UV crop can be rectangular (PvP).
    -- Fit that cropped image inside Size instead of stretching it into a square.
    local aspect = coords and math.abs(coords[2] - coords[1]) / math.abs(coords[4] - coords[3]) or 1
    frame.goodUnitFramesGlyphAspect = aspect
    fitIndicatorIcon(frame, aspect)
    frame.icon:SetShown(file ~= nil)
    if file and not GUF.ApplyIndicatorArtwork(frame, GUF.IndicatorArtworkKey(file, coords)) then
        -- Native interface icons can reject mip filters with a fatal client
        -- assertion (Feign Death). Keep TRILINEAR on owned generated art only.
        frame.icon:SetTexture(file, "CLAMP", "CLAMP", "LINEAR")
        frame.icon:SetTexCoord(unpack(coords or { 0, 1, 0, 1 }))
    end
    local options = cfg.text[kind == "level" and "level" or "name"]
    frame.text:SetFont(GUF.Font(options.custom and options.font or cfg.font),
        (kind == "level" and (options.custom and options.size or cfg.fontSize) or 10) * state.scale * scale,
        options.custom and options.outline or cfg.outline)
    frame.text:SetShadowColor(0, 0, 0, 0)
    frame.text:SetShadowOffset(0, 0)
    local defaultColor = kind == "level" and state.playerRefinement and { 1, 1, 1 } or { 1, .82, 0 }
    frame.text:SetTextColor(unpack(kind == "level" and options.customColor and options.color or defaultColor))
    frame.text:SetText(text or "")
    GUF.StyleLayeredBadge(entry, kind, frame, file)
    frame:Show()
end

GUF.PositionArtisticBadge = badge

function GUF.SetArtisticRoleIcon(icon, role, frame)
    local keys = { TANK = "role-tank", HEALER = "role-healer", DAMAGER = "role-damage" }
    if frame and GUF.ApplyIndicatorArtwork(frame, keys[role]) then return end
    local atlases = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }
    local coords = { TANK = { 0, 19/64, 22/64, 41/64 }, HEALER = { 20/64, 39/64, 1/64, 20/64 }, DAMAGER = { 20/64, 39/64, 22/64, 41/64 } }
    icon:SetTexCoord(0, 1, 0, 1)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlases[role])
    if info then
        icon:SetAtlas(atlases[role])
        if frame and number(info.width) and number(info.height) and info.height > 0 then fitIndicatorIcon(frame, info.width / info.height) end
    else
        icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", "CLAMP", "CLAMP", "LINEAR")
        icon:SetTexCoord(unpack(coords[role]))
        if frame then fitIndicatorIcon(frame, 1) end
    end
end

function GUF.UpdateArtisticState(entry)
    local state, cfg = entry.artisticLayout, GUF.Runtime.Settings("layout", entry).frames[entry.unit]
    if not state or not state.active then return end
    if entry.unit == "player" and not entry.configurationPreview then
        local summons = GUF.Client.ResolveDruidSummonFrame()
        if summons and not summons.goodUnitFramesOwned then
            -- Suppress only the native summon presentation. Its events,
            -- cooldowns and shown state stay native; normal layout release
            -- restores the latest captured alpha. Recheck late-loaded hosts.
            state.hidden[summons] = true
            leaseAlpha(summons, 0)
        end
    end
    -- Complete generated rings replace the historical procedural border inlay.
    for _, segment in ipairs(state.classTrim) do segment:Hide() end
    for _, frame in pairs(state.badges) do frame:Hide() end
    local unit = entry.frame.unit or entry.unit
    GUF.SyncArtisticPowerLayout(entry)
    GUF.UpdateArtisticPortrait(entry)
    GUF.LayoutDesignLevel(entry)
    GUF.UpdateArtisticResources(entry)
    if not yes(UnitExists(unit)) then
        for _, item in ipairs(state.dragon) do item.region:Hide() end
        return
    end
    local outward = entry.unit == "target" and 1 or -1
    local halfWidth = state.portraitWidth / state.scale / 2
    local halfHeight = state.portraitHeight / state.scale / 2
    local outerX, innerX = outward * (halfWidth - 12), -outward * (halfWidth - 12)
    local upperY, lowerY = halfHeight - 10, -halfHeight + 10
    local resourceLane = entry.unit == "player" and state.resourceLane and not cfg.hide.resource
    local levelDiameter = 30
    local levelX = resourceLane and -16 or outerX
    local level = UnitLevel(unit)
    if entry.unit ~= "player" and entry.unit ~= "target" and number(level) then
        badge(entry, "level", "level", levelX, lowerY, levelDiameter,
            level < 0 and "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" or nil, nil,
            level >= 0 and tostring(level) or nil)
    end
    local combat = UnitAffectingCombat(unit)
    -- Local lockdown is public; do not infer a secret Target combat state.
    if entry.unit == "player" then combat = InCombatLockdown() end
    local fighting = yes(combat)
    -- Player uses the resting glyph for every public out-of-combat state.
    local resting = entry.unit == "player" and not GUF.Secret(combat) and not fighting
    local socketHandled = GUF.LayoutDesignCombatStatus(entry, combat)
    if not socketHandled and (fighting or resting) then
        local combatKind = resting and "resting" or "combat"
        local clearance = levelDiameter / 2 * cfg.indicators.level.scale
            + 12 * cfg.indicators[combatKind].scale + 2
        local combatX, combatY = outerX - outward * clearance, lowerY
        if entry.unit == "player" or entry.unit == "target" then combatX, combatY = outerX, lowerY end
        if resourceLane then combatX = 22 end
        badge(entry, "combat", combatKind, combatX, combatY, 24,
            "Interface\\CharacterFrame\\UI-StateIcon", resting and { 0, .5, 0, .5 } or { .5, 1, 0, .5 })
    end
    -- PvP alone displays faction identity; avoid a duplicate always-on emblem.
    local faction = UnitFactionGroup(unit)
    if UnitIsPVPFreeForAll and yes(UnitIsPVPFreeForAll(unit)) then
        badge(entry, "pvp", "pvp", innerX, upperY, 20, "Interface\\TargetingFrame\\UI-PVP-FFA")
    elseif yes(UnitIsPVP(unit)) and not GUF.Secret(faction) and (faction == "Horde" or faction == "Alliance") then
        badge(entry, "pvp", "pvp", innerX, upperY, 20, "Interface\\TargetingFrame\\UI-PVP-" .. faction,
            faction == "Horde" and { 0, .625, 0, .625 } or { .0625, .625, 0, .6875 })
    end
    if (entry.unit == "player" or entry.unit == "target") and UnitGroupRolesAssigned then
        local assigned = UnitGroupRolesAssigned(unit)
        local atlases = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }
        if not GUF.Secret(assigned) and atlases[assigned] then
            badge(entry, "role", "role", innerX, lowerY, 18, white)
            GUF.SetArtisticRoleIcon(state.badges.role.icon, assigned, state.badges.role)
        end
    end
    local role
    if UnitIsGroupLeader and yes(UnitIsGroupLeader(unit)) then role = "UI-Group-LeaderIcon"
    elseif UnitIsGroupAssistant and yes(UnitIsGroupAssistant(unit)) then role = "UI-Group-AssistantIcon" end
    -- Target's outer flank belongs to combat. Roles use the upper
    -- middle of its portrait, between the PvP and raid-marker corners.
    local leaderX, lootX, roleY = outerX, innerX, 0
    if entry.unit == "target" then leaderX, lootX, roleY = -10, 10, upperY end
    if role then badge(entry, "leader", "leader", leaderX, entry.unit == "player" and upperY or roleY, 18, "Interface\\GroupFrame\\" .. role) end
    if GetLootMethod and UnitIsUnit then
        local method, partyIndex, raidIndex = GetLootMethod()
        local looter
        if not GUF.Secret(method) and method == "master" then
            if number(raidIndex) and raidIndex > 0 then looter = "raid" .. raidIndex
            elseif number(partyIndex) then looter = partyIndex == 0 and "player" or "party" .. partyIndex end
        end
        if looter and yes(UnitIsUnit(unit, looter)) then
            badge(entry, "loot", "loot", entry.unit == "player" and outerX or lootX, roleY, 18, "Interface\\GroupFrame\\UI-Group-MasterLooter")
        end
    end
    GUF.UpdateAutomaticIndicators(entry)
    state.nameStrip:SetAlpha(cfg.artistic.nameBackgroundAlpha)
    for _, item in ipairs(state.dragon) do item.region:Hide() end
end

function GUF.ReleaseArtisticLayout(entry)
    if GUF.Restricted() or GUF.editing then GUF.DeferRuntime("native-readiness"); return "deferred", "restricted" end
    local state = entry.artisticLayout
    if not (state and (state.active or state.restorePending)) then return "released" end
    -- Exit must release native visibility and every readable component even
    -- when a single native bar's current/cached geometry is restricted.
    local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
    entry.layoutWriting, GUF.geometryWriting = true, true
    restore(entry, state)
    entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
    if state.restorePending then return "restoring", "native-geometry", state.restorePending end
    return "released"
end

function GUF.ApplyArtisticLayout(entry)
    if GUF.Restricted() or GUF.editing then GUF.DeferRuntime("native-readiness"); return "deferred", "restricted" end
    -- Keep the legacy entry point usable while dispatch moves to definitions.
    if GUF.Runtime.Settings("layout", entry).general.frameStyle ~= "artistic" then return GUF.ReleaseArtisticLayout(entry) end
    local state = entry.artisticLayout
    if not state or not state.created then state = create(entry) end
    if not state then return "unavailable", "native-parts" end
    local nativeRegions = { entry.frame, state.portrait }
    if not GUF.ArtisticNativeBarsIsolated(entry, state) then
        nativeRegions[#nativeRegions + 1] = entry.health
        nativeRegions[#nativeRegions + 1] = entry.power
    end
    for _, region in ipairs(nativeRegions) do
        local item = track(entry, state, region)
        if not item or not number(item.geometry.width) or not number(item.geometry.height)
            or not GUF.ReadPoints(region) then GUF.DeferRuntime("native-readiness"); return "deferred", "native-geometry" end
    end
    entry.layoutWriting, GUF.geometryWriting = true, true
    do
        state.restorePending = nil
        state.active = true
        local geometry = GUF.Presentation.Geometry(entry)
        for key, value in pairs(geometry) do state[key] = value end
        local scale, width, height = compact(entry.unit), state.width, state.height
        state.scale = scale
        entry.frame:SetSize(width, height)
        state.background:SetFrameLevel(entry.frame:GetFrameLevel())
        if state.renderBars then
            entry.powerText:SetParent(state.renderBars.power)
            for _, text in pairs(entry.powerSlots or {}) do text:SetParent(state.renderBars.power) end
        end
        local ornamentLevel = math.max(entry.frame:GetFrameLevel(), entry.health:GetFrameLevel(), entry.power:GetFrameLevel()) + 5
        state.ornaments:SetFrameLevel(ornamentLevel)
        state.rim:SetFrameLevel(ornamentLevel + 1)
        state.badgeLayer:SetFrameLevel(ornamentLevel + 4)
        GUF.LayoutArtisticRenderedLayers(entry)
        local referencePortraitWidth = state.referencePortraitWidth
        local portraitSource = GUF.ArtisticPortraitArtwork(entry.unit, entry.frame.unit or entry.unit)
        local barWidth, healthFillHeight = state.barWidth - 8 * scale, state.healthFillHeight
        local powerFillHeight = state.powerFillHeight
        local healthHeight, powerHeight = state.healthRowHeight, state.powerRowHeight
        local divider, topInset = state.dividerHeight, state.healthTopInset
        local stackHeight = healthHeight + powerHeight
        local healthY, powerY, padding = state.healthY, state.powerY, -state.healthY
        state.rim:ClearAllPoints()
        -- The portrait is a child of the rim; anchor the rim to the secure button
        -- rather than creating a dependency on its own descendant.
        state.rim:SetPoint("CENTER", entry.frame, "TOPLEFT", state.px, state.py)
        state.rim.mirrored = portraitSource.combined and not portraitSource.targetOnly and entry.unit == "target" or false
        state.rim.source = portraitSource
        state.rim:SetSize(state.portraitWidth, state.portraitHeight)
        state.rim:LayoutBorder(state.portraitWidth, state.portraitHeight)
        state.junction:Hide()
        GUF.LayoutArtisticPortrait(entry)
        -- Continue live fills through the recessed side gaps. The circular
        -- portrait and foreground border cover their intentional underlap.
        local sideInset = (state.refinedHousing and 1.5 or 2) * scale
        local fillX, fillWidth = state.housingX + sideInset, state.housingWidth - 2 * sideInset
        place(entry, state, entry.health, fillX, healthY - topInset,
            fillWidth, healthFillHeight)
        place(entry, state, entry.power, fillX, powerY - divider,
            fillWidth, powerFillHeight)
        local visibleX = state.barX + 4 * scale
        state.castAnchorBottom = powerY - divider - powerFillHeight
        -- Match the bottom of the visible power fill, ending beside the circle.
        -- The outer cast rim stays outside the portrait even at its upper edge.
        local castLeft, castRight = state.castLeft, state.castRight
        for kind, area in pairs(state.textAreas) do
            area:ClearAllPoints()
            -- Readable bounds follow the presentation, not native reset geometry.
            local host = GUF.ArtisticBarHost(entry, kind)
            area:SetPoint("TOPLEFT", host, "TOPLEFT", visibleX - fillX, 0)
            area:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", visibleX + barWidth - fillX - fillWidth, 0)
            local castArea = state.castAreas[kind]
            castArea:ClearAllPoints()
            castArea:SetPoint("TOPLEFT", host, "TOPLEFT", castLeft + state.castBorderInset - fillX, 0)
            castArea:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", castRight - state.castBorderInset - fillX - fillWidth, 0)
        end
        local headerHeight = GUF.LayoutPresentationHeader(entry, state, GUF.PresentationFrameSettings(entry))
        if not state.indicatorArea then
            state.indicatorArea = GUF.Runtime.CreateFrame("Frame", nil, state.ornaments)
            state.indicatorArea.goodUnitFramesOwned = true
        end
        state.indicatorArea:ClearAllPoints()
        state.indicatorArea:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", state.barX, healthY)
        state.indicatorArea:SetSize(state.barWidth, stackHeight)
        if entry.unit == "player" then
            state.fullWidthCast = state.fullWidthCast or GUF.Runtime.CreateFrame("Frame", nil, state.ornaments)
            state.fullWidthCast.goodUnitFramesOwned = true
            state.fullWidthCast:ClearAllPoints()
            state.fullWidthCast:SetPoint("BOTTOMLEFT", entry.frame, "BOTTOMLEFT", state.barOffset + state.castBorderInset, state.castBorderInset)
            state.fullWidthCast:SetPoint("BOTTOMRIGHT", entry.frame, "BOTTOMRIGHT", state.barOffset - state.castBorderInset, state.castBorderInset)
            state.fullWidthCast:SetHeight(1)
            state.castAnchorBottom = -height + state.castBorderInset
        end
        place(entry, state, entry.name, 4 * scale, 0,
            state.nameTextWidth, headerHeight, state.ornaments, "LEFT", state.nameArea)
        if entry.unit == "target" and entry.name then
            -- Bind both edges once outside restrictions. Threat visibility can
            -- then resize only nameArea, leaving native text untouched in combat.
            entry.name:SetWidth(0)
            entry.name:SetPoint("RIGHT", state.nameArea, "RIGHT", -4 * scale, 0)
            transformBase(entry.name, { { "LEFT", state.nameArea, "LEFT", 4 * scale, 0 },
                { "RIGHT", state.nameArea, "RIGHT", -4 * scale, 0 } }, 0, headerHeight)
        end
        -- Keep Blizzard formatting while anchoring outer labels at their own
        -- edges, so a longer right-hand value extends into the bar toward left.
        local seen = {}
        for _, text in pairs(GUF.NativeTexts(entry, "health")) do
            if not seen[text] then
                seen[text] = true
                ownNativeHealthText(entry, state, text)
            end
        end
        state.housing:ClearAllPoints()
        state.housing:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", state.housingX, -padding)
        state.housing:SetSize(state.housingWidth, stackHeight)
        state.housing.border.edgeSize = state.housingEdge
        state.housing.border:LayoutBorder(state.housingWidth, stackHeight)
        for _, spec in ipairs({ { state.healthShell, healthY, healthHeight }, { state.powerShell, powerY, powerHeight } }) do
            spec[1]:ClearAllPoints()
            if state.refinedHousing then
                -- Back only the live interiors: an outer rectangular backdrop
                -- otherwise paints black wedges outside the transparent curves.
                local health = spec[1] == state.healthShell
                spec[1]:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", fillX, spec[2] - (health and topInset or divider))
                spec[1]:SetSize(fillWidth, health and healthFillHeight or powerFillHeight)
            else
                spec[1]:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", state.housingX, spec[2])
                spec[1]:SetSize(state.housingWidth, spec[3])
            end
        end
        GUF.LayoutArtisticBarDividers(entry)
        GUF.SyncArtisticPowerLayout(entry, true)
        if not state.renderBars then
            barMasks(entry, state, entry.health, state.healthMask)
            barMasks(entry, state, entry.power, state.powerMask)
        end
        GUF.PrepareAutomaticIndicators(entry)
        hideTextures(state, state.container, state.portrait)
        hideTextures(state, entry.frame, state.portrait)
        hideTextures(state, entry.main)
        hideTextures(state, entry.context)
        hideTextures(state, entry.healthArea, entry.health:GetStatusBarTexture())
        if state.refinedHousing then hideTextures(state, entry.health, entry.health:GetStatusBarTexture()) end
        hideTextures(state, entry.power, entry.power:GetStatusBarTexture())
        GUF.SuppressArtisticNativeBars(entry)
        hide(state, entry.nameBackground)
        hide(state, state.portrait)
        for key, regions in pairs(entry.regions) do
            if key ~= "resource" then for _, region in pairs(regions) do hide(state, region) end end
        end
        local name, frame = entry.frame:GetName(), entry.frame
        for _, region in pairs({ state.container.FrameFlash, state.container.Flash, frame.flash,
            frame.threatIndicator, frame.ThreatIndicator, _G[name .. "Flash"], _G[name .. "StatusTexture"],
            _G[name .. "ThreatIndicator"], frame.ReadyCheckIcon, entry.context.ReadyCheckIcon,
            frame.masterLooterIcon, _G[name .. "LeaderIcon"], _G[name .. "MasterIcon"], _G[name .. "RaidTargetIcon"],
            entry.unit == "pet" and PetAttackModeTexture or nil }) do hide(state, region) end
        state.background:Show(); state.ornaments:Show(); state.badgeLayer:Show()
        GUF.LayoutArtisticResources(entry)
        GUF.LayoutBarDesign(entry)
    end
    entry.layoutWriting, GUF.geometryWriting = nil, nil
    return "applied"
end

function GUF.FinalizeArtisticLayout(entry)
    local state = entry.artisticLayout
    if not state or not state.active then return end
    for region in pairs(state.hidden) do leaseAlpha(region, 0) end
    GUF.UpdateArtisticState(entry)
end

function GUF.UpdateArtisticStates()
    if not GUF.db then return end
    for _, entry in pairs(GUF.frames) do GUF.UpdateArtisticState(entry) end
    -- Reuse the existing state refresh if this client changes class without
    -- reloading. The renderer reads the current class; refresh cached cards too.
    local class = GUF.PlayerDesignClass()
    if class ~= GUF.portraitClass then
        GUF.portraitClass = class
        local window = GUF.options
        if window and window:IsShown() and not window.buildingOptions and window.page == "units" then
            if window.tab == "design" then GUF.BuildOptions() end
            GUF.UpdateOptionsPreview()
        end
    end
end

local function needsArtisticRefresh(entry, region, geometry)
    local layout = entry.artisticLayout
    if not layout then return false end
    if layout.active then
        -- CaptureSize watches the native subtree, including children Artistic
        -- never moves. Only our tracked geometry can need a layout repair.
        -- Root/owned-bar repairs already ran before this fallback; resources
        -- retain their own native lifecycle hooks and are excluded by CaptureSize.
        if not layout.regions or layout.regions[region]
            or layout.barGeometry and layout.barGeometry[region] then return true end
        local counts = GUF.Updates.stats.geometryUnowned
        counts[entry.unit] = (counts[entry.unit] or 0) + 1
        return false
    end
    if not (layout.restorePending and layout.restorePending[region]) then return false end
    if geometry.hasSize and (not number(geometry.width) or not number(geometry.height)) then return false end
    return geometry.pointsReadable ~= false and GUF.ReadPoints(region) ~= nil
end

function GUF.RefreshArtisticNativeGeometry(entry, region, geometry)
    if GUF.RestoreArtisticBarGeometry(entry, region) then return true end
    local retry = needsArtisticRefresh(entry, region, geometry)
    local state = entry.artisticLayout
    return false, retry, retry and state and not state.active and "cleanup" or nil
end

function GUF.ArtisticWriterStates(entry, shallow)
    local state = entry.artisticLayout
    if not state then return {} end
    local result = { state }
    if not shallow then
        for _, mask in pairs(state.masks or {}) do result[#result + 1] = mask end
    end
    return result
end
