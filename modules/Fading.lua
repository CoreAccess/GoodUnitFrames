local _, GUF = ...

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function opacity(value, fallback)
    return number(value) and math.max(0, math.min(1, value)) or fallback
end

local function deferred(reason)
    GUF.QueueRecovery("fading-deferred")
    return "deferred", reason
end

-- Fading is cosmetic and may bind before the structural gate. A queued layout
-- still owns no active settings: capture the currently committed layout, then
-- replace this family snapshot if that same request later commits its layout.
function GUF.CaptureFrameFadingRequest(request)
    if not GUF.LayoutTransitions.IsCurrent(request) then return false end
    local layout = GUF.db.general.frameStyle
    if request.frameFadings and request.frameFadings.layout == layout then return true end
    local inputs = {}
    for _, unit in ipairs(GUF.order) do
        local fade = request.profile.frames[unit].fading
        inputs[unit] = { fading = { native = fade.native == true, enabled = fade.enabled == true,
            combat = opacity(fade.combat, 1), inactive = opacity(fade.inactive, .6) },
            layout = layout, revision = request.revision, scope = "request" }
    end
    request.frameFadings = { layout = layout, units = inputs }
    return true
end

local function inputCurrent(entry, input, request)
    if GUF.frames[entry.unit] ~= entry then return false end
    if request then
        return GUF.LayoutTransitions.IsCurrent(request) and GUF.db.general.frameStyle == input.layout
            and request.frameFadings.units[entry.unit] == input
    end
    return entry.appliedFrameFading == input
end

-- The root has one GUF alpha writer. RegionAlpha retains the physical lease
-- and latest native baseline independently of this family's acknowledgement.
-- In particular, a native-owned binding must never reacquire alpha on a tick.
local function setAlpha(entry, value)
    local state = GUF.alphaStates and GUF.alphaStates[entry.frame]
    if value == nil then
        if state and state.override ~= nil then GUF.RegionAlpha(entry.frame, nil, false, "Fading") end
    elseif not state or state.override ~= value or state.relative then
        GUF.RegionAlpha(entry.frame, value, false, "Fading")
    end
end

-- Only explicit requests change the binding. Ticks and native alpha repairs
-- use the last acknowledged input, including while structural work is blocked.
local function render(entry, input, delta, request)
    if not inputCurrent(entry, input, request) then return deferred("superseded") end
    if entry.fadingWriting then return deferred("writing") end
    local forbidden = entry.frame.IsForbidden and entry.frame:IsForbidden()
    if GUF.Secret(forbidden) or forbidden then return deferred("native-forbidden") end
    local fade = input.fading
    local animation, value, start, target, elapsed, duration
    if fade.native and not fade.enabled then
        value = nil
    elseif not fade.enabled or GUF.editing then
        value = 1
    else
        local inCombat = InCombatLockdown()
        animation = entry.fade
        if not animation then animation = { value = opacity(entry.frame:GetAlpha(), 1) } end
        start, target, elapsed, duration = animation.start, animation.target, animation.elapsed, animation.duration
        local desired = inCombat and fade.combat or fade.inactive
        if desired ~= target then
            start, target, elapsed, duration = animation.value, desired, 0, inCombat and .25 or .75
        end
        elapsed = math.min(duration, elapsed + (delta or 0))
        value = start + (target - start) * math.min(1, elapsed / duration)
    end
    if not inputCurrent(entry, input, request) then return deferred("superseded") end
    entry.fadingWriting = true
    setAlpha(entry, value)
    entry.fadingWriting = nil
    if not inputCurrent(entry, input, request) then return deferred("superseded") end
    if animation then
        animation.value, animation.start, animation.target = value, start, target
        animation.elapsed, animation.duration = elapsed, duration
    end
    entry.fade = animation
    entry.fadingEnvironment = GUF.editing and "edit" or InCombatLockdown() and "combat" or "inactive"
    return "applied"
end

function GUF.ApplyFrameFading(entry, request)
    if not GUF.IsManagedUnit(entry.unit) then return "unavailable", "unsupported-unit" end
    if not GUF.LayoutTransitions.IsCurrent(request) then return deferred("superseded") end
    local input = request.frameFadings and request.frameFadings.units[entry.unit]
    if not input then return deferred("settings") end
    local status, reason = render(entry, input, 0, request)
    if not inputCurrent(entry, input, request) then return deferred("superseded") end
    entry.frameFadingResult = { revision = input.revision, layout = input.layout, status = status, reason = reason }
    if status == "applied" then entry.appliedFrameFading = input end
    return status, reason
end

function GUF.ApplyFadingRequest(request)
    if not GUF.CaptureFrameFadingRequest(request) then return false end
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then GUF.ApplyFrameFading(entry, request) end
        if not GUF.LayoutTransitions.IsCurrent(request) then return false end
    end
    return true
end

function GUF.UpdateFading(delta)
    if not GUF.db then return end
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then
            local input = entry.appliedFrameFading
            if input then
                local environment = GUF.editing and "edit" or InCombatLockdown() and "combat" or "inactive"
                local animation = entry.fade
                if input.fading.enabled and (entry.fadingEnvironment ~= environment
                    or animation and animation.elapsed < animation.duration) then render(entry, input, delta) end
            else GUF.QueueRecovery("fading-input", entry) end
        end
    end
end
