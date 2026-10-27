local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "ArtisticResources")
end
local unpack = unpack or table.unpack

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function yes(value)
    return not GUF.Secret(value) and (value == true or value == 1)
end

local function targetComboReady(frame)
    if not frame or frame ~= ComboFrame then return false end
    -- Forever's target ring uses a mixin Update method and a ComboPoints array;
    -- it need not publish the old global controller's maxComboPoints field.
    -- Recognize it while hidden at zero, before the next combat begins.
    return (number(frame.maxComboPoints) and frame.maxComboPoints > 0)
        or (type(frame.Update) == "function" and type(frame.ComboPoints) == "table" and #frame.ComboPoints > 0)
end

local function playerClass()
    local class
    if UnitClassBase then class = UnitClassBase("player")
    else local _, token = UnitClass("player"); class = token end
    if not GUF.Secret(class) then return class end
end

function GUF.SupportsClassResources()
    local class = playerClass()
    -- Combo rows remain automatic; the other eligible Player resources share
    -- the existing Enable control, with fixed appearance and placement.
    return class == "WARLOCK" or GUF.UsesRunes() or GUF.RetailResourceKind("player") ~= nil
end

local function candidates()
    local class = playerClass()
    local result = {}
    local function add(frame) if frame then result[#result + 1] = frame end end
    if class == "ROGUE" or class == "DRUID" then
        -- Prefer the target's functioning controller to an inactive Player bar.
        if targetComboReady(ComboFrame) then add(ComboFrame) end
        if class == "ROGUE" then add(RogueComboPointBarFrame) else add(DruidComboPointBarFrame) end
        if not targetComboReady(ComboFrame) then add(ComboFrame) end
    elseif class == "WARLOCK" then
        add(WarlockPowerFrame)
        -- Other Mists resources are bars, not five shards. Leave those native.
        if not WarlockPowerFrame or not WarlockPowerFrame.activeBar or WarlockPowerFrame.activeBar == ShardBarFrame then
            add(ShardBarFrame)
        end
    end
    return result
end

local function nodes(controller)
    local result, seen = {}, {}
    local function add(node)
        if node and node.SetPoint and node.GetScale and not seen[node] then
            seen[node] = true
            result[#result + 1] = node
        end
    end
    local list = (controller == ComboFrame and controller.ComboPoints) or controller.classResourceButtonTable
        or controller.ComboPoints or controller.comboPoints
        or controller.Shards or controller.shards
    if type(list) == "table" then for _, node in ipairs(list) do add(node) end end
    if #result == 0 then
        local name = controller:GetName()
        for i = 1, 10 do
            add(controller["ComboPoint" .. i] or controller["Shard" .. i]
                or (controller == ComboFrame and _G["ComboPoint" .. i])
                or (name and (_G[name .. "ComboPoint" .. i] or _G[name .. "Shard" .. i])))
        end
    end
    if targetComboReady(controller) then
        local capacity = controller.maxComboPoints
        if not number(capacity) or capacity <= 0 then
            local unit = controller.unit
            if GUF.Secret(unit) or (unit ~= "player" and unit ~= "vehicle") then unit = "player" end
            if UnitPowerMax and Enum and Enum.PowerType then
                capacity = UnitPowerMax(unit, Enum.PowerType.ComboPoints)
            end
        end
        -- Some legacy versions keep an unused first point in a nine-slot pool.
        -- Select the exact native slice; trimming the tail alone shifts fills.
        local first = controller.startComboPointIndex
        if not number(first) or first < 1 then first = 1 end
        first = math.floor(first)
        local last = #result
        if number(capacity) and capacity > 0 then last = math.min(last, first + math.floor(capacity) - 1) end
        local active = {}
        for i = first, last do active[#active + 1] = result[i] end
        result = active
    end
    return result
end

local function queue(entry)
    local state = entry.artisticLayout
    if state and state.active and not state.resourceWriting then
        state.resourcesDirty = true
        state.resourceBlocked = {}
        GUF.DeferRuntime("native-readiness")
    end
end

function GUF.ArtisticOwnsResource(entry, controller)
    if GUF.OwnsNativeComboPoints(controller) then return true end
    local state = entry.artisticLayout
    if not state or not state.active then return false end
    -- Own only the Priest controller's cosmetic children. Keep its root out
    -- of the legacy resource positioning path, including saved old offsets.
    if GUF.isRetail and entry.unit == "player" and InsanityBarFrame and controller == InsanityBarFrame then return true end
    if state.resourceSuppressed and state.resourceSuppressed[controller] then return true end
    for native in pairs(state.resourceControllers or {}) do
        if native == controller or native:GetParent() == controller then return true end
    end
    return false
end

function GUF.RestoreArtisticResources(entry)
    GUF.RestoreComboPoints(entry)
    local state = entry.artisticLayout
    if not state then return end
    state.resourceWriting = true
    for controller, saved in pairs(state.resourceControllers or {}) do
        controller:SetFrameLevel(saved.level)
        for _, node in ipairs(saved.nodes) do
            node.frame:ClearAllPoints()
            for _, point in ipairs(node.points) do node.frame:SetPoint(unpack(point)) end
            node.frame:SetScale(node.scale)
        end
        for region in pairs(saved.hidden) do leaseAlpha(region, nil) end
    end
    for controller in pairs(state.resourceSuppressed or {}) do leaseAlpha(controller, nil) end
    state.resourceSuppressed, state.resourceLane = {}, nil
    state.resourceControllers, state.resourceWriting = {}, nil
    if state.resourceRail then state.resourceRail:Hide() end
end

function GUF.LayoutArtisticResources(entry)
    if entry.configurationPreview then return end
    local state = entry.artisticLayout
    if not state or not state.active then return end
    if GUF.Restricted() or GUF.editing then GUF.DeferRuntime("native-readiness"); return end
    state.resourcesDirty = nil
    state.resourceBlocked = state.resourceBlocked or {}
    GUF.RestoreArtisticResources(entry)
    if entry.unit == "target" or GUF.UsesSegmentedResources("player") or GUF.HasRetailResourceClass("player") then
        GUF.LayoutComboPoints(entry); return
    end
    if entry.unit ~= "player" then return end
    local controllers = candidates()
    local controller, points
    -- Pre-position an eligible hidden controller too, so its first in-combat
    -- appearance does not require protected geometry changes.
    for _, item in ipairs(controllers) do
        local list = nodes(item)
        if #list > 0 then
            if not controller then controller, points = item, list end
            if targetComboReady(item) or (yes(item:IsVisible()) and number(item:GetAlpha()) and item:GetAlpha() > 0) then
                controller, points = item, list; break
            end
        end
    end
    if not controller then return end
    local settings = GUF.Runtime.Settings("layout", "player").frames.player.indicators.resource
    GUF.TransformRegion(controller, settings, false)
    for _, root in pairs(entry.regions.resource) do
        if controller:GetParent() == root then GUF.TransformRegion(root, settings, false) end
    end
    local saved = { level = controller:GetFrameLevel(), nodes = {}, hidden = {} }
    local parentScale = controller:GetEffectiveScale()
    local coreScale = entry.frame:GetEffectiveScale()
    if not number(parentScale) or not number(coreScale) or parentScale <= 0 or coreScale <= 0
        or not number(saved.level) then state.resourceBlocked[controller] = true; return end
    for _, node in ipairs(points) do
        local anchors, width, height, scale = GUF.ReadPoints(node), node:GetWidth(), node:GetHeight(), node:GetScale()
        if not anchors or not number(width) or not number(height) or not number(scale)
            or width <= 0 or height <= 0 or scale <= 0 then state.resourceBlocked[controller] = true; return end
        -- Legacy 12x12 frames include 16-high textures and a 20-high shine span.
        local footprint = controller == ComboFrame and math.max(20, width, height) or math.max(width, height)
        saved.nodes[#saved.nodes + 1] = { frame = node, points = anchors, scale = scale, size = footprint }
    end
    if not state.resourceRail then
        state.resourceRail = GUF.Runtime.CreateFrame("Frame", nil, state.ornaments)
        state.resourceRail.goodUnitFramesOwned = true
        state.resourceRail:EnableMouse(false)
        state.resourceRail.wells, state.resourceRail.links = {}, {}
        state.resourceRail:Hide()
        GUF.Runtime.Constructed()
    end
    local rail = state.resourceRail
    rail.wells, rail.links = rail.wells or {}, rail.links or {}
    local count = #points
    local diameter = math.min(18 * state.scale * settings.scale, 20 * state.scale)
    local gap = 2 * state.scale
    -- Keep native glyphs readable when the portrait shrinks. Use additional
    -- outward columns instead of overlapping five full-size wells vertically.
    local extent = math.min(state.portraitHeight * .35,
        state.portraitHeight / 2 - diameter / 2 - 4 * state.scale)
    local rows = math.max(1, math.min(count, 5, math.floor(2 * extent / (diameter + gap)) + 1))
    rail:ClearAllPoints()
    rail:SetPoint("CENTER", state.rim, "CENTER", settings.x, settings.y)
    rail:SetSize(state.portraitWidth, state.portraitHeight)
    rail:SetAlpha(settings.alpha)
    for _, well in ipairs(rail.wells) do well:Hide() end
    for _, link in ipairs(rail.links) do link:Hide() end
    state.resourceControllers[controller] = saved
    state.resourceLane = true
    for _, other in ipairs(controllers) do
        if other ~= controller then
            state.resourceSuppressed[other] = true
            leaseAlpha(other, 0)
        end
    end
    state.resourceBlocked[controller] = nil
    state.resourceWriting = true
    -- Parentage, glyphs, fill states, capacity and animations remain native.
    -- Only anchors/uniform scale change; their native fill/shine controllers stay.
    controller:SetFrameLevel(state.badgeLayer:GetFrameLevel() + 1)
    local previous, linkIndex = {}, 0
    for i, node in ipairs(saved.nodes) do
        local factor = diameter * .78 / node.size * coreScale / parentScale
        local col, row = math.floor((i - 1) / rows), (i - 1) % rows
        local columnCount = math.min(rows, count - col * rows)
        local y = columnCount == 1 and 0 or extent * (1 - 2 * row / (columnCount - 1))
        local radius = state.portraitWidth / 2 + 14 * state.scale + col * (diameter + gap)
        local x = -math.sqrt(math.max(0, radius * radius - y * y))
        local well = rail.wells[i]
        if not well then well = GUF.CreateArtisticBadge(rail); rail.wells[i] = well end
        well:SetFrameLevel(state.badgeLayer:GetFrameLevel())
        well:ClearAllPoints()
        well:SetPoint("CENTER", rail, "CENTER", x, y)
        well:SetSize(diameter, diameter)
        well.icon:Hide(); well.text:SetText("")
        well:Show()
        local last = previous[col]
        if last then
            linkIndex = linkIndex + 1
            local link = rail.links[linkIndex]
            if not link then
                link = rail:CreateTexture(nil, "BACKGROUND")
                link.goodUnitFramesOwned = true
                rail.links[linkIndex] = link
            end
            GUF.PaintBlizzardBarSlice(link, entry.unit, 1, 2)
            local dx, dy = x - last.x, y - last.y
            link:ClearAllPoints()
            link:SetPoint("CENTER", rail, "CENTER", (x + last.x) / 2, (y + last.y) / 2)
            link:SetSize(math.sqrt(dx * dx + dy * dy), 3 * state.scale)
            link:SetRotation(math.atan2(dy, dx))
            link:Show()
        end
        previous[col] = { x = x, y = y }
        node.frame:SetScale(factor)
        node.frame:ClearAllPoints()
        node.frame:SetPoint("CENTER", rail, "CENTER", x * coreScale / (parentScale * factor),
            y * coreScale / (parentScale * factor))
        if not node.frame.foreverArtisticResourceHooked then
            GUF.NativeProperties.Hook("ArtisticResources:1", node.frame, "SetPoint", function() queue(entry) end)
            node.frame.foreverArtisticResourceHooked = true
        end
    end
    for _, region in pairs({ controller:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            saved.hidden[region] = true
            leaseAlpha(region, 0)
        end
    end
    if not controller.foreverArtisticResourceHooked then
        for _, method in ipairs({ "Layout", "UpdateMax", "UpdateMaxPower", "Setup", "SetUpCurrentPower" }) do
            if type(controller[method]) == "function" then GUF.NativeProperties.Hook("ArtisticResources:2", controller, method, function() queue(entry) end) end
        end
        GUF.NativeProperties.HookScript("ArtisticResources:script:1", controller, "OnShow", function() GUF.UpdateArtisticResources(entry); queue(entry) end)
        GUF.NativeProperties.HookScript("ArtisticResources:script:2", controller, "OnHide", function() GUF.UpdateArtisticResources(entry) end)
        controller.foreverArtisticResourceHooked = true
    end
    if controller == ComboFrame and not controller.foreverArtisticLegacyHooked then
        if type(ComboFrame_UpdateMax) == "function" then GUF.NativeProperties.Hook("ArtisticResources:3", "ComboFrame_UpdateMax", function() queue(entry) end) end
        controller.foreverArtisticLegacyHooked = true
    end
    state.resourceWriting, state.resourcesDirty = nil, nil
    GUF.UpdateArtisticResources(entry)
end

function GUF.UpdateArtisticResources(entry)
    local state = entry.artisticLayout
    if not state or not state.active or entry.configurationPreview then return end
    if entry.unit == "target" or GUF.UsesSegmentedResources("player") then GUF.UpdateComboPoints(entry); return end
    GUF.RestoreComboPoints(entry)
    if entry.unit ~= "player" then return end
    if state.resourcesDirty then GUF.DeferRuntime("native-readiness") end
    -- Controllers can be loaded or become eligible after the initial layout.
    for _, controller in ipairs(candidates()) do
        local preferredRing = targetComboReady(controller)
            and not (state.resourceControllers and state.resourceControllers[controller])
        if (preferredRing or not GUF.ArtisticOwnsResource(entry, controller))
            and not (state.resourceBlocked and state.resourceBlocked[controller])
            and (preferredRing or yes(controller:IsShown())) and #nodes(controller) > 0 then
            state.resourcesDirty = true
            GUF.DeferRuntime("native-readiness")
        end
    end
    if not state.resourceRail then return end
    local cfg, visible = GUF.Runtime.Settings("layout", "player").frames.player, false
    for controller in pairs(state.resourceSuppressed or {}) do leaseAlpha(controller, 0) end
    for controller, saved in pairs(state.resourceControllers or {}) do
        if yes(controller:IsVisible()) then visible = true end
        for region in pairs(saved.hidden) do leaseAlpha(region, 0) end
        -- Mixin versions need not expose the old UpdateMax global. Notice pool
        -- or capacity changes without taking over their live point-state update.
        local active = nodes(controller)
        local changed = #active ~= #saved.nodes
        if not changed then
            for i, node in ipairs(active) do
                if node ~= saved.nodes[i].frame then changed = true; break end
            end
        end
        if changed then queue(entry) end
    end
    -- Match native show/fade state without multiplying the resource opacity twice.
    for controller in pairs(state.resourceControllers or {}) do
        local alpha = controller:GetAlpha()
        state.resourceRail:SetAlpha(number(alpha) and alpha or cfg.indicators.resource.alpha)
    end
    state.resourceRail:SetShown(visible and not cfg.hide.resource)
end

-- Reserve an internal row using configured dimensions only. Never change the
-- secure root, native bars, saved heights or portrait/Level geometry.
function GUF.LayoutArtisticResourceStack(entry, force)
    local state, row = entry.artisticLayout, entry.comboRow
    if not GUF.IsManagedUnit(entry.unit) then return end
    if not state or not row then return end
    if not state.active then state.targetComboStack = nil; return end
    local bars = state.renderBars or entry.configurationPreview and { health = entry.health, power = entry.power }
    if not bars then return end
    if not entry.configurationPreview and GUF.editing then GUF.DeferRuntime("native-readiness"); return end
    local shown = row.displayed == true
    local previous = state.targetComboStack
    local lanes = shown and ((row.primaryShown ~= false and 1 or 0) + (row.auxShown and 1 or 0)) or 1
    lanes = math.max(1, lanes)
    if not force and previous and previous.shown == shown and previous.noPower == state.noPower
        and previous.lanes == lanes and previous.primary == row.primaryShown then return end
    local scale = state.scale
    local bottom = state.healthY - state.healthRowHeight - state.powerRowHeight
    local baseHealth = state.noPower and state.healthRowHeight + state.powerRowHeight - state.healthTopInset - 2 * scale
        or state.healthFillHeight
    local basePower = state.noPower and 0 or state.powerFillHeight
    local total = baseHealth + basePower
    local cfg = GUF.PresentationFrameSettings(entry).indicators.resource
    local reserve = shown and math.min((8 * cfg.scale + 1) * scale * lanes, total * (lanes > 1 and .45 or .3)) or 0
    local factor = (total - reserve) / total
    local healthHeight, powerHeight = baseHealth * factor, basePower * factor
    local powerY = state.powerY + baseHealth - healthHeight
    local stack = { shown = shown, noPower = state.noPower, powerY = powerY, lanes = lanes, primary = row.primaryShown,
        comboY = bottom + 2 * scale + reserve, height = reserve,
        healthHeight = healthHeight, powerHeight = powerHeight }
    state.targetComboStack = stack
    local writing, geometryWriting = entry.layoutWriting, GUF.geometryWriting
    entry.layoutWriting, GUF.geometryWriting = true, true
    local inset = 1.5 * scale
    local x, width = state.housingX + inset, state.housingWidth - 2 * inset
    stack.x, stack.width = x, width
    for _, kind in ipairs({ "health", "power" }) do
        local bar = bars[kind]
        local y = kind == "health" and state.healthY - state.healthTopInset or powerY - state.dividerHeight
        local height = kind == "health" and healthHeight or math.max(1, powerHeight)
        if state.renderBars then GUF.LayoutArtisticRenderedBar(entry, kind, x, y, width, height)
        else
            bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", x, y)
            bar:SetSize(width, height)
        end
        local area = state.textAreas[kind]
        area:ClearAllPoints(); area:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", state.barX + 4 * scale, y)
        area:SetSize(state.barWidth - 8 * scale, height)
        local shell = kind == "health" and state.healthShell or state.powerShell
        if shell then
            shell:ClearAllPoints(); shell:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", x, y)
            shell:SetSize(width, height)
        end
    end
    bars.power:SetShown(not state.noPower)
    if row.integrated then
        row.baseX, row.baseY = x, stack.comboY
        row:SetSize(width, math.max(state.dividerHeight, reserve))
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", row.baseX, row.baseY)
        -- Divide the visible span at the portrait's curved edge, rather than
        -- assigning its entire exposed underlap to the final point. All inputs
        -- are configured geometry; no portrait pixels or live fill bounds.
        local visibleWidth, hiddenLeft = width, 0
        local radiusX, radiusY = state.portraitWidth / 2 + scale, state.portraitHeight / 2 + scale
        local dy = (stack.comboY - reserve / 2 - state.py) / radiusY
        if math.abs(dy) < 1 then
            local reach = radiusX * math.sqrt(math.max(0, 1 - dy * dy))
            if entry.unit == "player" then
                hiddenLeft = math.max(0, math.min(width - 1, state.px + reach - x))
                visibleWidth = width - hiddenLeft
            else
                local portraitEdge = state.px - reach
                visibleWidth = math.max(1, math.min(width, portraitEdge - x))
            end
        end
        local segment = math.max(1, visibleWidth / row.capacity)
        for i = 1, row.capacity do
            local slot = row.slots[i]
            local start = hiddenLeft + (i - 1) * segment
            if entry.unit == "player" and i == 1 then start = 0 end
            slot:ClearAllPoints(); slot:SetPoint("TOPLEFT", row, "TOPLEFT", start, 0)
            local underlap = entry.unit == "player" and i == 1 and hiddenLeft
                or entry.unit == "target" and i == row.capacity and math.max(0, width - visibleWidth) or 0
            slot:SetSize(segment + underlap, math.max(1, reserve / lanes))
            slot:SetShown(row.primaryShown ~= false)
        end
        if row.aux then
            local offset = row.primaryShown and reserve / lanes or 0
            row.aux:ClearAllPoints(); row.aux:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -offset)
            row.aux:SetSize(width, math.max(1, reserve / lanes))
            row.aux:SetShown(row.auxShown == true)
        end
    end
    GUF.LayoutArtisticBarDividers(entry)
    if entry.predictions then entry.predictions.dirty = true end
    entry.layoutWriting, GUF.geometryWriting = writing, geometryWriting
    if entry.predictions then GUF.UpdatePredictionBars(entry) end
end

