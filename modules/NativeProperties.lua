local _, GUF = ...
local Properties = {}
GUF.NativeProperties = Properties
local unpack = unpack or table.unpack
local registry = {}
local hooks, scripts, globalHooks = {}, {}, {}

local function install(map, key, owner, method, callback, script, guard)
    local methods = map[owner]
    if not methods then methods = {}; map[owner] = methods end
    local id = key .. ":" .. method
    local cell = methods[id]
    if cell then cell.callback, cell.binding, cell.guard = callback, GUF.Runtime.Current(), guard; return end
    cell = { callback = callback, binding = GUF.Runtime.Current(), guard = guard }
    local function dispatch(...)
        if cell.guard and cell.guard() then return end
        local forbidden = owner.IsForbidden and owner:IsForbidden()
        if GUF.Secret(forbidden) or forbidden then GUF.DeferRuntime("native-forbidden"); return end
        return GUF.Runtime.NativeCallback(cell.binding, cell.callback, ...)
    end
    if script then owner:HookScript(method, dispatch)
    else hooksecurefunc(owner, method, dispatch) end
    methods[id] = cell
end

function Properties.Hook(key, owner, method, callback, guard)
    if callback then install(hooks, key, owner, method, callback, false, guard)
    else
        local cell = globalHooks[key .. ":" .. owner]
        if cell then cell.callback, cell.binding = method, GUF.Runtime.Current(); return end
        cell = { callback = method, binding = GUF.Runtime.Current() }
        hooksecurefunc(owner, function(...) return GUF.Runtime.NativeCallback(cell.binding, cell.callback, ...) end)
        globalHooks[key .. ":" .. owner] = cell
    end
end

function Properties.HookScript(key, owner, script, callback)
    install(scripts, key, owner, script, callback, true)
end

-- Specialized capture records remain authoritative. This inventory connects
-- their physical ownership and writer guards to runtime failure recovery.
function Properties.Track(region, property, owner, state)
    local item = registry[region]
    if not item then item = {}; registry[region] = item end
    local binding = GUF.Runtime.Current()
    item[property] = { owner = owner or binding and binding.owner, state = state }
    return state
end

function Properties.Write(state, fn, ...)
    local previous = state.writing
    state.writing = true
    local ok, err = pcall(fn, ...)
    state.writing = previous
    if not ok then
        if GUF.Secret(err) then error("Native cosmetic write failed.", 0) end
        error(err, 0)
    end
end

local function alphaValue(state)
    if state.override == nil then return state.native end
    if state.relative then
        if GUF.Secret(state.native) then return state.native end
        return state.native * state.override
    end
    return state.override
end

local function combine(state)
    local absolute, relative = nil, 1
    for _, lease in pairs(state.leases) do
        if lease.relative then relative = relative * lease.alpha
        else absolute = absolute and math.min(absolute, lease.alpha) or lease.alpha end
    end
    if absolute ~= nil then state.override, state.relative = absolute * relative, false
    elseif next(state.leases) then state.override, state.relative = relative, true
    else state.override, state.relative = nil, nil end
end

local function writeAlpha(region, state)
    combine(state)
    Properties.Write(state, region.SetAlpha, region, alphaValue(state))
end

-- Each consumer releases only its own cosmetic lease. Absolute hides dominate
-- relative artwork opacity, so one owner cannot uncover another owner's region.
-- Native alpha may be opaque; only the existing supported SetAlpha sink sees it.
function GUF.RegionAlpha(region, alpha, relative, owner, independentRelease)
    if not region or not region.SetAlpha then return end
    owner = owner or "legacy"
    local state = GUF.alphaStates and GUF.alphaStates[region]
    if alpha == nil and (not state or not state.leases[owner]) then return true end
    local forbidden = region.IsForbidden and region:IsForbidden()
    if GUF.Secret(forbidden) or forbidden then
        if independentRelease and alpha == nil then GUF.Runtime.DeferCleanup("alpha-forbidden")
        else GUF.DeferRuntime("alpha-forbidden") end
        return
    end
    GUF.alphaStates = GUF.alphaStates or {}
    if not state then
        state = { native = region:GetAlpha(), leases = {}, leaseVersions = {} }
        GUF.alphaStates[region] = state
        Properties.Track(region, "alpha", "cosmetic-leases", state)
    elseif state.override == nil and alpha ~= nil then
        -- Native animation may have advanced since the previous lease ended.
        state.native = region:GetAlpha()
    end
    if not state.hooked then
        Properties.Hook("alpha", region, "SetAlpha", function(self, native)
            if state.writing then return end
            local forbidden = self.IsForbidden and self:IsForbidden()
            if GUF.Secret(forbidden) or forbidden then GUF.DeferRuntime("alpha-forbidden"); return end
            state.native = native
            if state.override ~= nil then Properties.Write(state, self.SetAlpha, self, alphaValue(state)) end
        end, function() return state.writing end)
        state.hooked = true
    end
    local binding = GUF.Runtime.Current()
    if binding then
        binding.alphaChanges = binding.alphaChanges or {}
        local changes = binding.alphaChanges[region]
        if not changes then changes = {}; binding.alphaChanges[region] = changes end
        if independentRelease and alpha == nil then
            -- Releasing a previous view is independent cleanup. A failure in
            -- the replacement must not undo either completed cleanup or a
            -- retained release duty. Its acquiring owner tracks that duty.
            changes[owner] = nil
        elseif changes[owner] == nil then changes[owner] = state.leases[owner] or false end
    end
    local previous, version = state.leases[owner], state.leaseVersions[owner]
    state.leases[owner] = alpha ~= nil and { alpha = alpha, relative = relative, binding = binding } or nil
    state.leaseVersions[owner] = binding
    if independentRelease and alpha == nil then
        local ok, err = pcall(writeAlpha, region, state)
        if not ok then
            -- A failed setter is not a released lease. Preserve its baseline
            -- and physical duty so the acquiring view can retry restoration.
            state.leases[owner], state.leaseVersions[owner] = previous, version
            combine(state)
            if GUF.Secret(err) then error("Native alpha release failed.", 0) end
            error(err, 0)
        end
    else writeAlpha(region, state) end
    return true
end

local flags = { "writing", "scaleWriting", "positionWriting", "fadingWriting", "sizeWriting", "layoutWriting",
    "nameWriting", "nameColoring", "coloring", "powerColoring", "geometryWriting", "nativeAuraApplying",
    "suppressWriting", "presentationWriting", "powerWriting", "reparenting", "textureWriting", "releasing",
    "resourceWriting", "renderWriting", "nativeHealthTextWriting", "automaticWriting", "barStyleWriting" }

local function writerTables(owner, shallow)
    local result = { GUF }
    if owner then
        result[#result + 1] = owner
        for _, key in ipairs({ "nativeCastStyle", "nativeCastArtwork", "blizzardRoleArtwork", "predictions" }) do
            if owner[key] then result[#result + 1] = owner[key] end
        end
        for _, state in ipairs(GUF.Layouts.WriterStates(owner, shallow)) do result[#result + 1] = state end
        if not shallow then
            for _, key in ipairs({ "textOriginals", "sizeRegions", "barStyles" }) do
                for _, state in pairs(owner[key] or {}) do result[#result + 1] = state end
            end
        end
    end
    if not shallow then
        for _, items in pairs(registry) do
            for _, item in pairs(items) do
                if item.owner == owner then result[#result + 1] = item.state end
            end
        end
    end
    return result
end

function Properties.CaptureWriters(owner, shallow)
    local saved = {}
    for _, state in ipairs(writerTables(owner, shallow)) do
        local values = {}
        for _, flag in ipairs(flags) do values[flag] = state[flag] end
        saved[state] = values
    end
    return saved
end

function Properties.RestoreWriters(saved, owner)
    for _, state in ipairs(writerTables(owner)) do
        local values = saved and saved[state] or {}
        for _, flag in ipairs(flags) do state[flag] = values[flag] end
    end
end

function Properties.Recover(binding, owner)
    for region, changes in pairs(binding.alphaChanges or {}) do
        local state = GUF.alphaStates and GUF.alphaStates[region]
        local forbidden = region.IsForbidden and region:IsForbidden()
        if state and not GUF.Secret(forbidden) and not forbidden then
            local changed = false
            for key, previous in pairs(changes) do
                if state.leaseVersions[key] == binding then
                    state.leases[key] = previous or nil
                    state.leaseVersions[key] = previous and previous.binding or nil
                    changed = true
                end
            end
            if changed then pcall(writeAlpha, region, state) end
        end
    end
    -- Retain native geometry/media records and layout release tickets. Never
    -- guess unreadable points, discard a baseline or force a secure controller.
    if owner and binding.family == "layout" then pcall(GUF.Layouts.RecoverLive, owner, binding) end
    if owner and binding.family == "cast" then
        if owner.castBar then
            owner.castBar.managed = false
            pcall(Properties.HideOwned, owner.castBar)
        end
        if GUF.SetNativeCastArtworkHidden then pcall(GUF.SetNativeCastArtworkHidden, owner, nil, false) end
        if GUF.ReleaseNativeCastBar then pcall(GUF.ReleaseNativeCastBar, owner) end
    end
    if owner and binding.family == "predictions" then
        for _, item in pairs(owner.predictions and owner.predictions.bars or {}) do
            for _, key in ipairs({ "clip", "bar", "fullClip", "fullBar" }) do
                if item[key] then pcall(Properties.HideOwned, item[key]) end
            end
        end
    end
    if owner and binding.family == "combatText" and owner.combatText then pcall(Properties.HideOwned, owner.combatText) end
end

function Properties.HideOwned(region)
    if not region or not region.goodUnitFramesOwned or not region.Hide then return false end
    local forbidden = region.IsForbidden and region:IsForbidden()
    if GUF.Secret(forbidden) or forbidden then GUF.QueueRecovery("owned-hide-forbidden"); return false end
    local protected = GUF.Restricted() and region.IsProtected and region:IsProtected()
    if GUF.Secret(protected) or protected then GUF.QueueRecovery("owned-hide-protected"); return false end
    region:Hide()
    return true
end

function Properties.Count()
    local count = 0
    for _, items in pairs(registry) do for _ in pairs(items) do count = count + 1 end end
    return count
end

-- Preserve native anchors and dimensions instead of rebuilding Blizzard's artwork.
function GUF.TransformRegion(region, settings, enabled)
    if not region or not region.GetNumPoints then return end
    GUF.regionTransforms = GUF.regionTransforms or {}
    local state = GUF.regionTransforms[region]
    local changed = enabled and (settings.layoutPoints ~= nil or settings.scale ~= 1 or settings.x ~= 0 or settings.y ~= 0)
    if not state and not changed then return true end
    if GUF.editing then return end
    if InCombatLockdown() then GUF.DeferRuntime("transform-geometry"); return end
    if not state then
        local points = GUF.ReadPoints(region)
        if not points then if settings.layoutPoints then GUF.DeferRuntime("transform-geometry") end; return end
        state = { points = points, width = region:GetWidth(), height = region:GetHeight(), scale = region.GetScale and region:GetScale() }
        GUF.regionTransforms[region] = state
        Properties.Track(region, "transform", GUF.sizeOwners and GUF.sizeOwners[region], state)
    end
    if not state.hooked then
        Properties.Hook("transform:point", region, "SetPoint", function()
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
        state.hooked = true
    end
    -- The role's layout anchor is transient, never a replacement native
    -- baseline. CaptureSize keeps native anchors through our guarded writes.
    local geometry = state.settings and state.settings.nativeGeometry or settings.nativeGeometry
    if geometry and geometry.pointsReadable == false then GUF.DeferRuntime("transform-geometry"); return end
    if geometry then state.points = geometry.points end
    if settings.layoutPoints and not state.layoutHooks then
        for _, method in ipairs({ "ClearAllPoints", "SetAllPoints" }) do
            Properties.Hook("transform:layout", region, method, function()
                if state.writing or GUF.geometryWriting or not state.enabled or not state.settings.layoutPoints then return end
                GUF.DeferRuntime("transform-geometry")
            end)
        end
        state.layoutHooks = true
    end
    local resized = changed and settings.scale ~= 1
    local anchors = state.points
    if changed or state.owned then
        local points = GUF.ReadPoints(region)
        if not points then
            state.pointsReadable = false
            if settings.layoutPoints then GUF.DeferRuntime("transform-geometry") end
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
    Properties.Write(state, function()
        if changed or state.owned then
            state.owned = true
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
        state.owned, state.enabled, state.settings = changed, changed, settings
    end)
    return true
end

