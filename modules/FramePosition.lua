local _, GUF = ...
local unpack = unpack or table.unpack

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function deferred(reason)
    GUF.QueueRecovery("position-deferred")
    return "deferred", reason
end

-- Capture public settings for both units before either position is written.
-- The source reference permits guarded normalization, never native repair reads.
function GUF.CaptureFramePositionRequest(request)
    if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return false end
    if request.framePositions then return true end
    local inputs = {}
    for _, unit in ipairs(GUF.order) do
        local source = request.profile.frames[unit].position
        inputs[unit] = { position = GUF.Copy(source), source = source, layout = request.layout,
            revision = request.revision, scope = "request" }
    end
    request.framePositions = inputs
    return true
end

function GUF.FramePositionDragIsCurrent(entry, session)
    return session ~= nil and GUF.db ~= nil and entry.positionDrag == session and GUF.frames[entry.unit] == entry
        and session.profile == GUF.db and session.frames == GUF.db.frames
        and session.layout == GUF.db.general.frameStyle and session.position == GUF.db.frames[entry.unit].position
end

function GUF.BeginFramePositionDrag(entry)
    if GUF.Restricted() or GUF.editing or entry.editPositionPending or entry.positionWriting or entry.scaleWriting or not GUF.db
        or not GUF.IsManagedUnit(entry.unit) or GUF.frames[entry.unit] ~= entry then return end
    local session = { profile = GUF.db, frames = GUF.db.frames, layout = GUF.db.general.frameStyle,
        position = GUF.db.frames[entry.unit].position }
    entry.positionDrag = session
    return session
end

function GUF.EndFramePositionDrag(entry, session)
    if entry.positionDrag and (session == nil or entry.positionDrag == session) then
        entry.positionDrag = nil
        GUF.QueueRecovery("position-drag-ended", entry)
    end
end

local function inputCurrent(entry, input, request, drag)
    if GUF.frames[entry.unit] ~= entry or GUF.Restricted() or GUF.editing or entry.editPositionPending then return false end
    if request then
        return GUF.LayoutTransitions.IsCurrent(request, input.layout)
            and not GUF.FramePositionDragIsCurrent(entry, entry.positionDrag)
    end
    if drag then return GUF.FramePositionDragIsCurrent(entry, drag) end
    return entry.appliedFramePosition == input and not GUF.FramePositionDragIsCurrent(entry, entry.positionDrag)
end

local function sameSettings(first, second)
    for _, key in ipairs({ "enabled", "point", "anchorTo", "relativePoint", "x", "y" }) do
        if first[key] ~= second[key] then return false end
    end
    return true
end

-- Explicit requests and a matching drag session can acquire a new binding.
-- Native SetPoint/OnShow callbacks pass neither and repair the last binding.
function GUF.ApplyPosition(entry, request, drag)
    if not GUF.IsManagedUnit(entry.unit) then return "unavailable", "unsupported-unit" end
    if GUF.frames[entry.unit] ~= entry then return "unavailable", "unit-frame" end
    if GUF.Restricted() or GUF.editing then return deferred("restricted") end
    if entry.editPositionPending then return deferred("edit-import") end
    if entry.positionWriting or entry.scaleWriting then return deferred("writing") end
    if not drag and GUF.FramePositionDragIsCurrent(entry, entry.positionDrag) then return deferred("dragging") end
    local input
    if request then
        if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return deferred("superseded") end
        input = request.framePositions and request.framePositions[entry.unit]
    elseif drag then
        if not GUF.FramePositionDragIsCurrent(entry, drag) then return deferred("drag-superseded") end
        input = { position = GUF.Copy(drag.position), source = drag.position, layout = drag.layout, scope = "drag" }
    else input = entry.appliedFramePosition end
    if not input then return deferred("settings") end
    local position, frame = input.position, entry.frame
    local effective = position
    local relative, frameScale, screenScale
    local restoring = not position.enabled and entry.positionOwned
    local originals
    if position.enabled or restoring then
        local forbidden = frame.IsForbidden and frame:IsForbidden()
        if GUF.Secret(forbidden) or forbidden then return deferred("native-forbidden") end
        local points = GUF.ReadPoints(frame)
        if not points then return deferred("native-geometry") end
        if not entry.original.points or entry.positionCapturePending then
            entry.original.points, entry.positionCapturePending = points, nil
        end
        if position.enabled then
            local anchor = position.anchorTo
            if request or drag then
                local allowed = GUF.CanAnchor(entry.unit, anchor, request and request.framePositions)
                if allowed == nil then return deferred("anchor-geometry") end
                if not allowed then
                    effective = GUF.Copy(position)
                    anchor, effective.anchorTo = "UIParent", "UIParent"
                end
            end
            -- A valid final graph can still cycle during A->B->A handoff.
            -- Wait for the other unit's later pass; do not rewrite its settings.
            local allowed = GUF.CanAnchor(entry.unit, anchor, false)
            if allowed == nil then return deferred("anchor-geometry") end
            if not allowed then return deferred("anchor-handoff") end
            relative = anchor == "UIParent" and UIParent or GUF.AnchorFrame(anchor)
            if not relative then return deferred("anchor-unavailable") end
            frameScale, screenScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
            if not number(frameScale) or not number(screenScale) or frameScale <= 0 or screenScale <= 0
                or not number(position.x) or not number(position.y) then return deferred("position-geometry") end
        else
            originals = entry.original.points
            for _, point in ipairs(originals) do
                local allowed = GUF.CanAnchorFrame(frame, point[2], false)
                if allowed == nil then return deferred("anchor-geometry") end
                if not allowed then return deferred("restore-anchor") end
            end
        end
    end
    if not inputCurrent(entry, input, request, drag) then return deferred("superseded") end
    if position.enabled or restoring then
        entry.positionWriting = true
        -- ClearAllPoints already changes the resource. Retain the baseline and
        -- cleanup duty even if this attempt is superseded before SetPoint.
        entry.positionOwned = true
        GUF.NativeProperties.Track(frame, "rootPosition", entry, entry)
        frame:ClearAllPoints()
        if not inputCurrent(entry, input, request, drag) then
            entry.positionWriting = nil; return deferred("superseded")
        end
        if position.enabled then
            local coordinateScale = screenScale / frameScale
            frame:SetPoint(position.point, relative, position.relativePoint, position.x * coordinateScale, position.y * coordinateScale)
        else
            for _, point in ipairs(originals) do
                frame:SetPoint(unpack(point))
                if not inputCurrent(entry, input, request, drag) then
                    entry.positionWriting = nil; return deferred("superseded")
                end
            end
            entry.positionOwned = nil
        end
        entry.positionWriting = nil
    end
    if not inputCurrent(entry, input, request, drag) then return deferred("superseded") end
    if input ~= entry.appliedFramePosition or effective ~= position then
        entry.appliedFramePosition = { position = GUF.Copy(effective), layout = input.layout,
            revision = input.revision, scope = input.scope }
    end
    local source = input.source
    if source and effective.anchorTo ~= position.anchorTo and GUF.db.frames[entry.unit].position == source
        and sameSettings(source, position) then source.anchorTo = effective.anchorTo end
    return "applied"
end
