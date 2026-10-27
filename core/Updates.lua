local _, GUF = ...
local Updates = {}
GUF.Updates = Updates
Updates.stats = { full = 0, targeted = 0, coalesced = 0, families = {}, values = {} }
local stats = Updates.stats
stats.fullSources, stats.fullReasons = {}, {}
stats.recoveryStarts, stats.pendingTickCauses = {}, {}
stats.geometryUnowned = {}
stats.castAnchorless = {}
stats.cleanupRetries, stats.cleanupWaits = 0, 0
stats.scoped, stats.queued, stats.flushed, stats.targetedReady, stats.fullRepeated = 0, 0, 0, 0, 0
local recoveryCauses = {}
local families = { construction = true, layout = true, scale = true, size = true, position = true,
    artwork = true, bars = true, cast = true, colors = true, combatText = true, finalize = true,
    predictions = true, rootFading = true, text = true, textCapture = true,
    auras = true, threat = true, visibility = true }
local requestSources = { login = true, ["entering-world"] = true, ["combat-ended"] = true,
    ["power-type"] = true, shapeshift = true, ["layout-selection"] = true, profile = true,
    ["unit-copy"] = true, reset = true, ["edit-mode"] = true, mover = true,
    ["visibility-restore"] = true, ["pending-tick"] = true, ["queued-edit"] = true,
    settings = true, unspecified = true }

-- Caller labels are fixed public tokens, never event payloads, identities,
-- preferences, errors or caller-stack strings. Diagnostics retain no history.
function Updates.Source(source, change)
    if not GUF.Secret(source) and type(source) == "string" and requestSources[source] then return source end
    return change and "settings" or "unspecified"
end

-- All sources are literal code-site labels. Keep only aggregate counters and
-- the set of causes awaiting the next pass, never event payloads or a history.
-- This replaces a pending=true write; it does not dispatch or defer any work.
function GUF.QueueRecovery(source, entry, family)
    local request = GUF.LayoutTransitions.Current()
    if request and source ~= "layout-release" then request.cleanupWaiting = nil end
    local binding = GUF.Runtime.Current()
    entry, family = entry or binding and binding.owner, family or binding and binding.family
    local unit = entry and GUF.IsManagedUnit(entry.unit) and entry.unit or "shared"
    local key = source .. "/" .. unit
    if family and not GUF.Secret(family) and families[family] then key = key .. "/" .. family end
    if not GUF.pending then stats.recoveryStarts[key] = (stats.recoveryStarts[key] or 0) + 1 end
    recoveryCauses[key] = true
    GUF.pending = true
end

function Updates.TakeRecovery(request)
    request.recoveryCauses, recoveryCauses = recoveryCauses, {}
end

local function cleanupCauses(readiness)
    local found = false
    for cause in pairs(recoveryCauses) do
        if cause ~= "layout-release/player" and cause ~= "layout-release/target"
            and not (readiness and (cause == "layout-cleanup-ready/player" or cause == "layout-cleanup-ready/target")) then return false end
        found = true
    end
    return found
end

local function clean(owner)
    return not next(owner.runtimeFailures or {}) and not next(owner.runtimePending or {})
        and not next(owner.runtimeCleanup or {})
end

-- Only the exact request whose entire presentation finished can retry just
-- inactive layout restoration. New edits, failures or unrelated dirty causes
-- keep the complete coordinator; cleanup never acknowledges unapplied settings.
function Updates.CanRetryCleanup(request)
    if not GUF.LayoutTransitions.IsCurrent(request, request.layout) or request.phase ~= "cleanup"
        or not request.settingsSnapshot or GUF.GetRequestedLayout() or not cleanupCauses(true) then return false end
    local shared = GUF.Runtime.Shared()
    if not clean(shared) then return false end
    for _, family in ipairs({ "auras", "visibility", "threat" }) do
        local binding = GUF.Runtime.Binding(family)
        if not binding or binding.revision ~= request.revision or binding.layout ~= request.layout then return false end
    end
    local retained = false
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        local state = entry and entry.layoutTransition
        local lifecycle = entry and entry.layoutLifecycle
        if not entry or not clean(entry) or entry.appliedSettingsRevision ~= request.revision
            or not state or state.request ~= request or (state.phase ~= "ready" and state.phase ~= "cleanup")
            or not lifecycle or lifecycle.revision ~= request.revision or lifecycle.applyStatus ~= "applied"
            or lifecycle.incompleteFamily then return false end
        for id, ticket in pairs(state.tickets) do
            if not ticket.parked then
                local definition = GUF.Layouts.Get(id)
                if ticket.status ~= "restoring" or not definition or type(definition.live.cleanupReady) ~= "function" then return false end
                retained = true
            end
        end
    end
    return retained
end

function Updates.ParkCleanup(request)
    request.cleanupWaiting = nil
    if cleanupCauses(false) and Updates.CanRetryCleanup(request) then
        request.cleanupWaiting = true
        stats.cleanupWaits = stats.cleanupWaits + 1
    end
end

-- The existing safe tick probes only retained cleanup readiness. A region that
-- becomes public without a setter callback must still be restored eventually.
function Updates.CleanupWaiting()
    local request = GUF.LayoutTransitions.Current()
    if not request or not request.cleanupWaiting then return false end
    if not Updates.CanRetryCleanup(request) then request.cleanupWaiting = nil; return false end
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        for id, ticket in pairs(entry.layoutTransition.tickets) do
            if not ticket.parked then
                local definition = GUF.Layouts.Get(id)
                local ok, ready = pcall(definition.live.cleanupReady, entry)
                if not ok or GUF.Secret(ready) or ready then request.cleanupWaiting = nil; return false end
            end
        end
    end
    return true
end

function Updates.RetryCleanup(request)
    stats.cleanupRetries = stats.cleanupRetries + 1
    request.cleanupWaiting = nil
    Updates.TakeRecovery(request)
    GUF.pending = nil
    local transitions, selected = GUF.LayoutTransitions, {}
    for _, unit in ipairs(GUF.order) do
        for _, ticket in pairs(GUF.frames[unit].layoutTransition.tickets) do
            if not ticket.parked then selected[unit] = true end
        end
    end
    -- Release may restore anchors used by the current skin's text/artwork.
    -- Reconcile the affected unit through its ordinary ordered families after
    -- restoration; never write old geometry beneath an acknowledged new skin.
    if not GUF.ApplyFrames(request, selected) then GUF.QueueRecovery("cleanup-incomplete"); return end
    if not transitions.IsCurrent(request, request.layout) then GUF.QueueRecovery("request-superseded"); return end
    if selected.target and not GUF.Runtime.Apply(nil, "threat", request, GUF.ApplyThreat) then
        GUF.QueueRecovery("cleanup-incomplete"); return
    end
    if not transitions.FinishRequest(request) then GUF.QueueRecovery("request-incomplete"); return end
    if request.phase == "ready" then GUF.Runtime.Commit(request)
    else Updates.ParkCleanup(request) end
end

function Updates.RecordFull(request, reason)
    local source = Updates.Source(request.source)
    reason = reason or "unclassified"
    stats.full = stats.full + 1
    stats.fullSources[source] = (stats.fullSources[source] or 0) + 1
    stats.fullReasons[reason] = (stats.fullReasons[reason] or 0) + 1
    if source == "pending-tick" then
        local causes = request.recoveryCauses or {}
        if not next(causes) then stats.pendingTickCauses.unattributed = (stats.pendingTickCauses.unattributed or 0) + 1 end
        for cause in pairs(causes) do stats.pendingTickCauses[cause] = (stats.pendingTickCauses[cause] or 0) + 1 end
    end
    if request.fullAttempts then stats.fullRepeated = stats.fullRepeated + 1 end
    request.fullAttempts = (request.fullAttempts or 0) + 1
    request.lastFullReason = reason
end
local domains = { layout = "geometry", scale = "geometry", position = "geometry",
    artwork = "media", bars = "media", colors = "media", predictions = "values",
    cast = "values", combatText = "text", fading = "visibility", threat = "values" }

local function unitPlan(plan, unit)
    plan.units[unit] = plan.units[unit] or {}
    return plan.units[unit]
end

local function auraUnit(plan, unit)
    plan.shared.auras, plan.shared.visibility = true, true
    plan.auraUnits[unit] = true
    plan.domains[unit] = plan.domains[unit] or {}
    plan.domains[unit].auras = true
end

-- Domains describe the user's edit; families are its conservative dependency
-- closure. Coupled frame geometry/media/resources still reconcile together.
-- Only audited independent features take the smaller path. Unknown callers,
-- profile/layout transitions and native recovery keep the complete apply path.
local function classify(plan, change)
    if not change or type(change.keys) ~= "table" then
        plan.full, plan.fullReason = true, plan.fullReason or "unscoped-request"
        return
    end
    local keys, unit = change.keys, change.unit
    if change.scope == "visibility" then
        plan.shared.visibility = true
        plan.domains.shared = plan.domains.shared or {}
        plan.domains.shared.visibility = true
        if keys[1] == "buffs" or keys[1] == "debuffs" then
            for _, managed in ipairs(GUF.order) do auraUnit(plan, managed) end
        elseif keys[1] == "cast" then unitPlan(plan, "player").cast = true end
        return
    end
    if not GUF.IsManagedUnit(unit) then plan.full, plan.fullReason = true, "unsupported-scope"; return end
    local selected = unitPlan(plan, unit)
    plan.domains[unit] = plan.domains[unit] or {}
    for _, domain in ipairs(GUF.Settings.Group(keys).domains) do plan.domains[unit][domains[domain] or domain] = true end
    local first, second = keys[1], keys[2]
    if first == "fading" then selected.fading = true
    elseif first == "auras" then auraUnit(plan, unit)
    elseif first == "bars" and second == "cast" then selected.cast = true
    elseif first == "bars" and (second == "incHeal" or second == "incAbsorb" or second == "healAbsorb") then
        selected.predictions = true
    elseif first == "combatText" or first == "indicators" and second == "feedback" then selected.combatText = true
    elseif first == "text" and (second == "health" or second == "power") then selected.text = true
    elseif first == "nameColor" or first == "customName" or first == "nameDisplay" then selected.text = true
    else
        selected.frame = true
        if unit == "target" then plan.shared.threat = true end
        -- Aura text inherits these shared frame font preferences.
        if first == "font" or first == "fontSize" or first == "outline" then auraUnit(plan, unit) end
    end
end

function Updates.ForRequest(previous, profile, layout, change)
    if change then stats.scoped = stats.scoped + 1 end
    local plan = { units = {}, shared = {}, domains = {}, auraUnits = {} }
    if previous and previous.profile == profile and previous.layout == layout and previous.phase ~= "ready" then
        if previous.updates then plan = GUF.Copy(previous.updates)
        else plan.full, plan.fullReason = true, "unfinished-unclassified-request" end
    end
    classify(plan, change)
    if GUF.Runtime.lastProfile ~= profile then plan.full, plan.fullReason = true, "profile-baseline"
    elseif GUF.Runtime.lastLayout ~= layout then plan.full, plan.fullReason = true, "layout-baseline"
    elseif GUF.GetRequestedLayout() then plan.full, plan.fullReason = true, "layout-selection"
    elseif GUF.pending then plan.full, plan.fullReason = true, "recovery-pending" end
    return plan
end

function Updates.CanApply(request)
    if not request.updates then return false, "missing-plan" end
    if request.updates.full then return false, request.updates.fullReason or "full-plan" end
    if GUF.pending then return false, "recovery-pending" end
    local shared = GUF.Runtime.Shared()
    if next(shared.runtimeFailures or {}) then return false, "shared-failure" end
    if next(shared.runtimePending or {}) then return false, "shared-pending" end
    if next(shared.runtimeCleanup or {}) then return false, "shared-cleanup" end
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        local binding = entry and GUF.Runtime.Binding("layout", entry)
        if not entry or not entry.initialized then return false, unit .. "-not-ready" end
        if not binding or binding.layout ~= request.layout then return false, unit .. "-layout-binding" end
        if next(entry.runtimeFailures or {}) then return false, unit .. "-failure" end
        if next(entry.runtimePending or {}) then return false, unit .. "-pending" end
        if next(entry.runtimeCleanup or {}) then return false, unit .. "-cleanup" end
        for _, ticket in pairs(entry.layoutTransition and entry.layoutTransition.tickets or {}) do
            if not ticket.parked then return false, unit .. "-layout-cleanup" end
        end
    end
    return true, "eligible"
end

function Updates.Apply(request)
    local plan, runtime = request.updates, GUF.Runtime
    Updates.stats.targeted = Updates.stats.targeted + 1
    local frames, hasFrames = {}, false
    for unit, work in pairs(plan.units) do
        if work.frame then frames[unit], hasFrames = true, true end
    end
    if hasFrames and not GUF.ApplyFrames(request, frames) then return false end
    for _, unit in ipairs(GUF.order) do
        local work, entry = plan.units[unit], GUF.frames[unit]
        if work and not work.frame then
            for _, item in ipairs({ { "combatText", GUF.ApplyCombatText }, { "predictions", GUF.ApplyPredictionBars },
                { "cast", GUF.ApplyCastBar }, { "text", GUF.ApplyText } }) do
                if work[item[1]] and not runtime.Apply(entry, item[1], request, item[2], entry) then return false end
                if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return false end
            end
        end
    end
    for _, item in ipairs({ { "auras", GUF.ApplyAuras }, { "visibility", GUF.ApplyBlizzardFrames }, { "threat", GUF.ApplyThreat } }) do
        if plan.shared[item[1]] and not runtime.Apply(nil, item[1], request, item[2], plan.auraUnits) then return false end
        if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return false end
    end
    if GUF.pending then return false end
    -- A targeted request acknowledges only its affected families. In particular
    -- do not relabel an untouched layout binding as newly applied geometry.
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        local state = entry.layoutTransition
        state.request, state.phase, state.reason = request, "ready", nil
        if plan.units[unit] or plan.auraUnits[unit] then entry.appliedSettingsRevision = request.revision end
    end
    stats.targetedReady = stats.targetedReady + 1
    return true
end

-- Reuse Core's frame driver. Values/events remain immediate; only explicit UI
-- structural edits coalesce until its next frame. Combat/Edit Mode retain intent.
function GUF.FlushQueuedUpdates()
    local request = GUF.updateQueued
    if not request then return end
    if not GUF.LayoutTransitions.IsCurrent(request) then GUF.updateQueued = nil; return end
    if GUF.Restricted() or GUF.editing then return end
    GUF.updateQueued = nil
    stats.flushed = stats.flushed + 1
    GUF.RequestApply(true, nil, "queued-edit")
end

function GUF.ShowUpdateReport()
    if GUF.Restricted() or GUF.editing then
        GUF.Print("Open diagnostic reports outside combat and Edit Mode.")
        return
    end
    local stats, request = Updates.stats, GUF.LayoutTransitions.Current()
    local lines = { "Update scheduling v6 (public counters since reload; family counts are attempts)",
        "full=" .. stats.full .. "; targeted=" .. stats.targeted .. "; coalesced=" .. stats.coalesced,
        "scoped requests=" .. stats.scoped .. "; queued edits=" .. stats.queued .. "; flush dispatches=" .. stats.flushed
            .. "; targeted ready=" .. stats.targetedReady .. "; repeated full passes=" .. stats.fullRepeated,
        "queued=" .. tostring(GUF.updateQueued ~= nil) .. "; fullRecovery=" .. tostring(GUF.pending == true) }
    lines[#lines + 1] = "layout cleanup: retries=" .. stats.cleanupRetries .. "; waits=" .. stats.cleanupWaits
        .. "; waiting=" .. tostring(request ~= nil and request.cleanupWaiting == true)
    local function totals(label, counts)
        local values = {}
        for key, count in pairs(counts) do values[#values + 1] = key .. "=" .. count end
        table.sort(values); lines[#lines + 1] = label .. ": " .. (#values > 0 and table.concat(values, "; ") or "none")
    end
    totals("full origins", stats.fullSources)
    totals("full reasons", stats.fullReasons)
    totals("recovery starts (clear to pending)", stats.recoveryStarts)
    totals("pending-tick causes (passes; may overlap)", stats.pendingTickCauses)
    totals("unowned native geometry skipped", stats.geometryUnowned)
    totals("native cast anchorless geometry attempts", stats.castAnchorless)
    for _, unit in ipairs(GUF.order) do
        local values = {}
        for family, count in pairs(stats.families[unit] or {}) do values[#values + 1] = family .. "=" .. count end
        table.sort(values); lines[#lines + 1] = unit .. ": " .. table.concat(values, "; ")
            .. "; immediate value events=" .. (stats.values[unit] or 0)
    end
    local values = {}
    for family, count in pairs(stats.families.shared or {}) do values[#values + 1] = family .. "=" .. count end
    table.sort(values); lines[#lines + 1] = "shared: " .. table.concat(values, "; ")
    local pooled, containers = 0, 0
    for _, pool in pairs(GUF.auraHostPools or {}) do
        for _, host in pairs(pool) do pooled = pooled + 1; containers = containers + (host.alternate and 2 or 1) end
    end
    lines[#lines + 1] = "aura host variants=" .. pooled .. "; containers=" .. containers
        .. "; created=" .. (stats.auraCreated or 0) .. "; reused=" .. (stats.auraReused or 0)
    lines[#lines + 1] = "Runtime.CreateFrame allocations=" .. (stats.framesCreated or 0)
        .. "; owned prediction masks created=" .. (stats.maskCreated or 0)
    if request then
        lines[#lines + 1] = "request=" .. request.revision .. "; phase=" .. request.phase
            .. "; origin=" .. Updates.Source(request.source)
        if request.lastFullReason then lines[#lines + 1] = "request last full reason=" .. request.lastFullReason end
        for unit, dirty in pairs(request.updates and request.updates.domains or {}) do
            local names = {}
            for domain in pairs(dirty) do names[#names + 1] = domain end
            table.sort(names); lines[#lines + 1] = unit .. " domains: " .. table.concat(names, ", ")
        end
    end
    GUF.ShowDiagnosticReport("Good Unit Frames Updates", table.concat(lines, "\n"))
end
