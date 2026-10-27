local _, GUF = ...

local function create(unit, parent)
    local entry = GUF.CreateSpecimenBase(unit, parent, "artistic")
    local frame, state = entry.frame, entry.specimenState
    state.active, state.playerRefinement, state.circular = true, unit == "player", true
    entry.artisticLayout = state
    state.housing = GUF.CreateArtisticHousing(frame, unit == "player" or unit == "target", true, unit, true)
    state.housing:SetFrameLevel(40)
    state.nameStrip = GUF.CreateArtisticNameHeader(frame, unit)
    state.nameArea = CreateFrame("Frame", nil, state.nameStrip)
    state.nameArea.goodUnitFramesOwned = true
    state.nameArea:SetAllPoints()
    state.rim = GUF.CreateArtisticPortraitRim(frame)
    state.rim.configurationPreview = true
    state.rim:SetFrameLevel(42)
    GUF.CreateArtisticPortrait(entry, state)
    state.dividerLayer = CreateFrame("Frame", nil, frame)
    state.dividerLayer.goodUnitFramesOwned = true
    state.dividerLayer:EnableMouse(false)
    state.dividerLayer:SetAllPoints(frame)
    state.divider = state.dividerLayer:CreateTexture(nil, "OVERLAY")
    state.divider:SetColorTexture(.66, .68, .71, 1)
    state.divider.goodUnitFramesOwned = true
    state.headerDivider = state.dividerLayer:CreateTexture(nil, "OVERLAY")
    state.headerDivider.goodUnitFramesOwned = true
    for _, divider in ipairs({ state.headerDivider, state.divider }) do
        if divider.SetSnapToPixelGrid then divider:SetSnapToPixelGrid(false) end
        if divider.SetTexelSnappingBias then divider:SetTexelSnappingBias(0) end
    end
    state.indicatorArea = CreateFrame("Frame", nil, frame)
    state.indicatorArea.goodUnitFramesOwned = true
    local badgeLayer = CreateFrame("Frame", nil, frame)
    badgeLayer.goodUnitFramesOwned = true
    badgeLayer:SetFrameLevel(52)
    for _, kind in ipairs({ "combat", "resting", "pvp", "leader", "loot", "role", "raid", "status", "resurrect" }) do
        local badge = GUF.CreateArtisticBadge(badgeLayer)
        state.badges[kind] = badge
    end
    return entry
end

GUF.CreateArtisticSpecimen = create

local function showIcon(entry, kind, file, coords, dx, dy, diameter)
    if kind == "raid" or kind == "status" or kind == "resurrect" then
        GUF.PositionAutomaticBadge(entry, kind, file, coords)
        return
    end
    GUF.PositionArtisticBadge(entry, kind, kind, dx, dy, diameter, file, coords)
    entry.artisticLayout.badges[kind].previewUsed = true
end

local function render(entry, options, context)
    local unit, frame, state = entry.unit, entry.frame, entry.artisticLayout
    local cfg = GUF.PresentationFrameSettings(entry)
    local sampleState, showAll, group = options.state, options.showAll, options.group
    local function hasState(key)
        return options.states[key] == true
    end
    local function hasGroup(key)
        if options and options.groups then return options.groups[key] == true end
        return group == key
    end
    local grouped = hasGroup("party") or hasGroup("raid")
    options.portraitSource = options.portraitSource or GUF.SelectArtisticPortraitArtwork(unit, "player", entry.previewIdentity)
    local geometry = context.definition.presentation.geometry(context)
    for key, value in pairs(geometry) do state[key] = value end
    state.targetComboStack = nil
    frame:SetSize(state.width, state.height)
    if not entry.optionsPreview or frame:GetNumPoints() == 0 then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", 0, 0)
    end
    local header = (unit == "player" or unit == "target") and cfg.artistic.playerGeometry.header or 15 * state.scale
    local healthY = state.healthY
    local powerY = healthY - state.healthRowHeight
    local powerHeight = state.powerFillHeight
    state.rim.source = options.portraitSource
    state.rim.mirrored = state.rim.source.combined and not state.rim.source.targetOnly and unit == "target" or false
    state.rim:ClearAllPoints(); state.rim:SetPoint("CENTER", frame, "TOPLEFT", state.px, state.py)
    state.rim:SetSize(state.portraitWidth, state.portraitWidth); state.rim:LayoutBorder(state.portraitWidth, state.portraitWidth)
    GUF.LayoutArtisticPortrait(entry)
    state.viewport:Show(); state.portraitFallback:Show()
    if options.subject ~= "player" then
        state.portraitFallback:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Bear", "CLAMP", "CLAMP", "LINEAR")
        state.portraitFallback:SetTexCoord(0, 1, 0, 1)
    else GUF.SetArtisticPortraitTexture(state.portraitFallback, "player") end
    GUF.LayoutPresentationHeader(entry, state, cfg)
    entry.name:ClearAllPoints(); entry.name:SetPoint("CENTER", state.nameArea, "CENTER", cfg.text.name.x, cfg.text.name.y)
    entry.name:SetTextColor(.67, .9, .4); entry.name:SetJustifyH(cfg.text.name.align)
    entry.name:SetSize(math.max(1, state.barWidth - 16), header)
    if unit == "target" then
        entry.name:ClearAllPoints(); entry.name:SetWidth(0)
        entry.name:SetPoint("LEFT", state.nameArea, "LEFT", 4 * state.scale + cfg.text.name.x, cfg.text.name.y)
        entry.name:SetPoint("RIGHT", state.nameArea, "RIGHT", -4 * state.scale + cfg.text.name.x, cfg.text.name.y)
    end
    entry.name:SetText(entry.previewData.name)
    entry.name:SetShown(not cfg.hide.name)
    GUF.StylePresentationText(entry.name, cfg, cfg.text.name, GUF.PresentationTextSize(cfg, "name", "artistic"))
    if options then entry.name:SetTextColor(GUF.PreviewNameColor(entry, options.subject)) end
    entry.name:SetHeight(math.max(header, GUF.PresentationTextSize(cfg, "name", "artistic") + 4))
    state.housing:ClearAllPoints(); state.housing:SetPoint("TOPLEFT", frame, "TOPLEFT", state.housingX, healthY)
    state.housing:SetSize(state.housingWidth, state.healthRowHeight + state.powerRowHeight)
    state.housing.edgeSize = 3 * state.scale; state.housing:LayoutBorder(state.housingWidth, state.healthRowHeight + state.powerRowHeight)
    state.indicatorArea:ClearAllPoints(); state.indicatorArea:SetPoint("TOPLEFT", frame, "TOPLEFT", state.barX, healthY)
    state.indicatorArea:SetSize(state.barWidth, state.healthRowHeight + state.powerRowHeight)
    for _, badge in pairs(state.badges) do badge.previewUsed = false end
    local data = entry.previewData
    if not GUF.LayeredDesignSettings(unit, entry) then
        state.badges.level = state.badges.level or GUF.CreateArtisticBadge(state.rim)
        GUF.PositionArtisticBadge(entry, "level", "level", -state.portraitWidth / state.scale / 2 + 7,
            -state.portraitHeight / state.scale / 2 + 7, 22, nil, nil, data.level)
        state.badges.level.previewUsed = true
    elseif state.badges.level then state.badges.level:Hide() end
    GUF.LayoutDesignLevel(entry, data.level)
    for _, kind in ipairs({ "health", "power" }) do
        local bar = entry[kind]
        local height, y = kind == "health" and state.healthFillHeight or powerHeight, kind == "health" and healthY - state.healthTopInset or powerY - state.scale
        bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", frame, "TOPLEFT", state.housingX + 1.5 * state.scale, y)
        bar:SetSize(state.housingWidth - 3 * state.scale, height)
        bar:SetMinMaxValues(0, kind == "health" and data.healthMax or data.powerMax)
        bar:SetValue(kind == "health" and data.health or data.power)
        local selectedTexture = GUF.MediaTexture(cfg.bars[kind .. "Texture"])
        bar:SetStatusBarTexture(selectedTexture or "Interface\\TargetingFrame\\UI-StatusBar")
        bar:GetStatusBarTexture():SetDesaturated(false)
        if not selectedTexture then GUF.PaintBlizzardBarFill(bar:GetStatusBarTexture(), unit, kind) end
        local anchor = state.textAreas[kind]
        anchor:ClearAllPoints(); anchor:SetPoint("TOPLEFT", frame, "TOPLEFT", state.barX + 4 * state.scale, y)
        anchor:SetSize(state.barWidth - 8 * state.scale, height)
        data.value, data.maximum, data.percent = kind == "health" and data.health or data.power, kind == "health" and data.healthMax or data.powerMax, kind == "health" and data.healthPercent or data.powerPercent
        GUF.RenderPreviewBarText(entry, kind, data, anchor)
    end
    GUF.LayoutArtisticBarDividers(entry)
    GUF.LayoutBarDesign(entry)
    local outer = unit == "target" and 1 or -1
    local edge = outer * (state.portraitWidth / state.scale / 2 - 12)
    local upperY, lowerY = state.portraitHeight / state.scale / 2 - 10, -state.portraitHeight / state.scale / 2 + 10
    local enabledIndicators = options and options.enabledIndicators
    if grouped or showAll or enabledIndicators then showIcon(entry, "leader", "Interface\\GroupFrame\\UI-Group-LeaderIcon", nil, edge, upperY, 18) end
    if hasGroup("raid") or showAll or enabledIndicators then showIcon(entry, "loot", "Interface\\GroupFrame\\UI-Group-MasterLooter", nil, edge, 0, 18) end
    if hasState("pvp") or showAll or enabledIndicators then
        local faction = UnitFactionGroup("player")
        if not GUF.Secret(faction) and (faction == "Horde" or faction == "Alliance") then
            showIcon(entry, "pvp", "Interface\\TargetingFrame\\UI-PVP-" .. faction,
                faction == "Horde" and { 0, .625, 0, .625 } or { .0625, .625, 0, .6875 }, -edge, upperY, 20)
        end
    end
    local roleSubject = unit == "player" or unit == "target" and options.subject == "player"
    if roleSubject and (grouped or showAll or enabledIndicators) then showIcon(entry, "role", "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", nil, -edge, lowerY, 18)
    GUF.SetArtisticRoleIcon(state.badges.role.icon, "DAMAGER", state.badges.role) end
    if hasGroup("raid") or showAll then
        showIcon(entry, "raid", "Interface\\TargetingFrame\\UI-RaidTargetingIcons", { .25, .5, .25, .5 })
    end
    local socketHandled = GUF.LayoutDesignCombatStatus(entry, hasState("combat"))
    if socketHandled then
        -- The one fixed socket follows Combat even under Show all; it can
        -- never display a second resting glyph or obscure the Level number.
    else
        if unit == "player" and hasState("resting") then showIcon(entry, "resting", "Interface\\CharacterFrame\\UI-StateIcon", { 0, .5, 0, .5 }, edge, lowerY, 24) end
        if hasState("combat") or showAll then showIcon(entry, "combat", "Interface\\CharacterFrame\\UI-StateIcon", { .5, 1, 0, .5 }, edge, lowerY, 24) end
    end
    -- Match stock presentation: ready/resurrection overlay a visible portrait;
    -- Dead/Ghost/Offline/Feign Death are Health text, never portrait art.
    local readyFiles = { ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
        notready = "Interface\\RaidFrame\\ReadyCheck-NotReady", waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting" }
    local file = readyFiles[sampleState]
    if file then showIcon(entry, "status", file) end
    if hasState("resurrect") then showIcon(entry, "resurrect", "Interface\\RaidFrame\\Raid-Icon-Rez") end
    for _, badge in pairs(state.badges) do if not badge.previewUsed then badge:Hide() end end
    if options.layoutCard then
        -- General cards show the selected layout's appearance, with no live
        -- controller/active-layout cast or aura dependencies.
        entry.castBar:Hide()
        state.housing:Show(); state.nameStrip:Show(); state.headerDivider:Show(); state.divider:Show()
        state.rim.art:Show(); state.rim.fill:SetShown(not state.rim.source.combined)
        frame:SetAlpha(1); frame:Show()
        return "applied"
    end
    local channeling = hasState("channel")
    local casting = hasState("casting") or channeling
    -- Interactive State is a diagnostic sample independent of live enablement.
    local selectedCast = casting
    entry.previewCasting = selectedCast and true or nil
    entry.castBar:SetShown(selectedCast or (casting or showAll) and (cfg.bars.cast.enabled or showAll))
    local castWidth = state.width - 4
    if unit ~= "player" then
        castWidth = state.castRight - state.castLeft - 2 * state.castBorderInset
    end
    if cfg.bars.cast.width > 0 then castWidth = cfg.bars.cast.width end
    local castHeight = cfg.bars.cast.height > 0 and cfg.bars.cast.height or 16
    GUF.AnchorCastBar(entry, entry.castBar)
    entry.castBar:SetSize(math.max(1, castWidth), castHeight); entry.castBar.layoutHeight = castHeight
    GUF.StyleCastBarPresentation(entry.castBar, state, channeling)
    GUF.CacheCastAuraGeometry(entry, entry.castBar, castWidth, castHeight)
    entry.castBar:SetMinMaxValues(0, 1); entry.castBar:SetValue(casting and .65 or 0)
    entry.castBar.spark:SetShown(casting)
    entry.castBar.name:SetText(casting and (channeling and "Channeling" or "Aimed Shot") or "")
    entry.castBar.time:SetText(casting and "2.1" or "")
    GUF.LayoutCastLabels(entry, entry.castBar, entry.castBar.name, entry.castBar.time, GUF.CastSourceText(entry))
    GUF.PositionCastIcon(entry, entry.castBar)
    entry.castBar.icon:SetShown(casting and cfg.bars.cast.icon ~= "HIDE")
    if unit == "target" then GUF.RenderConfigurationThreat(entry, options.previewThreat) end
    state.housing:Show(); state.nameStrip:Show(); state.headerDivider:Show(); state.divider:Show()
    state.rim.art:Show(); state.rim.fill:SetShown(not state.rim.source.combined)
    local fading = cfg.fading
    frame:SetAlpha(fading.enabled and (hasState("combat") and fading.combat or fading.inactive) or 1)
    frame:Show()
    return "applied"
end

GUF.RenderArtisticSample = render

function GUF.ArtisticPresentationRole(entry, role)
    local state = GUF.PresentationState(entry)
    local indicator = role:match("^indicator:(.+)$")
    if indicator then return state and state.badges and state.badges[indicator] end
    if role == "root" then return entry.frame end
    if role == "ownedBars" then return state and state.active and state.renderBars ~= nil or false end
    if role == "powerAbsent" then return state and state.active and state.noPower == true or false end
    if role == "nameWidth" then
        if state and state.active then return state.nameTextWidth end
        return
    end
    if role == "featureGap" then
        if state and state.active then return 6 * state.scale end
        return
    end
    if role == "castInset" then
        if state and state.active then return state.castBorderInset end
        return
    end
    if role == "castStyle" then return { active = state and state.active == true } end
    if role == "castAnchor" then
        return state and state.active and (state.fullWidthCast or state.castAreas
            and state.castAreas[state.noPower and "health" or "power"]) or entry.power or entry.health or entry.frame
    end
    if role == "barMetrics" then
        if not state or not state.active then return end
        return { width = state.barWidth - 8 * state.scale,
            health = state.noPower and state.healthRowHeight + state.powerRowHeight - state.healthTopInset - 2 * state.scale
                or state.healthFillHeight, power = state.powerRowHeight - 3 * state.scale }
    end
    if role == "auraTopGap" then
        if state and state.active and state.nameArea then return 6 * state.scale end
        return
    end
    if role == "resourceGeometry" then
        if not state or not state.active then return end
        return { scale = state.scale, barX = state.barX, barWidth = state.barWidth,
            bottom = state.healthY - state.healthRowHeight - state.powerRowHeight }
    end
    if role == "resourceBounds" then
        local stack = state and state.active and state.targetComboStack
        if not stack then return end
        local top = state.height + stack.comboY
        return { left = stack.x, right = stack.x + stack.width, bottom = top - stack.height, top = top }
    end
    if role == "threatHost" then
        if state and state.active and entry.unit == "target" then return state.nameStrip end
        return
    end
    if role == "threatGeometry" then
        if state and state.active then return state.threatGeometry end
        return
    end
    if role == "health" or role == "power" then
        return state and state.active and state.renderBars and state.renderBars[role] or entry[role]
    end
    if role == "healthText" or role == "powerText" then
        local kind = role == "healthText" and "health" or "power"
        return GUF.ArtisticPresentationRole(entry, kind)
    end
    if role == "healthAnchor" or role == "powerAnchor" then
        local kind = role == "healthAnchor" and "health" or "power"
        return state and state.active and state.textAreas[kind] or entry[kind]
    end
    if role == "name" or role == "auraTop" then return state and state.active and state.nameArea or entry.frame end
    if role == "auraBottom" then return entry.frame end
    if role == "portrait" then return state and state.viewport end
    if role == "cast" then return entry.castBar end
    if role == "resources" then
        if state and state.active then return state.indicatorArea end
        return
    end
end

function GUF.ArtisticPaintedBounds(entry, region)
    local state = GUF.PresentationState(entry)
    if not state or not state.rim or region ~= state.rim.art then return end
    local source = state.rim.source
    if not source or not source.combined then return end
    local factor = state.portraitWidth / source.diameter
    return state.py + (source.centerY - source.paintTop) * factor,
        state.py + (source.centerY - source.paintBottom) * factor
end

-- Captured native metadata is consumed through its guarded stock backend;
-- this accessor never samples amount-driven Health/Power fills.
function GUF.ArtisticNativeOriginal(entry, region)
    local state = entry and entry.artisticLayout
    if not state then return end
    if not region then
        if state.active then return { active = true } end
        return
    end
    local saved = state.regions and state.regions[region]
    local overridden = state.active or state.restorePending and state.restorePending[region]
    local mask = overridden and state.masks and state.masks[region]
    if not saved and not mask then return end
    return { geometry = saved and saved.geometry, parent = saved and saved.parent,
        mask = mask }
end

function GUF.ArtisticGeometryFromContext(context)
    local liveUnit = context.mode == "live" and (context.view.frame.unit or context.unit) or "player"
    return GUF.ArtisticPresentationGeometry(context.unit, liveUnit, context.settings.frames[context.unit],
        context.scenario.portraitSource)
end
