local _, GUF = ...
-- Feature module for the existing Blizzard unit frames.
local unpack = unpack or table.unpack

local Client = GUF.Client

-- Keep managed-unit policy in the runtime; the adapter only discovers native
-- objects. Legacy consumers continue to receive the descriptor/reference alone.
function GUF.Resolve(unit)
    if not GUF.IsManagedUnit(unit) then return end
    local resolved = Client.ResolveUnitFrame(unit)
    return resolved
end

function GUF.AnchorFrame(unit)
    local frame = Client.ResolveAnchorFrame(unit)
    return frame
end

GUF.IsUnmanagedUnitFrame = Client.IsUnmanagedUnitFrame
GUF.PlayerRoleRegions = Client.ResolvePlayerRoleRegions

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
        local curve = UnitHealthPercent and GUF.HealthPercentCurve()
        if curve then
            local color = UnitHealthPercent(unit, true, curve)
            return color:GetRGB()
        end
        local health, maximum = UnitHealth(unit), UnitHealthMax(unit)
        if not GUF.Secret(health) and not GUF.Secret(maximum) and maximum > 0 then
            return GUF.HealthPercentColor(health / maximum)
        end
    end
    if UnitIsPlayer(unit) then return GUF.ClassColor(unit) end
    if unit == "pet" then return GUF.ClassColor("player") end
    -- Class mode keeps class colors for players and reaction colors for NPCs.
    if cfg.healthColor == "class" then return GUF.NPCHealthColor(unit) end
    if npcEngagedWithGroup(unit) then return unpack(GUF.colors.hostile) end
    return GUF.ReactionColor(unit)
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
    if entry.unit ~= "target" or entry.targetColorQueued or GUF.Runtime.Settings("colors", entry).general.frameStyle ~= "blizzard" then return end
    local binding = GUF.Runtime.Binding("colors", entry)
    if not binding then GUF.QueueRecovery("target-color-binding", entry); return end
    entry.targetColorQueued = binding
    C_Timer.After(0, function()
        if entry.targetColorQueued ~= binding then return end
        entry.targetColorQueued = nil
        if not GUF.Runtime.IsBinding(binding, "colors", entry) then return end
        if GUF.Runtime.Settings("colors", entry).general.frameStyle ~= "blizzard" or GUF.editing then return end
        if GUF.Presentation.Role(entry, "ownedBars") then return end
        -- Native retarget/classification work can finish after our unit event.
        -- Refresh tint only from the current unit, never native values/geometry.
        GUF.UpdateColors(entry)
    end)
end

function GUF.UpdateColors(entry)
    local cfg = GUF.Runtime.Settings("colors", entry).frames[entry.unit]
    if not UnitExists(entry.unit) then return end
    local unit = entry.frame.unit or entry.unit
    local rendered = GUF.Presentation.Role(entry, "ownedBars")
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


local function makeEntry(unit)
    local entry = GUF.frames[unit] or GUF.Resolve(unit)
    if not entry then return end
    GUF.frames[unit] = entry
    if entry.initialized then return entry end
    local frame = entry.frame
    entry.original = entry.original or { points = GUF.ReadPoints(frame), width = frame:GetWidth(), height = frame:GetHeight() }
    if entry.name then
        entry.original.nameColor = { entry.name:GetTextColor() }
        if unit ~= "pet" then
            entry.original.nameText = entry.name:GetText()
            local function nativeNameChanged()
                if entry.nameWriting then return end
                entry.original.nameText = entry.name:GetText()
                GUF.UpdateUnitName(entry)
            end
            GUF.NativeProperties.Hook("Frames:1", entry.name, "SetText", nativeNameChanged)
            GUF.NativeProperties.Hook("Frames:2", entry.name, "SetFormattedText", nativeNameChanged)
        end
        GUF.NativeProperties.Hook("Frames:3", entry.name, "SetTextColor", function()
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
                    GUF.NativeProperties.Hook("Frames:4", bar, "SetStatusBarDesaturated", function(_, desaturated)
                        if entry.coloring then return end
                        entry.original.healthDesaturated = desaturated
                        GUF.UpdateColors(entry)
                    end)
                end
            else
                local texture = bar:GetStatusBarTexture()
                entry.original.powerDesaturated = texture and texture.IsDesaturated and texture:IsDesaturated() or false
                if bar.SetStatusBarDesaturated then
                    GUF.NativeProperties.Hook("Frames:5", bar, "SetStatusBarDesaturated", function(_, desaturated)
                        if entry.powerColoring then return end
                        entry.original.powerDesaturated = desaturated
                        GUF.UpdateColors(entry)
                    end)
                end
            end
            entry[kind .. "Text"] = entry[kind .. "Text"] or GUF.Runtime.TrackRegion(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
            entry[kind .. "Text"].goodUnitFramesOwned = true
            entry[kind .. "Text"]:SetPoint("CENTER", bar, "CENTER")
            entry[kind .. "Text"]:SetDrawLayer("OVERLAY", 7)
            GUF.NativeProperties.Hook("Frames:6", bar, "SetStatusBarColor", function()
                if not entry.coloring and not entry.powerColoring then
                    entry.original[kind .. "Color"] = { bar:GetStatusBarColor() }
                    GUF.UpdateColors(entry)
                end
            end)
            if bar.HookScript then
                GUF.NativeProperties.HookScript("Frames:script:1", bar, "OnValueChanged", function() GUF.UpdateBarText(entry, kind) end)
            end
        end
    end
    GUF.NativeProperties.Hook("Frames:7", frame, "SetPoint", function()
        if entry.scaleWriting or entry.positionWriting then return end
        local forbidden = frame.IsForbidden and frame:IsForbidden()
        if GUF.Secret(forbidden) or forbidden then
            entry.positionCapturePending = true; GUF.QueueRecovery("position-capture", entry); return
        end
        if not entry.positionOwned or GUF.editing or entry.editPositionPending then
            local points = GUF.ReadPoints(frame)
            if points then entry.original.points, entry.positionCapturePending = points, nil
            else entry.positionCapturePending = true end
        end
        GUF.ApplyPosition(entry)
    end)
    GUF.NativeProperties.HookScript("Frames:script:2", frame, "OnShow", function()
        GUF.UpdateColors(entry)
        GUF.UpdateUnitName(entry)
        GUF.UpdateBarText(entry, "health")
        GUF.UpdateBarText(entry, "power")
        GUF.ApplyPosition(entry)
        if entry.sizeOwned or GUF.Presentation.Role(entry, "ownedBars")
            or GUF.Layouts.NeedsLiveApply(entry) then GUF.QueueRecovery("unit-show", entry) end
    end)
    GUF.CaptureSize(entry)
    GUF.CaptureBlizzardArtwork(entry)
    entry.initialized = true
    GUF.Runtime.Constructed()
    return entry
end

local function applyEntry(entry, layout, request)
    local transitions, runtime = GUF.LayoutTransitions, GUF.Runtime
    local lifecycle = transitions.BeginEntry(entry, layout, request)
    if not lifecycle then return false end
    local function stage(family, fn, ...)
        local ok, reason = runtime.Apply(entry, family, request, fn, ...)
        if not ok then transitions.EntryIncomplete(entry, request, family, reason) end
        return ok
    end
    if not stage("construction", makeEntry, entry.unit) then return false end
    if not stage("colors", GUF.UpdateColors, entry) then return false end
    if not stage("rootFading", function()
        lifecycle.fadingStatus, lifecycle.fadingReason = GUF.ApplyFrameFading(entry, request)
        return lifecycle.fadingStatus, lifecycle.fadingReason
    end) then return false end
    if not stage("scale", function()
        lifecycle.scaleStatus, lifecycle.scaleReason = GUF.ApplyFrameScale(entry, false, request)
        return lifecycle.scaleStatus, lifecycle.scaleReason
    end) then return false end
    if not transitions.IsCurrent(request, layout.id) then return false end
    if not stage("position", function()
        lifecycle.positionStatus, lifecycle.positionReason = GUF.ApplyPosition(entry, request)
        return lifecycle.positionStatus, lifecycle.positionReason
    end) then return false end
    if not transitions.IsCurrent(request, layout.id) then return false end
    if lifecycle.scaleStatus ~= "applied" or lifecycle.positionStatus ~= "applied" or lifecycle.fadingStatus ~= "applied" then
        transitions.EntryIncomplete(entry, request, "root", lifecycle.scaleReason or lifecycle.positionReason or lifecycle.fadingReason)
        return false
    end
    if not stage("textCapture", GUF.CaptureText, entry) then return false end
    -- Release with each acquiring owner's settings/operation, including owners
    -- which are no longer available. Their cleanup tickets survive supersession.
    lifecycle.releases = GUF.Layouts.ReleaseOtherLive(entry, layout)
    transitions.RecordReleases(entry, layout, request, lifecycle.releases)
    for _, result in pairs(lifecycle.releases) do
        if result.status == "failed" or result.status == "deferred" then
            transitions.EntryIncomplete(entry, request, "release", result.reason)
            return false
        end
    end
    if not stage("size", GUF.ApplySize, entry) and entry.runtimeFailures and entry.runtimeFailures.size then return false end
    if not transitions.Acquire(entry, layout, request) then return false end
    if not stage("layout", function()
        entry.runtimeLayoutAttempts = entry.runtimeLayoutAttempts or {}
        entry.runtimeLayoutAttempts[layout.id] = runtime.Current()
        local status, reason = layout.live.apply(entry)
        lifecycle.applyStatus, lifecycle.applyReason = status or "unreported", reason
        return status, reason
    end) then return false end
    entry.runtimeLayouts = entry.runtimeLayouts or {}
    entry.runtimeLayouts[layout.id] = runtime.Binding("layout", entry)
    entry.runtimeLayoutAttempts[layout.id] = nil
    for _, item in ipairs({ { "artwork", GUF.ApplyArtwork }, { "combatText", GUF.ApplyCombatText },
        { "bars", GUF.ApplyBars }, { "predictions", GUF.ApplyPredictionBars },
        { "cast", GUF.ApplyCastBar }, { "text", GUF.ApplyText } }) do
        if not stage(item[1], item[2], entry) then return false end
    end
    if not stage("finalize", GUF.Layouts.FinalizeLive, entry) then return false end
    if not stage("bars", function()
        local cfg, original = runtime.Settings("bars", entry).frames[entry.unit], entry.original
        if cfg.healthColor == "blizzard" and entry.health then
            entry.coloring = true
            setHealthDesaturation(entry, original.healthDesaturated)
            entry.health:SetStatusBarColor(unpack(original.healthColor))
            entry.coloring = nil
        end
        if cfg.bars.powerMode == "blizzard" and entry.power then
            entry.powerColoring = true
            setBarDesaturation(entry, "power", original.powerDesaturated)
            entry.power:SetStatusBarColor(unpack(original.powerColor))
            entry.powerColoring = nil
        end
        GUF.UpdateColors(entry)
    end) then return false end
    entry.appliedSettingsRevision = request.revision
    return transitions.FinishEntry(entry, layout, request, lifecycle)
end

function GUF.ApplyFrames(request, selectedUnits)
    local layout = GUF.Layouts.Get(GUF.db.general.frameStyle)
    if not layout then error("Good Unit Frames cannot apply an unregistered layout.") end
    local transitions = GUF.LayoutTransitions
    request = request or transitions.Request(GUF.db, layout.id, true)
    if not GUF.Runtime.Capture(request) or not GUF.Runtime.CaptureColors(request) or not GUF.CaptureFrameScaleRequest(request)
        or not GUF.CaptureFramePositionRequest(request) or not GUF.CaptureFrameFadingRequest(request) then
        GUF.QueueRecovery("frame-inputs"); return false
    end
    local complete = true
    for _, unit in ipairs(GUF.order) do
        if not selectedUnits or selectedUnits[unit] then
            local entry = GUF.frames[unit] or GUF.Resolve(unit)
            if entry then
                GUF.frames[unit] = entry
                if not applyEntry(entry, layout, request) then complete = false end
            else complete = false; GUF.QueueRecovery("frame-not-ready") end
            if not transitions.IsCurrent(request, layout.id) then return false end
        end
    end
    GUF.UpdateFading(0)
    return complete
end
