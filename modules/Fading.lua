local _, GUF = ...

-- Alpha-only fading leaves Blizzard's secure unit buttons and click behavior intact.
local function setAlpha(entry, value)
    local state = GUF.alphaStates and GUF.alphaStates[entry.frame]
    if not state or state.override ~= value then GUF.RegionAlpha(entry.frame, value) end
end

function GUF.UpdateFading(delta)
    if not GUF.db then return end
    local inCombat = InCombatLockdown()
    for unit, entry in pairs(GUF.frames) do
        local cfg = GUF.db.frames[unit]
        local fade = cfg.fading
        if GUF.configurationUnlocked and unit == GUF.configurationUnit then
            setAlpha(entry, 0)
            entry.fade = nil
        elseif fade.native and not fade.enabled then
            setAlpha(entry, nil)
            entry.fade = nil
        elseif not fade.enabled or GUF.editing then
            setAlpha(entry, 1)
            entry.fade = nil
        else
            local state = entry.fade
            if not state then
                local alpha = entry.frame:GetAlpha()
                state = { value = GUF.Secret(alpha) and 1 or alpha }
            end
            entry.fade = state
            local target = inCombat and fade.combat or fade.inactive
            if target ~= state.target then
                state.start, state.target, state.elapsed = state.value, target, 0
                state.duration = inCombat and .25 or .75
            end
            state.elapsed = state.elapsed + (delta or 0)
            local progress = math.min(1, state.elapsed / state.duration)
            state.value = state.start + (state.target - state.start) * progress
            setAlpha(entry, state.value)
        end
    end
end
