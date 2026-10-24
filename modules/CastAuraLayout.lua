local _, GUF = ...
local anchorX, anchorY = GUF.CastAnchorX, GUF.CastAnchorY

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function parentRect(entry, parent)
    entry.castAuraParents = entry.castAuraParents or {}
    local rect = GUF.FrameRectInUnit(entry, parent)
    if rect then entry.castAuraParents[parent] = rect end
    return rect or entry.castAuraParents[parent]
end

local function ratioFor(entry, region)
    local scale, rootScale = region:GetEffectiveScale(), entry.frame:GetEffectiveScale()
    if number(scale) and number(rootScale) and scale > 0 and rootScale > 0 then return scale / rootScale end
end

local function atPoint(parent, point, relative, x, y, width, height, ratio)
    if not parent or not ratio then return end
    local left = parent.left + (parent.right - parent.left) * anchorX[relative] + x * ratio - width * ratio * anchorX[point]
    local bottom = parent.bottom + (parent.top - parent.bottom) * anchorY[relative] + y * ratio - height * ratio * anchorY[point]
    return { left = left, bottom = bottom, right = left + width * ratio, top = bottom + height * ratio }
end

local function sideFor(entry, cfg, rect)
    local root = parentRect(entry, entry.frame)
    if rect and root then return rect.top + rect.bottom >= root.top and 1 or -1 end
    if cfg.anchorPoint:find("TOP", 1, true) then return 1 end
    if cfg.anchorPoint:find("BOTTOM", 1, true) then return -1 end
    return 0
end

local function makeGroup(entry, key, cfg, region, width, height, boss)
    if not region or cfg.anchorPoint == "FREE" then return end
    local point, relative = GUF.AuraAnchor(cfg)
    local parent = GUF.AuraParent(entry, cfg)
    local x, y = GUF.AuraPosition(entry, cfg)
    local ratio = ratioFor(entry, region)
    if not ratio then GUF.pending = true; return end
    if boss then
        point, relative, parent = "CENTER", cfg.anchorPoint, entry.frame
        x, y = cfg.x / ratio, cfg.y / ratio
    end
    local parentBounds = parentRect(entry, parent)
    local rect = atPoint(parentBounds, point, relative, x, y, width, height, ratio)
    local group = { key = key, cfg = cfg, region = region, point = point, relative = relative,
        parent = parent, x = x, y = y, ratio = ratio, rects = {} }
    if rect then group.rects[1] = rect end
    -- Live and sample linked rows use the same one-icon anchor proxy.
    local proxy = cfg.size
    group.proxy = atPoint(parentBounds, point, relative, x, y, proxy, proxy, ratio)
    group.side = sideFor(entry, cfg, group.proxy or rect)
    return group
end

local function pair(auras, index)
    if auras.buffs[index].enabled and auras.debuffs[index].enabled then
        if auras.buffs[index].anchorOn then return "debuffs", "buffs" end
        if auras.debuffs[index].anchorOn then return "buffs", "debuffs" end
    end
end

local function addChild(group, width, height)
    local parent = group.proxy
    local relative = group.cfg.growV == "TOP" and group.point:gsub("BOTTOM", "TOP") or group.point:gsub("TOP", "BOTTOM")
    local y = group.cfg.growV == "TOP" and group.cfg.spacing or -group.cfg.spacing
    local rect = atPoint(parent, group.point, relative, 0, y, width, height, group.ratio)
    if rect then group.rects[#group.rects + 1] = rect end
end

-- Native aura-container dimensions are deliberately secret-wrapped. Model the
-- configured capacity, never native child visibility, amounts or frame counts.
local function capacitySize(host, cfg)
    local widthLimit = cfg.perRow * (cfg.size + cfg.spacing) - cfg.spacing + 1
    local x, y, width, rowHeight = 0, 0, 0, 0
    local function add(size, spacing)
        if x > 0 and x + size > widthLimit then x, y, rowHeight = 0, y + rowHeight + spacing, 0 end
        width, rowHeight = math.max(width, x + size), math.max(rowHeight, size)
        x = x + size + spacing
    end
    local sections = host.sections
    local enchantCfg = host.enchantSection and sections[host.enchantSection].cfg
    local enchantCount = enchantCfg and math.min(2, enchantCfg.perRow * enchantCfg.maxRows) or 0
    for _ = 1, enchantCount do add(enchantCfg.size, enchantCfg.spacing) end
    local limits = GUF.AuraSectionLimits(sections, enchantCfg, enchantCount)
    for i, section in ipairs(sections) do
        for _ = 1, limits[i] do add(section.size, section.cfg.spacing) end
    end
    return math.max(1, width), math.max(1, y + rowHeight)
end

local function overlaps(rect, cast, shift)
    return rect.left < cast.right and rect.right > cast.left
        and rect.bottom + shift < cast.top and rect.top + shift > cast.bottom
end

local function solve(groups, obstacles)
    local shifts = { [-1] = 0, [0] = 0, [1] = 0 }
    if #obstacles == 0 then return shifts end
    -- A common shift preserves independent same-side groups' separation.
    -- Repeat because moving one group may bring a later group into the bar.
    local parts = 0
    for _, group in ipairs(groups) do parts = parts + #group.rects end
    for _, side in ipairs({ -1, 1 }) do
        local shift = 0
        for _ = 1, parts * #obstacles + 1 do
            local previous = shift
            for _, group in ipairs(groups) do
                if group.side == side then
                    for _, rect in ipairs(group.rects) do
                        for _, obstacle in ipairs(obstacles) do
                            if overlaps(rect, obstacle, shift) then
                                if side == 1 then shift = math.max(shift, obstacle.top - rect.bottom)
                                else shift = math.min(shift, obstacle.bottom - rect.top) end
                            end
                        end
                    end
                end
            end
            if math.abs(shift - previous) < .001 then break end
        end
        shifts[side] = shift
    end
    return shifts
end

local function apply(entry, groups, force)
    GUF.AdjustTargetComboCast(entry)
    -- External Player rows avoid casts; internal Target rows keep their fixed
    -- housing and displace an overlapping owned cast. Auras avoid both bounds.
    local obstacles = {}
    local combo, cast = GUF.ComboAuraBounds(entry), GUF.CastAuraBounds(entry)
    if combo then obstacles[#obstacles + 1] = combo end
    if cast then obstacles[#obstacles + 1] = cast end
    local shifts = solve(groups, obstacles)
    local changed = false
    for _, group in ipairs(groups) do
        local region = group.region
        local protected = region:IsProtected()
        if not entry.configurationPreview and GUF.Restricted() and (GUF.Secret(protected) or protected) then GUF.pending = true
        else
            local y = group.y + shifts[group.side] / group.ratio
            local saved = region.goodUnitFramesCastAnchor
            local different = not saved or saved.point ~= group.point or saved.relative ~= group.relative
                or saved.parent ~= group.parent or math.abs(saved.x - group.x) > .001 or math.abs(saved.y - y) > .001
            if force or different then
                region:ClearAllPoints()
                region:SetPoint(group.point, group.parent, group.relative, group.x, y)
                region.goodUnitFramesCastAnchor = { point = group.point, parent = group.parent,
                    relative = group.relative, x = group.x, y = y }
            end
            changed = changed or different
        end
    end
    return changed
end

function GUF.ApplyLiveCastAuraLayout(entry)
    local auras, groups = GUF.db.frames[entry.unit].auras, {}
    for i = 1, GUF.auraFrameCount do
        local parentKind, childKind = pair(auras, i)
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local cfg, host = auras[kind][i], GUF.auraHosts[entry.unit .. kind .. i]
            if cfg.enabled and kind ~= childKind and host and host.configured and host.anchor then
                local width, height = capacitySize(host, cfg)
                local group = makeGroup(entry, kind .. i, cfg, host.anchor, width, height)
                if group then
                    if kind == parentKind and auras[childKind][i].anchorMode ~= "SEQUENTIAL" then
                        local child = GUF.auraHosts[entry.unit .. childKind .. i]
                        if child and child.configured then
                            width, height = capacitySize(child, auras[childKind][i])
                            addChild(group, width, height)
                        end
                    end
                    groups[#groups + 1] = group
                end
            end
        end
    end
    local boss, host = auras.bossDebuffs, entry.unit == "player" and GUF.privateAuraHost
    if boss.enabled and host and host.signature then
        local group = makeGroup(entry, "boss", boss, host.container, boss.perRow * 34 - 2, boss.maxRows * 34 - 2, true)
        if group then groups[#groups + 1] = group end
    end
    return apply(entry, groups, true)
end

local function sampleSize(host)
    if not host or not host.previewUsed then return end
    local width, height = host.frame:GetSize()
    if number(width) and number(height) and width > 0 and height > 0 then return width, height end
end

function GUF.ApplyPreviewCastAuraLayout(entry, pool, auras, force)
    local groups = {}
    for i = 1, GUF.auraFrameCount do
        local parentKind, childKind = pair(auras, i)
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local cfg, host = auras[kind][i], pool[kind .. i]
            local width, height = sampleSize(host)
            if cfg.enabled and kind ~= childKind and width then
                local group = makeGroup(entry, kind .. i, cfg, host.frame, width, height)
                if group then
                    if kind == parentKind and auras[childKind][i].anchorMode ~= "SEQUENTIAL" then
                        width, height = sampleSize(pool[childKind .. i])
                        if width then addChild(group, width, height) end
                    end
                    groups[#groups + 1] = group
                end
            end
        end
    end
    local boss, host = auras.bossDebuffs, pool.boss
    local width, height = sampleSize(host)
    if entry.unit == "player" and boss.enabled and width then
        local group = makeGroup(entry, "boss", boss, host.frame, width, height, true)
        if group then groups[#groups + 1] = group end
    end
    return apply(entry, groups, force)
end
