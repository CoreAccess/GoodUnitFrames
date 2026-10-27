local _, GUF = ...
local Transitions = {}
GUF.LayoutTransitions = Transitions

local revision, current = 0, nil

local function stateFor(entry)
    local state = entry.layoutTransition
    if not state then
        state = { tickets = {} }
        entry.layoutTransition = state
    end
    return state
end

function Transitions.Current()
    return current
end

-- Revisions identify apply requests/invalidations, not immutable settings
-- snapshots. A pending tick continues its request; a new explicit call does not.
function Transitions.Request(profile, layout, retry, change, source)
    if retry == true and current and current.profile == profile and current.layout == layout
        and current.phase ~= "ready" then return current end
    if current and current.phase ~= "ready" then current.phase = "superseded" end
    revision = revision + 1
    current = { revision = revision, profile = profile, layout = layout, phase = "queued",
        updates = GUF.Updates.ForRequest(current, profile, layout, change),
        source = GUF.Updates.Source(source, change) }
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then
            local state = stateFor(entry)
            state.requestedRevision, state.requestedLayout = revision, layout
            state.phase, state.reason = "queued", nil
        end
    end
    return current
end

function Transitions.IsCurrent(request, layout)
    return request ~= nil and request == current and request.profile == GUF.db
        and (layout == nil or request.layout == layout and GUF.db.general.frameStyle == layout)
end

function Transitions.Defer(request, reason)
    if not Transitions.IsCurrent(request) then return end
    request.phase, request.reason = "deferred", reason
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        local state = entry and entry.layoutTransition
        if state and state.requestedRevision == request.revision then
            state.phase, state.reason = "deferred", reason
        end
    end
end

function Transitions.BeginEntry(entry, layout, request)
    if not Transitions.IsCurrent(request, layout.id) then return end
    request.phase, request.reason = "applying", nil
    local state = stateFor(entry)
    state.request = request
    state.requestedRevision, state.requestedLayout = request.revision, layout.id
    state.phase, state.reason = "applying", nil
    local lifecycle = { layout = layout.id, revision = request.revision, applyStatus = "not-run" }
    entry.layoutLifecycle = lifecycle
    return lifecycle
end

-- Retain the matching cleanup operation with the obligation. Registration
-- availability or a newer apply request cannot replace that operation.
function Transitions.ReleaseOperation(entry, definition)
    local state = entry.layoutTransition
    local ticket = state and state.tickets[definition.id]
    return ticket and ticket.release or definition.live.release
end

-- Acquisition itself creates a cleanup obligation, before the first native
-- mutation. A selected owner's ticket is parked, not lost on a newer request.
function Transitions.Acquire(entry, definition, request)
    if not Transitions.IsCurrent(request, definition.id) then return false end
    local state = stateFor(entry)
    local ticket = state.tickets[definition.id]
    if not ticket then
        ticket = { owner = definition.id, release = definition.live.release, revision = request.revision }
        state.tickets[definition.id] = ticket
    end
    ticket.status, ticket.parked, ticket.lastRevision = "owned", true, request.revision
    return true
end

function Transitions.EntryIncomplete(entry, request, family, reason)
    if not Transitions.IsCurrent(request) then return end
    local state = stateFor(entry)
    local failed = entry.runtimeFailures and entry.runtimeFailures[family]
    state.phase, state.reason = failed and "failed" or "deferred", family .. ":" .. (reason or "pending")
    if entry.layoutLifecycle then entry.layoutLifecycle.incompleteFamily = family end
    GUF.QueueRecovery("entry-incomplete", entry, family)
end

function Transitions.RecordReleases(entry, layout, request, results)
    local state = entry.layoutTransition
    if not state or state.request ~= request or not Transitions.IsCurrent(request, layout.id) then return end
    for id, result in pairs(results) do
        if result.status == "released" then
            state.tickets[id] = nil
        else
            GUF.QueueRecovery("layout-release", entry)
            local ticket = state.tickets[id]
            if not ticket then
                ticket = { owner = id, release = result.release, revision = request.revision }
                state.tickets[id] = ticket
            end
            ticket.status, ticket.reason = result.status, result.reason
            ticket.lastRevision = request.revision
            -- A restriction-only retry may have no new reference. Preserve the
            -- last known native cleanup map/region until explicit release.
            if result.pending ~= nil then ticket.pending = result.pending end
        end
    end
end

function Transitions.FinishEntry(entry, layout, request, lifecycle)
    local state = entry.layoutTransition
    if not state or state.request ~= request or not Transitions.IsCurrent(request, layout.id) then return false end
    for id, ticket in pairs(state.tickets) do
        -- Reacquiring the same view parks its old cleanup duty with that owner;
        -- never restore beneath an active view or silently discard the duty.
        ticket.parked = id == layout.id
    end
    if lifecycle.applyStatus == "applied" then
        -- Last acknowledged layout callback only, not all feature settings.
        state.appliedRevision, state.appliedLayout = request.revision, layout.id
        if lifecycle.incompleteFamily then
            state.phase = "deferred"
            GUF.QueueRecovery("entry-finalize", entry, lifecycle.incompleteFamily)
            return true
        end
        local cleanup = false
        for _, ticket in pairs(state.tickets) do if not ticket.parked then cleanup = true end end
        state.phase = cleanup and "cleanup" or "ready"
        state.reason = state.phase == "cleanup" and "native-cleanup" or nil
    else
        state.phase, state.reason = lifecycle.applyStatus, lifecycle.applyReason
    end
    return true
end

function Transitions.FinishRequest(request)
    if not GUF.db or not Transitions.IsCurrent(request, GUF.db.general.frameStyle) then return false end
    local phase, reason = "ready", nil
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        local state = entry and entry.layoutTransition
        if not state or state.request ~= request then
            phase, reason = "unavailable", "unit-frame"
            break
        elseif state.phase ~= "ready" and phase == "ready" then
            phase, reason = state.phase, state.reason
        end
    end
    if phase == "ready" and GUF.pending then phase, reason = "pending", "shared-apply" end
    request.phase, request.reason = phase, reason
    return true
end
