local _, GUF = ...

-- Custom surrounds are paused. Keep the release path so existing owned
-- cosmetic surfaces return to the Blizzard presentation during an apply.
-- Health/Power fill media, Name opacity and all geometry keep their owners.
function GUF.LayoutBarDesign(entry)
    local state = entry.artisticLayout
    if not state then return end
    if state.barDesign then state.barDesign:Hide() end
    if not state.barDesignApplied then return end
    for _, region in ipairs({ state.nameStrip.topTrim, state.nameStrip.sideTrim, state.nameStrip.cornerTrim }) do region:Show() end
    if state.housing.border then state.housing.border:Show() else state.housing:Show() end
    local divider = state.divider or state.separators and state.separators[2]
    if divider then divider:SetShown(not state.noPower) end
    state.barDesignApplied = nil
end
