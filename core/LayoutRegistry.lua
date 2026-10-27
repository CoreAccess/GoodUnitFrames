local _, GUF = ...
local Layouts = {}
GUF.Layouts = Layouts

local definitions, ordered = {}, {}
local nativeScale = { minimum = 1, maximum = 1.5, step = .01, nativeSetting = true }

local function number(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Definitions are registered during addon loading and read only afterward.
-- Forwarding callbacks resolve their presenters when used, after the TOC loads.
function Layouts.Register(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string" or definition.id == "" then
        error("Good Unit Frames layout registration requires a nonempty string id.")
    end
    local id = definition.id
    local function invalid(reason)
        error("Good Unit Frames layout '" .. id .. "': " .. reason)
    end
    if definitions[id] then invalid("duplicate registration.") end
    for _, key in ipairs({ "title", "description" }) do
        if type(definition[key]) ~= "string" or definition[key] == "" then invalid("missing " .. key .. ".") end
    end
    if not number(definition.order) then invalid("missing numeric order.") end
    local defaults = definition.defaults
    if type(defaults) ~= "table" or type(defaults.frames) ~= "table"
        or type(defaults.frames.player) ~= "table" or type(defaults.frames.target) ~= "table"
        or type(defaults.threat) ~= "table" or type(defaults.hideBlizzard) ~= "table" then
        invalid("missing managed-unit factory defaults.")
    end
    if type(definition.units) ~= "table" or definition.units.player ~= true or definition.units.target ~= true then
        invalid("Player and Target support is required for the shared layout.")
    end
    for _, key in ipairs({ "capabilities", "renderCard" }) do
        if type(definition[key]) ~= "function" then invalid("missing " .. key .. " callback.") end
    end
    if type(definition.presentation) ~= "table" then invalid("missing presentation callbacks.") end
    if type(definition.presentation.nativeBarColors) ~= "boolean" then invalid("missing native bar-color policy.") end
    for _, key in ipairs({ "createSample", "renderSample", "geometry", "role", "bounds" }) do
        if type(definition.presentation[key]) ~= "function" then invalid("missing presentation." .. key .. " callback.") end
    end
    if type(definition.live) ~= "table" then invalid("missing live lifecycle callbacks.") end
    for _, key in ipairs({ "release", "apply", "finalize" }) do
        if type(definition.live[key]) ~= "function" then invalid("missing live." .. key .. " callback.") end
    end
    for _, key in ipairs({ "writerStates", "recover", "pending", "refreshGeometry", "cleanupReady" }) do
        if definition.live[key] ~= nil and type(definition.live[key]) ~= "function" then invalid("invalid live." .. key .. " callback.") end
    end
    for _, key in ipairs({ "dimensions", "nativeOriginal", "paintedBounds", "layoutResources", "positionThreat", "threatVisibility", "renderThreatSample" }) do
        if definition.presentation[key] ~= nil and type(definition.presentation[key]) ~= "function" then
            invalid("invalid presentation." .. key .. " callback.")
        end
    end
    if definition.available ~= nil and type(definition.available) ~= "function" then
        invalid("available must be a client capability callback.")
    end
    local scale = definition.scale
    if type(scale) ~= "table" or not number(scale.minimum) or not number(scale.maximum)
        or not number(scale.step) or scale.minimum <= 0 or scale.maximum < scale.minimum
        or scale.step <= 0 or type(scale.nativeSetting) ~= "boolean" then
        invalid("invalid scale policy.")
    end
    if type(definition.allowSize) ~= "boolean" then invalid("missing native size policy.") end
    definitions[id] = definition
    ordered[#ordered + 1] = definition
    table.sort(ordered, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
end

function Layouts.Get(id)
    return definitions[id]
end

-- Native metadata may still belong to a released/unavailable owner while
-- restoration waits. Ask every registered owner, never just the new layout.
function Layouts.NativeOriginal(entry, region)
    for _, definition in ipairs(ordered) do
        local callback = definition.presentation.nativeOriginal
        local original = callback and callback(entry, region)
        if original then return original end
    end
end

function Layouts.WriterStates(entry, shallow)
    local states = {}
    for _, definition in ipairs(ordered) do
        local callback = definition.live.writerStates
        for _, state in ipairs(callback and callback(entry, shallow) or {}) do states[#states + 1] = state end
    end
    return states
end

function Layouts.RecoverLive(entry, binding)
    local definition = definitions[binding.layout]
    if definition and definition.live.recover then definition.live.recover(entry) end
end

function Layouts.RefreshNativeGeometry(entry, region, geometry)
    local pending, cleanup = false, true
    for _, definition in ipairs(ordered) do
        local callback = definition.live.refreshGeometry
        if callback then
            local restored, retry, scope = callback(entry, region, geometry)
            if restored then return true end
            if retry then pending, cleanup = true, cleanup and scope == "cleanup" end
        end
    end
    if pending then GUF.QueueRecovery(cleanup and "layout-cleanup-ready" or "layout-native-geometry", entry) end
end

-- Availability describes definitions/client capability, never combat permission
-- or whether a native frame has been constructed yet. Do not cache the result.
function Layouts.IsAvailable(id, unit)
    local definition = definitions[id]
    if not definition then return false, "unknown-layout" end
    if unit and not definition.units[unit] then return false, "unsupported-unit" end
    if definition.available then
        local available, reason = definition.available(GUF.Client)
        if not available then return false, reason or "unavailable-client" end
    end
    return true
end

function Layouts.List()
    local available = {}
    for _, definition in ipairs(ordered) do
        if Layouts.IsAvailable(definition.id) then available[#available + 1] = definition end
    end
    return available
end

function Layouts.Capabilities(id, unit)
    if not Layouts.IsAvailable(id, unit) then return {} end
    return definitions[id].capabilities(unit)
end

function Layouts.ScalePolicy(id)
    local definition = definitions[id]
    -- Conservative normalization fallback does not make an unknown layout
    -- available; Settings and activation validate availability separately.
    return definition and definition.scale or nativeScale
end

-- Readiness callbacks may retry an incomplete pass for the current settings.
-- They only queue RequestApply's existing guarded tick, never attach a view.
function Layouts.NeedsLiveApply(entry)
    local lifecycle = entry and entry.layoutLifecycle
    return lifecycle ~= nil and GUF.db ~= nil and lifecycle.layout == GUF.db.general.frameStyle
        and (lifecycle.applyStatus == "deferred" or lifecycle.applyStatus == "unavailable")
end

-- Retry release even without an applied-layout marker: a nonselected layout
-- may retain deferred restoration. Availability does not cancel cleanup.
function Layouts.ReleaseOtherLive(entry, selected)
    local results = {}
    for _, definition in ipairs(ordered) do
        if definition ~= selected then
            local release = GUF.LayoutTransitions.ReleaseOperation(entry, definition)
            local status, reason, pending = GUF.Runtime.Release(entry, definition, release)
            results[definition.id] = { status = status or "unreported", reason = reason,
                pending = pending, release = release }
        end
    end
    return results
end

-- Finalizers inspect their own retained ownership before doing any work. Keep
-- the existing Artistic finalization on both paths, including deferred release;
-- these compatibility callbacks do not mark a transition applied/complete.
function Layouts.FinalizeLive(entry)
    for _, definition in ipairs(ordered) do definition.live.finalize(entry) end
end
