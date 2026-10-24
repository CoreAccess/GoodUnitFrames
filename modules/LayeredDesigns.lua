local _, GUF = ...
local unpack = unpack or table.unpack
local orbitAngles = { level = 225, role = 135, leader = 90, loot = 45, pvp = 180 }
local portraitIndicators = { pvp = true, leader = true, role = true, loot = true }

function GUF.IsPortraitIndicator(kind)
    return portraitIndicators[kind] == true
end

-- Resolve the automatic size from public configuration, before Scale. The UI
-- shows this same value instead of exposing the legacy zero sentinel.
function GUF.PortraitIndicatorSize(unit, kind, config)
    local cfg = config or GUF.db.frames[unit]
    local size = cfg.indicators[kind].size
    if type(size) == "number" and size > 0 and size < math.huge then return size end
    if cfg.design and cfg.design.layered and cfg.design.layered.enabled then
        return GUF.ArtisticPortraitWidth(unit, cfg) * .28
    end
    return kind == "pvp" and 20 or 18
end

-- New paintings share one registered socket blueprint. Legacy V15 paintings
-- keep their existing Level faces until their class receives replacement art.
function GUF.PortraitLevelGeometry(source)
    local geometry = source.sockets or source
    return geometry.levelX, geometry.levelY, geometry.levelRatio
end

function GUF.LayeredOrbitAngle(unit, kind, entry)
    if kind == "level" then return unit == "target" and 315 or 225 end
    local cfg = (entry and GUF.PresentationFrameSettings(entry) or GUF.db.frames[unit]).design.layered
    local angle = cfg.angles[kind]
    if type(angle) == "number" and angle == angle and math.abs(angle) ~= math.huge then return math.max(0, math.min(360, angle)) end
    angle = orbitAngles[kind] or 90
    return unit == "target" and (180 - angle) % 360 or angle
end

function GUF.LayeredDesignSettings(unit, entry)
    if unit ~= "player" and unit ~= "target" then return end
    local cfg = entry and GUF.PresentationFrameSettings(entry) or GUF.db and GUF.db.frames[unit]
    local settings = cfg and cfg.design and cfg.design.layered
    local style = entry and entry.configurationPreview and entry.presentationStyle or GUF.db and GUF.db.general.frameStyle
    if style == "artistic" and settings and settings.enabled then return settings end
end

-- One registered complete portrait image. Reflection moves the entire finished
-- assembly to Target's outer right; live portrait content/digits stay upright.
function GUF.PlaceDesignTexture(texture, source, parent, diameter, mirrored)
    if source.targetOnly then mirrored = false end
    if source.native then
        texture.goodUnitFramesDesignFile = nil
        return GUF.PlaceBlizzardRing(texture, source, parent, diameter)
    end
    texture.goodUnitFramesBlizzardPiece = nil
    if texture.goodUnitFramesBlizzardMaskAttached then
        texture:RemoveMaskTexture(texture.goodUnitFramesBlizzardMask)
        texture.goodUnitFramesBlizzardMaskAttached = nil
    end
    local effective = parent:GetEffectiveScale()
    local canvasSize = source.canvas * diameter / source.diameter
    local pixels = not GUF.Secret(effective) and type(effective) == "number" and canvasSize * effective * 2 or 1024
    local variant = pixels <= 64 and 64 or pixels <= 128 and 128 or pixels <= 256 and 256 or pixels <= 512 and 512 or 1024
    local file = source.textureFile or source.path .. variant
    if texture.goodUnitFramesDesignFile ~= file then
        texture:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
        texture.goodUnitFramesDesignFile = file
    end
    local center = mirrored and source.canvas - source.centerX or source.centerX
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", parent, "CENTER", (source.canvas / 2 - center) * diameter / source.diameter,
        (source.centerY - source.canvas / 2) * diameter / source.diameter)
    texture:SetSize(canvasSize, canvasSize)
    texture:SetTexCoord(mirrored and 1 or 0, mirrored and 0 or 1, 0, 1)
    texture:Show()
end

local function position(entry, frame, kind)
    local state = entry.artisticLayout
    if kind ~= "level" then
        local settings = GUF.PresentationFrameSettings(entry).indicators[kind]
        local relativePoint = settings.point and settings.point ~= "DEFAULT" and settings.point or "CENTER"
        frame:ClearAllPoints()
        frame:SetPoint(settings.anchorPoint or "CENTER", state.rim, relativePoint, settings.x, settings.y)
        return
    end
    -- The fallback Level socket keeps its existing fixed placement.
    local angle = math.rad(GUF.LayeredOrbitAngle(entry.unit, kind, entry))
    local radius = state.portraitWidth / 2
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", state.rim, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function ringFace(badge, source, size, color, level)
    if level and source.native then source = GUF.BlizzardRingArtwork(source.unit, true) end
    badge.rim.source = source
    badge.rim.mirrored = false
    GUF.SetArtisticBadgeChrome(badge, true)
    -- The level's legacy smallLevel closure must not substitute its old rim.
    GUF.PlaceDesignTexture(badge.rim.art, source, badge, size, false)
    badge.rim.art:Show()
    badge.rim.chrome:SetFrameLevel(badge:GetFrameLevel() + 3)
    local opening = size * source.openingRatio
    badge.rim.fill:SetSize(opening, opening)
    badge.rim.fill:SetVertexColor(unpack(color or { .025, .025, .03, 1 }))
    badge.rim.fill:Show()
    badge.background:Hide()
end

local function releaseMask(badge)
    if badge.goodUnitFramesGlyphMaskAttached then
        badge.icon:RemoveMaskTexture(badge.goodUnitFramesGlyphMask)
        badge.goodUnitFramesGlyphMaskAttached = nil
    end
end

-- Reuse ONE existing owned badge for both states. The surrounding socket is
-- painted into the complete Portrait; neither glyph ever covers Level digits.
function GUF.LayoutDesignCombatStatus(entry, fighting)
    local state = entry.artisticLayout
    if not state or not state.active or not GUF.LayeredDesignSettings(entry.unit, entry) then return false end
    local badge = state.badges.combat
    if state.badges.resting then state.badges.resting:Hide() end
    badge.previewUsed = true
    local source = state.rim.source
    -- Only player-class portraits have designed status sockets. Selection
    -- already guards live player identity and explicit preview subjects.
    -- Return handled while hidden so neither live nor preview falls back to
    -- a loose combat/rest glyph on an NPC's native or Level-only portrait.
    if entry.unit == "target" and (not (source and source.combined) or source.creature or source.noStatus) then
        badge:Hide()
        return true
    end
    if GUF.Secret(fighting) or fighting == nil then badge:Hide(); return true end
    fighting = fighting == true or fighting == 1
    -- Use the blueprint installed with this painting. A new artwork trial must
    -- not move glyphs off the sockets in classes that still use older art.
    local geometry = source and source.sockets or GUF.portraitSocketTemplate
    local diameter = state.portraitWidth
    badge.configurationPreview = entry.configurationPreview
    badge:SetSize(diameter * geometry.statusOuterRatio, diameter * geometry.statusOuterRatio)
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", state.rim, "CENTER", diameter * geometry.statusX * (entry.unit == "target" and -1 or 1),
        diameter * geometry.statusY)
    badge:SetFrameLevel(state.rim.chrome:GetFrameLevel() + 5)
    badge:SetAlpha(1)
    releaseMask(badge)
    GUF.SetArtisticBadgeChrome(badge, false)
    badge.text:Hide()
    badge.iconSize = diameter * geometry.statusGlyphRatio
    badge.goodUnitFramesGlyphAspect = 1
    local key = fighting and "combat" or "resting"
    local applied
    if geometry.statusFaceRatio then
        applied = GUF.ApplySocketIndicatorArtwork(badge.icon, badge, key,
            diameter * geometry.statusFaceRatio * geometry.statusFill)
    else applied = GUF.ApplyIndicatorArtwork(badge, key) end
    if not applied then
        badge.icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon", "CLAMP", "CLAMP", "LINEAR")
        badge.icon:SetTexCoord(fighting and .5 or 0, fighting and 1 or .5, 0, .5)
        GUF.FitArtisticIndicatorIcon(badge, 1)
    end
    badge.icon:SetDrawLayer("OVERLAY", 2)
    badge.icon:Show(); badge:Show()
    return true
end

function GUF.StyleLayeredBadge(entry, kind, badge, file)
    badge.goodUnitFramesLayeredRing = nil
    if not GUF.LayeredDesignSettings(entry.unit, entry) or not orbitAngles[kind] or kind == "level" then releaseMask(badge); return end
    -- Read the old opening ratio only to preserve existing glyph sizes. No
    -- portrait media, circular crop, backplate or added rim surrounds an icon.
    local source = GUF.BlizzardRingArtwork(entry.unit)
    badge.configurationPreview = entry.configurationPreview
    local state, cfg = entry.artisticLayout, GUF.PresentationFrameSettings(entry)
    local settings = cfg.indicators[kind]
    local size = GUF.PortraitIndicatorSize(entry.unit, kind, cfg) * settings.scale
    badge:SetSize(size, size)
    position(entry, badge, kind)
    releaseMask(badge)
    GUF.SetArtisticBadgeChrome(badge, false)
    local completeIcon = kind == "role" or kind == "pvp" and file == "Interface\\TargetingFrame\\UI-PVP-Horde"
    local ratio = completeIcon and 1 or source.openingRatio * (kind == "pvp" and .96 or .88)
    badge.iconSize = size * ratio
    GUF.FitArtisticIndicatorIcon(badge, badge.goodUnitFramesGlyphAspect or 1)
    badge.icon:SetDrawLayer("OVERLAY", 2)
end

function GUF.HideLayeredDesign(entry)
    if GUF.HideCreatureRank then GUF.HideCreatureRank(entry) end
    local layer = entry.artisticLayout and entry.artisticLayout.layered
    if layer then layer.level:Hide() end
    for _, badge in pairs(entry.artisticLayout and entry.artisticLayout.badges or {}) do releaseMask(badge) end
end

local function publicTrue(value)
    return not GUF.Secret(value) and value == true
end

-- Match TargetFrameMixin:CheckLevel without driving any native regions.
local function targetLevelPresentation(unit, sampleLevel)
    local value = sampleLevel
    if value == nil then value = UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit) end
    local color = { r = 1, g = .82, b = 0 }
    local skull = not GUF.Secret(value) and type(value) == "number" and value <= 0
    local attackable = sampleLevel ~= nil
    if sampleLevel == nil then
        if UnitIsCorpse and publicTrue(UnitIsCorpse(unit)) then return value, color, true end
        if UnitIsWildBattlePet and publicTrue(UnitIsWildBattlePet(unit))
            or UnitIsBattlePetCompanion and publicTrue(UnitIsBattlePetCompanion(unit)) then
            return UnitBattlePetLevel(unit), color, false
        end
        attackable = publicTrue(UnitCanAttack("player", unit))
        if not skull and attackable and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer
            and GetDifficultyColor then
            local difficulty = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit)
            if not GUF.Secret(difficulty) then color = GetDifficultyColor(difficulty) end
            return value, color, skull
        end
    end
    -- Legacy clients and synthetic equal-level Target examples use Blizzard's
    -- level-based helper, never a live Target's difficulty for a specimen.
    if not skull and attackable and GetCreatureDifficultyColor and not GUF.Secret(value) and type(value) == "number" then
        local playerLevel = UnitEffectiveLevel and UnitEffectiveLevel("player") or UnitLevel("player")
        if not GUF.Secret(playerLevel) and type(playerLevel) == "number" then color = GetCreatureDifficultyColor(value) end
    end
    return value, color, skull
end

function GUF.LayoutLayeredDesign(entry, sampleLevel)
    local state = entry.artisticLayout
    local settings = GUF.LayeredDesignSettings(entry.unit, entry)
    if not state or not state.active or not settings then GUF.HideLayeredDesign(entry); return false end
    local source = state.rim.source and state.rim.source.combined and state.rim.source
    GUF.LayoutCreatureRank(entry)
    local layer = state.layered
    if not layer then
        if not entry.configurationPreview and (GUF.Restricted() or GUF.editing) then GUF.pending = true; return true end
        layer = { level = GUF.CreateArtisticBadge(state.rim) }
        -- The skull needs the same foreground parent as the digits; native
        -- fallback Level chrome has an opaque face above the rim itself.
        layer.level.icon:SetParent(layer.level.rim.chrome)
        state.layered = layer
    end
    local mirrored = entry.unit == "target" and not (source and source.targetOnly)
    local level = layer.level
    level.configurationPreview = entry.configurationPreview
    local unit = entry.frame.unit or entry.unit
    local exists = entry.configurationPreview or UnitExists(unit)
    local show = GUF.Secret(exists) or exists
    if not show then level:Hide(); return true end
    local levelX, levelY, levelRatio
    if source then levelX, levelY, levelRatio = GUF.PortraitLevelGeometry(source) end
    local size = state.portraitWidth * (levelRatio or .45)
    level:SetSize(size, size)
    level:SetFrameLevel(state.rim.chrome:GetFrameLevel() + 4)
    if source then
        -- V16 uses the shared template; unreplaced V15 classes retain their
        -- registered painted faces. Level content uses the same shared socket.
        level:ClearAllPoints()
        level:SetPoint("CENTER", state.rim, "CENTER", state.portraitWidth * levelX * (mirrored and -1 or 1),
            state.portraitWidth * levelY)
        -- All painted housing/face/ornament pixels are in state.rim.art.
        -- Only the live digits/skull are drawn above that complete image.
        GUF.SetArtisticBadgeChrome(level, false)
    else
        position(entry, level, "level")
        ringFace(level, GUF.BlizzardRingArtwork(entry.unit), size, nil, true)
    end
    local cfg = GUF.PresentationFrameSettings(entry)
    GUF.StylePresentationText(level.text, cfg, cfg.text.level, math.max(8, math.floor(size * .44 + .5)))
    level.text:ClearAllPoints(); level.text:SetPoint("CENTER", level, "CENTER")
    level.text:SetSize(0, math.max(12, size * .8))
    level.text:SetWordWrap(false); level.text:SetTextColor(1, 1, 1)
    -- Pass live/opaque level directly to the renderer; no string measurement.
    local value, skull = sampleLevel, false
    if entry.unit == "target" then
        local color
        value, color, skull = targetLevelPresentation(unit, sampleLevel)
        -- NormalizeTextEditors forces legacy customColor=true even when the
        -- user never chose a tint. Target difficulty owns this automatic color.
        level.text:SetTextColor(color.r, color.g, color.b)
    else
        if value == nil then value = UnitLevel(unit) end
        if not GUF.Secret(value) and type(value) == "number" and value < 0 then value = "??" end
    end
    if skull then
        level.text:SetText(nil); level.text:Hide()
        level.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull", "CLAMP", "CLAMP", "LINEAR")
        level.icon:SetTexCoord(0, 1, 0, 1); level.icon:SetVertexColor(1, 1, 1, 1)
        level.iconSize = size * .60
        GUF.FitArtisticIndicatorIcon(level, 1)
        level.icon:Show(); level:Show()
        return true
    end
    level.text:SetText(value)
    level.text:Show(); level.icon:Hide(); level:Show()
    return true
end
