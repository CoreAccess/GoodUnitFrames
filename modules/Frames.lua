local _, GUF = ...
-- Feature module for the existing Blizzard unit frames.
local unpack = unpack or table.unpack

local function path(root, ...)
    for i = 1, select("#", ...) do
        if not root then return nil end
        root = root[select(i, ...)]
    end
    return root
end

function GUF.Resolve(unit)
    if not GUF.IsManagedUnit(unit) then return end
    local frame
    if unit == "player" then frame = PlayerFrame
    elseif unit == "target" then frame = TargetFrame end
    if not frame then return end
    local player = unit == "player"
    local main = player and path(frame, "PlayerFrameContent", "PlayerFrameContentMain")
        or path(frame, "TargetFrameContent", "TargetFrameContentMain") or frame
    local context = player and path(frame, "PlayerFrameContent", "PlayerFrameContentContextual")
        or path(frame, "TargetFrameContent", "TargetFrameContentContextual") or frame
    local container = frame.PlayerFrameContainer or frame.TargetFrameContainer or frame
    local healthArea = main.HealthBarsContainer or main
    local health = healthArea.HealthBar or frame.healthbar or frame.HealthBar or _G[frame:GetName() .. "HealthBar"]
    local power = path(main, "ManaBarArea", "ManaBar") or main.ManaBar or frame.manabar or frame.ManaBar
        or _G[frame:GetName() .. "ManaBar"]
    local name = frame.name or main.Name or frame.Name or (player and PlayerName) or _G[frame:GetName() .. "Name"]
    local priestMana = false
    if player and GUF.isRetail then
        local _, class = UnitClass("player")
        priestMana = not GUF.Secret(class) and class == "PRIEST"
    end
    return {
        frame = frame, unit = unit, health = health, power = power, name = name,
        nameBackground = main.ReputationColor or frame.ReputationColor or frame.nameBackground
            or _G[frame:GetName() .. "NameBackground"],
        healthArea = healthArea, main = main, context = context,
        feedbackRegions = { path(main, "HitIndicator", "HitText"), path(frame, "HitIndicator", "HitText"),
            frame.feedbackText, unit == "pet" and PetHitIndicator or nil },
        regions = {
            level = { main.LevelText, player and PlayerLevelText or frame.LevelText,
                main.LevelBackgroundCircle, context.HighLevelTexture },
            pvp = { context.PVPIcon, context.PvpIcon, context.PrestigePortrait, context.PrestigeBadge,
                main.PvpBackgroundCircle, main.PvpBackgroundIcon, context.PvpBackgroundCircle, context.PvpBackgroundIcon,
                frame.pvpIcon, player and PlayerPVPIcon or nil, unit == "pet" and PetPVPIcon or nil },
            leader = { context.LeaderIcon, context.GuideIcon, context.GroupIndicator, frame.leaderIcon,
                player and PlayerLeaderIcon or nil },
            combat = { main.StatusTexture, container.FrameFlash, container.Flash, frame.statusTexture,
                context.AttackIcon, frame.AttackIcon, player and PlayerAttackIcon or nil },
            resting = { context.PlayerRestIcon, context.PlayerRestLoop, player and PlayerRestIcon or nil },
            resource = player and { RogueComboPointBarFrame, DruidComboPointBarFrame, ComboFrame,
                PaladinPowerBarFrame, RuneFrame, WarlockPowerFrame, MageArcaneChargesFrame,
                MonkHarmonyBarFrame, EssencePlayerFrame, GUF.isRetail and DemonHunterSoulFragmentsBar or nil,
                GUF.isRetail and MonkStaggerBar or nil, GUF.isRetail and EvokerEbonMightBar or nil,
                priestMana and AlternatePowerBar or nil, priestMana and InsanityBarFrame or nil } or {},
        },
    }
end

-- Native attachments remain read-only anchor targets for existing saved Player
-- or Target positions. Resolving them here never creates a managed entry.
function GUF.AnchorFrame(unit)
    if unit == "pet" then return PetFrame end
    if unit == "targettarget" then return TargetFrameToT or (TargetFrame and TargetFrame.totFrame) end
    local resolved = GUF.Resolve(unit)
    return resolved and resolved.frame
end

function GUF.IsUnmanagedUnitFrame(frame)
    return frame and (frame == PetFrame or frame == TargetFrameToT or frame == (TargetFrame and TargetFrame.totFrame))
end

function GUF.PlayerRoleRegions(entry)
    if entry.unit ~= "player" then return end
    local frame, main, context = entry.frame, entry.main, entry.context
    local container = frame.PlayerFrameContainer or frame
    local role = context.RoleIcon or main.RoleIcon or context.GroupRoleIcon
        or frame.RoleIcon or frame.roleIcon or PlayerRoleIcon
    local portrait = container.PlayerPortrait or container.Portrait or frame.portrait or frame.Portrait or PlayerPortrait
    return role, portrait
end

-- Shared default for the native Player role and its owned specimen copy.
function GUF.PlayerRolePoints(portrait)
    return { { "CENTER", portrait, "BOTTOM", 0, 0 } }
end

function GUF.ClassColor(unit)
    local class
    if UnitClassBase then class = UnitClassBase(unit)
    else
        local _, token = UnitClass(unit)
        class = token
    end
    if C_ClassColor and C_ClassColor.GetClassColor and (GUF.Secret(class) or class ~= nil) then
        local color = C_ClassColor.GetClassColor(class)
        if color then return color:GetRGB() end
    end
    if not GUF.Secret(class) and class then
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        color = GUF.classColors[class]
        if color then return unpack(color) end
    end
    return unpack(GUF.colors.friendly)
end

function GUF.ReactionColor(unit)
    if UnitIsFriend(unit, "player") then return unpack(GUF.colors.friendly) end
    if UnitIsEnemy(unit, "player") then return unpack(GUF.colors.hostile) end
    return unpack(GUF.colors.neutral)
end

local function npcTapDenied(unit)
    local player = UnitIsPlayer(unit)
    if GUF.Secret(player) or player or not UnitIsTapDenied then return false end
    local denied = UnitIsTapDenied(unit)
    return not GUF.Secret(denied) and denied == true
end

local function publicThreatMembership(member, unit)
    if not UnitDetailedThreatSituation then return false end
    local tanking, status = UnitDetailedThreatSituation(member, unit)
    if not GUF.Secret(tanking) and tanking == true then return true end
    return not GUF.Secret(status) and type(status) == "number" and status >= 0
end

local function npcEngagedWithGroup(unit)
    if GUF.Secret(unit) or type(unit) ~= "string" then return false end
    local attackable = UnitCanAttack("player", unit)
    local unitCombat = UnitAffectingCombat(unit)
    if GUF.Secret(attackable) or not attackable
        or GUF.Secret(unitCombat) or not unitCombat then return false end
    -- The pet/group can be fighting before the player enters combat. Require
    -- a relationship to this NPC, not the player's unrelated combat flag.
    local victim = unit .. "target"
    if UnitIsUnit then
        for _, member in ipairs({ "player", "pet" }) do
            local attacking = UnitIsUnit(victim, member)
            if not GUF.Secret(attacking) and attacking then return true end
        end
    end
    if UnitPlayerOrPetInParty then
        local party = UnitPlayerOrPetInParty(victim)
        if not GUF.Secret(party) and party then return true end
    end
    if UnitPlayerOrPetInRaid then
        local raid = UnitPlayerOrPetInRaid(victim)
        if not GUF.Secret(raid) and raid then return true end
    end
    -- Threat membership also covers casting or a temporarily missing victim.
    -- Never inspect percentages, amounts or secret identities/status values.
    if publicThreatMembership("player", unit) or publicThreatMembership("pet", unit) then return true end
    local raid = IsInRaid and IsInRaid()
    if GUF.Secret(raid) then return false end
    local count, prefix, petPrefix, limit
    if raid then
        count = GetNumGroupMembers and GetNumGroupMembers()
        prefix, petPrefix, limit = "raid", "raidpet", 40
    else
        count = GetNumSubgroupMembers and GetNumSubgroupMembers()
        prefix, petPrefix, limit = "party", "partypet", 4
    end
    if GUF.Secret(count) or type(count) ~= "number" then return false end
    for index = 1, math.min(count, limit) do
        if publicThreatMembership(prefix .. index, unit)
            or publicThreatMembership(petPrefix .. index, unit) then return true end
    end
    return false
end

function GUF.ReactionNameColor(unit)
    if npcTapDenied(unit) then return unpack(GUF.colors.tapped) end
    local friendly = UnitIsFriend(unit, "player")
    if not GUF.Secret(friendly) and friendly then return unpack(GUF.colors.friendly) end
    local player = UnitIsPlayer(unit)
    local enemy = UnitIsEnemy(unit, "player")
    if not GUF.Secret(enemy) and enemy then
        if not GUF.Secret(player) and not player then return unpack(GUF.npcHostileNameColor) end
        return unpack(GUF.colors.hostile)
    end
    if not GUF.Secret(player) and not player and npcEngagedWithGroup(unit) then
        return unpack(GUF.npcHostileNameColor)
    end
    return unpack(GUF.colors.neutral)
end

function GUF.NPCHealthColor(unit)
    -- Preserve Dino's palette, with hostile red for actual group engagement.
    -- Attackability or unrelated combat alone must not turn a neutral red.
    local reaction = UnitReaction(unit, "player")
    if not GUF.Secret(reaction) and type(reaction) == "number" then
        if reaction > 4 then return unpack(GUF.npcHealthColors.friendly) end
        if reaction == 4 then
            if npcEngagedWithGroup(unit) then return unpack(GUF.npcHealthColors.hostile) end
            return unpack(GUF.npcHealthColors.neutral)
        end
        return unpack(GUF.npcHealthColors.hostile)
    end
    -- Restricted/unknown reaction must not be compared or used as a table key.
    local friendly = UnitIsFriend(unit, "player")
    if not GUF.Secret(friendly) and friendly then return unpack(GUF.npcHealthColors.friendly) end
    if npcEngagedWithGroup(unit) then return unpack(GUF.npcHealthColors.hostile) end
    return unpack(GUF.npcHealthColors.neutral)
end

local healthCurve
function GUF.UnitOffline(unit)
    if not UnitIsConnected then return false end
    local connected = UnitIsConnected(unit)
    return not GUF.Secret(connected) and connected == false
end

function GUF.UnitHealthStatus(unit)
    if GUF.UnitOffline(unit) then return "Offline" end
    local ghost = UnitIsGhost(unit)
    if not GUF.Secret(ghost) and ghost then return "Ghost" end
    local dead = UnitIsDead(unit)
    if not GUF.Secret(dead) and dead then return "Dead" end
end

function GUF.HealthColor(unit, cfg)
    if GUF.UnitOffline(unit) then return unpack(GUF.colors.offline) end
    if npcTapDenied(unit) then return unpack(GUF.colors.tapped) end
    if cfg.healthColor == "static" then return unpack(cfg.customHealth) end
    if cfg.healthColor == "percent" then
        if UnitHealthPercent and C_CurveUtil and C_CurveUtil.CreateColorCurve then
            if not healthCurve then
                healthCurve = C_CurveUtil.CreateColorCurve()
                healthCurve:AddPoint(0, CreateColor(.90, 0, 0))
                healthCurve:AddPoint(.5, CreateColor(.93, .93, 0))
                healthCurve:AddPoint(1, CreateColor(.20, .90, .20))
            end
            local color = UnitHealthPercent(unit, true, healthCurve)
            return color:GetRGB()
        end
        local health, maximum = UnitHealth(unit), UnitHealthMax(unit)
        if not GUF.Secret(health) and not GUF.Secret(maximum) and maximum > 0 then
            local ratio = math.max(0, math.min(1, health / maximum))
            return math.min(1, 2 * (1 - ratio)), math.min(1, 2 * ratio), 0
        end
    end
    if UnitIsPlayer(unit) then return GUF.ClassColor(unit) end
    if unit == "pet" then return GUF.ClassColor("player") end
    -- Class mode keeps class colors for players and reaction colors for NPCs.
    if cfg.healthColor == "class" then return GUF.NPCHealthColor(unit) end
    if npcEngagedWithGroup(unit) then return unpack(GUF.colors.hostile) end
    return GUF.ReactionColor(unit)
end

-- Keep each cosmetic alpha through Blizzard updates; remember its latest native value for restoration.
local function regionAlphaValue(state)
    if state.override == nil then return state.native end
    if state.relative then
        if GUF.Secret(state.native) then return state.native end
        return state.native * state.override
    end
    return state.override
end

function GUF.RegionAlpha(region, alpha, relative)
    if not region or not region.SetAlpha then return end
    if not GUF.alphaStates then GUF.alphaStates = {} end
    local state = GUF.alphaStates[region]
    if not state then
        state = { native = region:GetAlpha() }
        GUF.alphaStates[region] = state
        hooksecurefunc(region, "SetAlpha", function(self, native)
            if state.writing then return end
            state.native = native
            if state.override ~= nil then
                state.writing = true
                self:SetAlpha(regionAlphaValue(state))
                state.writing = nil
            end
        end)
    end
    state.override, state.relative, state.writing = alpha, relative, true
    region:SetAlpha(regionAlphaValue(state))
    state.writing = nil
end

local function nativeTexts(entry, kind)
    local bar = entry[kind]
    if not bar then return {} end
    local area = kind == "health" and entry.healthArea or bar
    return { area.HealthBarText, area.ManaBarText, area.TextString, area.LeftText, area.RightText,
        bar.TextString, bar.HealthBarText, bar.ManaBarText, bar.LeftText, bar.RightText }
end
GUF.NativeTexts = nativeTexts

function GUF.NativeHealthStatusTexts(entry)
    local area, bar = entry.healthArea or entry.health, entry.health
    if not area or not bar then return {} end
    return { area.DeadText, area.UnconsciousText, bar.DeadText, bar.UnconsciousText }
end

local function setBarDesaturation(entry, kind, desaturated)
    local bar = entry[kind]
    if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(desaturated)
    else
        local texture = bar:GetStatusBarTexture()
        if texture and texture.SetDesaturated then texture:SetDesaturated(desaturated) end
    end
end

local function setHealthDesaturation(entry, desaturated)
    setBarDesaturation(entry, "health", desaturated)
end

function GUF.PowerColor(unit, cfg)
    if GUF.UnitHealthStatus(unit) then return unpack(GUF.colors.offline) end
    if cfg.bars.powerMode == "class" then return GUF.ClassColor(unit == "pet" and "player" or unit) end
    local id, token, r, g, b = UnitPowerType(unit)
    local color = not GUF.Secret(token) and GUF.powerColors[token]
    local native = not GUF.Secret(id) and PowerBarColor and PowerBarColor[id]
    if color then return unpack(color) end
    if native then return native.r, native.g, native.b end
    return r, g, b
end

-- Stock atlases can carry green/Power-type color with a neutral white tint.
-- Translate that presentation for replacement media, never for owned Target
-- bars (those keep their independent unit-data/color path).
function GUF.BlizzardTextureColor(entry, kind)
    if kind == "power" and GUF.UnitHealthStatus(entry.frame.unit or entry.unit) then return unpack(GUF.colors.offline) end
    local color = entry.original[kind .. "Color"]
    if color then
        local r, g, b = color[1], color[2], color[3]
        if GUF.Secret(r) or GUF.Secret(g) or GUF.Secret(b) then return r, g, b end
        if type(r) == "number" and type(g) == "number" and type(b) == "number"
            and (r ~= 1 or g ~= 1 or b ~= 1) then return r, g, b end
    end
    local desaturated = entry.original[kind .. "Desaturated"]
    if not GUF.Secret(desaturated) and desaturated == true then return unpack(GUF.colors.offline) end
    if kind == "health" then return 0, 1, 0 end
    local unit = entry.frame.unit or entry.unit
    local id, token, r, g, b = UnitPowerType(unit)
    local native = PowerBarColor and (not GUF.Secret(token) and PowerBarColor[token]
        or not GUF.Secret(id) and PowerBarColor[id])
    if native then return native.r, native.g, native.b end
    return r, g, b
end

local function tintBlizzardTexture(entry, kind)
    if not entry[kind] then return end
    local state = entry.barStyles and entry.barStyles[kind]
    local guard = kind == "health" and "coloring" or "powerColoring"
    local inactive = kind == "power" and GUF.UnitHealthStatus(entry.frame.unit or entry.unit) ~= nil
    local restoring = kind == "power" and entry.inactivePowerTint
    local owned = state and state.owned
    if entry[guard] or not owned and not inactive and not restoring then return end
    local r, g, b = GUF.BlizzardTextureColor(entry, kind)
    local desaturated = true
    if not owned and not inactive and restoring then
        r, g, b = unpack(entry.original.powerColor)
        desaturated = entry.original.powerDesaturated
    end
    if GUF.Secret(r) or r ~= nil then
        entry[guard] = true
        setBarDesaturation(entry, kind, desaturated)
        entry[kind]:SetStatusBarColor(r, g, b, 1)
        entry[guard] = nil
        if kind == "power" then entry.inactivePowerTint = inactive or nil end
    end
end

function GUF.QueueTargetColorRefresh(entry)
    if entry.unit ~= "target" or entry.targetColorQueued or GUF.db.general.frameStyle ~= "blizzard" then return end
    entry.targetColorQueued = true
    C_Timer.After(0, function()
        entry.targetColorQueued = nil
        if GUF.db.general.frameStyle ~= "blizzard" or GUF.editing then return end
        local artistic = entry.artisticLayout
        if artistic and artistic.active and artistic.renderBars then return end
        -- Native retarget/classification work can finish after our unit event.
        -- Refresh tint only from the current unit, never native values/geometry.
        GUF.UpdateColors(entry)
    end)
end

function GUF.UpdateColors(entry)
    local cfg = GUF.db.frames[entry.unit]
    if not UnitExists(entry.unit) then return end
    local unit = entry.frame.unit or entry.unit
    local artistic = entry.artisticLayout
    local rendered = artistic and artistic.active and artistic.renderBars
    if cfg.bars.powerMode ~= "blizzard" then entry.inactivePowerTint = nil end
    if rendered then
        GUF.SyncArtisticRenderedBar(entry, "health")
        GUF.SyncArtisticRenderedBar(entry, "power")
    else
        if cfg.healthColor == "blizzard" then tintBlizzardTexture(entry, "health") end
        if cfg.bars.powerMode == "blizzard" then tintBlizzardTexture(entry, "power") end
    end
    if entry.health and cfg.healthColor ~= "blizzard" and not entry.coloring and not rendered then
        local r, g, b = GUF.HealthColor(unit, cfg)
        if GUF.Secret(r) or r ~= nil then
            entry.coloring = true
            -- Neutralize baked green before applying the selected tint, including
            -- NPC reaction colors used by Class mode.
            setHealthDesaturation(entry, true)
            entry.health:SetStatusBarColor(r, g, b, 1)
            entry.coloring = nil
        end
    end
    if entry.power and cfg.bars.powerMode ~= "blizzard" and not entry.powerColoring and not rendered then
        local r, g, b = GUF.PowerColor(unit, cfg)
        if GUF.Secret(r) or r ~= nil then
            entry.powerColoring = true
            setBarDesaturation(entry, "power", true)
            entry.power:SetStatusBarColor(r, g, b, 1)
            entry.powerColoring = nil
        end
    end
    if entry.name and not entry.nameColoring then
        local r, g, b
        if cfg.nameColor == "custom" then r, g, b = unpack(cfg.customName)
        elseif cfg.nameColor == "class" and UnitIsPlayer(unit) then r, g, b = GUF.ClassColor(unit)
        else r, g, b = GUF.ReactionNameColor(unit) end
        entry.nameColoring = true
        entry.name:SetTextColor(r, g, b)
        entry.nameColoring = nil
    end
end

function GUF.ApplyPosition(entry)
    if InCombatLockdown() or GUF.editing or entry.editPositionPending or entry.positionWriting then return end
    local cfg, frame = GUF.db.frames[entry.unit], entry.frame
    if not entry.original.points or entry.positionCapturePending then
        local points = GUF.ReadPoints(frame)
        if not points then GUF.pending = true; return end
        entry.original.points, entry.positionCapturePending = points, nil
    end
    entry.positionWriting = true
    if cfg.position.enabled then
        local anchor = cfg.position.anchorTo
        local allowed = GUF.CanAnchor(entry.unit, anchor)
        if allowed == nil then entry.positionWriting = nil; GUF.pending = true; return end
        if not allowed then anchor = "UIParent"; cfg.position.anchorTo = anchor end
        local relative = anchor == "UIParent" and UIParent or GUF.AnchorFrame(anchor)
        local frameScale, screenScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if GUF.Secret(frameScale) or GUF.Secret(screenScale) or frameScale <= 0 then entry.positionWriting = nil; return end
        frame:ClearAllPoints()
        local coordinateScale = screenScale / frameScale
        frame:SetPoint(cfg.position.point, relative, cfg.position.relativePoint, cfg.position.x * coordinateScale, cfg.position.y * coordinateScale)
        entry.positionOwned = true
    elseif entry.unit == "pet" and GUF.db.general.frameStyle == "artistic"
        and GUF.frames.player and GUF.CanAnchor("pet", "player") == true then
        local frameScale, screenScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if GUF.Secret(frameScale) or GUF.Secret(screenScale) or frameScale <= 0 then entry.positionWriting = nil; return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", GUF.frames.player.frame, "BOTTOMLEFT", 0,
            -GUF.ArtisticPetOffset() * GUF.db.frames.player.scale * screenScale / frameScale)
        entry.positionOwned = true
    elseif entry.positionOwned then
        frame:ClearAllPoints()
        for _, point in ipairs(entry.original.points) do frame:SetPoint(unpack(point)) end
        entry.positionOwned = nil
    end
    entry.positionWriting = nil
end

local function makeEntry(unit)
    local entry = GUF.Resolve(unit)
    if not entry then return end
    local frame = entry.frame
    entry.original = { points = GUF.ReadPoints(frame), width = frame:GetWidth(), height = frame:GetHeight() }
    if entry.name then
        entry.original.nameColor = { entry.name:GetTextColor() }
        if unit ~= "pet" then
            entry.original.nameText = entry.name:GetText()
            local function nativeNameChanged()
                if entry.nameWriting then return end
                entry.original.nameText = entry.name:GetText()
                GUF.UpdateUnitName(entry)
            end
            hooksecurefunc(entry.name, "SetText", nativeNameChanged)
            hooksecurefunc(entry.name, "SetFormattedText", nativeNameChanged)
        end
        hooksecurefunc(entry.name, "SetTextColor", function()
            if not entry.nameColoring then
                entry.original.nameColor = { entry.name:GetTextColor() }
                GUF.UpdateColors(entry)
            end
        end)
    end
    for _, kind in ipairs({ "health", "power" }) do
        local bar = entry[kind]
        if bar then
            entry.original[kind .. "Color"] = { bar:GetStatusBarColor() }
            if kind == "health" then
                local texture = bar:GetStatusBarTexture()
                entry.original.healthDesaturated = texture and texture.IsDesaturated and texture:IsDesaturated() or false
                if bar.SetStatusBarDesaturated then
                    hooksecurefunc(bar, "SetStatusBarDesaturated", function(_, desaturated)
                        if entry.coloring then return end
                        entry.original.healthDesaturated = desaturated
                        GUF.UpdateColors(entry)
                    end)
                end
            else
                local texture = bar:GetStatusBarTexture()
                entry.original.powerDesaturated = texture and texture.IsDesaturated and texture:IsDesaturated() or false
                if bar.SetStatusBarDesaturated then
                    hooksecurefunc(bar, "SetStatusBarDesaturated", function(_, desaturated)
                        if entry.powerColoring then return end
                        entry.original.powerDesaturated = desaturated
                        GUF.UpdateColors(entry)
                    end)
                end
            end
            entry[kind .. "Text"] = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            entry[kind .. "Text"].goodUnitFramesOwned = true
            entry[kind .. "Text"]:SetPoint("CENTER", bar, "CENTER")
            entry[kind .. "Text"]:SetDrawLayer("OVERLAY", 7)
            hooksecurefunc(bar, "SetStatusBarColor", function()
                if not entry.coloring and not entry.powerColoring then
                    entry.original[kind .. "Color"] = { bar:GetStatusBarColor() }
                    GUF.UpdateColors(entry)
                end
            end)
            if bar.HookScript then
                bar:HookScript("OnValueChanged", function() GUF.UpdateBarText(entry, kind) end)
            end
        end
    end
    hooksecurefunc(frame, "SetPoint", function()
        if entry.scaleWriting then return end
        if not entry.positionWriting and (not entry.positionOwned or GUF.editing or entry.editPositionPending) then
            local points = GUF.ReadPoints(frame)
            if points then entry.original.points, entry.positionCapturePending = points, nil
            else entry.positionCapturePending = true end
        end
        GUF.ApplyPosition(entry)
    end)
    frame:HookScript("OnShow", function()
        GUF.UpdateColors(entry)
        GUF.UpdateUnitName(entry)
        GUF.UpdateBarText(entry, "health")
        GUF.UpdateBarText(entry, "power")
        GUF.ApplyPosition(entry)
        if entry.sizeOwned or (entry.artisticLayout and entry.artisticLayout.active) then GUF.pending = true end
    end)
    GUF.CaptureSize(entry)
    GUF.CaptureBlizzardArtwork(entry)
    return entry
end

function GUF.ApplyFrames()
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit] or makeEntry(unit)
        GUF.frames[unit] = entry
        if entry then
            local cfg, original = GUF.db.frames[unit], entry.original
            GUF.ApplyFrameScale(entry)
            GUF.ApplyPosition(entry)
            GUF.CaptureText(entry)
            -- Restore the previous skin before capturing/placing the next one.
            local style = GUF.db.general.frameStyle
            if style ~= "blizzard" then GUF.ReleaseBlizzardPlayerRole(entry) end
            if style ~= "artistic" then GUF.ApplyArtisticLayout(entry) end
            GUF.ApplySize(entry)
            if style == "artistic" then GUF.ApplyArtisticLayout(entry) end
            GUF.ApplyArtwork(entry)
            GUF.ApplyCombatText(entry)
            GUF.ApplyBars(entry)
            GUF.ApplyPredictionBars(entry)
            GUF.ApplyCastBar(entry)
            GUF.ApplyText(entry)
            GUF.FinalizeArtisticLayout(entry)
            if cfg.healthColor == "blizzard" then
                if entry.health then
                    entry.coloring = true
                    setHealthDesaturation(entry, original.healthDesaturated)
                    entry.health:SetStatusBarColor(unpack(original.healthColor))
                    entry.coloring = nil
                end
            end
            if cfg.bars.powerMode == "blizzard" then
                if entry.power then
                    entry.powerColoring = true
                    setBarDesaturation(entry, "power", original.powerDesaturated)
                    entry.power:SetStatusBarColor(unpack(original.powerColor))
                    entry.powerColoring = nil
                end
            end
            GUF.UpdateColors(entry)
        end
    end
    GUF.UpdateFading(0)
end
