local _, GUF = ...

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function GUF.FrameDimension(unit, dimension)
    local entry = GUF.frames[unit]
    local definition = GUF.Layouts.Get(GUF.db.general.frameStyle)
    local dimensions = definition and definition.presentation.dimensions
    if dimensions then
        local settings = GUF.Runtime.Settings("layout", unit)
        local width, height = dimensions(unit, settings.frames[unit])
        local value = dimension == "width" and width or height
        if number(value) and value > 0 then return value end
    end
    local value = entry and entry.original[dimension]
    if number(value) then return value end
    local resolved = GUF.Resolve(unit)
    if resolved then
        if dimension == "width" then value = resolved.frame:GetWidth()
        else value = resolved.frame:GetHeight() end
    end
    return number(value) and value or 0
end

local function screenPosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    local scale, screenScale, screenHeight = frame:GetEffectiveScale(), UIParent:GetEffectiveScale(), UIParent:GetHeight()
    if number(left) and number(top) and number(scale) and scale > 0
        and number(screenScale) and screenScale > 0 and number(screenHeight) then
        return { enabled = true, point = "TOPLEFT", anchorTo = "UIParent", relativePoint = "TOPLEFT",
            x = left * scale / screenScale, y = top * scale / screenScale - screenHeight }
    end
end

function GUF.PositionValues(unit)
    local position = GUF.Copy(GUF.db.frames[unit].position)
    if position.enabled then return position end
    local entry = GUF.frames[unit] or GUF.Resolve(unit)
    local current = entry and screenPosition(entry.frame)
    if current then current.enabled = false; return current end
    return position
end

local function samePoints(before, after)
    if not before or not after or #before ~= #after then return false end
    for i, point in ipairs(before) do
        local other = after[i]
        if point[1] ~= other[1] or point[2] ~= other[2] or point[3] ~= other[3]
            or not number(point[4]) or not number(point[5]) or not number(other[4]) or not number(other[5])
            or math.abs(point[4] - other[4]) > .000001 or math.abs(point[5] - other[5]) > .000001 then return false end
    end
    return true
end

function GUF.BeginEditMode()
    GUF.editing = true
    GUF.BeginFrameScaleEdit()
    GUF.editModeSession = {}
    GUF.editModeAnchors, GUF.editModeSavedUnits = {}, {}
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then GUF.editModeAnchors[unit] = GUF.ReadPoints(entry.frame) end
    end
    GUF.SetMovers(false)
    GUF.ApplyBlizzardEndCaps()
end

function GUF.SaveEditModePositions()
    if not GUF.editing or not GUF.editModeAnchors then return end
    GUF.SaveFrameScaleEdit()
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then
            local points = GUF.ReadPoints(entry.frame)
            if not samePoints(GUF.editModeAnchors[unit], points) then
                GUF.editModeSavedUnits[unit] = true
            end
            if points then GUF.editModeAnchors[unit] = points end
        end
    end
end

function GUF.EndEditMode()
    local session = GUF.editModeSession
    -- Keep enforcement paused through Blizzard's final native layout callbacks.
    C_Timer.After(0, function()
        if GUF.editModeSession ~= session then return end
        GUF.editPositionUnits = GUF.editPositionUnits or {}
        for unit in pairs(GUF.editModeSavedUnits or {}) do
            GUF.editPositionUnits[unit] = true
            local entry = GUF.frames[unit]
            if entry then entry.editPositionPending = true end
        end
        GUF.editModeAnchors, GUF.editModeSavedUnits, GUF.editModeSession = nil, nil, nil
        GUF.EndFrameScaleEdit()
        GUF.editing = nil
        GUF.RequestApply(nil, nil, "edit-mode")
    end)
end

function GUF.SyncEditModePositions()
    if not GUF.editPositionUnits then return true end
    local complete = true
    for unit in pairs(GUF.editPositionUnits) do
        local entry, cfg = GUF.frames[unit], GUF.db.frames[unit]
        if not entry then
            GUF.editPositionUnits[unit] = nil
        else
            local points = GUF.ReadPoints(entry.frame)
            local position
            if points and #points > 0 then
                local point = points[1]
                local scale, screenScale = entry.frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
                if #points == 1 and point[2] == UIParent and number(point[4]) and number(point[5])
                    and number(scale) and scale > 0 and number(screenScale) and screenScale > 0 then
                    -- ApplyPosition converts screen-unit offsets back into the frame's coordinate space.
                    position = { enabled = true, point = point[1], anchorTo = "UIParent", relativePoint = point[3],
                        x = point[4] * scale / screenScale, y = point[5] * scale / screenScale }
                else
                    position = screenPosition(entry.frame)
                end
            end
            if position then
                cfg.position = position
                entry.original.points, entry.positionCapturePending, entry.editPositionPending = points, nil, nil
                GUF.editPositionUnits[unit] = nil
                GUF.editPositionRefresh = true
            else
                -- Leave the saved native placement intact until its geometry becomes public.
                entry.editPositionPending = true
                complete = false
            end
        end
    end
    if complete then GUF.editPositionUnits = nil end
    return complete
end

-- Nil inputs preserve the desired-settings UI check. A captured input map
-- models that request; false follows only actual native parent/anchor edges.
-- Nil return means unreadable, not a proven invalid dependency.
function GUF.CanAnchorFrame(source, target, inputs)
    if GUF.Secret(source) or GUF.Secret(target) then return end
    local units, visited, restricted = {}, {}, false
    for _, id in ipairs(GUF.order) do
        local resolved = GUF.Resolve(id)
        if resolved then units[resolved.frame] = id end
    end
    local function dependsOn(frame)
        if GUF.Secret(frame) then restricted = true; return true end
        if frame == source then return true end
        if not frame or frame == UIParent or visited[frame] then return false end
        visited[frame] = true
        local forbidden = frame.IsForbidden and frame:IsForbidden()
        if GUF.Secret(forbidden) or forbidden then restricted = true; return true end
        if frame.GetParent and dependsOn(frame:GetParent()) then return true end
        local unit = units[frame]
        local input = inputs and unit and inputs[unit]
        local position
        if inputs == nil then position = unit and GUF.db.frames[unit].position
        elseif input then position = input.position end
        if position and position.enabled then
            if position.anchorTo == "UIParent" or not GUF.labels[position.anchorTo] then return false end
            local resolved = GUF.AnchorFrame(position.anchorTo)
            if not resolved then restricted = true; return true end
            return dependsOn(resolved)
        end
        if frame.GetNumPoints then
            local entry = unit and GUF.frames[unit]
            local anchors
            if input and entry and entry.positionOwned and not entry.positionCapturePending then
                anchors = entry.original.points
            else anchors = GUF.ReadPoints(frame) end
            if not anchors then restricted = true; return true end
            for _, point in ipairs(anchors) do
                if dependsOn(point[2]) then return true end
            end
        end
        return false
    end
    local dependent = dependsOn(target)
    if restricted then return end
    return not dependent
end

function GUF.CanAnchor(unit, anchor, inputs)
    if anchor == "UIParent" then return true end
    if not GUF.labels[anchor] or unit == anchor then return false end
    local source, target = GUF.AnchorFrame(unit), GUF.AnchorFrame(anchor)
    if not source or not target then return end
    return GUF.CanAnchorFrame(source, target, inputs)
end

function GUF.AnchorChoices(unit)
    local choices = { { "UIParent", "Screen" } }
    for _, anchor in ipairs(GUF.order) do
        if GUF.CanAnchor(unit, anchor) then choices[#choices + 1] = { anchor, GUF.labels[anchor] } end
    end
    return choices
end

local function addonWriting(entry, region)
    local transform = GUF.regionTransforms and GUF.regionTransforms[region]
    local font = entry.textOriginals and entry.textOriginals[region]
    -- Mask reapplication also uses the shared writer guard outside a full
    -- layout pass. Never capture that temporary geometry as native restore data.
    return GUF.geometryWriting or entry.sizeWriting or entry.layoutWriting
        or (transform and transform.writing) or (font and font.writing)
end

local function applyRegion(entry, state, sx, sy)
    local region = state.region
    if state.hasSize and (not number(state.width) or not number(state.height)) then return false end
    if region ~= entry.frame then
        local current = GUF.ReadPoints(region)
        if not current then state.pointsReadable = false; return false end
        if state.pointsReadable == false then state.points = current; state.pointsReadable = true end
        for _, point in ipairs(state.points) do
            if not number(point[4]) or not number(point[5]) then return false end
        end
    end
    entry.sizeWriting = true
    GUF.geometryWriting = true
    local transformed = {}
    if state.hasSize then region:SetSize(state.width * sx, state.height * sy) end
    if region ~= entry.frame then
        region:ClearAllPoints()
        for i, point in ipairs(state.points) do
            local x, y = point[4] * sx, point[5] * sy
            region:SetPoint(point[1], point[2], point[3], x, y)
            transformed[i] = { point[1], point[2], point[3], x, y }
        end
        -- Indicator/text offsets compose with the resized native layout.
        local transform = GUF.regionTransforms and GUF.regionTransforms[region]
        if transform then
            transform.points = transformed
            if state.hasSize then transform.width, transform.height = state.width * sx, state.height * sy end
        end
    end
    entry.sizeWriting = nil
    GUF.geometryWriting = nil
    local transform = GUF.regionTransforms and GUF.regionTransforms[region]
    if transform and transform.enabled then GUF.TransformRegion(region, transform.settings, true) end
    return true
end

-- Capture before font/indicator styling, and exclude independently configured attachments.
function GUF.CaptureSize(entry)
    entry.sizeRegions = {}
    GUF.sizeOwners = GUF.sizeOwners or {}
    local excluded = {}
    for _, unit in ipairs(GUF.order) do
        local other = GUF.Resolve(unit)
        if other and other.frame ~= entry.frame then excluded[other.frame] = true end
    end
    for _, region in pairs(entry.regions.resource) do excluded[region] = true end
    local function capture(region)
        if GUF.IsUnmanagedUnitFrame(region) or excluded[region] or region.goodUnitFramesOwned or not region.GetNumPoints then return end
        -- Native managed aura containers may be unnamed Frames, not AuraContainers.
        if region.GetAuraContainer then
            local container = region:GetAuraContainer()
            if container then excluded[container] = true end
        end
        local name = region.GetName and region:GetName() or ""
        if region ~= entry.frame and (region:GetObjectType() == "AuraContainer" or
            name:find("AuraContainer") or name:find("SpellBar") or name:find("CastBar") or
            name:find("CastingBar") or name:find("Buff") or name:find("Debuff") or name:find("Selection")) then return end
        -- Status bars own their changing fill geometry, including secret health/power values.
        if region.GetStatusBarTexture then
            local texture = region:GetStatusBarTexture()
            if texture then excluded[texture] = true end
        end
        local anchors = {}
        if region ~= entry.frame then
            anchors = GUF.ReadPoints(region)
            if not anchors then return end
        end
        local state = { region = region, points = anchors, hasSize = not region.GetFont }
        GUF.sizeOwners[region] = entry
        -- Font sizes remain controlled by Text; resizing moves their anchors only.
        if state.hasSize then state.width, state.height = region:GetWidth(), region:GetHeight() end
        entry.sizeRegions[#entry.sizeRegions + 1] = state
        GUF.NativeProperties.Track(region, "nativeSize", entry, state)
        local function refresh()
            -- Reapply trusted Artistic bar bounds within the native write's call,
            -- before a frame paints with Blizzard's default half-width/height.
            if GUF.Layouts.RefreshNativeGeometry(entry, region, state) then return end
            if entry.sizeOwned then
                if InCombatLockdown() or GUF.editing then GUF.QueueRecovery("native-size-restricted", entry)
                else applyRegion(entry, state, entry.sizeX, entry.sizeY) end
            end
        end
        if state.hasSize then
            for _, method in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
                local setter = method
                GUF.NativeProperties.Hook("Geometry:1", region, setter, function(_, width, height)
                    if addonWriting(entry, region) then return end
                    if setter == "SetHeight" then state.height = width
                    elseif setter == "SetWidth" then state.width = width
                    else state.width, state.height = width, height end
                    if region == entry.frame then
                        entry.original.width, entry.original.height = state.width, state.height
                        if GUF.Layouts.RefreshNativeGeometry(entry, region, state) then return end
                        if entry.sizeOwned then GUF.QueueRecovery("native-root-size", entry) end
                    else refresh() end
                end)
            end
        end
        if region ~= entry.frame then
            GUF.NativeProperties.Hook("Geometry:2", region, "ClearAllPoints", function()
                if not addonWriting(entry, region) then state.points = {}; state.pointsReadable = true end
            end)
            GUF.NativeProperties.Hook("Geometry:3", region, "SetPoint", function(_, anchor)
                if addonWriting(entry, region) then return end
                local current = GUF.ReadPoints(region)
                if not current or GUF.Secret(anchor) then state.pointsReadable = false; return end
                if state.pointsReadable == false then state.points = current end
                state.pointsReadable = true
                for _, point in ipairs(current) do
                    if point[1] == anchor then
                        local found
                        for i, previous in ipairs(state.points) do
                            if previous[1] == anchor then state.points[i], found = point, true; break end
                        end
                        if not found then state.points[#state.points + 1] = point end
                    end
                end
                refresh()
            end)
            GUF.NativeProperties.Hook("Geometry:4", region, "SetAllPoints", function()
                if addonWriting(entry, region) then return end
                local current = GUF.ReadPoints(region)
                if not current then state.pointsReadable = false; return end
                state.points, state.pointsReadable = current, true
                refresh()
            end)
        end
        if region.GetRegions then for _, child in pairs({ region:GetRegions() }) do capture(child) end end
        if region.GetChildren then for _, child in pairs({ region:GetChildren() }) do capture(child) end end
    end
    capture(entry.frame)
end

function GUF.ApplySize(entry)
    if InCombatLockdown() or GUF.editing or entry.sizeWriting then return "deferred", "restricted" end
    local cfg, original = GUF.Runtime.Settings("size", entry).frames[entry.unit], entry.original
    local changed = GUF.CanResizeFrames() and (cfg.width >= 0 or cfg.height >= 0)
    if not changed and not entry.sizeOwned then return "applied" end
    if not number(original.width) or not number(original.height) or original.width <= 0 or original.height <= 0 then
        return "deferred", "native-size"
    end
    local sx = changed and cfg.width >= 0 and cfg.width / original.width or 1
    local sy = changed and cfg.height >= 0 and cfg.height / original.height or 1
    entry.sizeOwned, entry.sizeX, entry.sizeY = true, sx, sy
    local complete = true
    for _, state in ipairs(entry.sizeRegions) do
        if not applyRegion(entry, state, sx, sy) then complete = false end
    end
    if not complete then return "deferred", "native-size-geometry" end
    entry.sizeOwned = changed
    return "applied"
end

-- Manual transition evidence only. Inspect public host/static-mask metadata,
-- never native fill geometry, amounts, ranges, identity or aura containers.
function GUF.ShowLayoutReport()
    if GUF.Restricted() or GUF.editing then
        GUF.Print("Open layout reports outside combat and Edit Mode.")
        return
    end
    local function public(value)
        if GUF.Secret(value) then return "<restricted>" end
        if type(value) == "number" then return string.format("%.3f", value) end
        return tostring(value)
    end
    local lines = { "Layout restoration report v8; interface=" .. public(GUF.clientInterface)
        .. "; selected=" .. public(GUF.db.general.frameStyle) .. "; pending=" .. public(GUF.pending) }
    local request = GUF.LayoutTransitions.Current()
    if request then
        lines[#lines + 1] = "request.revision=" .. public(request.revision)
            .. "; layout=" .. public(request.layout) .. "; phase=" .. public(request.phase)
            .. "; reason=" .. public(request.reason) .. "; failures=" .. public(request.requestFailures or 0)
    end
    lines[#lines + 1] = "nativePropertyRecords=" .. public(GUF.NativeProperties.Count())
    local function runtimeReport(owner, prefix)
        for family, binding in pairs(owner.runtimeFamilies or {}) do
            lines[#lines + 1] = prefix .. ".applied." .. family .. "=" .. public(binding.layout)
                .. "; revision=" .. public(binding.revision) .. "; generation=" .. public(binding.generation)
                .. "; status=" .. public(binding.status)
        end
        for family, binding in pairs(owner.runtimeCleanup or {}) do
            lines[#lines + 1] = prefix .. ".pending." .. family .. "=" .. public(binding.status)
                .. "; revision=" .. public(binding.revision) .. "; generation=" .. public(binding.generation)
                .. "; reason=" .. public(binding.reason) .. "; attempts=" .. public(binding.attempts)
        end
    end
    runtimeReport(GUF.Runtime.Shared(), "shared")
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then
            runtimeReport(entry, unit)
            local state = entry.artisticLayout
            local container = entry.frame.PlayerFrameContainer or entry.frame.TargetFrameContainer or entry.frame
            local portrait = container.PlayerPortrait or container.Portrait or entry.frame.portrait or entry.frame.Portrait
                or _G[entry.frame:GetName() .. "Portrait"]
            local labels, baselines = {}, {}
            local nodes = { { "root", entry.frame }, { "container", container },
                { "healthArea", entry.healthArea }, { "powerArea", entry.main.ManaBarArea },
                { "portrait", portrait }, { "health", entry.health }, { "power", entry.power }, { "name", entry.name } }
            for _, node in ipairs(nodes) do if node[2] then labels[node[2]] = node[1] end end
            for _, saved in ipairs(entry.sizeRegions or {}) do baselines[saved.region] = saved end
            local function reference(region)
                if GUF.Secret(region) then return "<restricted>" end
                if not region then return "nil" end
                return labels[region] or region.GetName and public(region:GetName()) or "<unnamed>"
            end
            local function points(anchors)
                if not anchors then return "<restricted>" end
                local values = {}
                for _, point in ipairs(anchors) do
                    values[#values + 1] = public(point[1]) .. "->" .. reference(point[2]) .. "." .. public(point[3])
                        .. "(" .. public(point[4]) .. "," .. public(point[5]) .. ")"
                end
                return #values > 0 and table.concat(values, " | ") or "<none>"
            end
            local function saved(label, geometry)
                if not geometry then lines[#lines + 1] = label .. "=missing"; return end
                lines[#lines + 1] = label .. "=" .. public(geometry.width) .. "x" .. public(geometry.height)
                    .. "; hasSize=" .. public(geometry.hasSize) .. "; pointsReadable=" .. public(geometry.pointsReadable)
                    .. "; anchors=" .. points(geometry.points)
            end
            local function describe(label, region)
                if not region then lines[#lines + 1] = label .. "=missing"; return end
                lines[#lines + 1] = label .. "=" .. public(region:GetWidth()) .. "x" .. public(region:GetHeight())
                    .. "; parent=" .. reference(region:GetParent()) .. "; anchors=" .. points(GUF.ReadPoints(region))
                saved(label .. ".native", baselines[region])
                local tracked = state and state.regions[region]
                if tracked then
                    saved(label .. ".restore", tracked.geometry)
                    lines[#lines + 1] = label .. ".restoreParent=" .. reference(tracked.parent)
                end
            end
            lines[#lines + 1] = "\n" .. unit .. "; artisticActive=" .. public(state and state.active)
                .. "; restoreDeferred=" .. public(state and state.restorePending ~= nil)
                .. "; ownedBars=" .. public(state and state.renderBars ~= nil)
                .. "; nativeBarsIsolated=" .. public(GUF.ArtisticNativeBarsIsolated(entry, state))
                .. "; sizeOwned=" .. public(entry.sizeOwned) .. "; layoutWriting=" .. public(entry.layoutWriting)
                .. "; geometryWriting=" .. public(GUF.geometryWriting)
            local lifecycle = entry.layoutLifecycle
            if lifecycle then
                lines[#lines + 1] = "lifecycle.layout=" .. public(lifecycle.layout)
                    .. "; revision=" .. public(lifecycle.revision)
                    .. "; apply=" .. public(lifecycle.applyStatus) .. "; reason=" .. public(lifecycle.applyReason)
                lines[#lines + 1] = "lifecycle.scale=" .. public(lifecycle.scaleStatus)
                    .. "; reason=" .. public(lifecycle.scaleReason)
                lines[#lines + 1] = "lifecycle.position=" .. public(lifecycle.positionStatus)
                    .. "; reason=" .. public(lifecycle.positionReason)
                for id, result in pairs(lifecycle.releases or {}) do
                    lines[#lines + 1] = "lifecycle.release." .. id .. "=" .. public(result.status)
                        .. "; reason=" .. public(result.reason) .. "; cleanupPending=" .. public(result.pending ~= nil)
                end
            end
            local transition = entry.layoutTransition
            if transition then
                lines[#lines + 1] = "transition.requested=" .. public(transition.requestedLayout)
                    .. "; revision=" .. public(transition.requestedRevision)
                    .. "; lastLayoutAck=" .. public(transition.appliedLayout)
                    .. "; revision=" .. public(transition.appliedRevision)
                    .. "; phase=" .. public(transition.phase) .. "; reason=" .. public(transition.reason)
                for id, ticket in pairs(transition.tickets) do
                    lines[#lines + 1] = "cleanup." .. id .. "=" .. public(ticket.status)
                        .. "; firstRequest=" .. public(ticket.revision)
                        .. "; latestRequest=" .. public(ticket.lastRevision)
                        .. "; reason=" .. public(ticket.reason) .. "; parked=" .. public(ticket.parked)
                        .. "; nativeReference=" .. public(ticket.pending ~= nil)
                end
            end
            local appliedScale = entry.appliedFrameScale
            if appliedScale then
                lines[#lines + 1] = "scale.appliedLayout=" .. public(appliedScale.layout)
                    .. "; revision=" .. public(appliedScale.revision) .. "; scope=" .. public(appliedScale.scope)
                    .. "; absolute=" .. public(appliedScale.value)
            end
            local appliedPosition = entry.appliedFramePosition
            if appliedPosition then
                local position = appliedPosition.position
                lines[#lines + 1] = "position.appliedLayout=" .. public(appliedPosition.layout)
                    .. "; revision=" .. public(appliedPosition.revision) .. "; scope=" .. public(appliedPosition.scope)
                    .. "; enabled=" .. public(position.enabled) .. "; anchor=" .. public(position.anchorTo)
                    .. "; points=" .. public(position.point) .. "/" .. public(position.relativePoint)
                    .. "; offset=" .. public(position.x) .. "," .. public(position.y)
                    .. "; dragging=" .. public(GUF.FramePositionDragIsCurrent(entry, entry.positionDrag))
            end
            local fadingResult = entry.frameFadingResult
            if fadingResult then
                lines[#lines + 1] = "fading.requestLayout=" .. public(fadingResult.layout)
                    .. "; revision=" .. public(fadingResult.revision) .. "; status=" .. public(fadingResult.status)
                    .. "; reason=" .. public(fadingResult.reason)
            end
            local appliedFading = entry.appliedFrameFading
            if appliedFading then
                local fade = appliedFading.fading
                local alpha = GUF.alphaStates and GUF.alphaStates[entry.frame]
                lines[#lines + 1] = "fading.appliedLayout=" .. public(appliedFading.layout)
                    .. "; revision=" .. public(appliedFading.revision) .. "; scope=" .. public(appliedFading.scope)
                    .. "; native=" .. public(fade.native) .. "; enabled=" .. public(fade.enabled)
                    .. "; combat=" .. public(fade.combat) .. "; inactive=" .. public(fade.inactive)
                    .. "; alphaOwned=" .. public(alpha ~= nil and alpha.override ~= nil)
            end
            local castArt, castStyle = entry.nativeCastArtwork, entry.nativeCastStyle
            local castRegions = 0
            for _ in pairs(castArt and castArt.regions or {}) do castRegions = castRegions + 1 end
            lines[#lines + 1] = "cast.ownedManaged=" .. public(entry.castBar and entry.castBar.managed == true)
                .. "; nativeCreated=" .. public(castStyle and castStyle.created == true)
                .. "; nativeActive=" .. public(castStyle and castStyle.active == true)
                .. "; artworkRelease=" .. public(castArt and castArt.releasePending == true)
                .. "; artworkItems=" .. public(castRegions)
                .. "; styleAlphaRelease=" .. public(castStyle and castStyle.alphaReleasePending == true)
            local function castAlpha(label, region)
                if GUF.Secret(region) then lines[#lines + 1] = "cast." .. label .. "=<restricted>"; return end
                local alpha = region and GUF.alphaStates and GUF.alphaStates[region]
                local leases = alpha and alpha.leases or {}
                lines[#lines + 1] = "cast." .. label .. ".present=" .. public(region ~= nil)
                    .. "; replacementLease=" .. public(leases.NativeCastArtwork ~= nil)
                    .. "; stylingLease=" .. public(leases.NativeCastBar ~= nil)
                    .. "; layoutLease=" .. public(leases.ArtisticLayout ~= nil)
            end
            local castHost = castStyle and castStyle.bar or castArt and castArt.bar or GUF.NativeCastBar(entry)
            if not GUF.Secret(castHost) and castHost then
                local forbidden = castHost.IsForbidden and castHost:IsForbidden()
                if not GUF.Secret(forbidden) and not forbidden then
                    local fill
                    if castHost.GetStatusBarTexture then fill = castHost:GetStatusBarTexture() end
                    castAlpha("fill", fill)
                    castAlpha("icon", castStyle and castStyle.icon or castHost.Icon or castHost.icon)
                    castAlpha("background", castHost.Background or castHost.background)
                    castAlpha("border", castHost.BarBorder or castHost.Border or castHost.border)
                end
            end
            saved("root.original", entry.original)
            for _, node in ipairs(nodes) do describe(node[1], node[2]) end
            if state then
                for _, node in ipairs({ { "root", entry.frame }, { "portrait", state.portrait },
                    { "health", entry.health }, { "power", entry.power } }) do
                    local region = node[2]
                    local item = region and state.regions[region]
                    local geometry = item and item.geometry
                    if GUF.ArtisticNativeBarsIsolated(entry, state) and (node[1] == "health" or node[1] == "power") then
                        lines[#lines + 1] = "applyGate." .. node[1] .. "=skipped (isolated native source)"
                    else
                        lines[#lines + 1] = "applyGate." .. node[1] .. "="
                            .. public(geometry and number(geometry.width) and number(geometry.height)
                                and region and GUF.ReadPoints(region) ~= nil or false)
                    end
                end
            end
            for _, kind in ipairs({ "health", "power" }) do
                local fill = entry[kind] and entry[kind]:GetStatusBarTexture()
                if GUF.Secret(fill) then fill = nil end
                local count = fill and fill.GetNumMaskTextures and fill:GetNumMaskTextures()
                if number(count) and fill.GetMaskTexture then
                    for index = 1, count do
                        local mask = fill:GetMaskTexture(index)
                        if not GUF.Secret(mask) and mask and not mask.goodUnitFramesOwned then
                            local label = kind .. ".mask" .. index
                            labels[mask] = label
                            describe(label, mask)
                            local original = state and state.masks[mask]
                            lines[#lines + 1] = label .. ".media=" .. public(mask:GetTexture())
                                .. "/" .. public(mask:GetAtlas()) .. "; captured="
                                .. public(original and original.texture) .. "/" .. public(original and original.atlas)
                        end
                    end
                end
            end
        end
    end
    GUF.ShowDiagnosticReport("Layout restoration", table.concat(lines, "\n"))
end
