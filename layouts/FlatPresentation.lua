local _, GUF = ...
local unpack = unpack or table.unpack

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function clamp(value, minimum, maximum, fallback)
    return number(value) and math.max(minimum, math.min(maximum, value)) or fallback
end

local function stateFor(entry)
    return entry.configurationPreview and entry.specimenState or entry.flatLayout
end

function GUF.NormalizeFlatSettings(frames)
    for _, unit in ipairs(GUF.order) do
        local cfg = frames and frames[unit]
        if cfg then
            if type(cfg.flat) ~= "table" then cfg.flat = {} end
            local flat = cfg.flat
            if flat.portrait ~= "LEFT" and flat.portrait ~= "RIGHT" and flat.portrait ~= "HIDE" then
                flat.portrait = unit == "player" and "LEFT" or "RIGHT"
            end
            flat.backgroundAlpha = clamp(flat.backgroundAlpha, 0, 1, .35)
            cfg.bars.width = clamp(cfg.bars.width, 120, 800, 280)
            cfg.bars.healthSize.height = clamp(cfg.bars.healthSize.height, 10, 160, 34)
            cfg.bars.powerSize.height = clamp(cfg.bars.powerSize.height, 5, 80, 18)
            if type(cfg.bars.cast.texture) ~= "string" or cfg.bars.cast.texture == "" then cfg.bars.cast.texture = "Flat" end
        end
    end
end

-- Public configuration only. Temporary resource/cast rows never resize the
-- secure button or change the user's chosen Health/Power/portrait dimensions.
function GUF.FlatGeometry(cfg)
    local width = clamp(cfg.bars.width, 120, 800, 280)
    local health = clamp(cfg.bars.healthSize.height, 10, 160, 34)
    local power = clamp(cfg.bars.powerSize.height, 5, 80, 18)
    local flat = cfg.flat or {}
    local height = health + power + 3
    local portrait = flat.portrait ~= "HIDE" and math.min(height - 2, math.floor(width * .4)) or 0
    local left = flat.portrait == "LEFT" and portrait + 2 or 1
    local barWidth = width - portrait - (portrait > 0 and 3 or 2)
    return { width = width, height = height, health = health, power = power,
        barX = left, barWidth = math.max(24, barWidth), portrait = portrait,
        portraitX = flat.portrait == "RIGHT" and width - portrait - 1 or 1,
        portraitY = -(height - portrait) / 2, healthY = -1, powerY = -health - 2,
        bottom = -height, scale = 1 }
end

local function place(frame, parent, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
end

local function makeBar(parent)
    local bar = GUF.Runtime.CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.goodUnitFramesFill = bar:GetStatusBarTexture()
    bar.goodUnitFramesFill.goodUnitFramesOwned = true
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background.goodUnitFramesOwned = true
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(.08, .08, .08, 1)
    return bar
end

local function geometryAllowed(entry, region)
    if entry.configurationPreview then return true end
    if GUF.editing then GUF.DeferRuntime("native-readiness"); return false end
    local forbidden = region.IsForbidden and region:IsForbidden()
    local protected = GUF.Restricted() and region.IsProtected and region:IsProtected()
    if GUF.Secret(forbidden) or forbidden or GUF.Secret(protected) or protected then
        GUF.DeferRuntime("native-readiness")
        return false
    end
    return true
end

local function makeView(entry, sample)
    local frame = entry.frame
    local state = sample and entry.specimenState or entry.flatLayout
    if state and state.created then return state end
    state = state or { hidden = {}, badges = {}, textAreas = {} }
    state.hidden, state.badges, state.textAreas = state.hidden or {}, state.badges or {}, state.textAreas or {}
    if not sample then entry.flatLayout = state end
    local view = GUF.Runtime.CreateFrame("Frame", nil, frame)
    state.view = view
    view:EnableMouse(false)
    local level = frame:GetFrameLevel()
    if not number(level) then level = 1 end
    view:SetFrameLevel(level + 6)
    state.background = view:CreateTexture(nil, "BACKGROUND")
    state.background.goodUnitFramesOwned = true
    state.background:SetAllPoints(); state.background:SetColorTexture(0, 0, 0, 1)
    state.renderBars = sample and { health = entry.health, power = entry.power }
        or { health = makeBar(view), power = makeBar(view) }
    for _, kind in ipairs({ "health", "power" }) do
        local bar = state.renderBars[kind]
        if sample then bar:SetParent(view) end
        bar:SetFrameLevel(level + 7)
        state.textAreas[kind] = state.textAreas[kind] or GUF.Runtime.CreateFrame("Frame", nil, view)
        state.textAreas[kind]:SetFrameLevel(level + 12)
    end
    state.name = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    state.name.goodUnitFramesOwned = true
    state.name:SetDrawLayer("OVERLAY", 7)
    state.name:SetWordWrap(false); state.name:SetNonSpaceWrap(false); state.name:SetMaxLines(1)
    state.nameHost = GUF.Runtime.CreateFrame("Frame", nil, view)
    state.nameHost:SetFrameLevel(level + 14)
    state.name:SetParent(state.nameHost)
    state.portraitHost = GUF.Runtime.CreateFrame("Frame", nil, view)
    state.portraitHost:EnableMouse(false)
    state.portrait = state.portraitHost:CreateTexture(nil, "ARTWORK")
    state.portrait.goodUnitFramesOwned = true
    state.portrait:SetAllPoints()
    state.indicatorLayer = GUF.Runtime.CreateFrame("Frame", nil, view)
    state.indicatorLayer:SetAllPoints(view); state.indicatorLayer:SetFrameLevel(level + 18)
    for _, kind in ipairs({ "pvp", "leader", "role", "loot", "combat", "resting", "raid", "status", "resurrect" }) do
        local badge = GUF.Runtime.CreateFrame("Frame", nil, state.indicatorLayer)
        badge:EnableMouse(false)
        badge.icon = badge:CreateTexture(nil, "ARTWORK")
        badge.icon.goodUnitFramesOwned = true
        badge.icon:SetAllPoints(); badge:Hide()
        state.badges[kind] = badge
    end
    state.created = true
    GUF.Runtime.Constructed()
    return state
end

local function layoutView(entry, cfg)
    local state, g = stateFor(entry), GUF.FlatGeometry(cfg)
    if not geometryAllowed(entry, state.view) then return false end
    for _, kind in ipairs({ "health", "power" }) do
        if not geometryAllowed(entry, state.renderBars[kind]) then return false end
    end
    state.geometry, state.scale = g, 1
    place(state.view, entry.frame, 0, 0, g.width, g.height)
    local health = state.noPower and g.health + g.power + 1 or g.health
    for _, kind in ipairs({ "health", "power" }) do
        local y, height = kind == "health" and g.healthY or g.powerY, kind == "health" and health or g.power
        local bar = state.renderBars[kind]
        place(bar, entry.frame, g.barX, y, g.barWidth, height)
        place(state.textAreas[kind], entry.frame, g.barX, y, g.barWidth, height)
        bar.background:SetColorTexture(.12, .12, .12, cfg.flat.backgroundAlpha)
    end
    state.renderBars.power:SetShown(not state.noPower)
    place(state.nameHost, entry.frame, g.barX, g.healthY, g.barWidth, health)
    state.portraitHost:SetShown(g.portrait > 0)
    if g.portrait > 0 then place(state.portraitHost, entry.frame, g.portraitX, g.portraitY, g.portrait, g.portrait) end
    if entry.predictions then entry.predictions.dirty = true end
    return true
end

-- Leases cover native artwork only. Controllers, secure scripts, aura
-- providers and foreign/dormant unit roots retain their native lifecycle.
function GUF.SuppressFlatNative(entry)
    local state = entry.flatLayout
    if not state or not state.active or state.suppressWriting then return end
    state.suppressWriting = true
    local excluded = {}
    local nativeCast = GUF.Client.ResolveCastBar(entry.unit, entry.frame)
    if nativeCast then excluded[nativeCast] = true end
    local resolved = GUF.Client.ResolveUnitFrame(entry.unit)
    for _, region in pairs(resolved and resolved.regions.resource or {}) do excluded[region] = true end
    local function collect(owner)
        if not owner or owner.goodUnitFramesOwned or excluded[owner] or GUF.IsUnmanagedUnitFrame(owner) then return end
        local forbidden = owner.IsForbidden and owner:IsForbidden()
        if GUF.Secret(forbidden) or forbidden then return end
        if owner.GetAuraContainer then
            local container = owner:GetAuraContainer()
            if container then excluded[container] = true end
        end
        local name = owner.GetName and owner:GetName() or ""
        if owner ~= entry.frame and (owner:GetObjectType() == "AuraContainer"
            or name:find("Buff", 1, true) or name:find("Debuff", 1, true)) then return end
        if owner.GetRegions then
            for _, region in pairs({ owner:GetRegions() }) do
                local kind = region:GetObjectType()
                if not region.goodUnitFramesOwned and (kind == "Texture" or kind == "FontString") then
                    state.hidden[region] = true
                    GUF.RegionAlpha(region, 0, false, "FlatLayout")
                end
            end
        end
        if owner.GetChildren then for _, child in pairs({ owner:GetChildren() }) do collect(child) end end
    end
    collect(entry.frame)
    state.suppressWriting = nil
end

function GUF.SyncFlatBar(entry, kind)
    local state = entry.flatLayout
    if not state or not state.active or state.renderWriting then return end
    state.renderWriting = true
    local unit = entry.frame.unit or entry.unit
    local cfg = GUF.Runtime.Settings("colors", entry).frames[entry.unit]
    local value, maximum, r, g, b
    if kind == "health" then
        value, maximum = UnitHealth(unit), UnitHealthMax(unit)
        r, g, b = GUF.HealthColor(unit, cfg)
    else
        local powerType = UnitPowerType(unit)
        value, maximum = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
        r, g, b = GUF.PowerColor(unit, cfg)
        -- Capacity is inspected only when public. Restricted amounts do not
        -- determine geometry or disappear by being treated as zero.
        local absent = number(maximum) and maximum <= 0
        if state.noPower ~= absent then
            local previous = state.noPower
            state.noPower = absent
            if not layoutView(entry, GUF.Runtime.Settings("layout", entry).frames[entry.unit]) then state.noPower = previous end
        end
    end
    if cfg.healthColor == "blizzard" and kind == "health" then r, g, b = GUF.BlizzardTextureColor(entry, kind) end
    if cfg.bars.powerMode == "blizzard" and kind == "power" then r, g, b = GUF.BlizzardTextureColor(entry, kind) end
    local bar = state.renderBars[kind]
    bar:SetMinMaxValues(0, maximum); bar:SetValue(value)
    GUF.TintPresentationBar(bar, r, g, b)
    bar:SetShown(kind ~= "power" or not state.noPower)
    state.renderWriting = nil
end

function GUF.RefreshFlatName(entry)
    local state = stateFor(entry)
    if not state or not state.active then return end
    local cfg = entry.configurationPreview and entry.presentationConfig or GUF.Runtime.Settings("text", entry).frames[entry.unit]
    local name, unit = entry.configurationPreview and entry.previewData.name, entry.frame.unit or entry.unit
    if not entry.configurationPreview then
        name = UnitName(unit)
        name = GUF.UnitNamePart(name, cfg.nameDisplay)
    end
    local options = cfg.text.name
    GUF.StylePresentationText(state.name, cfg, options, GUF.PresentationTextSize(cfg, "name", "flat"))
    local r, g, b
    if entry.configurationPreview then r, g, b = GUF.PreviewNameColor(entry, entry.previewClassification)
    elseif cfg.nameColor == "custom" then r, g, b = unpack(cfg.customName)
    else
        local player = UnitIsPlayer(unit)
        if cfg.nameColor == "class" and not GUF.Secret(player) and player then r, g, b = GUF.ClassColor(unit)
        else r, g, b = GUF.ReactionNameColor(unit) end
    end
    state.name:SetTextColor(r, g, b)
    state.name:ClearAllPoints()
    state.name:SetPoint("LEFT", state.nameHost, "LEFT", 4 + options.x, options.y)
    state.name:SetSize(math.max(1, state.geometry.barWidth * .46 - 8), math.max(state.geometry.health, cfg.nameSize + 4))
    state.name:SetJustifyH(options.align)
    state.name:SetText(name); state.name:Show()
end

local indicatorPoints = { pvp = "BOTTOMLEFT", leader = "TOPLEFT", role = "BOTTOMRIGHT", loot = "RIGHT",
    combat = "TOPRIGHT", resting = "TOPRIGHT", raid = "TOP", status = "CENTER", resurrect = "CENTER" }
GUF.flatIndicatorPoints = indicatorPoints

local function badge(entry, kind, file, coords, atlas)
    local state = stateFor(entry)
    local cfg = GUF.PresentationFrameSettings(entry)
    local preference = kind == "resting" and "combat" or kind
    local settings = cfg.indicators[preference] or { scale = 1, x = 0, y = 0, alpha = 1, size = 0 }
    local icon = state.badges[kind]
    if not icon or cfg.hide[preference] then return end
    local size = (settings.size and settings.size > 0 and settings.size or 18) * settings.scale
    local requested = settings.point or "DEFAULT"
    local point = requested ~= "DEFAULT" and requested or indicatorPoints[kind]
    local host = state.geometry.portrait > 0 and state.portraitHost or state.view
    if preference == "combat" then host = state.view
    else
        if settings.anchor == "bars" then host = state.nameHost end
        if settings.anchor == "frame" and requested ~= "DEFAULT" then host = state.view end
    end
    icon:ClearAllPoints(); icon:SetPoint(settings.anchorPoint or point, host, point, settings.x, settings.y)
    icon:SetSize(size, size); icon:SetAlpha(settings.alpha)
    icon.icon:SetAlpha(1)
    if atlas then icon.icon:SetTexture(nil, "CLAMP", "CLAMP", "LINEAR"); icon.icon:SetAtlas(atlas)
    else icon.icon:SetTexture(file, "CLAMP", "CLAMP", "LINEAR"); icon.icon:SetTexCoord(unpack(coords or { 0, 1, 0, 1 })) end
    icon:Show()
    return icon
end

local function nativeIcon(source, depth)
    if not source then return end
    if source.GetTexture then return source end
    local icon = source.Icon or source.icon or source.Texture or source.texture
    if icon and icon.GetTexture then return icon end
    if (depth or 0) >= 3 then return end
    if source.GetRegions then
        for _, region in pairs({ source:GetRegions() }) do if region.GetTexture and not region.goodUnitFramesOwned then return region end end
    end
    if source.GetChildren then
        for _, child in pairs({ source:GetChildren() }) do
            if not child.goodUnitFramesOwned then local found = nativeIcon(child, (depth or 0) + 1); if found then return found end end
        end
    end
end

local function mirror(entry, kind, source)
    local icon = nativeIcon(source)
    if not icon then return false end
    local shown = icon:IsVisible()
    if not GUF.Secret(shown) and not shown then return false end
    local state = entry.flatLayout
    if state and state.active then
        state.hidden[icon] = true
        GUF.RegionAlpha(icon, 0, false, "FlatLayout")
    end
    local target = badge(entry, kind)
    if not target then return false end
    if not GUF.CopyBlizzardTexture(icon, target.icon) then target:Hide(); return false end
    local alpha = GUF.alphaStates and GUF.alphaStates[icon]
    if alpha then target.icon:SetAlpha(alpha.native) else target.icon:SetAlpha(icon:GetAlpha()) end
    target:SetShown(shown)
    return true
end

local function indicators(entry, scenario)
    local state = stateFor(entry)
    for _, icon in pairs(state.badges) do icon:Hide() end
    if scenario then
        local states = scenario.states
        if states.combat then badge(entry, "combat", "Interface\\CharacterFrame\\UI-StateIcon", { .5, 1, 0, .5 })
        elseif states.resting and (entry.unit == "player" or scenario.subject == "player") then
            badge(entry, "resting", "Interface\\CharacterFrame\\UI-StateIcon", { 0, .5, 0, .5 })
        end
        if states.pvp then badge(entry, "pvp", "Interface\\TargetingFrame\\UI-PVP-Alliance", { .0625, .625, 0, .6875 }) end
        if scenario.group ~= "solo" and scenario.subject == "player" then
            badge(entry, "leader", "Interface\\GroupFrame\\UI-Group-LeaderIcon")
            badge(entry, "role", nil, nil, "UI-LFG-RoleIcon-Tank")
            badge(entry, "loot", "Interface\\GroupFrame\\UI-Group-MasterLooter")
        end
        if states.ready or states.notready or states.waiting then
            badge(entry, "status", "Interface\\RaidFrame\\ReadyCheck-" .. (states.ready and "Ready" or states.notready and "NotReady" or "Waiting"))
        end
        if states.resurrect then badge(entry, "resurrect", "Interface\\RaidFrame\\Raid-Icon-Rez") end
        return
    end
    local unit = entry.frame.unit or entry.unit
    for _, kind in ipairs({ "leader", "pvp" }) do
        for _, source in pairs(entry.regions[kind] or {}) do if mirror(entry, kind, source) then break end end
    end
    for kind, source in pairs(GUF.AutomaticIndicatorSources(entry)) do mirror(entry, kind, source) end
    local fighting
    if entry.unit == "player" then fighting = InCombatLockdown()
    else fighting = UnitAffectingCombat(unit) end
    if not GUF.Secret(fighting) and fighting then
        badge(entry, "combat", "Interface\\CharacterFrame\\UI-StateIcon", { .5, 1, 0, .5 })
    elseif not GUF.Secret(fighting) then
        -- Player and player targets share the out-of-combat status. A secret
        -- target combat state is unknown, never evidence that it is resting.
        local resting = entry.unit == "player"
        if entry.unit == "target" then
            local player = UnitIsPlayer(unit)
            resting = not GUF.Secret(player) and player
        end
        if resting then badge(entry, "resting", "Interface\\CharacterFrame\\UI-StateIcon", { 0, .5, 0, .5 }) end
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    local roles = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }
    if not GUF.Secret(role) and roles[role] then badge(entry, "role", nil, nil, roles[role]) end
    local looter = GUF.Client.MasterLooterUnit()
    if looter then
        local same = UnitIsUnit(unit, looter)
        if not GUF.Secret(same) and same then badge(entry, "loot", "Interface\\GroupFrame\\UI-Group-MasterLooter") end
    end
end

function GUF.AnchorFlatCast(entry, bar)
    local state = stateFor(entry)
    if not state or not state.active then return end
    if not geometryAllowed(entry, bar) then return true end
    local cfg = entry.configurationPreview and entry.presentationConfig or GUF.Runtime.Settings("cast", entry).frames[entry.unit]
    local g = state.geometry
    local reserve = state.resourceHeight or 0
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", g.barX + cfg.bars.cast.position.x,
        g.bottom - reserve + cfg.bars.cast.position.y)
    bar.goodUnitFramesComboCastOffset = 0
    return true
end

function GUF.LayoutFlatResources(entry)
    local state, row = stateFor(entry), entry.comboRow
    if not state or not state.active then return end
    if row and not geometryAllowed(entry, row) then return end
    local g, reserve = state.geometry, 0
    if row then
        local primary = row.displayed and row.primaryShown ~= false
        local auxiliary = row.displayed and row.auxShown
        local lanes = (primary and 1 or 0) + (auxiliary and 1 or 0)
        local height = 8
        reserve = lanes * (height + 1)
        row.baseX, row.baseY = g.barX, g.bottom - 1
        place(row, entry.frame, row.baseX, row.baseY, g.barWidth, math.max(1, reserve - 1))
        for i, slot in ipairs(row.slots) do
            slot:SetSize(g.barWidth / math.max(1, row.capacity or 5), height)
            slot:ClearAllPoints(); slot:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * g.barWidth / math.max(1, row.capacity or 5), 0)
            slot:SetShown(primary and i <= (row.capacity or 5))
        end
        if row.aux then
            place(row.aux, row, 0, primary and -height - 1 or 0, g.barWidth, height)
            row.aux:SetShown(not not auxiliary)
        end
    end
    local changed = state.resourceHeight ~= reserve
    state.resourceHeight = reserve
    if changed and entry.castBar and entry.castBar.managed then
        if entry.configurationPreview then GUF.AnchorFlatCast(entry, entry.castBar)
        else GUF.PositionCastBar(entry) end
    end
end

function GUF.FlatPresentationRole(entry, role)
    local state = stateFor(entry)
    if role == "root" then return entry.frame end
    if not state or not state.active or not state.geometry then return end
    local g = state.geometry
    local kind = role:match("^indicator:(.+)$")
    if kind then return state.badges[kind] end
    if role == "ownedBars" then return true end
    if role == "powerAbsent" then return state.noPower == true end
    if role == "health" or role == "power" then return state.renderBars[role] end
    if role == "healthAnchor" or role == "healthText" then return state.textAreas.health end
    if role == "powerAnchor" or role == "powerText" then return state.textAreas.power end
    if role == "name" then return state.nameHost end
    if role == "nameWidth" then return g.barWidth end
    if role == "auraTop" then return state.view end
    if role == "auraBottom" then return state.view end
    if role == "portrait" then return state.portraitHost end
    if role == "cast" then return entry.castBar end
    if role == "castAnchor" then return state.view end
    if role == "castStyle" then
        return { flat = true, texture = GUF.Runtime.Settings("cast", entry).frames[entry.unit].bars.cast.texture }
    end
    if role == "featureGap" or role == "castInset" or role == "auraTopGap" then return 1 end
    if role == "barMetrics" then return { width = g.barWidth, health = state.noPower and g.health + g.power + 1 or g.health, power = g.power } end
    if role == "resources" then return state.view end
    if role == "resourceGeometry" then return { scale = 1, barX = g.barX, barWidth = g.barWidth, bottom = g.bottom - 1 } end
    if role == "resourceBounds" and entry.comboRow and entry.comboRow.displayed then
        return { left = g.barX, right = g.barX + g.barWidth, top = g.height + entry.comboRow.baseY,
            bottom = g.height + entry.comboRow.baseY - (state.resourceHeight or 0) }
    end
end

function GUF.UpdateFlatState(entry)
    local state = entry.flatLayout
    if not state or not state.active then return end
    GUF.SuppressFlatNative(entry)
    GUF.SyncFlatBar(entry, "health"); GUF.SyncFlatBar(entry, "power")
    GUF.RefreshFlatName(entry)
    local unit = entry.frame.unit or entry.unit
    local exists = UnitExists(unit)
    if not GUF.Secret(exists) and not exists then return end
    if state.geometry.portrait > 0 then GUF.SetArtisticPortraitTexture(state.portrait, unit) end
    indicators(entry)
    GUF.UpdateComboPoints(entry)
end

function GUF.ApplyFlatLayout(entry)
    if GUF.Restricted() or GUF.editing then return "deferred", "restricted" end
    if not geometryAllowed(entry, entry.frame) then return "deferred", "native-root" end
    if not entry.health or not entry.power or not entry.healthText or not entry.powerText then return "unavailable", "native-bars" end
    local cfg = GUF.Runtime.Settings("layout", entry).frames[entry.unit]
    local state = makeView(entry)
    local width, height = entry.original.width, entry.original.height
    if not number(width) or not number(height) then return "deferred", "native-size" end
    local g = GUF.FlatGeometry(cfg)
    -- Native size setters can synchronously call the shared name/text hooks.
    -- Publish complete public geometry before those hooks see an active view.
    state.geometry, state.scale = g, 1
    state.active, state.rootOwned, state.restorePending, state.resourceHeight = true, true, nil, 0
    entry.layoutWriting, GUF.geometryWriting = true, true
    entry.frame:SetSize(g.width, g.height)
    entry.layoutWriting, GUF.geometryWriting = nil, nil
    if not layoutView(entry, cfg) then return "deferred", "owned-geometry" end
    state.view:Show()
    -- Shared owned text must move with its visible bar after a layout switch.
    state.textOwned = true
    entry.powerText:SetParent(state.textAreas.power)
    GUF.SuppressFlatNative(entry)
    state.featuresOwned = true
    GUF.LayoutComboPoints(entry)
    GUF.LayoutFlatResources(entry)
    GUF.UpdateFlatState(entry)
    return "applied"
end

function GUF.FlatCleanupReady(entry)
    local state = entry.flatLayout
    if not state or not (state.rootOwned or state.restorePending) then return true end
    if GUF.Restricted() or GUF.editing then return false end
    local forbidden = entry.frame.IsForbidden and entry.frame:IsForbidden()
    return not GUF.Secret(forbidden) and not forbidden
end

function GUF.ReleaseFlatLayout(entry)
    local state = entry.flatLayout
    if not state or not (state.active or state.rootOwned or state.textOwned or state.featuresOwned or next(state.hidden)) then return "released" end
    if GUF.Restricted() or GUF.editing then state.restorePending = true; return "deferred", "restricted", state end
    if not GUF.FlatCleanupReady(entry) then return "deferred", "native-root", state end
    state.active = false
    if state.featuresOwned then GUF.RestoreComboPoints(entry); state.featuresOwned = nil end
    if state.rootOwned then
        local width, height = entry.original.width, entry.original.height
        if not number(width) or not number(height) then state.restorePending = true; return "deferred", "native-size", state end
        entry.layoutWriting, GUF.geometryWriting = true, true
        entry.frame:SetSize(width, height)
        entry.layoutWriting, GUF.geometryWriting = nil, nil
        state.rootOwned = nil
    end
    local complete = true
    for region in pairs(state.hidden) do
        if GUF.RegionAlpha(region, nil, false, "FlatLayout", true) then state.hidden[region] = nil else complete = false end
    end
    if state.textOwned then
        entry.powerText:SetParent(entry.power)
        for _, text in pairs(entry.powerSlots or {}) do text:SetParent(entry.power) end
        state.textOwned = nil
    end
    state.view:Hide()
    state.restorePending = not complete or nil
    if complete then return "released" end
    return "restoring", "native-alpha", state
end

function GUF.FinalizeFlatLayout(entry)
    local state = entry.flatLayout
    if not state or not state.active then return end
    GUF.UpdateFlatState(entry)
end

function GUF.FlatNativeOriginal(entry, region)
    local state = entry.flatLayout
    if not state or not state.rootOwned then return end
    if not region then return { active = true } end
    if region == entry.frame then return { geometry = { width = entry.original.width, height = entry.original.height, points = {} } } end
    -- Root resizing can synchronously lay out native children. The existing
    -- guarded capture records retain their native baseline for Blizzard cards.
    for _, saved in ipairs(entry.sizeRegions or {}) do
        if saved.region == region then
            return { geometry = { width = saved.width, height = saved.height, points = saved.points }, parent = region:GetParent() }
        end
    end
end

function GUF.RefreshFlatNativeGeometry(entry, region)
    local state = entry.flatLayout
    if not state or region ~= entry.frame then return false end
    if state.active and not entry.layoutWriting then return false, true end
    if state.restorePending then return false, GUF.FlatCleanupReady(entry), "cleanup" end
    return false
end

-- Fit the window to public wrapper rectangles, never animated cooldown
-- internals, changing aura timer glyphs or progress-fill textures. A saved setup has
-- the same bounds on every editor tab, including its first presentation.
function GUF.FlatPresentationBounds(context)
    local entry, cfg = context.view, context.settings.frames[context.unit]
    local g = GUF.FlatGeometry(cfg)
    local bounds = { left = 0, right = g.width, top = 0, bottom = -g.height }
    if context.mode == "live" then return bounds end
    local function include(region)
        if not region or not region:IsShown() then return end
        local rect = GUF.FrameRectInUnit(entry, region)
        if not rect then return end
        bounds.left, bounds.right = math.min(bounds.left, rect.left), math.max(bounds.right, rect.right)
        bounds.top = math.max(bounds.top, rect.top - g.height)
        bounds.bottom = math.min(bounds.bottom, rect.bottom - g.height)
    end
    local state = entry.specimenState
    include(state.name)
    for _, badge in pairs(state.badges) do include(badge) end
    for _, kind in ipairs({ "health", "power" }) do
        for _, text in pairs(entry[kind .. "Slots"]) do include(text) end
    end
    if entry.castBar:IsShown() then
        include(entry.castBar); include(entry.castBar.name); include(entry.castBar.time)
    end
    if entry.comboRow and entry.comboRow.displayed then include(entry.comboRow) end
    for _, host in pairs(entry.auraSamples or {}) do
        if host.previewUsed then include(host.frame) end
    end
    if entry.combatText and entry.combatText.feedbackPreview then include(entry.combatText.previewBounds) end
    return bounds
end

function GUF.CreateFlatSpecimen(unit, parent)
    local entry = GUF.CreateSpecimenBase(unit, parent, "flat")
    makeView(entry, true)
    entry.name:Hide()
    return entry
end

function GUF.RenderFlatSample(entry, scenario)
    local state, cfg = entry.specimenState, entry.presentationConfig
    state.active, state.noPower = true, false
    layoutView(entry, cfg)
    local g = state.geometry
    entry.frame:SetSize(g.width, g.height)
    for _, kind in ipairs({ "health", "power" }) do
        local bar = entry[kind]
        bar:SetStatusBarTexture(GUF.MediaTexture(cfg.bars[kind .. "Texture"]) or "Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetMinMaxValues(0, kind == "health" and entry.previewData.healthMax or entry.previewData.powerMax)
        bar:SetValue(kind == "health" and entry.previewData.health or entry.previewData.power)
        local data = entry.previewData
        data.value, data.maximum, data.percent = kind == "health" and data.health or data.power,
            kind == "health" and data.healthMax or data.powerMax, kind == "health" and data.healthPercent or data.powerPercent
        GUF.RenderPreviewBarText(entry, kind, data, state.textAreas[kind])
    end
    if scenario.subject ~= "player" then
        state.portrait:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Bear", "CLAMP", "CLAMP", "LINEAR")
        state.portrait:SetTexCoord(.07, .93, .07, .93)
    else GUF.SetArtisticPortraitTexture(state.portrait, "player") end
    GUF.RefreshFlatName(entry)
    indicators(entry, scenario)
    local casting = not scenario.layoutCard and cfg.bars.cast.enabled and (scenario.states.casting or scenario.states.channel)
    local cast = entry.castBar
    GUF.StyleCastBarPresentation(cast, { flat = true, texture = cfg.bars.cast.texture }, scenario.states.channel)
    cast:SetSize(g.barWidth, cfg.bars.cast.height); cast.layoutHeight = cfg.bars.cast.height
    GUF.AnchorFlatCast(entry, cast)
    GUF.PositionCastIcon(entry, cast)
    cast:SetMinMaxValues(0, 1); cast:SetValue(.65)
    cast.name:SetText(scenario.states.channel and "Channeling" or "Aimed Shot"); cast.time:SetText("2.1")
    cast.icon:SetTexture(scenario.states.channel and "Interface\\Icons\\Spell_Nature_HealingWaveGreater" or "Interface\\Icons\\INV_Spear_07")
    GUF.LayoutCastLabels(entry, cast, cast.name, cast.time)
    cast.icon:SetShown(casting and cfg.bars.cast.icon ~= "HIDE")
    cast.spark:SetShown(not not casting); cast:SetShown(not not casting)
    entry.frame:SetAlpha(scenario.layoutCard and 1 or cfg.fading.enabled and (scenario.states.combat and cfg.fading.combat or cfg.fading.inactive) or 1)
    entry.frame:Show()
    return "applied"
end

function GUF.FlatLayoutCard(parent, entry)
    entry = entry or GUF.CreateFrameSpecimen("player", parent, "flat")
    entry.frame:SetParent(parent)
    GUF.RenderFrameSpecimen(entry, nil, { style = "flat", layoutCard = true, state = "resting", subject = "player", health = 55 })
    GUF.Presentation.FitCard(entry, parent, 12)
    return entry
end
