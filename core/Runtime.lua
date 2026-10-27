local _, GUF = ...
local Runtime = {}
GUF.Runtime = Runtime
local unpack = unpack or table.unpack
local current, generation = nil, 0
local shared = {}
local latest = {}
local deferSources = { ["native-readiness"] = "defer-native-readiness", settings = "defer-settings",
    ["native-forbidden"] = "defer-native-forbidden", ["alpha-forbidden"] = "defer-alpha-forbidden",
    ["text-fields"] = "defer-text-fields", ["visibility-parent"] = "defer-visibility-parent",
    ["transform-geometry"] = "defer-transform-geometry", ["native-cast-artwork"] = "defer-native-cast-artwork",
    ["native-cast-points"] = "defer-native-cast-points", ["native-cast-size"] = "defer-native-cast-size",
    ["native-cast-geometry-restricted"] = "defer-native-cast-geometry-restricted",
    ["native-cast-layer-restricted"] = "defer-native-cast-layer-restricted",
    ["native-cast-capture-restricted"] = "defer-native-cast-capture-restricted",
    ["cast-aura-restricted"] = "defer-cast-aura-restricted", ["cast-empower-restricted"] = "defer-cast-empower-restricted",
    ["cast-position-restricted"] = "defer-cast-position-restricted",
    failed = "defer-failed", superseded = "defer-superseded" }

function Runtime.Current() return current end
function Runtime.Shared() return shared end

local function pack(...) return { n = select("#", ...), ... } end
local function reportError(err)
    -- Preserve normal client debugging without retaining or formatting an
    -- opaque error object in GUF's diagnostics or retry state.
    if GUF.Secret(err) or type(err) ~= "string" or not geterrorhandler then return end
    local handler = geterrorhandler()
    if type(handler) == "function" then pcall(handler, err) end
end
local function host(entry)
    if type(entry) == "string" then entry = GUF.frames[entry] end
    return entry or shared
end
local function records(entry)
    local owner = host(entry)
    owner.runtimeFamilies = owner.runtimeFamilies or {}
    owner.runtimeFailures = owner.runtimeFailures or {}
    owner.runtimePending = owner.runtimePending or {}
    return owner, owner.runtimeFamilies, owner.runtimeFailures
end

local function copySettings(profile)
    return { general = GUF.Copy(profile.general), frames = GUF.Copy(profile.frames),
        threat = GUF.Copy(profile.threat), hideBlizzard = GUF.Copy(profile.hideBlizzard) }
end

function Runtime.Capture(request)
    if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return false end
    if not request.settingsSnapshot then
        request.settingsSnapshot = copySettings(request.profile)
        Runtime.initialSettings = Runtime.initialSettings or request.settingsSnapshot
    end
    return true
end

function Runtime.CaptureColors(request)
    if not GUF.LayoutTransitions.IsCurrent(request) then return false end
    local layout = GUF.db.general.frameStyle
    if not request.colorSettings or request.colorSettings.layout ~= layout then
        request.colorSettings = { layout = layout, settings = copySettings(request.profile) }
    end
    return true
end

function Runtime.ApplyColors(request)
    if not Runtime.CaptureColors(request) then return false end
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry and entry.initialized then Runtime.Apply(entry, "colors", request, GUF.UpdateColors, entry) end
        if not GUF.LayoutTransitions.IsCurrent(request) then return false end
    end
    return true
end

-- Read-only public settings, never a temporary replacement for GUF.db. An
-- explicit operation sees its captured family; callbacks see its last binding.
function Runtime.Settings(family, entry)
    local explicit = GUF.Presentation.SampleSettings(entry)
    if explicit then return explicit end
    if Runtime.sample then return GUF.db end
    if entry and type(entry) ~= "string" and entry.configurationPreview then return GUF.db end
    local owner, families = records(entry)
    if current and (current.owner == owner or current.owner == shared or current.status == "applying" or current.family == "construction")
        and (current.family == family or current.family == "construction") then return current.settings end
    local binding = families[family] or shared.runtimeFamilies and shared.runtimeFamilies[family]
        or (owner == shared and latest[family])
    return binding and binding.settings or Runtime.lastSettings or Runtime.initialSettings or GUF.defaults
end

function Runtime.Binding(family, entry)
    local owner, families = records(entry)
    if current and (current.owner == owner or current.owner == shared) and current.family == family then return current end
    return families[family] or shared.runtimeFamilies and shared.runtimeFamilies[family]
end

function Runtime.IsBinding(binding, family, entry)
    return binding ~= nil and not binding.cancelled and Runtime.Binding(family, entry) == binding
end

function Runtime.Defer(reason, entry, family)
    local source = not GUF.Secret(reason) and type(reason) == "string" and deferSources[reason]
    GUF.QueueRecovery(source or "runtime-defer", entry, family)
    if current then current.deferred = current.deferred or reason or "native-readiness" end
end
GUF.DeferRuntime = Runtime.Defer

function Runtime.DeferCleanup(reason)
    GUF.QueueRecovery("runtime-cleanup")
    if current then current.cleanupReason = reason or "native-cleanup" end
end

-- Record allocations before configuring them, including partially constructed
-- views. On failure they remain reachable and are retired before a retry.
function Runtime.CreateFrame(...)
    local frame = CreateFrame(...)
    GUF.Updates.stats.framesCreated = (GUF.Updates.stats.framesCreated or 0) + 1
    frame.goodUnitFramesOwned = true
    if current then
        current.allocations[#current.allocations + 1] = frame
    end
    return frame
end

function Runtime.TrackRegion(region)
    if region then region.goodUnitFramesOwned = true end
    if current and region then current.allocations[#current.allocations + 1] = region end
    return region
end

function Runtime.Constructed()
    if not current then return end
    current.reusable = current.reusable or {}
    for _, region in ipairs(current.allocations) do current.reusable[region] = true end
end

local function fail(binding, reason, err)
    if binding.cancelled and binding.status == "failed" then GUF.QueueRecovery("runtime-failure", binding.owner, binding.family); return end
    local owner, _, failures = records(binding.owner == shared and nil or binding.owner)
    local applied = binding.status == "applied"
    binding.cancelled, binding.status, binding.reason = true, "failed", reason
    failures[binding.family] = binding
    if GUF.NativeProperties then GUF.NativeProperties.Recover(binding, owner) end
    owner.runtimeCleanup = owner.runtimeCleanup or {}
    owner.runtimeCleanup[binding.family] = binding
    for _, region in ipairs(not applied and binding.allocations or {}) do
        -- These are owned allocations, never native frames/controllers.
        pcall(function()
            if binding.reusable and binding.reusable[region] then return end
            local forbidden = region.IsForbidden and region:IsForbidden()
            if GUF.Secret(forbidden) or forbidden then return end
            local protected = GUF.Restricted() and region.IsProtected and region:IsProtected()
            if GUF.Secret(protected) or protected then return end
            if region.goodUnitFramesNativeController then
                if region.SetEnabled then region:SetEnabled(false) end
            else
                if region.UnregisterAllEvents then region:UnregisterAllEvents() end
                if region.SetScript then region:SetScript("OnUpdate", nil); region:SetScript("OnEvent", nil) end
            end
            if region.Hide then region:Hide() end
        end)
    end
    GUF.QueueRecovery("runtime-failure", binding.owner, binding.family)
    if not binding.reported then
        binding.reported = true
        GUF.Print("A " .. binding.family .. " update could not finish; cleanup is retained. See /guf layoutdebug.")
        reportError(err)
    end
end

local function invoke(binding, fn, ...)
    local previous, sample = current, Runtime.sample
    current, Runtime.sample = binding, nil
    local presentation = GUF.Presentation.Enter(GUF.Presentation.ForBinding(binding))
    local writers = GUF.NativeProperties and GUF.NativeProperties.CaptureWriters(binding.owner, binding.status == "applied")
    local result = pack(pcall(fn, ...))
    current, Runtime.sample = previous, sample
    GUF.Presentation.Leave(presentation)
    if not result[1] then
        if GUF.NativeProperties then GUF.NativeProperties.RestoreWriters(writers, binding.owner) end
        fail(binding, "callback-error", result[2])
        return false
    end
    if binding.status == "applied" then binding.alphaChanges = nil end
    return true, unpack(result, 2, result.n)
end

function Runtime.Apply(entry, family, request, fn, ...)
    local safe = family == "colors"
    local layout = safe and request.colorSettings.layout or request.layout
    local function isCurrent()
        return GUF.LayoutTransitions.IsCurrent(request) and GUF.db.general.frameStyle == layout
            and (safe or request.layout == layout)
    end
    if not isCurrent() then return false, "superseded" end
    local owner, families, failures = records(entry)
    local previousFailure = failures[family]
    if previousFailure and previousFailure.revision == request.revision then
        -- Use the existing pending tick, with bounded retries and no error storm.
        if previousFailure.attempts >= 3 then Runtime.Defer("failed"); return false, "failed" end
    end
    local stats = GUF.Updates.stats.families
    local key = entry and entry.unit or "shared"
    stats[key] = stats[key] or {}
    stats[key][family] = (stats[key][family] or 0) + 1
    generation = generation + 1
    local cleanup = owner.runtimeCleanup and owner.runtimeCleanup[family]
    local binding = { owner = owner, family = family, settings = safe and request.colorSettings.settings or request.settingsSnapshot,
        revision = request.revision, layout = layout, generation = generation,
        allocations = cleanup and cleanup.allocations or {}, reusable = cleanup and cleanup.reusable,
        status = "applying", attempts = previousFailure and previousFailure.revision == request.revision
            and previousFailure.attempts + 1 or 1, reported = previousFailure and previousFailure.reported }
    -- Keep a physical cleanup record before entering a potentially throwing call.
    owner.runtimeAttempt = binding
    owner.runtimePending[family] = binding
    owner.runtimeCleanup = owner.runtimeCleanup or {}
    owner.runtimeCleanup[family] = binding
    local ok, status, reason = invoke(binding, fn, ...)
    if not ok then return false, "callback-error" end
    if binding.cancelled then return false, binding.reason or "failed" end
    if not isCurrent() then
        binding.cancelled = true
        Runtime.Defer("superseded")
        return false, "superseded"
    end
    if not GUF.Secret(status) and (status == "failed" or status == "deferred" or status == "unavailable") then
        if status == "failed" then fail(binding, reason or "feature-error")
        else binding.status, binding.reason = status, reason; Runtime.Defer(reason) end
        return false, reason or status
    end
    if binding.deferred then
        binding.status, binding.reason = "deferred", binding.deferred
        Runtime.Defer(binding.deferred)
        return false, binding.deferred
    end
    binding.status = "applied"
    families[family], failures[family] = binding, nil
    owner.runtimePending[family] = nil
    latest[family], binding.alphaChanges = binding, nil
    owner.runtimeAttempt = nil
    for id, attempt in pairs(owner.runtimeCleanup) do
        if attempt.family == family then owner.runtimeCleanup[id] = nil end
    end
    if binding.cleanupReason then
        binding.reason = binding.cleanupReason
        owner.runtimeCleanup[family] = binding
        GUF.QueueRecovery("runtime-cleanup", owner, family)
    end
    return true
end

-- Native hooks are installed once. Their refreshes use current bindings, not
-- the generation that happened to install the permanent engine hook.
function Runtime.Refresh(entry, family, fn, ...)
    if type(entry) == "table" and entry.configurationPreview then return fn(...) end
    local owner, families, failures = records(entry)
    if current and (current.owner == owner or current.owner == shared) then return fn(...) end
    local binding = Runtime.Binding(family, entry)
    if not binding or failures[family] or failures.construction or failures.layout
        or owner.runtimePending[family] or owner.runtimePending.construction or owner.runtimePending.layout
        or shared.runtimeFailures and shared.runtimeFailures[family] then
        Runtime.Defer("settings", owner, family)
        return
    end
    local ok, a, b, c = invoke(binding, fn, ...)
    if ok then return a, b, c end
end

function Runtime.Sample(fn, ...)
    local previous, scope = Runtime.sample, current
    Runtime.sample, current = true, nil
    local result = pack(pcall(fn, ...))
    Runtime.sample, current = previous, scope
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

function Runtime.NativeCallback(binding, fn, ...)
    if current and (not binding or binding.owner == current.owner) then return fn(...) end
    local writers = GUF.NativeProperties.CaptureWriters(binding and binding.owner, true)
    local result = pack(pcall(fn, ...))
    if not result[1] then
        GUF.NativeProperties.RestoreWriters(writers, binding and binding.owner)
        if binding then fail(binding, "native-callback-error", result[2])
        else GUF.QueueRecovery("native-callback-error"); reportError(result[2]) end
        return
    end
    return unpack(result, 2, result.n)
end

function Runtime.Wrap(family, names, unit)
    for _, name in ipairs(names) do
        local original = GUF[name]
        if type(original) ~= "function" then error("Missing runtime callback: " .. name) end
        GUF[name] = function(first, ...)
            local entry = unit and GUF.frames[unit] or first
            return Runtime.Refresh(entry, family, original, first, ...)
        end
    end
end

function Runtime.Release(entry, definition, fn)
    local binding = entry.runtimeLayoutAttempts and entry.runtimeLayoutAttempts[definition.id]
        or entry.runtimeLayouts and entry.runtimeLayouts[definition.id]
    if not binding then return fn(entry) end
    local ok, status, reason, pending = invoke(binding, fn, entry)
    if not ok then return "failed", "release-error", definition.live.pending and definition.live.pending(entry) end
    return status, reason, pending
end

function Runtime.Request(fn, retry, change, source)
    local queued = GUF.LayoutTransitions.Current()
    if retry and queued and GUF.LayoutTransitions.IsCurrent(queued) and (queued.requestFailures or 0) >= 3 then
        GUF.QueueRecovery("request-retry-limit"); return
    end
    if Runtime.applying or current or Runtime.sample then
        GUF.LayoutTransitions.Request(GUF.db, GUF.GetRequestedLayout() or GUF.db.general.frameStyle, retry, change, source)
        GUF.QueueRecovery("request-reentry")
        return
    end
    Runtime.applying = true
    local writers = {}
    for _, entry in pairs(GUF.frames) do writers[entry] = GUF.NativeProperties.CaptureWriters(entry) end
    local result = pack(pcall(fn, retry, change, source))
    Runtime.applying = nil
    if not result[1] then
        for entry, saved in pairs(writers) do GUF.NativeProperties.RestoreWriters(saved, entry) end
        local request = GUF.LayoutTransitions.Current()
        if request then
            request.phase, request.reason = "failed", "request-error"
            request.requestFailures = (request.requestFailures or 0) + 1
        end
        GUF.QueueRecovery("request-error")
        if request and not request.errorReported then
            request.errorReported = true
            GUF.Print("An apply request could not finish; cleanup is retained. See /guf layoutdebug.")
            reportError(result[2])
        end
        return
    end
    return unpack(result, 2, result.n)
end

function Runtime.Commit(request)
    if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return false end
    Runtime.lastSettings = request.settingsSnapshot
    Runtime.lastProfile, Runtime.lastLayout = request.profile, request.layout
    return true
end

