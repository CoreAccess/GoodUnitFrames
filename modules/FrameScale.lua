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
    local minimum = style == "artistic" and .75 or 1
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        if type(cfg) == "table" then
            cfg.scale = number(cfg.scale) and math.max(minimum, math.min(1.5, cfg.scale)) or 1
        end
    end
end

function GUF.FrameScaleLimits(unit)
    if GUF.db.general.frameStyle == "artistic" then return .75, 1.5, .01 end
    local entry = GUF.frames[unit]
    local setting = nativeSetting(entry)
    local info = setting and entry.frame.settingDisplayInfoMap and entry.frame.settingDisplayInfoMap[setting]
    if info and number(info.minValue) and number(info.maxValue) and info.minValue > 0 and info.maxValue >= info.minValue then
        local minimum, maximum = math.max(1, info.minValue / 100), math.min(1.5, info.maxValue / 100)
        if maximum >= minimum then
            return minimum, maximum,
                number(info.stepSize) and info.stepSize > 0 and info.stepSize / 100 or .01
        end
    end
    return 1, 1.5, .01
end

local function refresh(unit)
    if GUF.RefreshOptionsFrameScale then GUF.RefreshOptionsFrameScale(unit) end
    if GUF.UpdateOptionsPreview then GUF.UpdateOptionsPreview() end
end

local function receive(entry)
    if entry.scaleWriting or not GUF.db or not GUF.editing then return end
    local _, value = nativeSetting(entry)
    if not value or (entry.nativeScaleValue and math.abs(value - entry.nativeScaleValue) < .000001) then return end
    entry.nativeScaleValue = value
    local cfg = GUF.db.frames[entry.unit]
    cfg.scale = value
    GUF.pending = true
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
    hooksecurefunc(entry.frame, "SetScale", function()
        if entry.scaleWriting then return end
        if GUF.db and GUF.db.general.frameStyle == "artistic" then
            -- Native layout initialization still uses its own percentage.
            -- Reassert the independently configured Artistic scale only.
            -- Import a genuine native Edit Mode edit before reasserting scale;
            -- otherwise reading its new value here would hide it from receive.
            if not receive(entry) then GUF.ApplyFrameScale(entry, true) end
            return
        end
        -- The native setting update has not finished yet. Its posthook imports
        -- the new percentage; reapplying here would overwrite the user's edit.
        GUF.pending = true
    end)
    for _, method in ipairs({ "UpdateSystem", "UpdateSystemSettingValue" }) do
        if type(entry.frame[method]) == "function" then
            hooksecurefunc(entry.frame, method, function() receive(entry) end)
        end
    end
    entry.scaleHooked = true
end

function GUF.ApplyFrameScale(entry, editModeSizeChange)
    if GUF.Restricted() or (GUF.editing and not editModeSizeChange) then GUF.pending = true; return end
    hook(entry)
    local cfg = GUF.db.frames[entry.unit]
    local artistic = GUF.db.general.frameStyle == "artistic"
    local setting, nativeValue = nativeSetting(entry)
    if not number(cfg.scale) or cfg.scale <= 0 then cfg.scale = 1 end
    local minimum, maximum = GUF.FrameScaleLimits(entry.unit)
    local value = math.max(minimum, math.min(maximum, cfg.scale))
    local parent = entry.frame:GetParent()
    local parentScale, screenScale = parent and parent:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not number(parentScale) or not number(screenScale) or parentScale <= 0 or screenScale <= 0 then
        GUF.pending = true
        return
    end
    entry.scaleWriting = true
    -- Artistic can be smaller than Blizzard's native size control permits.
    -- Keep its absolute scale independent of the saved native setting.
    if not artistic and setting and math.abs(value - nativeValue) > .000001 then
        entry.frame:UpdateSystemSettingValue(setting, value * 100)
        local _, applied = nativeSetting(entry)
        if applied then value = applied end
    end
    -- Compare later native Edit Mode edits with the actual native value, not
    -- the independent Artistic percentage, so opening it preserves 75%.
    entry.nativeScaleValue = setting and (artistic and nativeValue or value) or nil
    local changed = math.abs(cfg.scale - value) > .000001
    cfg.scale = value
    -- Every unit uses an absolute UIParent scale, regardless of its native
    -- parent or selected layout. This also isolates Pet/ToT from parent scale.
    parent = entry.frame:GetParent()
    parentScale = parent and parent:GetEffectiveScale()
    if number(parentScale) and parentScale > 0 then
        entry.frame:SetScale(value * screenScale / parentScale)
    else GUF.pending = true end
    entry.scaleWriting = nil
    if changed then refresh(entry.unit) end
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
