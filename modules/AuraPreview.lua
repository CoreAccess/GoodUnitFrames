local _, GUF = ...

-- Public sample data only. These buttons never use native aura templates or unit attributes.
local samples = {
    buffs = {
        { "Rejuvenation", "Spell_Nature_Rejuvenation" }, { "Power Word: Shield", "Spell_Holy_PowerWordShield" },
        { "Regrowth", "Spell_Nature_Regeneration" }, { "Flash Heal", "Spell_Holy_FlashHeal" },
        { "Lightning Shield", "Spell_Nature_LightningShield" }, { "Devotion Aura", "Spell_Holy_DevotionAura" },
        { "Arcane Intellect", "Spell_Holy_MagicalSentry" }, { "Fortitude", "Spell_Holy_WordFortitude" },
        { "Divine Shield", "Spell_Holy_DivineIntervention" }, { "Innervate", "Spell_Nature_Lightning" },
        { "Icy Veins", "Spell_Frost_ColdHearted" }, { "Renew", "Spell_Holy_Renew" },
    },
    debuffs = {
        { "Shadow Word: Pain", "Spell_Shadow_ShadowWordPain" }, { "Curse", "Spell_Shadow_CurseOfSargeras" },
        { "Poison", "Spell_Nature_CorrosiveBreath" }, { "Disease", "Spell_Shadow_AbominationExplosion" },
        { "Rupture", "Ability_Rogue_Rupture" }, { "Immolation", "Spell_Fire_Immolation" },
        { "Frost Nova", "Spell_Frost_FrostNova" }, { "Corruption", "Spell_Shadow_AbominationExplosion" },
        { "Polymorph", "Spell_Nature_Polymorph" }, { "Rend", "Ability_Gouge" },
        { "Flame Shock", "Spell_Fire_FlameShock" }, { "Fear", "Spell_Shadow_Possession" },
    },
}
local borderColors = { { .2, .6, 1 }, { .6, 0, 1 }, { 0, .6, 0 }, { .6, .4, 0 }, { .8, 0, 0 } }
local hosts = {}
local driver = CreateFrame("Frame", nil, UIParent)
driver:Hide()

function GUF.SyncAuraPreviewVisibility()
    -- Alpha is reversible during combat; keep native containers updating normally underneath.
    for _, host in pairs(GUF.auraHosts) do
        host.container:SetAlpha(host.unit == GUF.auraPreviewUnit and 0 or 1)
        if host.alternate then host.alternate.container:SetAlpha(host.unit == GUF.auraPreviewUnit and 0 or 1) end
    end
    if GUF.privateAuraHost then
        GUF.privateAuraHost.container:SetAlpha(GUF.auraPreviewUnit == "player" and 0 or 1)
    end
end

local function getHost(key, entry)
    local pool = entry and entry.optionsPreview and entry.auraSamples or hosts
    local host = pool[key]
    if not host then
        host = { buttons = {}, count = 0, frame = CreateFrame("Frame", nil, entry and entry.optionsPreview and entry.frame or UIParent) }
        pool[key] = host
        host.frame.goodUnitFramesOwned = true
        host.anchor = CreateFrame("Frame", nil, host.frame)
        host.anchor.goodUnitFramesOwned = true
        host.anchor:EnableMouse(false)
        host.frame:SetFrameStrata(entry and entry.optionsPreview and entry.frame:GetFrameStrata() or "MEDIUM")
        host.frame:SetFrameLevel(entry and entry.optionsPreview and entry.frame:GetFrameLevel() + 30 or 20)
        host.frame:Hide()
    end
    return host
end

local function getButton(host, index)
    local record = host.buttons[index]
    if record then return record end
    local button = CreateFrame("Button", nil, host.frame)
    button.goodUnitFramesOwned = true
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(.07, .93, .07, .93)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button:GetFrameLevel() + 3)
    record = { button = button, icon = button.icon, cooldown = cooldown,
        timer = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        stack = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"),
        duration = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        border = overlay:CreateTexture(nil, "OVERLAY") }
    record.border:SetAllPoints(button)
    record.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    record.border:SetTexCoord(.296875, .5703125, 0, .515625)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(record.name)
        GameTooltip:AddLine("Preview - sample " .. record.kind .. ".", 1, 1, 1)
        GameTooltip:AddLine("Previews appearance and placement. Filters and sorting apply to real auras. Sample icons demonstrate appearance and placement.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnHide", hideTooltip)
    host.buttons[index] = record
    return record
end

local function updateTimer(record, now)
    local duration = record.fakeDuration
    local elapsed = (now - (record.previewStarted or GUF.auraPreviewStarted or now) + record.seed * 17) % duration
    local start = now - elapsed
    if not record.fakeStart or math.abs(record.fakeStart - start) > 1 then
        record.fakeStart = start
        record.cooldown:SetCooldown(start, duration)
    end
    local remaining = math.ceil(duration - elapsed)
    local label = remaining >= 60 and string.format("%dm", math.ceil(remaining / 60)) or tostring(remaining)
    record.timer:SetText(label)
    record.duration:SetText(label)
end

function GUF.TickSpecimenAuras(entry)
    for _, host in pairs(entry.auraSamples or {}) do
        if host.frame:IsShown() then
            for i = 1, host.count do updateTimer(host.buttons[i], GetTime()) end
        end
    end
    if entry.castAuraPreviewSettings and GUF.ApplyPreviewCastAuraLayout(entry, entry.auraSamples, entry.castAuraPreviewSettings, false)
        and GUF.UpdateOptionsPreviewBounds then GUF.UpdateOptionsPreviewBounds(entry) end
end

local function styleSample(record, section, frameCfg, seed, sample)
    record.name, record.kind, record.seed = sample[1], section.kind == "buffs" and "buff" or "debuff", seed
    record.fakeDuration = 45 + (seed % 8) * 30
    record.button.icon:SetTexture("Interface\\Icons\\" .. sample[2])
    GUF.StyleAuraButton(record, section, frameCfg)
    local text = section.cfg
    -- The owned font strings above provide predictable sample timers, with the same styling as live text.
    record.cooldown:SetHideCountdownNumbers(true)
    record.timer:SetShown(not text.disableBlizzardCC)
    record.duration:SetShown(text.durationText == true)
    record.stack:SetText(not text.disableStacks and seed % 3 == 0 and tostring(2 + seed % 5) or "")
    record.border:SetShown(section.kind == "debuffs" and section.cfg.debuffBorder)
    record.border:SetVertexColor(unpack(borderColors[(seed - 1) % #borderColors + 1]))
    updateTimer(record, GetTime())
    record.button:Show()
end

local function descriptors(kind, cfg, enchantCfg)
    local result, sections = {}, GUF.AuraSections(kind, cfg)
    local enchantCount = kind == "buffs" and cfg == enchantCfg
        and math.min(2, cfg.perRow * cfg.maxRows) or 0
    -- Like live enchants, sample enchants have priority and occupy existing buff slots.
    for i = 1, enchantCount do
        local sample = i == 1 and { "Main-hand enchant", "Spell_Fire_Immolation" }
            or { "Off-hand enchant", "Spell_Nature_RockBiter" }
        result[#result + 1] = { section = { kind = kind, cfg = cfg, size = cfg.size }, seed = i, sample = sample }
    end
    local limits = GUF.AuraSectionLimits(sections, enchantCount > 0 and cfg or nil, enchantCount)
    for i, section in ipairs(sections) do
        for n = 1, limits[i] do
            local seed = #result + 1
            result[#result + 1] = { section = section, seed = seed,
                sample = samples[kind][(seed - 1) % #samples[kind] + 1] }
        end
    end
    return result
end

local function renderFlow(key, entry, cfg, items)
    local host = getHost(key, entry)
    host.previewUsed = true
    local scale, parentScale = entry.frame:GetEffectiveScale(), entry.optionsPreview and entry.frame:GetEffectiveScale() or UIParent:GetEffectiveScale()
    if GUF.Secret(scale) or GUF.Secret(parentScale) then return end
    host.frame:SetScale(scale / parentScale)
    local widthLimit = cfg.perRow * (cfg.size + cfg.spacing) - cfg.spacing + 1
    local x, y, rowHeight, width = 0, 0, 0, 1
    local corner = (cfg.growV == "TOP" and "BOTTOM" or "TOP") .. (cfg.growH == "LEFT" and "RIGHT" or "LEFT")
    for i, item in ipairs(items) do
        local size, spacing = item.section.size, item.section.cfg.spacing
        if x > 0 and x + size > widthLimit then x, y, rowHeight = 0, y + rowHeight + cfg.spacing, 0 end
        local record = getButton(host, i)
        record.previewStarted = entry.previewStarted
        styleSample(record, item.section, GUF.db.frames[entry.unit], item.seed, item.sample)
        record.button:ClearAllPoints()
        record.button:SetPoint(corner, host.frame, corner, cfg.growH == "LEFT" and -x or x, cfg.growV == "TOP" and y or -y)
        rowHeight, width = math.max(rowHeight, size), math.max(width, x + size)
        x = x + size + spacing
    end
    host.count = #items
    for i = #items + 1, #host.buttons do host.buttons[i].button:Hide() end
    host.frame:SetSize(width, math.max(1, y + rowHeight))
    host.frame:ClearAllPoints()
    local point, relative = GUF.AuraAnchor(cfg)
    local x, y = GUF.AuraPosition(entry, cfg)
    host.frame:SetPoint(point, entry.optionsPreview and cfg.anchorPoint == "FREE" and entry.frame or GUF.AuraParent(entry, cfg), relative, x, y)
    -- Live linked containers attach to a one-icon proxy at the first icon,
    -- not the far edge of the complete multi-row capacity/sample rectangle.
    host.anchor:ClearAllPoints(); host.anchor:SetPoint(point, host.frame, point, 0, 0)
    host.anchor:SetSize(cfg.size, cfg.size)
    local kind, index = key:match("^(%a+)(%d+)$")
    if kind and not entry.optionsPreview and GUF.BindConfigurationDrag then
        index = tonumber(index)
        host.grip = host.grip or CreateFrame("Frame", nil, host.frame)
        host.grip.goodUnitFramesOwned = true
        host.grip:SetAllPoints(host.frame)
        host.grip:SetFrameLevel(host.frame:GetFrameLevel() + 8)
        GUF.BindConfigurationDrag(host.grip, entry.unit, function()
            local saved = GUF.db.frames[entry.unit].auras[kind][index]
            if not saved.enabled and GUF.configurationShowAll then
                saved.enabled, saved.anchorPoint, saved.growV = true, cfg.anchorPoint, cfg.growV
                saved.x, saved.y, saved.legacyPoint = cfg.x, cfg.y, nil
            end
            return saved
        end, "auras", { kind = kind, index = index })
    end
    host.frame:Show()
    return host
end

local function renderBoss(entry, cfg)
    if not cfg.enabled then return end
    local host = getHost("boss", entry)
    host.previewUsed = true
    local scale, parentScale = entry.frame:GetEffectiveScale(), entry.optionsPreview and entry.frame:GetEffectiveScale() or UIParent:GetEffectiveScale()
    if GUF.Secret(scale) or GUF.Secret(parentScale) then return end
    host.frame:SetScale(scale / parentScale * cfg.size / 32)
    host.frame:SetSize(cfg.perRow * 34 - 2, cfg.maxRows * 34 - 2)
    host.frame:ClearAllPoints()
    local ratio = cfg.size / 32
    local x, y = cfg.x, cfg.y
    host.frame:SetPoint("CENTER", cfg.anchorPoint == "FREE" and not entry.optionsPreview and UIParent or entry.frame,
        cfg.anchorPoint == "FREE" and "CENTER" or cfg.anchorPoint, x / ratio, y / ratio)
    local style = GUF.AuraFrameDefaults(true, 1)
    style.cooldown, style.disableBlizzardCC = cfg.showCooldown, not cfg.showCooldownNumbers
    style.disableStacks, style.debuffBorder = true, false
    host.count = cfg.perRow * cfg.maxRows
    for i = 1, host.count do
        local record = getButton(host, i)
        record.previewStarted = entry.previewStarted
        styleSample(record, { kind = "debuffs", cfg = style, size = 32 }, GUF.db.frames.player, i, samples.debuffs[(i - 1) % #samples.debuffs + 1])
        record.button:ClearAllPoints()
        record.button:SetPoint("TOPLEFT", host.frame, "TOPLEFT", ((i - 1) % cfg.perRow) * 34, -math.floor((i - 1) / cfg.perRow) * 34)
    end
    for i = host.count + 1, #host.buttons do host.buttons[i].button:Hide() end
    host.frame:Show()
end

function GUF.RefreshAuraPreview(specimen)
    if not specimen and not GUF.auraPreviewUnit then return end
    local entry = specimen or GUF.configurationPreviewEntry or GUF.frames[GUF.auraPreviewUnit]
    if not entry then return end
    entry.auraSamples = entry.auraSamples or {}
    local pool = entry.optionsPreview and entry.auraSamples or hosts
    for _, host in pairs(pool) do host.previewUsed = false end
    local auras = GUF.Copy(GUF.db.frames[entry.unit].auras)
    -- Options specimens mirror saved enablement across every editor tab. Only
    -- the separate legacy mover diagnostic may force disabled aura groups on.
    if not entry.optionsPreview and GUF.configurationShowAll then
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local any = false
            for _, cfg in ipairs(auras[kind]) do if cfg.enabled then any = true end end
            if not any then
                local cfg = auras[kind][1]
                cfg.enabled, cfg.perRow, cfg.maxRows = true, 8, 2
                cfg.anchorOn, cfg.legacyPoint = false, nil
                cfg.anchorPoint, cfg.growV, cfg.y = kind == "buffs" and "BOTTOMLEFT" or "TOPLEFT",
                    kind == "buffs" and "BOTTOM" or "TOP", kind == "buffs" and -6 or 6
            end
        end
    end
    local enchantCfg = GUF.AuraEnchantSettings(entry.unit, auras)
    for i = 1, GUF.auraFrameCount do
        local parentKind, childKind
        if auras.buffs[i].enabled and auras.debuffs[i].enabled then
            if auras.buffs[i].anchorOn then parentKind, childKind = "debuffs", "buffs"
            elseif auras.debuffs[i].anchorOn then parentKind, childKind = "buffs", "debuffs" end
        end
        local sequential = childKind and auras[childKind][i].anchorMode == "SEQUENTIAL"
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local cfg = auras[kind][i]
            if cfg.enabled and not (sequential and kind == childKind) then
                local layout, items = GUF.Copy(cfg), descriptors(kind, cfg, enchantCfg)
                if kind == childKind then layout.growH, layout.growV = auras[parentKind][i].growH, auras[parentKind][i].growV end
                if sequential then
                    for _, item in ipairs(descriptors(childKind, auras[childKind][i], enchantCfg)) do items[#items + 1] = item end
                end
                renderFlow(kind .. i, entry, layout, items)
            end
        end
        if parentKind and not sequential then
            local parent, child, cfg = pool[parentKind .. i], pool[childKind .. i], auras[parentKind][i]
            if parent and child then
                local point = GUF.AuraAnchor(cfg)
                local relative = cfg.growV == "TOP" and point:gsub("BOTTOM", "TOP") or point:gsub("TOP", "BOTTOM")
                child.frame:ClearAllPoints()
                child.frame:SetPoint(point, parent.anchor, relative, 0, cfg.growV == "TOP" and cfg.spacing or -cfg.spacing)
            end
        end
    end
    if entry.unit == "player" then renderBoss(entry, auras.bossDebuffs) end
    for _, host in pairs(pool) do if not host.previewUsed then host.frame:Hide() end end
    GUF.ApplyPreviewCastAuraLayout(entry, pool, auras, true)
    if entry.optionsPreview then entry.castAuraPreviewSettings = auras end
    if not entry.optionsPreview then GUF.SyncAuraPreviewVisibility() end
end

function GUF.SetConfigurationAuraPreview(enabled, unit)
    if enabled then
        if GUF.Restricted() then return end
        GUF.auraPreviewUnit, GUF.auraPreviewStarted = unit, GUF.auraPreviewStarted or GetTime()
        GUF.RefreshAuraPreview()
        driver:Show()
    else
        GUF.auraPreviewUnit, GUF.auraPreviewStarted = nil, nil
        driver:Hide()
        for _, host in pairs(hosts) do
            host.frame:Hide()
            if host.grip then host.grip:SetScript("OnUpdate", nil); host.grip.drag = nil end
        end
        GUF.SyncAuraPreviewVisibility()
    end
end

local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    if GUF.Restricted() then GUF.SetConfigurationMode(false); return end
    elapsed = elapsed + delta
    if elapsed < .1 then return end
    elapsed = 0
    local now = GetTime()
    for _, host in pairs(hosts) do
        if host.frame:IsShown() then
            for i = 1, host.count do updateTimer(host.buttons[i], now) end
        end
    end
end)
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" and GUF.auraPreviewUnit then GUF.SetConfigurationMode(false) end
end)
