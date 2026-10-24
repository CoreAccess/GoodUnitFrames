local _, GUF = ...
local unpack = unpack or table.unpack

-- Preserve native anchors and dimensions instead of rebuilding Blizzard's artwork.
function GUF.TransformRegion(region, settings, enabled)
    if not region or not region.GetNumPoints then return end
    GUF.regionTransforms = GUF.regionTransforms or {}
    local state = GUF.regionTransforms[region]
    local changed = enabled and (settings.layoutPoints ~= nil or settings.scale ~= 1 or settings.x ~= 0 or settings.y ~= 0)
    if not state and not changed then return true end
    if GUF.editing then return end
    if InCombatLockdown() then GUF.pending = true; return end
    if not state then
        local points = GUF.ReadPoints(region)
        if not points then if settings.layoutPoints then GUF.pending = true end; return end
        state = { points = points, width = region:GetWidth(), height = region:GetHeight(), scale = region.GetScale and region:GetScale() }
        GUF.regionTransforms[region] = state
        hooksecurefunc(region, "SetPoint", function()
            if state.writing or GUF.geometryWriting then return end
            local points = GUF.ReadPoints(region)
            if not points then state.pointsReadable = false; return end
            local owner = GUF.sizeOwners and GUF.sizeOwners[region]
            if not (owner and owner.sizeOwned) then
                local geometry = state.settings and state.settings.nativeGeometry
                state.points = geometry and geometry.points or points
            end
            state.pointsReadable = true
            if state.enabled then GUF.TransformRegion(region, state.settings, true) end
        end)
    end
    -- The role's layout anchor is transient, never a replacement native
    -- baseline. CaptureSize keeps native anchors through our guarded writes.
    local geometry = state.settings and state.settings.nativeGeometry or settings.nativeGeometry
    if geometry and geometry.pointsReadable == false then GUF.pending = true; return end
    if geometry then state.points = geometry.points end
    state.settings, state.enabled = settings, changed
    if settings.layoutPoints and not state.layoutHooks then
        state.layoutHooks = true
        for _, method in ipairs({ "ClearAllPoints", "SetAllPoints" }) do
            hooksecurefunc(region, method, function()
                if state.writing or GUF.geometryWriting or not state.enabled or not state.settings.layoutPoints then return end
                GUF.pending = true
            end)
        end
    end
    local resized = changed and settings.scale ~= 1
    local anchors = state.points
    if changed or state.owned then
        local points = GUF.ReadPoints(region)
        if not points then
            state.pointsReadable = false
            if settings.layoutPoints then GUF.pending = true end
            return
        end
        if state.pointsReadable == false then
            state.points = geometry and geometry.points or points
            state.pointsReadable = true
        end
        anchors = changed and settings.layoutPoints or state.points
        -- Validate native geometry before clearing anchors or doing any arithmetic.
        -- Secret coordinates/dimensions must remain controlled by Blizzard.
        for _, point in ipairs(anchors) do
            if GUF.Secret(point[4]) or GUF.Secret(point[5]) then return end
        end
        if resized or state.resized then
            if GUF.Secret(state.scale) then return end
            if not state.scale and (GUF.Secret(state.width) or GUF.Secret(state.height)) then return end
            if region.GetFont then
                state.font = state.font or { region:GetFont() }
                if GUF.Secret(state.font[2]) then return end
            end
        end
    end
    state.writing = true
    if changed or state.owned then
        region:ClearAllPoints()
        for _, point in ipairs(anchors) do
            region:SetPoint(point[1], point[2], point[3], point[4] + (changed and settings.x or 0),
                point[5] + (changed and settings.y or 0))
        end
        if resized or state.resized then
            if state.scale then region:SetScale(state.scale * (resized and settings.scale or 1))
            else region:SetSize(state.width * (resized and settings.scale or 1), state.height * (resized and settings.scale or 1)) end
            if region.GetFont then
                region:SetFont(state.font[1], state.font[2] * (resized and settings.scale or 1), state.font[3])
            end
        end
        state.resized = resized
    end
    state.owned, state.writing = changed, nil
    return true
end

function GUF.ReleaseBlizzardPlayerRole(entry)
    local region = entry.blizzardRole
    if not region then return end
    if GUF.Restricted() or GUF.editing then GUF.pending = true; return end
    if not GUF.TransformRegion(region, GUF.db.frames[entry.unit].indicators.role, false) then
        GUF.pending = true
        return
    end
    GUF.ReleaseBlizzardRoleArtwork(entry)
    GUF.RegionAlpha(region, nil)
    entry.blizzardRole = nil
end

local function playerRole(entry, cfg)
    if entry.unit ~= "player" or GUF.db.general.frameStyle ~= "blizzard" then return end
    local region, portrait = GUF.PlayerRoleRegions(entry)
    if entry.blizzardRole and entry.blizzardRole ~= region then GUF.ReleaseBlizzardPlayerRole(entry) end
    if not region or not portrait then return end
    local settings = cfg.indicators.role
    local transform = { x = settings.x, y = settings.y, scale = settings.scale,
        layoutPoints = GUF.PlayerRolePoints(portrait) }
    for _, saved in ipairs(entry.sizeRegions or {}) do
        if saved.region == region then transform.nativeGeometry = saved; break end
    end
    GUF.TransformRegion(region, transform, true)
    GUF.RegionAlpha(region, cfg.hide.role and 0 or settings.alpha, not cfg.hide.role)
    entry.blizzardRole = region
    GUF.ApplyBlizzardRoleArtwork(entry, region)
end

function GUF.ApplyArtwork(entry)
    local cfg = GUF.db.frames[entry.unit]
    if entry.unit == "player" then
        local resolved = GUF.Resolve("player")
        if resolved then
            entry.regions.resource = resolved.regions.resource
            entry.regions.resting = resolved.regions.resting
        end
    end
    for key, regions in pairs(entry.regions) do
        local nativeOnly = GUF.db.general.frameStyle == "blizzard" and (key == "level" or key == "resource")
        local hidden = cfg.hide[key]
        -- Combo rows are automatic on their class/client-selected unit. An old
        -- Player preference must not hide native fallback when capacity is unknown.
        if key == "resource" and GUF.UsesComboPoints() then hidden = false end
        for _, region in pairs(regions) do
            local settings = cfg.indicators[key]
            local alpha = settings and settings.alpha
            -- Multiply native opacity so inactive combat/resting artwork stays invisible.
            if nativeOnly then GUF.RegionAlpha(region, nil)
            elseif key == "resource" and GUF.OwnsNativeComboPoints(region) then GUF.RegionAlpha(region, 0)
            else GUF.RegionAlpha(region, hidden and 0 or alpha, not hidden) end
            if settings then
                if nativeOnly and key == "level" and region.GetFont then
                    -- Move only the numeric label; its native medallion/skull
                    -- and Blizzard's level/visibility controller stay in place.
                    local text = cfg.text.level
                    GUF.TransformRegion(region, { scale = 1, x = text.x, y = text.y }, not text.nativeStyle)
                elseif key ~= "resource" or not GUF.ArtisticOwnsResource(entry, region) then
                    GUF.TransformRegion(region, settings, not nativeOnly)
                end
            end
        end
    end
    playerRole(entry, cfg)
end
