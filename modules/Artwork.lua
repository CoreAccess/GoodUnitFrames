local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "Artwork")
end
local unpack = unpack or table.unpack

function GUF.ReleaseBlizzardPlayerRole(entry)
    local region = entry.blizzardRole
    if not region then return "released" end
    if GUF.Restricted() or GUF.editing then
        GUF.DeferRuntime("native-readiness")
        return "deferred", "restricted", region
    end
    if not GUF.TransformRegion(region, GUF.Runtime.Settings("artwork", entry).frames[entry.unit].indicators.role, false) then
        GUF.DeferRuntime("native-readiness")
        return "deferred", "role-geometry", region
    end
    GUF.ReleaseBlizzardRoleArtwork(entry)
    leaseAlpha(region, nil)
    entry.blizzardRole = nil
    return "released"
end

local function playerRole(entry, cfg)
    if entry.unit ~= "player" or GUF.Runtime.Settings("artwork", entry).general.frameStyle ~= "blizzard" then return end
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
    leaseAlpha(region, cfg.hide.role and 0 or settings.alpha, not cfg.hide.role)
    entry.blizzardRole = region
    GUF.ApplyBlizzardRoleArtwork(entry, region)
end

function GUF.ApplyArtwork(entry)
    local cfg = GUF.Runtime.Settings("artwork", entry).frames[entry.unit]
    if entry.unit == "player" then
        local resolved = GUF.Resolve("player")
        if resolved then
            entry.regions.resource = resolved.regions.resource
            entry.regions.resting = resolved.regions.resting
        end
    end
    for key, regions in pairs(entry.regions) do
        local nativeOnly = GUF.Runtime.Settings("artwork", entry).general.frameStyle == "blizzard" and (key == "level" or key == "resource")
        local hidden = cfg.hide[key]
        -- Combo rows are automatic on their class/client-selected unit. An old
        -- Player preference must not hide native fallback when capacity is unknown.
        if key == "resource" and GUF.UsesComboPoints() then hidden = false end
        for _, region in pairs(regions) do
            local settings = cfg.indicators[key]
            local alpha = settings and settings.alpha
            -- Multiply native opacity so inactive combat/resting artwork stays invisible.
            if nativeOnly then leaseAlpha(region, nil)
            elseif key == "resource" and GUF.OwnsNativeComboPoints(region) then leaseAlpha(region, 0)
            else leaseAlpha(region, hidden and 0 or alpha, not hidden) end
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
