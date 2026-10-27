local _, GUF = ...

local nativeKeys = {
    ["Interface\\GroupFrame\\UI-Group-LeaderIcon"] = "leader",
    ["Interface\\GroupFrame\\UI-Group-AssistantIcon"] = "assistant",
    ["Interface\\GroupFrame\\UI-Group-MasterLooter"] = "loot",
    ["Interface\\TargetingFrame\\UI-PVP-Alliance"] = "pvp-alliance",
    ["Interface\\TargetingFrame\\UI-PVP-Horde"] = "pvp-horde",
    ["Interface\\TargetingFrame\\UI-PVP-FFA"] = "pvp-ffa",
}

function GUF.IndicatorArtworkKey(file, coords)
    if file == "Interface\\CharacterFrame\\UI-StateIcon" then
        return coords and coords[1] == 0 and "resting" or "combat"
    end
    return nativeKeys[file]
end

function GUF.ApplyIndicatorArtwork(frame, key)
    local art = key and GUF.indicatorArtwork and GUF.indicatorArtwork[key]
    if not art or not frame.iconSize then return false end
    local effective = frame:GetEffectiveScale()
    local pixels = GUF.Secret(effective) and math.huge or frame.iconSize * effective / art.span
    local variant = pixels <= 64 and 64 or pixels <= 128 and 128 or pixels <= 256 and 256 or 512
    frame.icon:SetTexture(art.path .. variant, "CLAMP", "CLAMP", "TRILINEAR")
    frame.icon:SetTexCoord(art.left, art.right, art.top, art.bottom)
    frame.goodUnitFramesGlyphAspect = art.aspect
    GUF.FitArtisticIndicatorIcon(frame, art.aspect)
    return true
end

-- Production alpha measurements fit the complete visible glyph inside a round
-- face. The optical pivot and radius are shared artwork data, never live unit
-- measurements or per-class icon offsets. Cards use the same placement helper.
function GUF.ApplySocketIndicatorArtwork(icon, host, key, diameter, x, y)
    local art = GUF.indicatorArtwork[key]
    local fit = art and art.socketFit
    if not fit then return false end
    local canvas = diameter / (2 * fit.radius)
    local effective = host:GetEffectiveScale()
    local pixels = GUF.Secret(effective) and math.huge or canvas * effective
    local variant = pixels <= 64 and 64 or pixels <= 128 and 128 or pixels <= 256 and 256 or 512
    icon:SetTexture(art.path .. variant, "CLAMP", "CLAMP", "TRILINEAR")
    icon:SetTexCoord(art.left, art.right, art.top, art.bottom)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", host, "CENTER", (x or 0) + canvas * ((art.left + art.right) / 2 - fit.x),
        (y or 0) + canvas * (fit.y - (art.top + art.bottom) / 2))
    icon:SetSize(canvas * (art.right - art.left), canvas * (art.bottom - art.top))
    return true
end

local roleKeys = { TANK = "role-tank", HEALER = "role-healer", DAMAGER = "role-damage" }

-- Reuse the measured custom art without changing the native role's geometry.
function GUF.ApplyRoleIndicatorArtwork(icon, role)
    if GUF.Secret(role) then return false end
    local art = GUF.indicatorArtwork[roleKeys[role]]
    if not art then return false end
    local width, height = icon:GetSize()
    local effective = icon.GetEffectiveScale and icon:GetEffectiveScale() or icon:GetParent():GetEffectiveScale()
    if GUF.Secret(width) or GUF.Secret(height) or GUF.Secret(effective) then return false end
    local pixels = math.max(width, height) * effective / art.span
    local variant = pixels <= 64 and 64 or pixels <= 128 and 128 or pixels <= 256 and 256 or 512
    icon:SetTexture(art.path .. variant, "CLAMP", "CLAMP", "TRILINEAR")
    icon:SetTexCoord(art.left, art.right, art.top, art.bottom)
    return true
end

local unpack = unpack or table.unpack

local function nativeRoleMedia(icon)
    local media = { texture = icon:GetTexture(), atlas = icon:GetAtlas(), coords = { icon:GetTexCoord() } }
    if GUF.Secret(media.texture) or GUF.Secret(media.atlas) then return end
    for _, value in ipairs(media.coords) do if GUF.Secret(value) then return end end
    return media
end

local function restoreRoleMedia(state)
    state.writing = true
    local media, icon = state.native, state.icon
    if media.atlas and media.atlas ~= "" then icon:SetAtlas(media.atlas)
    else icon:SetTexture(media.texture, "CLAMP", "CLAMP", "LINEAR") end
    icon:SetTexCoord(unpack(media.coords))
    state.writing, state.owned = nil, nil
end

local function refreshRoleMedia(state)
    if not state.active or GUF.Runtime.Settings("artwork", state.entry).general.frameStyle ~= "blizzard" then return end
    if GUF.editing or GUF.Restricted() then GUF.DeferRuntime("native-readiness"); return end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    state.writing = true
    local applied = GUF.ApplyRoleIndicatorArtwork(state.icon, role)
    state.writing = nil
    if applied then state.owned = true
    elseif state.owned then restoreRoleMedia(state) end
end

function GUF.ReleaseBlizzardRoleArtwork(entry)
    local state = entry.blizzardRoleArtwork
    if not state then return end
    state.active = nil
    if state.owned then restoreRoleMedia(state) end
    entry.blizzardRoleArtwork = nil
end

function GUF.ApplyBlizzardRoleArtwork(entry, region)
    if GUF.editing or GUF.Restricted() then GUF.DeferRuntime("native-readiness"); return end
    local icon = region.GetTexture and region or region.Icon or region.Texture
    if not icon or not icon.GetTexture then return end
    local current = entry.blizzardRoleArtwork
    if current and current.icon ~= icon then GUF.ReleaseBlizzardRoleArtwork(entry); current = nil end
    if not current then
        local media = nativeRoleMedia(icon)
        if not media then GUF.DeferRuntime("native-readiness"); return end
        entry.roleArtworkStates = entry.roleArtworkStates or {}
        current = entry.roleArtworkStates[icon]
        if not current then
            current = { icon = icon, entry = entry }
            entry.roleArtworkStates[icon] = current
        end
        if not current.hooked then
            local state = current
            for _, method in ipairs({ "SetAtlas", "SetTexture", "SetTexCoord" }) do
                GUF.NativeProperties.Hook("IndicatorArtwork:1", icon, method, function(_, ...)
                    if state.writing or not state.active then return end
                    -- Capture each native write before reapplying custom media.
                    -- A UV-only update must not capture our custom file as native.
                    if method == "SetTexCoord" then
                        local coords = { ... }
                        for _, value in ipairs(coords) do if GUF.Secret(value) then GUF.DeferRuntime("native-readiness"); return end end
                        state.native.coords = coords
                    else
                        local media = nativeRoleMedia(icon)
                        if not media then GUF.DeferRuntime("native-readiness"); return end
                        if method == "SetTexture" then media.coords = state.native.coords end
                        state.native = media
                    end
                    refreshRoleMedia(state)
                end)
            end
            current.hooked = true
        end
        current.native, current.active = media, true
        GUF.NativeProperties.Track(icon, "roleMedia", entry, current)
        entry.blizzardRoleArtwork = current
    end
    refreshRoleMedia(current)
end
