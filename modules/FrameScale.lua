local _, GUF = ...

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Read display percentages, not Edit Mode's encoded setting values. Some
-- compact units have no native size control and keep the addon control alone.
local function nativeSetting(entry)
    local setting = Enum and Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.FrameSize
    local frame = entry and entry.frame
    if not setting or not frame or not frame.HasSetting or not frame.GetSettingValue
        or not frame.UpdateSystemSettingValue or not frame.systemInfo or not frame:HasSetting(setting) then return end
    local value = frame:GetSettingValue(setting)
    if number(value) and value > 0 then return setting, value / 100 end
end

function GUF.NormalizeFrameScales(frames, style)
    local policy = GUF.Layouts.ScalePolicy(style)
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        if type(cfg) == "table" then
            cfg.scale = number(cfg.scale) and math.max(policy.minimum, math.min(policy.maximum, cfg.scale)) or 1
        end
    end
end

local function limits(entry, policy)
    if not policy.nativeSetting then return policy.minimum, policy.maximum, policy.step end
    local setting = nativeSetting(entry)
    local info = setting and entry.frame.settingDisplayInfoMap and entry.frame.settingDisplayInfoMap[setting]
    if info and number(info.minValue) and number(info.maxValue) and info.minValue > 0 and info.maxValue >= info.minValue then
        local minimum, maximum = math.max(policy.minimum, info.minValue / 100), math.min(policy.maximum, info.maxValue / 100)
        if maximum >= minimum then
            return minimum, maximum,
                number(info.stepSize) and info.stepSize > 0 and info.stepSize / 100 or policy.step
        end
    end
    return policy.minimum, policy.maximum, policy.step
end

function GUF.FrameScaleLimits(unit)
    return limits(GUF.frames[unit], GUF.Layouts.ScalePolicy(GUF.db.general.frameStyle))
end

-- Capture only public scale inputs, once after layout commit and before either
-- unit is written. Never mutate these records or use profile tables as inputs
-- to a native repair hook after a newer request has been deferred.
function GUF.CaptureFrameScaleRequest(request)
    if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return false end
    if request.frameScales then return true end
    local inputs = {}
    local policy = GUF.Copy(GUF.Layouts.ScalePolicy(request.layout))
    for _, unit in ipairs(GUF.order) do
        local cfg = request.profile.frames[unit]
        inputs[unit] = { source = cfg, value = cfg.scale, layout = request.layout,
            revision = request.revision, scope = "request", policy = policy }
    end
    request.frameScales = inputs
    return true
end

local function editSession()
    local session = GUF.editModeScaleSession
    if GUF.editing and GUF.db and session and session.profile == GUF.db and session.frames == GUF.db.frames then return session end
end

local function scaleInput(entry, editModeSizeChange, request)
    if request then
        if not GUF.LayoutTransitions.IsCurrent(request, request.layout) then return end
        return request.frameScales and request.frameScales[entry.unit]
    end
    local session = editModeSizeChange and editSession()
    if session then
        local cfg = session.frames[entry.unit]
        return { source = cfg, value = cfg.scale, layout = GUF.db.general.frameStyle,
            scope = "edit-mode", policy = GUF.Copy(GUF.Layouts.ScalePolicy(GUF.db.general.frameStyle)) }, session
    end
    return entry.appliedFrameScale
end

local function inputCurrent(entry, input, request, session)
    if request then return GUF.LayoutTransitions.IsCurrent(request, input.layout) end
    if session then return editSession() == session end
    return entry.appliedFrameScale == input
end

local function refresh(unit)
    if GUF.RefreshOptionsFrameScale then GUF.RefreshOptionsFrameScale(unit) end
    if GUF.UpdateOptionsPreview then GUF.UpdateOptionsPreview() end
end

local function receive(entry)
    if entry.scaleWriting or not GUF.db or not editSession() then return end
    local _, value = nativeSetting(entry)
    if not value or (entry.nativeScaleValue and math.abs(value - entry.nativeScaleValue) < .000001) then return end
    entry.nativeScaleValue = value
    local cfg = GUF.db.frames[entry.unit]
    cfg.scale = value
    GUF.QueueRecovery("native-scale-import", entry)
    -- This is the user's native size change, not a general layout apply.
    -- Normalize parents without reapplying artwork/anchors inside Edit Mode.
    if not GUF.Restricted() then
        for _, unit in ipairs(GUF.order) do
            local other = GUF.frames[unit]
            if other then GUF.ApplyFrameScale(other, true) end
        end
    end
    refresh(entry.unit)
    return true
end

local function hook(entry)
    if entry.scaleHooked then return end
    GUF.NativeProperties.Hook("FrameScale:1", entry.frame, "SetScale", function()
        if entry.scaleWriting then return end
        local applied = entry.appliedFrameScale
        if applied and not applied.policy.nativeSetting then
            -- Native layout initialization still uses its own percentage.
            -- Reassert the independently configured Artistic scale only.
            -- Import a genuine native Edit Mode edit before reasserting scale;
            -- otherwise reading its new value here would hide it from receive.
            if not receive(entry) then GUF.ApplyFrameScale(entry, true) end
            return
        end
        -- The native setting update has not finished yet. Its posthook imports
        -- the new percentage; reapplying here would overwrite the user's edit.
        GUF.QueueRecovery("native-scale", entry)
    end)
    for _, method in ipairs({ "UpdateSystem", "UpdateSystemSettingValue" }) do
        if type(entry.frame[method]) == "function" then
            GUF.NativeProperties.Hook("FrameScale:2", entry.frame, method, function() receive(entry) end)
        end
    end
    entry.scaleHooked = true
end

function GUF.ApplyFrameScale(entry, editModeSizeChange, request)
    if GUF.Restricted() or (GUF.editing and not editModeSizeChange) then
        GUF.QueueRecovery("scale-restricted", entry); return "deferred", "restricted"
    end
    if entry.scaleWriting then GUF.QueueRecovery("scale-writing", entry); return "deferred", "writing" end
    local input, session = scaleInput(entry, editModeSizeChange, request)
    if not input then GUF.QueueRecovery("scale-input", entry); return "deferred", "settings" end
    hook(entry)
    local independent = not input.policy.nativeSetting
    local setting, nativeValue = nativeSetting(entry)
    local desired = number(input.value) and input.value > 0 and input.value or 1
    local minimum, maximum = limits(entry, input.policy)
    local value = math.max(minimum, math.min(maximum, desired))
    local parent = entry.frame:GetParent()
    local parentScale, screenScale = parent and parent:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not number(parentScale) or not number(screenScale) or parentScale <= 0 or screenScale <= 0 then
        GUF.QueueRecovery("scale-parent", entry)
        return "deferred", "parent-scale"
    end
    if not inputCurrent(entry, input, request, session) then GUF.QueueRecovery("scale-superseded", entry); return "deferred", "superseded" end
    entry.scaleWriting = true
    GUF.NativeProperties.Track(entry.frame, "rootScale", entry, entry)
    -- Artistic can be smaller than Blizzard's native size control permits.
    -- Keep its absolute scale independent of the saved native setting.
    if not independent and setting and math.abs(value - nativeValue) > .000001 then
        entry.frame:UpdateSystemSettingValue(setting, value * 100)
        local _, applied = nativeSetting(entry)
        if applied then value = applied end
    end
    if not inputCurrent(entry, input, request, session) then
        entry.scaleWriting = nil; GUF.QueueRecovery("scale-superseded", entry); return "deferred", "superseded"
    end
    -- Every unit uses an absolute UIParent scale, regardless of its native
    -- parent or selected layout. This also isolates Pet/ToT from parent scale.
    parent = entry.frame:GetParent()
    parentScale = parent and parent:GetEffectiveScale()
    if number(parentScale) and parentScale > 0 then
        entry.frame:SetScale(value * screenScale / parentScale)
    else
        entry.scaleWriting = nil; GUF.QueueRecovery("scale-parent", entry); return "deferred", "parent-scale"
    end
    entry.scaleWriting = nil
    if not inputCurrent(entry, input, request, session) then GUF.QueueRecovery("scale-superseded", entry); return "deferred", "superseded" end
    -- Compare later native Edit Mode edits with the actual native value, not
    -- the independent Artistic percentage, so opening it preserves 75%.
    entry.nativeScaleValue = setting and (independent and nativeValue or value) or nil
    if input ~= entry.appliedFrameScale or value ~= input.value then
        entry.appliedFrameScale = { value = value, layout = input.layout, revision = input.revision,
            scope = input.scope, policy = input.policy }
    end
    -- Only explicit apply/editor work may normalize its original desired value.
    -- Repair hooks never write settings or import a newer profile's scale.
    local source = input.source
    local changed = source and source.scale == input.value and (not number(input.value) or math.abs(input.value - value) > .000001)
    if source and source.scale == input.value then source.scale = value end
    if changed then refresh(entry.unit) end
    return "applied"
end

function GUF.SetFrameScale(unit, value)
    local cfg = GUF.db.frames[unit]
    local minimum, maximum = GUF.FrameScaleLimits(unit)
    cfg.scale = number(value) and math.max(minimum, math.min(maximum, value)) or 1
    if GUF.editing and not GUF.Restricted() then
        for _, id in ipairs(GUF.order) do
            local entry = GUF.frames[id]
            if entry then GUF.ApplyFrameScale(entry, true) end
        end
    end
end

function GUF.BeginFrameScaleEdit()
    local session = { profile = GUF.db, frames = GUF.db.frames, scales = {} }
    for _, unit in ipairs(GUF.order) do session.scales[unit] = GUF.db.frames[unit].scale end
    GUF.editModeScaleSession = session
    -- Native layout initialization must not replace a named profile's size
    -- simply because Edit Mode opened; only subsequent user edits import it.
    if not GUF.Restricted() then
        for _, unit in ipairs(GUF.order) do
            local entry = GUF.frames[unit]
            if entry then GUF.ApplyFrameScale(entry, true) end
        end
    end
end

function GUF.SaveFrameScaleEdit()
    local session = GUF.editModeScaleSession
    if not session or session.profile ~= GUF.db or session.frames ~= GUF.db.frames then return end
    -- Saving establishes the new rollback point for subsequent edits/discard.
    for _, unit in ipairs(GUF.order) do session.scales[unit] = GUF.db.frames[unit].scale end
end

function GUF.EndFrameScaleEdit()
    local session = GUF.editModeScaleSession
    GUF.editModeScaleSession = nil
    if not session or session.profile ~= GUF.db or session.frames ~= GUF.db.frames then return end
    for _, unit in ipairs(GUF.order) do
        GUF.db.frames[unit].scale = session.scales[unit]
        refresh(unit)
    end
end
