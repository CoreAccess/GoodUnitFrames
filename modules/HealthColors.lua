local _, GUF = ...
local colors = { { 0, .90, 0, 0 }, { .5, .93, .93, 0 }, { 1, .20, .90, .20 } }
local nativeCurve

-- One policy supplies both public synthetic/fallback RGB and the native curve.
-- Only public fractions enter Lua interpolation; opaque amounts use the curve
-- renderer directly through the existing UnitHealthPercent contract.
function GUF.HealthPercentColor(fraction)
    if GUF.Secret(fraction) or type(fraction) ~= "number" or fraction ~= fraction
        or math.abs(fraction) == math.huge then return end
    fraction = math.max(0, math.min(1, fraction))
    local first, last = colors[1], colors[2]
    if fraction > last[1] then first, last = colors[2], colors[3] end
    local amount = (fraction - first[1]) / (last[1] - first[1])
    return first[2] + (last[2] - first[2]) * amount,
        first[3] + (last[3] - first[3]) * amount, first[4] + (last[4] - first[4]) * amount
end

function GUF.HealthPercentCurve()
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return end
    if not nativeCurve then
        nativeCurve = C_CurveUtil.CreateColorCurve()
        for _, point in ipairs(colors) do nativeCurve:AddPoint(point[1], CreateColor(point[2], point[3], point[4])) end
    end
    return nativeCurve
end
