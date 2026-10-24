local _, GUF = ...

-- Shared by visibility handling and the options page.
GUF.blizzardFrameOptions = {
    { key = "buffs", label = "Hide buff frames", frames = { "BuffFrame" },
        auraPrefixes = { "TargetFrameBuff", "FocusFrameBuff" },
        tooltip = "Hide Blizzard's default player buffs/weapon enchants and stock Target/Focus buffs. Custom aura frames are unaffected. Uncheck to restore the default displays." },
    { key = "debuffs", label = "Hide debuff frames", frames = { "DebuffFrame" },
        auraPrefixes = { "TargetFrameDebuff", "FocusFrameDebuff" },
        tooltip = "Hide Blizzard's default player debuffs/private-aura display and stock Target/Focus debuffs. Custom aura frames and Boss debuffs are unaffected. Uncheck to restore the default displays." },
    { key = "player", label = "Hide player frames", frames = { "PlayerFrame", "AlternatePowerBar" },
        tooltip = "Hide Blizzard's player frame and its attached displays. Good Unit Frames currently customizes this same frame, so its attached enhancements will also be hidden." },
    { key = "target", label = "Hide target frames", frames = { "TargetFrame", "ComboFrame" },
        tooltip = "Hide Blizzard's target frame and target combo-point displays. Enhancements attached to these frames are also hidden." },
    { key = "targettarget", label = "Hide target of target", frames = { "TargetFrameToT" },
        related = function() return TargetFrame and TargetFrame.totFrame end,
        tooltip = "Hide Blizzard's Target of Target frame. Uncheck to restore Blizzard's control of its visibility." },
    { key = "focus", label = "Hide focus frames", frames = { "FocusFrame", "FocusFrameToT" },
        related = function() return FocusFrame and FocusFrame.totFrame end,
        tooltip = "Hide Blizzard's focus and focus-target displays." },
    { key = "party", label = "Hide party frames", frames = { "PartyFrame", "CompactPartyFrame" },
        prefix = "PartyMemberFrame", count = 4, countGlobal = "MAX_PARTY_MEMBERS",
        tooltip = "Hide Blizzard's party frames, including its compact party display." },
    { key = "raid", label = "Hide raid frames", frames = { "CompactRaidFrameManager", "CompactRaidFrameContainer" },
        tooltip = "Hide Blizzard's raid frames and raid manager. This includes party members when Blizzard uses the raid-frame container for the party." },
    { key = "boss", label = "Hide boss frames", frames = { "BossTargetFrameContainer" },
        prefix = "Boss", suffix = "TargetFrame", count = 5, countGlobal = "MAX_BOSS_FRAMES",
        tooltip = "Hide Blizzard's boss unit frames. The custom Boss debuffs aura setting is separate." },
    { key = "arena", label = "Hide arena/battleground frames",
        frames = { "CompactArenaFrame", "ArenaEnemyFrames", "ArenaEnemyMatchFrames", "ArenaEnemyPrepFrames" },
        prefix = "ArenaEnemyFrame", count = 5, countGlobal = "MAX_ARENA_ENEMIES",
        tooltip = "Hide Blizzard's arena and battleground opponent frames, including its compact arena and preparation displays." },
    { key = "cast", label = "Hide player cast bar", frames = { "PlayerCastingBarFrame", "CastingBarFrame" },
        tooltip = "Hide Blizzard's player cast bar, including the bar used by the Blizzard layout. Other layouts use Enable cast bar under Bars." },
    { key = "endCaps", label = "Hide action bar end caps", frames = {},
        tooltip = "Hide the gryphon/end-cap artwork on both sides of the main action bar, including in Edit Mode. Buttons and other bar artwork are unchanged. Uncheck to restore Blizzard's control of the end caps." },
}

local states, hooked, creationHooks = {}, {}, {}
local endCapRegions, endCapHooks = {}, {}
local hiddenParent

function GUF.ApplyBlizzardEndCaps()
    if not GUF.db then return end
    local desired = {}
    local function include(region)
        if region and not (region.IsForbidden and region:IsForbidden()) then desired[region] = true end
    end
    local function includeCap(cap)
        if not cap or (cap.IsForbidden and cap:IsForbidden()) then return end
        if cap:GetObjectType() == "Texture" then
            include(cap)
        else
            -- Forever exposes each cap as an Edit Mode frame. Target its actual
            -- artwork and selection overlay, which can ignore parent alpha.
            include(cap.Texture)
            include(cap.Selection)
        end
    end
    if GUF.db.hideBlizzard.endCaps then
        local caps = MainActionBar and MainActionBar.EndCaps
        if caps then includeCap(caps.LeftEndCap); includeCap(caps.RightEndCap) end
        includeCap(MainMenuBarLeftEndCap)
        includeCap(MainMenuBarRightEndCap)
        if MainActionBar and type(MainActionBar.UpdateEndCaps) == "function" and not endCapHooks[MainActionBar] then
            endCapHooks[MainActionBar] = true
            hooksecurefunc(MainActionBar, "UpdateEndCaps", GUF.ApplyBlizzardEndCaps)
        end
    end
    -- Override only cap artwork/selection alpha, never the secure bar or cap
    -- system's hierarchy, shown state, geometry or saved Edit Mode settings.
    -- RegionAlpha also remembers native alpha updates for restoration.
    for region in pairs(endCapRegions) do
        if not desired[region] and not (region.IsForbidden and region:IsForbidden()) then
            GUF.RegionAlpha(region, nil)
            endCapRegions[region] = nil
        end
    end
    for region in pairs(desired) do
        GUF.RegionAlpha(region, 0)
        endCapRegions[region] = true
    end
end

local function reparent(frame, state)
    -- Other addons can also hook SetParent; do not compete recursively with them.
    state.reparenting = true
    frame:SetParent(hiddenParent)
    state.reparenting = nil
end

local function suppress(frame, hide)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local state = states[frame]
    if not hide then
        if state then
            states[frame] = nil
            -- Only undo our own reparenting, preserving another addon's changes.
            if frame:GetParent() == hiddenParent then frame:SetParent(state.parent) end
        end
        return
    end
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame", nil, UIParent)
        hiddenParent.goodUnitFramesOwned = true
        hiddenParent:Hide()
    end
    if not state then
        local parent = frame:GetParent()
        if GUF.Secret(parent) then GUF.QueueBlizzardFrameRefresh(); return end
        state = { parent = parent }
        states[frame] = state
    end
    if not hooked[frame] then
        hooksecurefunc(frame, "SetParent", function(self, parent)
            local current = states[self]
            if not current or GUF.Secret(parent) or parent == hiddenParent then return end
            current.parent = parent
            if current.reparenting then return end
            if GUF.Restricted() or GUF.editing then GUF.QueueBlizzardFrameRefresh(); return end
            reparent(self, current)
        end)
        hooked[frame] = true
    end
    -- A hidden parent also suppresses tooltips/clicks and survives native Show calls.
    -- Leave events and the frame's own shown state intact for immediate restoration.
    if frame:GetParent() ~= hiddenParent then reparent(frame, state) end
end

function GUF.QueueBlizzardFrameRefresh()
    GUF.blizzardVisibilityPending = true
    -- Late-loaded action-bar art must also be suppressed while Edit Mode is open.
    GUF.ApplyBlizzardEndCaps()
end

function GUF.ApplyBlizzardFrames()
    GUF.ApplyBlizzardEndCaps()
    if GUF.Restricted() or GUF.editing then GUF.QueueBlizzardFrameRefresh(); return end
    GUF.blizzardVisibilityPending = nil
    -- Some opponent/raid frames are created or replaced after login.
    for _, name in ipairs({ "CompactArenaFrame_Generate", "CompactRaidFrameManager_UpdateShown" }) do
        if type(_G[name]) == "function" and not creationHooks[name] then
            hooksecurefunc(name, GUF.QueueBlizzardFrameRefresh)
            creationHooks[name] = true
        end
    end
    local desired = {}
    local function include(frame, hide)
        if frame then desired[frame] = desired[frame] or hide end
    end
    for _, option in ipairs(GUF.blizzardFrameOptions) do
        local hide = GUF.db.hideBlizzard[option.key]
        for _, name in ipairs(option.frames) do
            include(_G[name], hide)
        end
        if option.prefix then
            local count = option.countGlobal and _G[option.countGlobal]
            if GUF.Secret(count) or type(count) ~= "number" then count = option.count end
            for i = 1, count do include(_G[option.prefix .. i .. (option.suffix or "")], hide) end
        end
        if option.related then include(option.related(), hide) end
        -- Legacy clients expose individual stock buttons rather than one container.
        for _, prefix in ipairs(option.auraPrefixes or {}) do
            local replacement = prefix:find("^TargetFrame") and GUF.nativeAuraDesired and GUF.nativeAuraDesired.target
            for i = 1, 40 do include(_G[prefix .. i], hide or replacement) end
        end
    end
    -- Shared frames (e.g. ComboFrame) remain hidden if any selected group owns them.
    for frame in pairs(states) do
        if not desired[frame] then suppress(frame, false) end
    end
    for frame, hide in pairs(desired) do
        if hide then suppress(frame, true) end
    end
    GUF.ApplyNativeAuraVisibility()
end
