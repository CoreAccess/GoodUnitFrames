local _, GUF = ...
local unpack = unpack or table.unpack

-- These displays belong to Blizzard's controllers, including ready-check
-- timeout/animations. Artistic only mirrors their cosmetic textures above
-- its portrait. Never synthesize live ready state from GetReadyCheckStatus.
function GUF.AutomaticIndicatorSources(entry)
    local frame, context, main = entry.frame, entry.context, entry.main
    local name = frame:GetName()
    local container = frame.PlayerFrameContainer or frame.TargetFrameContainer or frame
    return {
        raid = entry.unit ~= "player" and (context.RaidTargetIcon or context.RaidTargetIndicator or main.RaidTargetIcon
            or container.RaidTargetIcon or context.RaidTargetIconTexture or frame.RaidTargetIconTexture
            or context.TargetMarker or main.TargetMarker or frame.TargetMarker
            or context.TargetMarkerIcon or frame.TargetMarkerIcon
            or frame.RaidTargetIcon or frame.raidTargetIcon
            or (frame.TextureFrame and frame.TextureFrame.RaidTargetIcon)
            or _G[name .. "TextureFrameRaidTargetIcon"] or _G[name .. "RaidTargetIcon"]) or nil,
        status = context.ReadyCheck or context.ReadyCheckIcon or frame.ReadyCheck or frame.ReadyCheckIcon
            or (entry.unit == "player" and PlayerFrameReadyCheck) or _G[name .. "ReadyCheck"],
        resurrect = context.ResurrectIcon or main.ResurrectIcon or frame.ResurrectIcon or frame.resurrectIcon
            or _G[name .. "ResurrectIcon"],
    }
end

local function iconRegion(source, depth)
    if source.GetTexture then return source end
    local icon = source.Icon or source.Texture or source.icon or source.texture
    if icon and icon.GetTexture then return icon end
    if source.GetRegions then
        for _, region in pairs({ source:GetRegions() }) do
            if region.GetTexture and not region.goodUnitFramesOwned then return region end
        end
    end
    if source.GetChildren and (depth or 0) < 3 then
        for _, child in pairs({ source:GetChildren() }) do
            if not child.goodUnitFramesOwned then
                local region = iconRegion(child, (depth or 0) + 1)
                if region then return region end
            end
        end
    end
end

function GUF.PrepareAutomaticIndicators(entry)
    local state = entry.artisticLayout
    state.automaticHooks = state.automaticHooks or {}
    local function observe(region)
        if not region or state.automaticHooks[region] then return end
        state.automaticHooks[region] = true
        local function refresh()
            if state.active and not state.automaticWriting and not entry.layoutWriting then
                GUF.UpdateAutomaticIndicators(entry)
            end
        end
        for _, method in ipairs({ "Show", "Hide", "SetShown", "SetAlpha", "SetTexture", "SetAtlas", "SetTexCoord" }) do
            if type(region[method]) == "function" then hooksecurefunc(region, method, refresh) end
        end
        if region.HookScript then region:HookScript("OnShow", refresh); region:HookScript("OnHide", refresh) end
    end
    for _, source in pairs(GUF.AutomaticIndicatorSources(entry)) do
        state.hidden[source] = true
        GUF.RegionAlpha(source, 0)
        observe(source); observe(iconRegion(source))
    end
end

function GUF.PositionAutomaticBadge(entry, kind, file, coords)
    local state = entry.artisticLayout
    local badge = state.badges[kind]
    local size = (kind == "status" and 40 or kind == "resurrect" and 32 or 26) * state.scale
    badge:ClearAllPoints(); badge:SetPoint("CENTER", state.rim, "CENTER", 0,
        kind == "raid" and state.portraitHeight / 2 or 0)
    badge:SetSize(size, size); badge:SetAlpha(1)
    GUF.SetArtisticBadgeChrome(badge, false)
    badge.text:SetText("")
    badge.iconSize = size
    GUF.FitArtisticIndicatorIcon(badge, 1)
    badge.icon:SetTexture(file, "CLAMP", "CLAMP", "LINEAR")
    badge.icon:SetTexCoord(unpack(coords or { 0, 1, 0, 1 }))
    badge.icon:Show(); badge:Show()
    badge.previewUsed = true
    return badge
end

function GUF.UpdateAutomaticIndicators(entry)
    local state = entry.artisticLayout
    state.automaticWriting = true
    for kind, source in pairs(GUF.AutomaticIndicatorSources(entry)) do
        local icon = iconRegion(source)
        local badge = state.badges[kind]
        if not state.hidden[source] then
            -- Late native allocations wait for the ordinary safe apply pass.
            GUF.pending = true
        elseif icon and icon.GetTexture then
            GUF.PositionAutomaticBadge(entry, kind)
            if GUF.CopyBlizzardTexture(icon, badge.icon) then
                local alpha = GUF.alphaStates and GUF.alphaStates[source]
                if alpha then badge:SetAlpha(alpha.native) else badge:SetAlpha(source:GetAlpha()) end
                if icon ~= source then
                    local iconAlpha = GUF.alphaStates and GUF.alphaStates[icon]
                    if iconAlpha then badge.icon:SetAlpha(iconAlpha.native) else badge.icon:SetAlpha(icon:GetAlpha()) end
                else badge.icon:SetAlpha(1) end
                -- Alpha suppression doesn't alter native show/hide state.
                -- Native timers and per-unit controller visibility stay final.
                badge:SetShown(icon:IsVisible())
            else badge:Hide() end
        end
    end
    state.automaticWriting = nil
end
