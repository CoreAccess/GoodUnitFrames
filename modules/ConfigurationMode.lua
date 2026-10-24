local _, GUF = ...
local unpack = unpack or table.unpack
local previews = {}
local function restoreVisibility(unit)
    local entry, cfg = GUF.frames[unit], GUF.db and GUF.db.frames[unit]
    if not entry or not cfg then return end
    local alpha = cfg.fading.enabled and (InCombatLockdown() and cfg.fading.combat or cfg.fading.inactive) or 1
    entry.fade = nil
    GUF.RegionAlpha(entry.frame, alpha)
end
local states = { { "normal", "Normal" }, { "combat", "Combat" }, { "pvp", "PvP" }, { "resting", "Resting" },
    { "casting", "Casting" }, { "channel", "Channeling" }, { "ready", "Ready" }, { "notready", "Not ready" },
    { "waiting", "Ready: waiting" }, { "dead", "Dead" }, { "ghost", "Ghost" }, { "resurrect", "Resurrection" },
    { "offline", "Offline" }, { "feign", "Feign death" } }
GUF.configurationStates = states

function GUF.PreviewPlayerLevel()
    local level = UnitLevel("player")
    if GUF.Secret(level) or type(level) ~= "number" or level < 1 then return 15 end
    return level
end

local function selectElement(unit, tab, category)
    local window = GUF.options or GUF.CreateOptions()
    window.tab = tab
    if tab == "indicators" then window.indicatorCategory = category
    elseif tab == "text" then window.textCategory = category
    elseif tab == "auras" then window.auraKind, window.auraIndex = category.kind, category.index end
    GUF.BuildOptions(unit)
    window:Show()
end

local function dragHandle(frame, unit, setting, tab, category)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not GUF.configurationUnlocked or GUF.Restricted() then return end
        local cfg = setting()
        local x, y = GetCursorPosition()
        self.drag = { x = x, y = y, originX = cfg.x, originY = cfg.y }
        self:SetScript("OnUpdate", function(control)
            if GUF.Restricted() then control:SetScript("OnUpdate", nil); control.drag = nil; return end
            local cx, cy = GetCursorPosition()
            local scale = control:GetEffectiveScale()
            if GUF.Secret(scale) or scale <= 0 then return end
            cfg.x = control.drag.originX + (cx - control.drag.x) / scale
            cfg.y = control.drag.originY + (cy - control.drag.y) / scale
            GUF.RefreshConfigurationMode()
        end)
    end)
    frame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.drag = nil
        if not GUF.configurationUnlocked then return end
        local cfg = setting()
        cfg.x, cfg.y = math.floor(cfg.x + .5), math.floor(cfg.y + .5)
        GUF.RequestApply()
        selectElement(unit, tab, category)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if not GUF.configurationUnlocked then return end
        if button == "RightButton" then GUF.SetConfigurationMode(false)
        elseif not self.drag then selectElement(unit, tab, category) end
    end)
end

GUF.BindConfigurationDrag = dragHandle

local function font(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text.goodUnitFramesOwned = true
    text:SetWordWrap(false)
    return text
end

local function create(unit, parent, readonly)
    if not GUF.IsManagedUnit(unit) then return end
    local frame = CreateFrame("Frame", nil, parent or UIParent)
    frame.goodUnitFramesOwned = true
    frame:SetFrameStrata(parent and parent:GetFrameStrata() or "HIGH")
    frame:SetFrameLevel(parent and parent:GetFrameLevel() + 4 or 30)
    frame:Hide()
    local entry = { unit = unit, frame = frame, configurationPreview = true, healthSlots = {}, powerSlots = {} }
    local state = { unit = unit, active = true, scale = 1, badges = {}, textAreas = {}, playerRefinement = unit == "player", circular = true }
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
        entry[kind] = bar
        entry[kind .. "Text"] = font(bar)
        bar.background = bar:CreateTexture(nil, "BACKGROUND")
        bar.background:SetAllPoints(); bar.background:SetColorTexture(.025, .025, .03, 1)
        state.textAreas[kind] = CreateFrame("Frame", nil, bar)
        state.textAreas[kind].goodUnitFramesOwned = true
        for _, side in ipairs({ "left", "center", "right" }) do
            local text = font(bar)
            entry[kind .. "Slots"][side] = text
            local handle = CreateFrame("Frame", nil, frame)
            handle.goodUnitFramesOwned = true
            handle:SetFrameLevel(48)
            handle:SetAllPoints(text)
            if not readonly then
                dragHandle(handle, unit, function() return GUF.db.frames[unit].text[kind].fields[side] end,
                    "text", kind .. (side == "left" and "Left" or side == "right" and "Right" or "Center"))
            end
            text.handle = handle
        end
    end
    local nameHandle = CreateFrame("Frame", nil, frame)
    entry.nameHandle = nameHandle
    nameHandle.goodUnitFramesOwned = true
    nameHandle:SetFrameLevel(48); nameHandle:SetAllPoints(entry.name)
    if not readonly then dragHandle(nameHandle, unit, function() return GUF.db.frames[unit].text.name end, "text", "name") end
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
        if not readonly and kind ~= "combat" and kind ~= "resting" and kind ~= "raid" and kind ~= "status" and kind ~= "resurrect" then
            dragHandle(badge, unit, function() return GUF.db.frames[unit].indicators[kind] end,
                "indicators", kind)
        end
    end
    entry.castBar = GUF.CreateCastBarPresentation(frame)
    entry.castBar.managed = true
    entry.castBar.icon:SetTexture("Interface\\Icons\\INV_Spear_07")
    if not readonly then previews[unit] = entry end
    return entry
end

GUF.CreateFrameSpecimen = create

local function showIcon(entry, kind, file, coords, dx, dy, diameter)
    if kind == "raid" or kind == "status" or kind == "resurrect" then
        GUF.PositionAutomaticBadge(entry, kind, file, coords)
        return
    end
    GUF.PositionArtisticBadge(entry, kind, kind, dx, dy, diameter, file, coords)
    entry.artisticLayout.badges[kind].previewUsed = true
end

local function render(entry, native, options)
    local unit, frame, state = entry.unit, entry.frame, entry.artisticLayout
    entry.presentationConfig = options and options.config or nil
    entry.presentationStyle = options and options.style or nil
    local cfg = GUF.PresentationFrameSettings(entry)
    local sampleState = options and options.state or GUF.configurationState or "normal"
    local showAll = options and options.showAll or not options and GUF.configurationShowAll
    local group = options and options.group or "raid"
    local function hasState(key)
        if options and options.states then return options.states[key] == true end
        return sampleState == key
    end
    local function hasGroup(key)
        if options and options.groups then return options.groups[key] == true end
        return group == key
    end
    local grouped = hasGroup("party") or hasGroup("raid")
    local artistic = (options and options.style or GUF.db.general.frameStyle) == "artistic"
    if options then state.active = artistic end
    entry.sampleState = sampleState
    entry.previewCombat = hasState("combat")
    entry.configurationShowAll = showAll
    local geometry = GUF.ArtisticPresentationGeometry(unit, options and "player" or nil,
        entry.presentationConfig, options and options.portraitSource)
    for key, value in pairs(geometry) do state[key] = value end
    state.targetComboStack = nil
    if not options and GUF.UsesComboPoints() and native and native.artisticLayout then state.noPower = native.artisticLayout.noPower end
    if options and not artistic then
        local compact = unit == "pet" or unit == "targettarget"
        local factor = compact and .7 or 1
        state.width, state.height, state.scale = 240 * factor, 80 * factor, factor
        state.portraitWidth, state.portraitHeight = 56 * factor, 56 * factor
        state.px, state.py = (unit == "target" and 194 or 46) * factor, -40 * factor
        state.barX = (unit == "target" and 8 or 88) * factor
        state.barWidth, state.housingWidth, state.housingX = 136 * factor, 136 * factor, state.barX
        state.headerTop, state.healthFillHeight, state.healthTopInset = -20 * factor, 12 * factor, factor
        state.healthRowHeight, state.powerRowHeight = 14 * factor, 14 * factor
        state.healthY, state.powerY, state.powerFillHeight = -37 * factor, -51 * factor, 12 * factor
        state.statusY, state.castAnchorBottom = -50 * factor, -80 * factor
        state.barOffset = 0
    end
    frame:SetSize(state.width, state.height)
    if not options then
        frame:ClearAllPoints()
        local effective = native and native.frame:GetEffectiveScale() or UIParent:GetEffectiveScale() * cfg.scale
        if GUF.Secret(effective) then return end
        frame:SetScale(effective / UIParent:GetEffectiveScale())
        if native then frame:SetPoint("TOPLEFT", native.frame, "TOPLEFT") else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150) end
    elseif not entry.optionsPreview or frame:GetNumPoints() == 0 then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", 0, 0)
    end
    local header = (unit == "player" or unit == "target") and cfg.artistic.playerGeometry.header or 15 * state.scale
    local healthY = options and not artistic and state.healthY or state.headerTop - header
    local powerY = healthY - state.healthRowHeight
    local powerHeight = state.powerFillHeight
    if not artistic then state.statusY = healthY - (state.healthRowHeight + state.powerRowHeight) / 2 end
    local portraitUnit = native and native.frame.unit or unit
    state.rim.source = options and options.portraitSource
        or options and GUF.SelectArtisticPortraitArtwork(unit, "player", entry.previewIdentity)
        or GUF.ArtisticPortraitArtwork(unit, portraitUnit)
    state.rim.mirrored = state.rim.source.combined and not state.rim.source.targetOnly and unit == "target" or false
    state.rim:ClearAllPoints(); state.rim:SetPoint("CENTER", frame, "TOPLEFT", state.px, state.py)
    state.rim:SetSize(state.portraitWidth, state.portraitWidth); state.rim:LayoutBorder(state.portraitWidth, state.portraitWidth)
    GUF.LayoutArtisticPortrait(entry)
    state.viewport:Show(); state.portraitFallback:Show()
    if options then portraitUnit = "player" end
    local exists = UnitExists(portraitUnit)
    if options and options.subject ~= "player" then
        state.portraitFallback:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Bear", "CLAMP", "CLAMP", "LINEAR")
        state.portraitFallback:SetTexCoord(0, 1, 0, 1)
    else
        GUF.SetArtisticPortraitTexture(state.portraitFallback, not GUF.Secret(exists) and exists and portraitUnit or "player")
    end
    local headerX, headerRight = unit == "target" and state.barX or state.px + state.barOffset, unit == "target" and state.px + state.barOffset or state.barX + state.barWidth
    state.nameStrip:ClearAllPoints(); state.nameStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, state.headerTop)
    state.nameStrip:SetSize(math.max(1, headerRight - headerX), header)
    state.nameStrip:LayoutHeader(math.max(1, headerRight - headerX), header, unit == "target", 6 * state.scale)
    state.nameStrip:SetAlpha(cfg.artistic.nameBackgroundAlpha)
    GUF.LayoutArtisticThreatName(entry)
    state.nameArea:ClearAllPoints()
    state.nameArea:SetPoint("TOPLEFT", state.nameStrip, "TOPLEFT", state.barX + 4 * state.scale - headerX, 0)
    state.nameArea:SetPoint("BOTTOMRIGHT", state.nameStrip, "BOTTOMRIGHT", state.barX + state.barWidth - 4 * state.scale - headerRight, 0)
    entry.name:ClearAllPoints(); entry.name:SetPoint("CENTER", state.nameArea, "CENTER", cfg.text.name.x, cfg.text.name.y)
    entry.name:SetFont(GUF.Font(cfg.text.name.custom and cfg.text.name.font or cfg.font), cfg.text.name.custom and cfg.text.name.size or cfg.nameSize, cfg.outline)
    entry.name:SetTextColor(.67, .9, .4); entry.name:SetJustifyH(cfg.text.name.align)
    entry.name:SetSize(math.max(1, state.barWidth - 16), header)
    if unit == "target" and artistic then
        entry.name:ClearAllPoints(); entry.name:SetWidth(0)
        entry.name:SetPoint("LEFT", state.nameArea, "LEFT", 4 * state.scale + cfg.text.name.x, cfg.text.name.y)
        entry.name:SetPoint("RIGHT", state.nameArea, "RIGHT", -4 * state.scale + cfg.text.name.x, cfg.text.name.y)
    end
    entry.name:SetText(options and options.subject ~= "player" and "Beary" or GUF.PreviewPlayerName())
    entry.name:SetText(GUF.UnitNamePart(entry.name:GetText(), cfg.nameDisplay))
    entry.name:SetShown(not cfg.hide.name)
    GUF.StylePresentationText(entry.name, cfg, cfg.text.name, cfg.text.name.custom and cfg.text.name.size or cfg.nameSize)
    if options then entry.name:SetTextColor(GUF.PreviewNameColor(entry, options.subject)) end
    entry.name:SetHeight(math.max(header, cfg.text.name.size + 4))
    state.housing:ClearAllPoints(); state.housing:SetPoint("TOPLEFT", frame, "TOPLEFT", state.housingX, healthY)
    state.housing:SetSize(state.housingWidth, state.healthRowHeight + state.powerRowHeight)
    state.housing.edgeSize = 3 * state.scale; state.housing:LayoutBorder(state.housingWidth, state.healthRowHeight + state.powerRowHeight)
    state.indicatorArea:ClearAllPoints(); state.indicatorArea:SetPoint("TOPLEFT", frame, "TOPLEFT", state.barX, healthY)
    state.indicatorArea:SetSize(state.barWidth, state.healthRowHeight + state.powerRowHeight)
    local data = { health = 5500, healthMax = 10000, healthPercent = 55, power = 100, powerMax = 100,
        powerPercent = 100, level = GUF.PreviewPlayerLevel(), name = GUF.PreviewPlayerName(), status = "" }
    if options then data.healthPercent = options.health or 55; data.health = data.healthMax * data.healthPercent / 100 end
    if sampleState == "dead" or sampleState == "ghost" or hasState("resurrect") then data.health, data.healthPercent = 0, 0 end
    data.name = entry.name:GetText()
    data.status = ({ dead = "Dead", ghost = "Ghost", offline = "Offline" })[sampleState]
        or (hasState("resurrect") and "Dead" or "")
    entry.previewData = data
    entry.previewClassification = options and options.subject
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
        if sampleState == "offline" or kind == "power" and (data.status == "Dead" or data.status == "Ghost") then
            GUF.TintPresentationBar(bar, unpack(GUF.colors.offline))
        elseif kind == "health" then GUF.TintPresentationBar(bar, .45, .65, .25)
        else GUF.TintPresentationBar(bar, .2, .42, .75) end
        local anchor = state.textAreas[kind]
        anchor:ClearAllPoints(); anchor:SetPoint("TOPLEFT", frame, "TOPLEFT", state.barX + 4 * state.scale, y)
        anchor:SetSize(state.barWidth - 8 * state.scale, height)
        data.value, data.maximum, data.percent = kind == "health" and data.health or data.power, kind == "health" and data.healthMax or data.powerMax, kind == "health" and data.healthPercent or data.powerPercent
        GUF.RenderPreviewBarText(entry, kind, data, anchor)
        for _, text in pairs(entry[kind .. "Slots"]) do text.handle:SetShown(text:IsShown()) end
    end
    GUF.LayoutArtisticBarDividers(entry)
    GUF.LayoutBarDesign(entry)
    for _, badge in pairs(state.badges) do badge.previewUsed = false end
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
    local roleSubject = unit == "player" or unit == "target" and (not options or options.subject == "player")
    if roleSubject and (grouped or showAll or enabledIndicators) then showIcon(entry, "role", "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", nil, -edge, lowerY, 18)
    GUF.SetArtisticRoleIcon(state.badges.role.icon, "DAMAGER", state.badges.role) end
    local nativeIndicators = native and GUF.AutomaticIndicatorSources(native)
    if nativeIndicators and nativeIndicators.raid and (hasGroup("raid") or showAll) then
        showIcon(entry, "raid", "Interface\\TargetingFrame\\UI-RaidTargetingIcons", { .25, .5, .25, .5 })
    end
    local socketHandled = artistic and GUF.LayoutDesignCombatStatus(entry, hasState("combat"))
    if socketHandled then
        -- The one fixed socket follows Combat even under Show all; it can
        -- never display a second resting glyph or obscure the Level number.
    elseif options and options.states then
        if unit == "player" and hasState("resting") then showIcon(entry, "resting", "Interface\\CharacterFrame\\UI-StateIcon", { 0, .5, 0, .5 }, edge, lowerY, 24) end
        if hasState("combat") or showAll then showIcon(entry, "combat", "Interface\\CharacterFrame\\UI-StateIcon", { .5, 1, 0, .5 }, edge, lowerY, 24) end
    elseif unit == "player" and sampleState ~= "combat" then
        showIcon(entry, "resting", "Interface\\CharacterFrame\\UI-StateIcon", { 0, .5, 0, .5 }, edge, lowerY, 24)
    elseif sampleState == "combat" or showAll then showIcon(entry, "combat", "Interface\\CharacterFrame\\UI-StateIcon", { .5, 1, 0, .5 }, edge, lowerY, 24) end
    -- Match stock presentation: ready/resurrection overlay a visible portrait;
    -- Dead/Ghost/Offline/Feign Death are Health text, never portrait art.
    local readyFiles = { ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
        notready = "Interface\\RaidFrame\\ReadyCheck-NotReady", waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting" }
    local file = readyFiles[sampleState]
    if file then showIcon(entry, "status", file) end
    if hasState("resurrect") then showIcon(entry, "resurrect", "Interface\\RaidFrame\\Raid-Icon-Rez") end
    for _, badge in pairs(state.badges) do if not badge.previewUsed then badge:Hide() end end
    if options and options.layoutCard then
        -- General cards show the selected layout's appearance, with no live
        -- controller/active-layout cast or aura dependencies.
        entry.castBar:Hide()
        state.housing:Show(); state.nameStrip:Show(); state.headerDivider:Show(); state.divider:Show()
        state.rim.art:Show(); state.rim.fill:SetShown(not state.rim.source.combined)
        if entry.nativeArt then entry.nativeArt:Hide() end
        frame:SetAlpha(1); frame:Show()
        return
    end
    local channeling = hasState("channel")
    local casting = hasState("casting") or channeling
    -- Interactive State is a diagnostic sample independent of live enablement.
    local selectedCast = options ~= nil and casting
    entry.previewCasting = selectedCast and true or nil
    entry.castBar:SetShown(selectedCast or (casting or showAll) and (cfg.bars.cast.enabled or showAll))
    local castWidth = state.width - 4
    if artistic and unit ~= "player" then
        castWidth = state.castRight - state.castLeft - 2 * state.castBorderInset
    elseif options and not artistic then castWidth = state.barWidth end
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
    entry.castBar.icon:ClearAllPoints()
    entry.castBar.icon:SetPoint(cfg.bars.cast.icon == "RIGHT" and "LEFT" or "RIGHT", entry.castBar, cfg.bars.cast.icon == "RIGHT" and "RIGHT" or "LEFT", cfg.bars.cast.icon == "RIGHT" and 3 or -3, 0)
    entry.castBar.icon:SetSize(16, 16)
    entry.castBar.icon:SetShown(casting and cfg.bars.cast.icon ~= "HIDE")
    if unit == "target" and (not options or artistic) then GUF.RenderConfigurationThreat(entry, options and options.previewThreat) elseif state.threatPreview then state.threatPreview:Hide() end
    if options then
        state.housing:SetShown(artistic); state.nameStrip:SetShown(artistic)
        state.headerDivider:SetShown(artistic); state.divider:SetShown(artistic)
        state.rim.art:SetShown(artistic); state.rim.fill:SetShown(artistic and not state.rim.source.combined)
        entry.nativeArt = entry.nativeArt or frame:CreateTexture(nil, "OVERLAY", nil, -1)
        entry.nativeArt:SetTexture(unit == "target" and "Interface\\TargetingFrame\\UI-TargetingFrame" or "Interface\\TargetingFrame\\UI-TargetingFrame")
        entry.nativeArt:SetSize(state.width, state.height); entry.nativeArt:ClearAllPoints(); entry.nativeArt:SetPoint("TOPLEFT")
        entry.nativeArt:SetTexCoord(unit == "target" and 0 or 1, unit == "target" and 1 or 0, 0, .78125)
        entry.nativeArt:SetShown(not artistic)
        local fading = cfg.fading
        frame:SetAlpha(fading.enabled and (hasState("combat") and fading.combat or fading.inactive) or 1)
    end
    if not options then GUF.PreviewComboPoints(entry, artistic and (showAll or GUF.ComboPointUnit() == unit or not cfg.hide.resource)) end
    frame:Show()
end

GUF.RenderFrameSpecimen = render

function GUF.RefreshConfigurationMode()
    if not GUF.configurationUnlocked or GUF.Restricted() or GUF.editing or not GUF.db then return end
    local unit = GUF.options and GUF.options.page == "units" and GUF.options.unit or GUF.configurationUnit or "player"
    if not GUF.IsManagedUnit(unit) or not GUF.db.frames[unit] then GUF.SetConfigurationMode(false); return end
    if GUF.db.general.frameStyle ~= "artistic" then
        for _, preview in pairs(previews) do preview.frame:Hide() end
        if GUF.configurationUnit then restoreVisibility(GUF.configurationUnit) end
        GUF.configurationUnit, GUF.configurationPreviewEntry = nil, nil
        GUF.SetConfigurationAuraPreview(true, unit)
        GUF.UpdateFading(0)
        return
    end
    if GUF.configurationUnit and GUF.configurationUnit ~= unit then restoreVisibility(GUF.configurationUnit) end
    GUF.configurationUnit = unit
    for name, preview in pairs(previews) do if name ~= unit then preview.frame:Hide() end end
    local entry = previews[unit] or create(unit)
    render(entry, GUF.frames[unit])
    GUF.configurationPreviewEntry = entry
    GUF.SetConfigurationAuraPreview(true, unit)
    GUF.UpdateFading(0)
    if GUF.UpdateConfigurationButton then GUF.UpdateConfigurationButton() end
end

function GUF.SetConfigurationMode(enabled)
    if enabled and (GUF.Restricted() or GUF.editing) then GUF.Print("Unlock is available outside combat and Blizzard Edit Mode."); return end
    GUF.configurationUnlocked = enabled and true or nil
    if enabled then
        GUF.configurationShowAll = GUF.configurationShowAll ~= false
        GUF.configurationState = GUF.configurationState or "normal"
        GUF.RefreshConfigurationMode()
        GUF.SetFrameMovers(true)
        GUF.Print("Frames unlocked. Drag a frame or preview element; /guf lock finishes.")
    else
        if GUF.configurationUnit then restoreVisibility(GUF.configurationUnit) end
        GUF.SetFrameMovers(false)
        GUF.SetConfigurationAuraPreview(false)
        GUF.configurationPreviewEntry = nil
        for _, preview in pairs(previews) do
            preview.frame:Hide()
            preview.nameHandle:SetScript("OnUpdate", nil); preview.nameHandle.drag = nil
            local threat = preview.artisticLayout.threatPreview
            if threat then
                threat.dragHandle:SetScript("OnUpdate", nil); threat.dragHandle.drag = nil
            end
            for _, badge in pairs(preview.artisticLayout.badges) do badge:SetScript("OnUpdate", nil); badge.drag = nil end
            for _, kind in ipairs({ "health", "power" }) do
                for _, text in pairs(preview[kind .. "Slots"]) do text.handle:SetScript("OnUpdate", nil); text.handle.drag = nil end
            end
        end
        GUF.UpdateFading(0)
        if GUF.UpdateConfigurationButton then GUF.UpdateConfigurationButton() end
    end
end
