local _, GUF = ...
local Client = GUF.Client

-- Read-only discovery. Re-resolve globals/children on every call, including
-- class-specific attachments that may appear after login. A ready descriptor
-- means the supported root exists; optional regions can still be absent.
-- Callers retain per-feature readiness, permission and ownership checks.

local function path(root, ...)
    for i = 1, select("#", ...) do
        if not root then return nil end
        root = root[select(i, ...)]
    end
    return root
end

function Client.ResolveUnitFrame(unit)
    if Client.IsSecret(unit) then return nil, "restricted" end
    local frame
    if unit == "player" then frame = PlayerFrame
    elseif unit == "target" then frame = TargetFrame
    else return nil, "unsupported-unit" end
    if not frame then return nil, "not-ready" end
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
    if player and Client.isRetail then
        local _, class = UnitClass("player")
        priestMana = not Client.IsSecret(class) and class == "PRIEST"
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
                MonkHarmonyBarFrame, EssencePlayerFrame, Client.isRetail and DemonHunterSoulFragmentsBar or nil,
                Client.isRetail and MonkStaggerBar or nil, Client.isRetail and EvokerEbonMightBar or nil,
                priestMana and AlternatePowerBar or nil, priestMana and InsanityBarFrame or nil } or {},
        },
    }, "ready"
end

-- Dormant unit attachments are reference-only anchor targets. Discovery never
-- creates an addon entry, captures geometry or changes their native controller.
function Client.ResolveAnchorFrame(unit)
    if Client.IsSecret(unit) then return nil, "restricted" end
    local frame
    if unit == "pet" then frame = PetFrame
    elseif unit == "targettarget" then frame = TargetFrameToT or (TargetFrame and TargetFrame.totFrame)
    else
        local resolved, status = Client.ResolveUnitFrame(unit)
        return resolved and resolved.frame, status
    end
    if not frame then return nil, "not-ready" end
    return frame, "ready"
end

function Client.IsUnmanagedUnitFrame(frame)
    return frame and (frame == PetFrame or frame == TargetFrameToT or frame == (TargetFrame and TargetFrame.totFrame))
end

function Client.ResolvePlayerRoleRegions(entry)
    if entry.unit ~= "player" then return end
    local frame, main, context = entry.frame, entry.main, entry.context
    local container = frame.PlayerFrameContainer or frame
    local role = context.RoleIcon or main.RoleIcon or context.GroupRoleIcon
        or frame.RoleIcon or frame.roleIcon or PlayerRoleIcon
    local portrait = container.PlayerPortrait or container.Portrait or frame.portrait or frame.Portrait or PlayerPortrait
    return role, portrait
end

-- Animated health loss can be a sibling of Health, outside the bar's child
-- subtree. Resolve controller/template references without reading live values.
function Client.ResolvePlayerHealthLoss(entry)
    local health, area, frame = entry.health, entry.healthArea, entry.frame
    local candidates = { health and health.AnimatedLossBar,
        area and area.PlayerFrameHealthBarAnimatedLoss, frame and frame.PlayerFrameHealthBarAnimatedLoss }
    for index = 1, 3 do
        local region = candidates[index]
        if region and not (region.IsForbidden and region:IsForbidden()) then return region end
    end
end

-- Optional cosmetic attachments on the Player's native Power bar. Feedback
-- textures can be shown/reinitialized independently; never inspect their
-- resource values, dimensions, UVs or timing to identify them.
function Client.ResolvePlayerPowerEffects(power)
    if not power or power.IsForbidden and power:IsForbidden() then return end
    local function available(region)
        if region and not (region.IsForbidden and region:IsForbidden()) then return region end
    end
    local feedback = available(power.FeedbackFrame)
    return {
        powerFeedback = feedback,
        powerFeedbackBar = feedback and available(feedback.BarTexture),
        powerFeedbackGain = feedback and available(feedback.GainGlowTexture),
        powerFeedbackLoss = feedback and available(feedback.LossGlowTexture),
        powerCostPrediction = available(power.ManaCostPredictionBar),
    }
end

-- Public resource kind in, native references out. Eligibility and live resource
-- data remain with the feature; missing native hosts are never cached here.
function Client.ResolveResourceFrames(kind)
    local frames = {}
    local function add(frame)
        if frame and frame.SetAlpha and frame.IsShown then frames[#frames + 1] = frame end
    end
    if kind == "holy" then add(PaladinPowerBarFrame)
    elseif kind == "chi" then add(MonkHarmonyBarFrame)
    elseif kind == "arcane" then add(MageArcaneChargesFrame)
    elseif kind == "essence" then add(EssencePlayerFrame)
    elseif kind == "fragments" then add(DemonHunterSoulFragmentsBar)
    elseif kind == "stagger" then add(MonkStaggerBar)
    elseif kind == "shadowmana" then add(AlternatePowerBar)
    elseif kind == "ebon" then add(EvokerEbonMightBar) end
    return frames
end
