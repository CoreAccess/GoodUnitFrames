local _, GUF = ...

local function yes(value)
    return not GUF.Secret(value) and (value == true or value == 1)
end

local function camera(model)
    -- The model renders in a fixed square surface, independent of chamber height.
    model:SetPortraitZoom(1)
    model:SetPosition(0, 0, 0)
end

function GUF.SetArtisticPortraitTexture(texture, unit)
    -- Blizzard owns the live portrait's coordinates, including cached renders.
    -- Do not reset them before OR after binding: a cached portrait may retain
    -- its rendered texture without replacing coordinates we just overwrote.
    -- Static specimen icons set their own coordinates in ConfigurationMode.
    -- Use the standard portrait bind used by Dino and the stock Target frame.
    -- Do not force the Player frame's disablePortraitMask mode on every unit.
    -- Our separate MaskTexture still clips the result to the painted opening.
    return pcall(SetPortraitTexture, texture, unit)
end

function GUF.CreateArtisticPortrait(entry, state)
    local viewport = CreateFrame("Frame", nil, state.rim)
    viewport.goodUnitFramesOwned = true
    viewport:EnableMouse(false)
    if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
    state.viewport = viewport
    state.portraitFallback = viewport:CreateTexture(nil, "ARTWORK")
    state.portraitFallback.goodUnitFramesOwned = true
    state.portraitFallback:SetPoint("CENTER", viewport, "CENTER")
    state.portraitCircleMask = viewport:CreateMaskTexture(nil, "ARTWORK")
    state.portraitCircleMask.goodUnitFramesOwned = true
    state.portraitCircleMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    state.portraitCircleMask:SetAllPoints(state.portraitFallback)
    state.portraitFallback:AddMaskTexture(state.portraitCircleMask)
    -- A circular texture mask cannot crop a PlayerModel render surface. Avoid
    -- allocating an unused model for the circular foundation.
    local ok, model
    if not state.circular then ok, model = pcall(CreateFrame, "PlayerModel", nil, viewport) end
    if ok and model then
        model.goodUnitFramesOwned = true
        model:EnableMouse(false)
        model:SetPoint("CENTER", viewport, "CENTER")
        if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, true) end
        model:SetScript("OnShow", function(self) pcall(camera, self) end)
        model:SetScript("OnModelLoaded", function(self)
            pcall(camera, self)
            if state.active and state.modelAccepted then state.portraitFallback:Hide() end
        end)
        model:Hide()
        state.model = model
    end
    state.portraitDirty = true
end

function GUF.LayoutArtisticPortrait(entry)
    local state = entry.artisticLayout
    local source = state.rim.source
    local side = state.portraitWidth * (source and source.openingRatio or .82)
    local openingX = state.portraitWidth * (source and source.openingX or 0) * (state.rim.mirrored and -1 or 1)
    local openingY = state.portraitWidth * (source and source.openingY or 0)
    state.viewport:ClearAllPoints()
    state.viewport:SetPoint("CENTER", state.rim, "CENTER", openingX, openingY)
    state.viewport:SetSize(side, side)
    state.viewport:SetFrameLevel(state.rim:GetFrameLevel() + 1)
    -- The square native texture has a circular alpha mask, fitted slightly
    -- underneath the rim's measured opening. The face is never reshaped.
    if state.model then
        state.model:SetFrameLevel(state.viewport:GetFrameLevel() + 1)
        state.model:ClearAllPoints()
        state.model:SetPoint("CENTER", state.viewport, "CENTER")
        state.model:SetSize(side, side)
    end
    state.portraitFallback:ClearAllPoints()
    state.portraitFallback:SetPoint("CENTER", state.viewport, "CENTER")
    state.portraitFallback:SetSize(side, side)
    -- Layout owns the viewport, not the native portrait's rendered coordinates.
    local mask = state.portraitCircleMask
    mask:ClearAllPoints()
    if source and source.combined then
        -- The complete painting can overlap its portrait aperture at the Level
        -- join. Clip only to its exported alpha opening, never through that boss.
        -- Keep masking independent of runtime UV reflection: the exported
        -- Target mask has its opening already mirrored in the pixels.
        local maskFile = state.rim.mirrored and source.maskTarget or source.mask
        if state.portraitMaskFile ~= maskFile then
            mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
            state.portraitMaskFile = maskFile
        end
        local factor = state.portraitWidth / source.diameter
        local center = state.rim.mirrored and source.canvas - source.centerX or source.centerX
        mask:SetPoint("CENTER", state.rim, "CENTER", (source.canvas / 2 - center) * factor,
            (source.centerY - source.canvas / 2) * factor)
        mask:SetSize(source.canvas * factor, source.canvas * factor)
        mask:SetTexCoord(0, 1, 0, 1)
    else
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
        mask:SetAllPoints(state.portraitFallback); mask:SetTexCoord(0, 1, 0, 1)
        state.portraitMaskFile = nil
    end
    state.portraitDirty = true
end

function GUF.ClearArtisticPortrait(state)
    state.modelAccepted = nil
    state.portraitDirty = true
    state.portraitUnit = nil
    if state.model then state.model:Hide(); state.model:ClearModel() end
    state.viewport:Hide()
end

function GUF.UpdateArtisticPortrait(entry)
    local state = entry.artisticLayout
    if not state or not state.active then return end
    GUF.UpdateArtisticPortraitArtwork(entry)
    local unit = entry.frame.unit or entry.unit
    -- PlayerModel has a rectangular render surface. Use Blizzard's maskable
    -- live portrait texture for this circular pass; preserve the saved 3D option.
    local wantModel = not state.circular and GUF.db.frames[entry.unit].artistic.portrait3D and state.model ~= nil
    if not yes(UnitExists(unit)) then GUF.ClearArtisticPortrait(state); return end
    if state.portraitUnit ~= unit or state.wantModel ~= wantModel then state.portraitDirty = true end
    if not state.portraitDirty then
        -- Retry a blocked model slowly, rather than restarting its animation every tick.
        if not wantModel or state.modelAccepted or GetTime() < (state.portraitRetry or 0) then return end
    end
    state.portraitDirty, state.portraitUnit, state.wantModel = false, unit, wantModel
    state.modelAccepted = nil
    state.viewport:Show()
    state.portraitFallback:Show()
    GUF.SetArtisticPortraitTexture(state.portraitFallback, unit)
    local model = state.model
    if model then model:Hide(); model:ClearModel() end
    if not wantModel then return end
    state.portraitRetry = GetTime() + 1
    if UnitIsVisible and not yes(UnitIsVisible(unit)) then return end
    if UnitIsConnected and not yes(UnitIsConnected(unit)) then return end
    -- SetUnit needs public unit identity in current clients. Never compare a secret GUID.
    if UnitGUID then
        local identityOK, guid = pcall(UnitGUID, unit)
        if not identityOK or GUF.Secret(guid) then return end
    end
    if model.CanSetUnit then
        local allowed, result = pcall(model.CanSetUnit, model, unit)
        if not allowed or GUF.Secret(result) or result == false then return end
    end
    local accepted, result = pcall(model.SetUnit, model, unit)
    if not accepted or GUF.Secret(result) or result == false then return end
    state.modelAccepted = true
    pcall(camera, model)
    model:Show()
    state.portraitFallback:Hide()
end

-- Refresh on identity/model changes, not on unrelated health/power updates.
local events = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED", "UNIT_MODEL_CHANGED", "PLAYER_TARGET_CHANGED",
    "UNIT_TARGET", "UNIT_PET", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_CLASSIFICATION_CHANGED",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, unit)
    if not GUF.db then return end
    for _, entry in pairs(GUF.frames) do
        local state = entry.artisticLayout
        if state and state.active then
            local affected = event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
                or event == "PORTRAITS_UPDATED"
                or (event == "PLAYER_TARGET_CHANGED" and (entry.unit == "target" or entry.unit == "targettarget"))
                or (event == "UNIT_TARGET" and not GUF.Secret(unit) and unit == "target" and entry.unit == "targettarget")
                or (event == "UNIT_PET" and not GUF.Secret(unit) and unit == "player" and entry.unit == "pet")
                or (not GUF.Secret(unit) and (unit == entry.unit or unit == entry.frame.unit))
            if affected then
                state.portraitDirty = true
                GUF.UpdateArtisticPortrait(entry)
            end
        end
    end
end)
