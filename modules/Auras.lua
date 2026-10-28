local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "Auras")
end
local Client = GUF.Client
-- Blizzard owns aura data, filtering, sorting, timers, tooltips and cancellation.
GUF.auraHosts = {}
-- Addon-created controller hosts only; native aura buttons stay in their
-- engine providers. Keys contain structural public choices, never aura data.
GUF.auraHostPools = {}

function GUF.AuraAnchor(cfg)
    local point = (cfg.growV == "TOP" and "BOTTOM" or "TOP")
        .. (cfg.growH == "CENTER" and "" or cfg.growH == "LEFT" and "RIGHT" or "LEFT")
    return cfg.legacyPoint or point, cfg.anchorPoint == "FREE" and "CENTER" or cfg.anchorPoint
end

function GUF.AuraParent(entry, cfg)
    if cfg.anchorPoint == "FREE" then return UIParent end
    return GUF.Presentation.Role(entry, cfg.anchorPoint:find("TOP", 1, true) and "auraTop" or "auraBottom") or entry.frame
end

function GUF.AuraPosition(entry, cfg)
    local gap = GUF.Presentation.Role(entry, "auraTopGap")
    local y = cfg.y
    -- Upper lanes follow the header. Upward-growing roots leave a small gap;
    -- preserve saved offsets and arbitrary legacy anchors underneath this rule.
    if gap and cfg.anchorPoint:find("TOP", 1, true)
        and cfg.growV == "TOP" then
        local point = GUF.AuraAnchor(cfg)
        if point:find("BOTTOM", 1, true) then y = math.max(y, gap) end
    end
    -- Cast avoidance is a separate pass over complete, unshifted groups.
    return cfg.x, y
end

function GUF.RefreshCastAuraPositions(entry)
    if not GUF.db or GUF.editing then return end
    GUF.ApplyLiveCastAuraLayout(entry)
end

local function disableHost(host)
    if host then
        host.configured = false
        host.retired = true
        host.binding = nil
        host.active = false
        host.container:SetEnabled(false)
        host.container:Hide()
        if host.alternate then disableHost(host.alternate) end
        host.container:ClearAllPoints()
        host.container.goodUnitFramesCastAnchor = nil
        if host.anchor then
            host.anchor:Hide(); host.anchor:ClearAllPoints()
            host.anchor.goodUnitFramesCastAnchor = nil
        end
    end
end

local function styleText(text, frameCfg, size, color, anchor, parent, x, y)
    text:SetFont(GUF.Font(frameCfg.font), size, frameCfg.outline)
    text:SetTextColor(unpack(color))
    text:ClearAllPoints()
    text:SetPoint(anchor, parent, anchor, x, y)
end

local function styleCountdown(record, text, frameCfg)
    if not record.timer then
        for _, region in ipairs({ record.cooldown:GetRegions() }) do
            if region:GetObjectType() == "FontString" then record.timer = region; break end
        end
    end
    if record.timer then
        styleText(record.timer, frameCfg, text.cooldownFontSize, text.cooldownFontColor,
            text.timerAnchor, record.cooldown, text.timerX, text.timerY)
    end
end

local function styleButton(record, section, frameCfg)
    local cfg, button = section.cfg, record.button
    local text = cfg
    local size = record.enchantment and cfg.size or section.size
    button:SetSize(size, size)
    -- The native debuff border has a transparent outer gutter. Keep the icon
    -- and swipe inside it, so bright artwork cannot show outside the rim.
    local inset = section.kind == "debuffs" and cfg.debuffBorder and record.border and math.max(1, size / 32) or 0
    record.icon:ClearAllPoints()
    record.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    record.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    record.cooldown:ClearAllPoints()
    record.cooldown:SetAllPoints(record.icon)
    record.cooldown:SetDrawSwipe(cfg.cooldown)
    record.cooldown:SetHideCountdownNumbers(text.disableBlizzardCC)
    styleCountdown(record, text, frameCfg)
    styleText(record.stack, frameCfg, text.stackFontSize, text.stackFontColor,
        text.stackAnchor, button, text.stackX, text.stackY)
    if record.duration then
        styleText(record.duration, frameCfg, text.cooldownFontSize, text.cooldownFontColor,
            text.durationPoint, button, 0, text.durationY)
        record.duration:SetAlpha(cfg.durationText and 1 or 0)
    end
    record.stack:SetAlpha(cfg.disableStacks and 0 or 1)
    if record.border then record.border:SetAlpha(cfg.debuffBorder and 1 or 0) end
end

local function initializeButton(host, sectionIndex, button, enchantment)
    if host.retired or not GUF.Runtime.IsBinding(host.binding, "auras", host.unit) then return end
    local section = host.sections[sectionIndex]
    local cfg, frameCfg = section.cfg, GUF.Runtime.Settings("auras", host.unit).frames[host.unit]
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(button)
    icon:SetTexCoord(.07, .93, .07, .93)
    button:SetIcon(icon)
    local cooldown = GUF.Runtime.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    button:SetDurationCooldown(cooldown)
    local overlay = GUF.Runtime.CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 3)
    local record = { button = button, icon = icon, cooldown = cooldown, sectionIndex = sectionIndex, enchantment = enchantment }
    record.stack = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button:SetApplicationCount(record.stack, {})
    -- Attach optional presentation once, in the native creation callback.
    -- Saved toggles change only owned decoration alpha, not provider topology.
    if button.SetDurationText then
        record.duration = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button:SetDurationText(record.duration, {})
    end
    if section.kind == "debuffs" and button.AddDispelTypeTexture then
        local border = overlay:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(button)
        border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        border:SetTexCoord(.296875, .5703125, 0, .515625)
        record.border = border
        button:AddDispelTypeTexture(border, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset or 3,
            showWhenHarmful = true, showWithoutDispelType = true,
        })
    end
    styleButton(record, section, frameCfg)
    host.buttons[#host.buttons + 1] = record
    -- Native aura cooldowns inherit secret aspects. Style them directly; script hooks are forbidden.
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end
    if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_BOTTOMLEFT", 0, 0) end
    if button.SetHideTooltipInCombat then button:SetHideTooltipInCombat(false) end
    if host.unit == "player" and section.kind == "buffs" and button.SetCancelAuraButtons then
        button:SetCancelAuraButtons("RightButtonUp")
    end
end

local function sectionsFor(kind, cfg)
    local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
    if cfg.filter ~= "ALL" then filter = filter .. "|" .. cfg.filter end
    return { { kind = kind, cfg = cfg, filter = filter, size = cfg.size } }
end

-- Shared appearance/layout descriptors for ordinary, unrestricted preview buttons.
GUF.StyleAuraButton = styleButton
GUF.AuraSections = sectionsFor

-- All sections belonging to one frame share its icon budget, including weapon enchants.
function GUF.AuraSectionLimits(sections, enchantCfg, enchantCount)
    local counts, seen, limits = {}, {}, {}
    for _, section in ipairs(sections) do counts[section.cfg] = (counts[section.cfg] or 0) + 1 end
    for i, section in ipairs(sections) do
        local cfg = section.cfg
        local budget = math.max(0, cfg.perRow * cfg.maxRows - (cfg == enchantCfg and enchantCount or 0))
        local share, remainder = math.floor(budget / counts[cfg]), budget % counts[cfg]
        seen[cfg] = (seen[cfg] or 0) + 1
        limits[i] = share + (seen[cfg] <= remainder and 1 or 0)
    end
    return limits
end

local function enchantState()
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local main = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND or 16)
        local off = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_OFFHAND or 17)
        if GUF.Secret(main) or GUF.Secret(off) then return true, true end
        return main ~= nil, off ~= nil
    end
    if GetWeaponEnchantInfo then
        local main, _, _, _, off = GetWeaponEnchantInfo()
        if GUF.Secret(main) or GUF.Secret(off) then return true, true end
        return not not main, not not off
    end
    -- Reserve both slots if this client cannot expose enchant presence safely.
    return true, true
end

local function applyLimits(host, enchantCount)
    local cfg = host.enchantSection and host.sections[host.enchantSection].cfg
    local limits = GUF.AuraSectionLimits(host.sections, cfg, enchantCount)
    host.limits = host.limits or {}
    for i, limit in ipairs(limits) do
        if host.limits[i] ~= limit then
            host.container:SetAuraGroupMaxFrameCount("auras" .. i, limit)
            host.limits[i] = limit
        end
    end
end

local function enableHost(host, enabled)
    if host.active ~= enabled then
        host.container:SetEnabled(enabled)
        host.active = enabled
    end
end

local function updateEnchants(host, main, off)
    local count = (main and 1 or 0) + (off and 1 or 0)
    if host.alternate then
        -- One available slot: show main-hand first, or off-hand when it is the only active enchant.
        -- Both native containers are prepared outside combat; only their public enable states change.
        local useOff = off and not main
        count = math.min(1, count)
        applyLimits(host, count)
        applyLimits(host.alternate, count)
        enableHost(useOff and host or host.alternate, false)
        enableHost(useOff and host.alternate or host, true)
    else
        applyLimits(host, count)
        enableHost(host, true)
    end
end

function GUF.UpdateAuraEnchants()
    local main, off
    for _, host in pairs(GUF.auraHosts) do
        if host.configured and host.enchantSection then
            if main == nil then main, off = enchantState() end
            updateEnchants(host, main, off)
        end
    end
end

local function structure(sections, enchants, singleEnchant)
    local values = { tostring(enchants), tostring(singleEnchant), #sections }
    for _, section in ipairs(sections) do
        values[#values + 1] = section.kind
    end
    return table.concat(values, ":")
end

local function createHost(entry, sections, enchantSection, singleSlot)
    local container = Client.CreateAuraContainer(entry.frame)
    if not container then
        error("Native aura groups are unavailable on this client.")
    end
    GUF.Updates.stats.auraCreated = (GUF.Updates.stats.auraCreated or 0) + 1
    local host = { container = container, unit = entry.unit, sections = sections, buttons = {},
        enchantSection = enchantSection, active = false, binding = GUF.Runtime.Binding("auras", entry) }
    GUF.Runtime.TrackRegion(container)
    container.goodUnitFramesNativeController = true
    container:SetEnabled(false)
    container.goodUnitFramesOwned = true
    container:SetSize(1, 1)
    container:SetFrameLevel(entry.frame:GetFrameLevel() + 6)
    -- Record it before configuration so any failed native call can still be retired.
    local configured, err = pcall(function()
        for i, section in ipairs(sections) do
            local cfg = section.cfg
            container:AddAuraGroup("auras" .. i, section.filter, {
                maxFrameCount = cfg.perRow * cfg.maxRows,
                initializeFrame = function(button) GUF.Runtime.Refresh(host.unit, "auras", initializeButton, host, i, button) end,
                layout = { elementWidth = section.size, elementHeight = section.size,
                    elementSpacing = cfg.spacing, lineSpacing = cfg.spacing },
            })
        end
        if enchantSection and container.AddItemEnchantment then
            local slots = AuraContainerItemEnchantmentSlot or { MainHand = 0, OffHand = 1 }
            for _, slot in ipairs(singleSlot ~= nil and { singleSlot } or { slots.MainHand, slots.OffHand }) do
                container:AddItemEnchantment(slot, {
                    initializeFrame = function(button) GUF.Runtime.Refresh(host.unit, "auras", initializeButton, host, enchantSection, button, true) end,
                })
            end
        end
    end)
    if not configured then disableHost(host); error(err) end
    GUF.Runtime.Constructed()
    return host
end

local function applyCandidates(container, group, section, unit)
    local cfg, candidates = section.cfg, {}
    if cfg.filterMode == "whitelist" then candidates.includeSpellIDs = GUF.ParseSpellIDs(cfg.whitelist) or {} end
    if cfg.filterMode ~= "all" then candidates.excludeSpellIDs = GUF.ParseSpellIDs(cfg.blacklist) or {} end
    -- Dispel filters have opposite meanings for helpful and harmful auras.
    local gated = cfg.filter == "RAID_PLAYER_DISPELLABLE" or cfg.filter == "DISPELLABLE"
        or (section.kind == "debuffs" and cfg.filter == "RAID")
    if gated then
        local assist = UnitCanAssist("player", unit)
        if not GUF.Secret(assist) and (not not assist) ~= (section.kind == "debuffs") then
            candidates.includeDispelTypes = {}
        end
    end
    container:SetAuraGroupCandidateFilters(group, candidates)
end

local function configureHost(entry, kind, index, extraKind)
    local frameCfg = GUF.Runtime.Settings("auras", entry).frames[entry.unit]
    local cfg = frameCfg.auras[kind][index]
    local sections = sectionsFor(kind, cfg)
    if extraKind then
        for _, section in ipairs(sectionsFor(extraKind, frameCfg.auras[extraKind][index])) do
            sections[#sections + 1] = section
        end
    end
    local enchantSection
    local enchantCfg = GUF.AuraEnchantSettings(entry.unit, frameCfg.auras)
    if enchantCfg then
        for i, section in ipairs(sections) do
            if section.kind == "buffs" and section.cfg == enchantCfg then enchantSection = i; break end
        end
    end
    local key = entry.unit .. kind .. index
    local host = GUF.auraHosts[key]
    local singleEnchant = enchantSection and sections[enchantSection].cfg.perRow * sections[enchantSection].cfg.maxRows == 1 or false
    local signature = structure(sections, enchantSection, singleEnchant)
    local pool = GUF.auraHostPools[key]
    if not pool then pool = {}; GUF.auraHostPools[key] = pool end
    if host and host.signature ~= signature then disableHost(host) end
    host = pool[signature]
    if not host then
        local slots = AuraContainerItemEnchantmentSlot or { MainHand = 0, OffHand = 1 }
        host = createHost(entry, sections, enchantSection, singleEnchant and slots.MainHand or nil)
        -- Keep partial pairs reachable, but pool only a completely built variant.
        GUF.auraHosts[key] = host
        if singleEnchant then host.alternate = createHost(entry, sections, enchantSection, slots.OffHand) end
        host.signature = signature
        pool[signature] = host
    else
        GUF.Updates.stats.auraReused = (GUF.Updates.stats.auraReused or 0) + 1
    end
    GUF.auraHosts[key] = host
    host.sections = sections
    if host.alternate then host.alternate.sections = sections end
    host.retired, host.binding = nil, GUF.Runtime.Binding("auras", entry)
    if host.alternate then host.alternate.retired, host.alternate.binding = nil, host.binding end
    -- An owned proxy lets cast visibility move aura rows without rebuilding or
    -- repositioning their native containers during combat.
    if not host.anchor then
        host.anchor = GUF.Runtime.CreateFrame("Frame", nil, entry.frame)
        host.anchor.goodUnitFramesOwned = true
        host.anchor:EnableMouse(false)
    end
    if host.anchor then
        host.anchor:SetParent(entry.frame)
        local point, relative = GUF.AuraAnchor(cfg)
        local x, y = GUF.AuraPosition(entry, cfg)
        host.anchor:ClearAllPoints()
        host.anchor:SetPoint(point, GUF.AuraParent(entry, cfg), relative, x, y)
        host.anchor:SetSize(cfg.size, cfg.size)
        host.anchor:Show()
    end
    for _, nativeHost in ipairs(host.alternate and { host, host.alternate } or { host }) do
        local container = nativeHost.container
        container:SetParent(entry.frame)
        container:SetFrameLevel(entry.frame:GetFrameLevel() + 6)
        container:ClearAllPoints()
        local point, relative = GUF.AuraAnchor(cfg)
        if host.anchor then
            container:SetPoint(point, host.anchor, point, 0, 0)
        else
            local x, y = GUF.AuraPosition(entry, cfg)
            container:SetPoint(point, GUF.AuraParent(entry, cfg), relative, x, y)
        end
        if container.SetFlowLayoutAxis then container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal) end
        container:SetFlowLayoutAnchorPoint(cfg.growV == "TOP" and (cfg.growH == "LEFT" and "BOTTOMRIGHT" or "BOTTOMLEFT")
            or (cfg.growH == "LEFT" and "TOPRIGHT" or "TOPLEFT"))
        container:SetFlowLayoutGrowthDirection(cfg.growH == "LEFT" and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
            cfg.growV == "TOP" and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
        container:SetFlowLayoutMaximumLineSize(cfg.perRow * (cfg.size + cfg.spacing) - cfg.spacing + 1)
        for i, section in ipairs(sections) do
            local sectionCfg, group = section.cfg, "auras" .. i
            container:SetAuraGroupLayout(group, { elementWidth = section.size, elementHeight = section.size,
                elementSpacing = sectionCfg.spacing, lineSpacing = sectionCfg.spacing })
            container:SetAuraGroupFilterString(group, section.filter)
            applyCandidates(container, group, section, entry.frame.unit or entry.unit)
            if container.SetAuraGroupSortMethod and AuraContainerSortMethod and AuraContainerSortDirection then
                container:SetAuraGroupSortMethod(group, AuraContainerSortMethod[sectionCfg.sort] or AuraContainerSortMethod.Default,
                    sectionCfg.reverseSort and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal)
            end
        end
        if container.SetItemEnchantmentLayout then
            local enchantCfg = enchantSection and sections[enchantSection].cfg or cfg
            container:SetItemEnchantmentLayout({ elementWidth = enchantCfg.size, elementHeight = enchantCfg.size,
                elementSpacing = enchantCfg.spacing, lineSpacing = enchantCfg.spacing,
                placement = CustomAuraContainerItemEnchantmentPlacement and CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups })
        end
        for _, record in ipairs(nativeHost.buttons) do styleButton(record, sections[record.sectionIndex], frameCfg) end
        container:SetUnit(entry.frame.unit or entry.unit)
        container:Show()
    end
    host.configured = true
    if enchantSection then
        local main, off = enchantState()
        updateEnchants(host, main, off)
    else
        applyLimits(host, 0)
        enableHost(host, true)
    end
    for _, nativeHost in ipairs(host.alternate and { host, host.alternate } or { host }) do
        local container = nativeHost.container
        if container.UpdateAllAuras then container:UpdateAllAuras() end
        -- Refresh after native aura updates so lazily created countdown text can be styled too.
        for _, record in ipairs(nativeHost.buttons) do
            styleCountdown(record, sections[record.sectionIndex].cfg, frameCfg)
        end
    end
    return host
end

local function configureUnit(entry)
    local frameCfg, displayed = GUF.Runtime.Settings("auras", entry).frames[entry.unit], { buffs = false, debuffs = false }
    local auras = frameCfg.auras
    for i = 1, GUF.auraFrameCount do
        local buffs, debuffs = auras.buffs[i], auras.debuffs[i]
        local parentKind, childKind
        if buffs.enabled and debuffs.enabled then
            if buffs.anchorOn then parentKind, childKind = "debuffs", "buffs"
            elseif debuffs.anchorOn then parentKind, childKind = "buffs", "debuffs" end
        end
        local sequential = childKind and auras[childKind][i].anchorMode == "SEQUENTIAL"
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local cfg = auras[kind][i]
            if cfg.enabled and not (sequential and kind == childKind) then
                configureHost(entry, kind, i, sequential and kind == parentKind and childKind or nil)
                displayed[kind] = true
                if sequential then displayed[childKind] = true end
            else
                disableHost(GUF.auraHosts[entry.unit .. kind .. i])
            end
        end
        if parentKind and not sequential then
            local parent = GUF.auraHosts[entry.unit .. parentKind .. i]
            local child = GUF.auraHosts[entry.unit .. childKind .. i]
            if parent and child then
                local parentCfg = auras[parentKind][i]
                local point = GUF.AuraAnchor(parentCfg)
                local relative = parentCfg.growV == "TOP" and point:gsub("BOTTOM", "TOP") or point:gsub("TOP", "BOTTOM")
                if child.anchor then
                    child.anchor:ClearAllPoints()
                    child.anchor:SetPoint(point, parent.anchor or parent.container, relative, 0,
                        parentCfg.growV == "TOP" and parentCfg.spacing or -parentCfg.spacing)
                end
                for _, nativeHost in ipairs(child.alternate and { child, child.alternate } or { child }) do
                    local container = nativeHost.container
                    container:ClearAllPoints()
                    if child.anchor then container:SetPoint(point, child.anchor, point, 0, 0)
                    else container:SetPoint(point, parent.anchor or parent.container, relative, 0,
                        parentCfg.growV == "TOP" and parentCfg.spacing or -parentCfg.spacing) end
                    container:SetFlowLayoutAnchorPoint(parentCfg.growV == "TOP"
                        and (parentCfg.growH == "LEFT" and "BOTTOMRIGHT" or "BOTTOMLEFT")
                        or (parentCfg.growH == "LEFT" and "TOPRIGHT" or "TOPLEFT"))
                    container:SetFlowLayoutGrowthDirection(parentCfg.growH == "LEFT" and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
                        parentCfg.growV == "TOP" and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
                end
            end
        end
    end
    -- Configuration resets proxies to their baseline. Restore avoidance in the
    -- same pass, then allow a follow-up for geometry that settles next frame.
    GUF.RefreshCastAuraPositions(entry)
    GUF.QueueCastAuraPositions(entry)
    return displayed.buffs and displayed.debuffs
end

local function enforceNativeAuras(container, state)
    if GUF.Restricted() or GUF.editing then GUF.QueueBlizzardFrameRefresh(); return end
    state.writing = true
    for _, spec in ipairs({ { "buffs", "SetMaxBuffs" }, { "debuffs", "SetMaxDebuffs" } }) do
        local kind, setter = spec[1], spec[2]
        if container[setter] then
            -- Only change a cap whose native value can be restored. ConfigureAuraContainer
            -- supplies these values on clients without public cap getters.
            if state[kind] and (GUF.Secret(state.caps[kind]) or state.caps[kind] ~= nil) then
                container[setter](container, 0)
                state.ownedCaps[kind] = true
            elseif state.ownedCaps[kind] then
                container[setter](container, state.caps[kind])
                state.ownedCaps[kind] = nil
            end
        end
    end
    local hideAll = state.buffs and state.debuffs
    if hideAll then
        container:SetEnabled(false)
        state.enabledOwned = true
        -- Hide already-created native buttons as well; no aura children are inspected.
        leaseAlpha(container, 0)
        state.alphaOwned = true
    else
        if state.enabledOwned then container:SetEnabled(state.enabled); state.enabledOwned = nil end
        if state.alphaOwned then leaseAlpha(container, nil); state.alphaOwned = nil end
    end
    state.writing = nil
end

local function captureNativeAuraContainer(owner, container)
    GUF.nativeAuraStates = GUF.nativeAuraStates or {}
    local state = GUF.nativeAuraStates[container]
    if state then return state end
    state = { owner = owner, caps = {}, ownedCaps = {}, enabled = not container.IsEnabled or container:IsEnabled() }
    GUF.nativeAuraStates[container] = state
    GUF.NativeProperties.Track(container, "auraControllerPresentation", nil, state)
    for _, spec in ipairs({ { "buffs", "SetMaxBuffs", "GetMaxBuffs" }, { "debuffs", "SetMaxDebuffs", "GetMaxDebuffs" } }) do
        local kind, setter, getter = spec[1], spec[2], spec[3]
        if container[getter] then state.caps[kind] = container[getter](container) end
        if container[setter] then
            GUF.NativeProperties.Hook("Auras:1", container, setter, function(_, value)
                if state.writing then return end
                state.caps[kind] = value
                if state.buffs or state.debuffs then enforceNativeAuras(container, state) end
            end)
        end
    end
    GUF.NativeProperties.Hook("Auras:2", container, "SetEnabled", function(_, value)
        if state.writing then return end
        state.enabled = value
        if state.buffs and state.debuffs then enforceNativeAuras(container, state) end
    end)
    -- Capture actual client defaults rather than inventing restoration caps.
    if owner.ConfigureAuraContainer then owner:ConfigureAuraContainer() end
    return state
end

function GUF.ApplyNativeAuraVisibility()
    if GUF.nativeAuraApplying or not GUF.db then return end
    if GUF.Restricted() or GUF.editing then GUF.QueueBlizzardFrameRefresh(); return end
    GUF.nativeAuraApplying = true
    GUF.nativeAuraOwnerHooks = GUF.nativeAuraOwnerHooks or {}
    local active = {}
    for unit, owner in pairs(Client.NativeAuraOwners()) do
        local container = Client.ResolveAuraContainer(owner)
        if container and container.SetEnabled and not container.goodUnitFramesOwned
            and not (container.IsForbidden and container:IsForbidden()) then
            local state = captureNativeAuraContainer(owner, container)
            active[container] = true
            local replace = GUF.nativeAuraDesired and GUF.nativeAuraDesired[unit]
            state.buffs = GUF.Runtime.Settings("auras").hideBlizzard.buffs or replace
            state.debuffs = GUF.Runtime.Settings("auras").hideBlizzard.debuffs or replace
            enforceNativeAuras(container, state)
        end
        if owner.ConfigureAuraContainer and not GUF.nativeAuraOwnerHooks[owner] then
            GUF.NativeProperties.Hook("Auras:3", owner, "ConfigureAuraContainer", GUF.ApplyNativeAuraVisibility)
            GUF.nativeAuraOwnerHooks[owner] = true
        end
    end
    -- Restore superseded containers too, preserving their own native enable state.
    for container, state in pairs(GUF.nativeAuraStates or {}) do
        if not active[container] then
            state.buffs, state.debuffs = false, false
            enforceNativeAuras(container, state)
        end
    end
    GUF.nativeAuraApplying = nil
end

function GUF.ApplyAuras(selectedUnits)
    GUF.auraError = nil
    GUF.nativeAuraDesired = GUF.nativeAuraDesired or {}
    Client.LoadAuraContainerModule()
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if selectedUnits and not selectedUnits[unit] then
            -- The shared family acquired a new snapshot. Untouched public
            -- descriptors remain valid; late native allocations need its token.
            for _, kind in ipairs({ "buffs", "debuffs" }) do
                for i = 1, GUF.auraFrameCount do
                    local host = GUF.auraHosts[unit .. kind .. i]
                    if host and host.configured then
                        host.binding = GUF.Runtime.Binding("auras", unit)
                        if host.alternate then host.alternate.binding = host.binding end
                    end
                end
            end
        elseif entry then
            local ok, displayed = pcall(configureUnit, entry)
            if not ok then GUF.auraError = "native-aura-configuration" end
            local settings = GUF.Runtime.Settings("auras", unit)
            local cfg = settings.frames[unit]
            if unit == "target" then
                -- Flat owns the target's aura presentation, including disabled
                -- custom groups. Keep its dormant stock-display preference so
                -- existing snapshots survive; failed setup restores native auras.
                GUF.nativeAuraDesired[unit] = ok and (settings.general.frameStyle == "flat"
                    or displayed and cfg.auras.replaceDefault)
            end
        else
            for _, kind in ipairs({ "buffs", "debuffs" }) do
                for i = 1, GUF.auraFrameCount do disableHost(GUF.auraHosts[unit .. kind .. i]) end
            end
        end
    end
    if GUF.auraError then
        for _, host in pairs(GUF.auraHosts) do disableHost(host) end
        GUF.nativeAuraDesired = {}
    end
    GUF.ApplyNativeAuraVisibility()
    local privateStatus, privateReason
    if not selectedUnits or selectedUnits.player then privateStatus, privateReason = GUF.ApplyPrivateAuras() end
    GUF.SyncAuraPreviewVisibility()
    if GUF.auraError and not GUF.auraErrorReported then
        GUF.Print("Aura customization could not start. " .. GUF.auraError)
        GUF.auraErrorReported = true
    end
    if GUF.auraError then return "failed", "native-aura-configuration" end
    if privateStatus == "failed" then return privateStatus, privateReason end
end

function GUF.RefreshUnitAuras(unit)
    local entry = GUF.frames[unit]
    if not entry then return end
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        for i = 1, GUF.auraFrameCount do
            local host = GUF.auraHosts[unit .. kind .. i]
            if host and host.configured then
                local token = entry.frame.unit or unit
                for _, nativeHost in ipairs(host.alternate and { host, host.alternate } or { host }) do
                    for j, section in ipairs(nativeHost.sections) do
                        applyCandidates(nativeHost.container, "auras" .. j, section, token)
                    end
                    nativeHost.container:SetUnit(token)
                    if nativeHost.container.UpdateAllAuras then nativeHost.container:UpdateAllAuras() end
                end
            end
        end
    end
end
