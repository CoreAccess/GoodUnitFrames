local _, GUF = ...

local function leaseAlpha(region, value, relative, independentRelease)
    return GUF.RegionAlpha(region, value, relative, "NativeCastBar", independentRelease)
end
local unpack = unpack or table.unpack
local entries, pending = {}, {}
local driver = GUF.Runtime.CreateFrame("Frame")
driver.goodUnitFramesOwned = true
driver:Hide()

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function writable(region)
    if GUF.Restricted() then
        local protected = region:IsProtected()
        if GUF.Secret(protected) or protected then GUF.DeferRuntime("native-cast-layer-restricted"); return false end
    end
    return true
end

-- A native cast controller reads its own alpha before starting its finish
-- fade. Hide its artwork, never the controller host, while an owned cast view
-- is active. Owned label/icon layers are excluded from native suppression.
local function suppressCastArtwork(state)
    if state.writing or state.releasePending or (state.bar.IsForbidden and state.bar:IsForbidden()) then return end
    state.writing = true
    local function hide(region)
        if not region or region == state.bar or region.goodUnitFramesOwned or not region.SetAlpha
            or (region.IsForbidden and region:IsForbidden()) then return end
        state.regions[region] = true
        GUF.RegionAlpha(region, 0, false, "NativeCastArtwork")
    end
    hide(state.bar:GetStatusBarTexture())
    for _, region in pairs({ state.bar:GetRegions() }) do hide(region) end
    for _, child in pairs({ state.bar:GetChildren() }) do hide(child) end
    state.writing = nil
end

function GUF.SetNativeCastArtworkHidden(entry, bar, hidden)
    local state = entry.nativeCastArtwork
    -- Reselecting this same owner parks its unfinished release and refreshes
    -- the complete suppression inventory from the current native host.
    if state and hidden and state.bar == bar then state.releasePending = nil end
    if state and (state.bar ~= bar or not hidden) then
        -- Stop refreshes from reacquiring suppression, but retain each cleanup
        -- item until its release actually succeeds. Committed cleanup must not
        -- roll back to hidden if first-time native styling later fails.
        state.releasePending = true
        for region in pairs(state.regions) do
            if GUF.RegionAlpha(region, nil, false, "NativeCastArtwork", true) then state.regions[region] = nil end
        end
        if next(state.regions) then
            GUF.DeferRuntime("native-cast-artwork")
            return "deferred", "native-cast-artwork"
        end
        entry.nativeCastArtwork = nil
        state = nil
    end
    if not hidden or not bar then return "released" end
    if not state then
        state = { bar = bar, regions = {} }
        entry.nativeCastArtwork = state
    end
    suppressCastArtwork(state)
    return "applied"
end

function GUF.RefreshNativeCastArtwork(entry, bar)
    local state = entry.nativeCastArtwork
    -- Refresh only an applied lease; pending layout settings cannot reacquire
    -- the previous owner after handoff. Native casts may create cosmetic children.
    if state and not state.releasePending and (not bar or state.bar == bar) then suppressCastArtwork(state) end
end

local function nativeText(bar)
    local prefix = bar:GetName()
    return bar.Text or bar.TextString or prefix and _G[prefix .. "Text"]
end

local function nativeIcon(bar)
    local prefix = bar:GetName()
    return bar.Icon or bar.icon or prefix and _G[prefix .. "Icon"]
end

local function fontInfo(source)
    if source and source.GetFont then
        local font, size, flags = source:GetFont()
        if not GUF.Secret(font) and type(font) == "string" and number(size) and not GUF.Secret(flags) then return font, size, flags end
    end
    return GUF.Font("Default"), 10, ""
end

function GUF.CastBarDimensions(unit)
    local cfg, entry = GUF.Runtime.Settings("cast", unit).frames[unit].bars.cast, GUF.frames[unit]
    local native = entry and GUF.NativeCastBar(entry)
    local state = entry and entry.nativeCastStyle
    local width, height
    if GUF.Runtime.Settings("cast", entry).general.frameStyle == "blizzard" and native then
        width, height = state and state.width or native:GetWidth(), state and state.height or native:GetHeight()
    elseif entry then
        local host = GUF.Presentation.Role(entry, "castAnchor")
        width, height = host and host:GetWidth(), 16
    end
    if GUF.Runtime.Settings("cast", entry).general.frameStyle == "blizzard" and not native then
        local player = GUF.frames.player
        local reference = player and GUF.NativeCastBar(player)
        local original = player and player.nativeCastStyle
        height = original and original.height or reference and reference:GetHeight() or 10
    end
    return cfg.width > 0 and cfg.width or number(width) and width > 0 and width or 190,
        cfg.height > 0 and cfg.height or number(height) and height > 0 and height or 16
end

local function labelFont(label, font, size, flags)
    local oldFont, oldSize, oldFlags = label:GetFont()
    local changed = GUF.Secret(oldFont) or GUF.Secret(oldSize) or GUF.Secret(oldFlags)
        or oldFont ~= font or oldSize ~= size or oldFlags ~= flags
    if changed then
        local text = label:GetText()
        -- A failed provider font must not leave an empty owned label. Keep the
        -- saved selection so it can be used when the provider is available.
        if label:SetFont(font, size, flags) == false then label:SetFont(GUF.Font("Default"), size, flags) end
        label:SetHeight(size + 4)
        -- Invalidate glyph layout after the font change, including the final
        -- stock specimen pass. Opaque live text goes straight back to SetText.
        label:SetText(""); label:SetText(text)
    else label:SetHeight(size + 4) end
end

-- Used by owned live labels, fallback bars and synthetic specimens alike.
function GUF.LayoutCastLabels(entry, bar, name, time, source)
    local cfg = GUF.Runtime.Settings("cast", entry).frames[entry.unit].bars.cast
    local font, size, flags = fontInfo(source)
    if GUF.Runtime.Settings("cast", entry).general.frameStyle ~= "blizzard" then
        size, flags = GUF.Runtime.Settings("cast", entry).frames[entry.unit].fontSize, GUF.Runtime.Settings("cast", entry).frames[entry.unit].outline
    end
    font = GUF.Font(cfg.font)
    local width = bar:GetWidth()
    if not number(width) or width <= 0 then return end
    time:ClearAllPoints(); time:SetPoint(cfg.time.point, bar, cfg.time.point, cfg.time.x, cfg.time.y)
    labelFont(time, font, math.max(6, size + cfg.time.size), cfg.time.outline or flags)
    time:SetJustifyH(cfg.time.point)
    -- The timer's natural text edge also bounds opposite-side spell names.
    -- The client follows changing/opaque timer glyphs without Lua measuring it.
    time:SetWidth(0); time:SetShown(cfg.time.enabled)
    name:SetWordWrap(false); time:SetWordWrap(false)
    name:SetNonSpaceWrap(false); name:SetMaxLines(1)
    -- Align against the actual bar, not the space remaining beside the timer.
    -- Opposite edge anchors bound long names at the timer; other combinations
    -- retain the bar-wide limit without moving the selected name anchor.
    local inset = cfg.name.point == "LEFT" and 4 or cfg.name.point == "RIGHT" and -4 or 0
    name:ClearAllPoints()
    name:SetPoint(cfg.name.point, bar, cfg.name.point, inset + cfg.name.x, cfg.name.y)
    if cfg.time.enabled and cfg.name.point == "LEFT" and cfg.time.point == "RIGHT" then
        name:SetWidth(0)
        name:SetPoint("RIGHT", time, "LEFT", -4, cfg.name.y - cfg.time.y)
    elseif cfg.time.enabled and cfg.name.point == "RIGHT" and cfg.time.point == "LEFT" then
        name:SetWidth(0)
        name:SetPoint("LEFT", time, "RIGHT", 4, cfg.name.y - cfg.time.y)
    else
        name:SetWidth(math.max(1, width - 8))
    end
    labelFont(name, font, math.max(6, size + cfg.name.size), cfg.name.outline or flags)
    name:SetJustifyH(cfg.name.point); name:SetShown(cfg.name.enabled)
end

function GUF.QueueNativeCastRefresh(entry)
    if entry.nativeCastStyle and entry.nativeCastStyle.writing then return end
    if not GUF.UsesNativeCastBar(entry) and not (entry.nativeCastStyle and entry.nativeCastStyle.active) then return end
    pending[entry] = GUF.Runtime.Binding("cast", entry); driver:Show()
end

local function points(region, saved)
    region:ClearAllPoints()
    for _, point in ipairs(saved) do region:SetPoint(unpack(point)) end
end

local function geometry(entry, state, cfg, cleanup)
    local defer = cleanup and GUF.Runtime.DeferCleanup or GUF.DeferRuntime
    local sized = cfg.width > 0 or cfg.height > 0
    local custom = sized or cfg.position ~= nil
    if GUF.Restricted() or GUF.editing then
        if custom or state.geometryOwned or state.iconOwned or cfg.icon == "LEFT" or cfg.icon == "RIGHT" then defer("native-cast-geometry-restricted") end
        return
    end
    -- ReadPoints returns an empty table for a readable anchorless controller.
    -- It is a valid restore baseline: points() clears anchors before replaying
    -- the list. Only nil means the native anchors cannot safely be captured.
    if not state.points or state.pointsReadable == false then
        if custom or state.geometryOwned or state.iconOwned then defer("native-cast-points") end
        return
    end
    if not number(state.width) or not number(state.height) or state.width <= 0 or state.height <= 0 then
        if custom or state.geometryOwned or state.iconOwned then defer("native-cast-size") end
        return
    end
    if #state.points == 0 and (custom or state.geometryOwned or state.iconOwned) then
        local counts = GUF.Updates.stats.castAnchorless
        counts[entry.unit] = (counts[entry.unit] or 0) + 1
    end
    if custom or state.geometryOwned then
        state.writing = true
        state.geometryOwned = true
        if custom then
            GUF.AnchorCastBar(entry, state.bar, cfg.position)
            state.bar:SetSize(cfg.width > 0 and cfg.width or state.width, cfg.height > 0 and cfg.height or state.height)
        else
            points(state.bar, state.points); state.bar:SetSize(state.width, state.height)
        end
        state.geometryOwned = custom or nil
        state.writing = nil
        if cfg.position then GUF.CacheCastAuraGeometry(entry, state.bar, cfg.width > 0 and cfg.width or state.width,
            cfg.height > 0 and cfg.height or state.height) end
    end
    if state.surfaces and (sized or state.surfaceOwned) then
        local width = sized and cfg.width > 0 and cfg.width or state.width
        local height = sized and cfg.height > 0 and cfg.height or state.height
        state.writing = true
        state.surfaceOwned = true
        for region, original in pairs(state.surfaces) do
            if number(original.width) and number(original.height) then
                -- Keep native border padding and spark width, rather than
                -- multiplying those details along with the complete texture.
                region:SetSize(math.max(1, original.width + (original.spark and 0 or width - state.width)),
                    math.max(1, original.height + height - state.height))
            end
        end
        state.surfaceOwned = sized or nil
        state.writing = nil
    end
    if state.icon and state.iconPoints and not state.displayIcon then
        state.writing = true
        if cfg.icon == "LEFT" or cfg.icon == "RIGHT" then
            state.iconOwned = true
            state.icon:ClearAllPoints()
            state.icon:SetPoint(cfg.icon == "LEFT" and "RIGHT" or "LEFT", state.bar,
                cfg.icon == "LEFT" and "LEFT" or "RIGHT", cfg.icon == "LEFT" and -4 or 4, 0)
            state.iconOwned = true
        elseif state.iconOwned then points(state.icon, state.iconPoints); state.iconOwned = nil end
        state.writing = nil
    end
end

function GUF.ReleaseNativeCastBar(entry)
    local state = entry.nativeCastStyle
    if not state or not (state.active or state.geometryOwned or state.iconOwned or state.surfaceOwned or state.alphaReleasePending) then return "released" end
    if state.geometryOwned or state.iconOwned or state.surfaceOwned then
        geometry(entry, state, { width = 0, height = 0 }, true)
    end
    state.alphaReleasePending = true
    local released = true
    for _, key in ipairs({ "text", "textBorder", "nativeTime", "icon", "bar" }) do
        local region = state[key]
        if region and not leaseAlpha(region, nil, false, true) then released = false end
    end
    state.alphaReleasePending = not released or nil
    if state.displayIcon then state.displayIcon:Hide() end
    state.layer:SetAlpha(0)
    state.active = nil
    entries[entry] = nil
    if state.geometryOwned or state.iconOwned or state.surfaceOwned or state.alphaReleasePending then
        local reason = state.alphaReleasePending and "native-cast-alpha" or "native-cast-geometry"
        GUF.Runtime.DeferCleanup(reason)
        return "restoring", reason
    end
    return "released"
end

local function capture(entry, bar)
    local state = entry.nativeCastStyle
    if state and state.bar == bar and state.created then return state end
    if state and state.created and GUF.ReleaseNativeCastBar(entry) ~= "released" then return end
    state = { bar = bar, width = bar:GetWidth(), height = bar:GetHeight(), points = GUF.ReadPoints(bar),
        text = nativeText(bar), icon = nativeIcon(bar), nativeTime = bar.CastTimeText or bar.TimeText }
    state.pointsReadable = state.points ~= nil
    entry.nativeCastStyle = state
    GUF.NativeProperties.Track(bar, "castGeometry", entry, state)
    state.surfaces = {}
    local prefix = bar:GetName()
    state.textBorder = bar.TextBorder or prefix and _G[prefix .. "TextBorder"]
    local spark = bar.Spark or bar.spark or prefix and _G[prefix .. "Spark"]
    for _, region in pairs({ bar.Border or bar.border or prefix and _G[prefix .. "Border"],
        bar.Background or bar.background or prefix and _G[prefix .. "Background"], spark }) do
        local region = region
        local saved = region.GetNumPoints and GUF.ReadPoints(region)
        if saved and #saved == 1 and region.GetSize then
            local width, height = region:GetSize()
            state.surfaces[region] = { width = width, height = height, spark = region == spark }
            for _, method in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
                local setter = method
                GUF.NativeProperties.Hook("NativeCastBar:1", region, method, function(_, first, last)
                    if state.writing then return end
                    local original = state.surfaces[region]
                    if setter == "SetHeight" then original.height = first
                    elseif setter == "SetWidth" then original.width = first
                    else original.width, original.height = first, last end
                    if state.active then GUF.QueueNativeCastRefresh(entry) end
                end)
            end
        end
    end
    state.layer = GUF.Runtime.CreateFrame("Frame", nil, bar)
    state.layer.goodUnitFramesOwned = true; state.layer:EnableMouse(false); state.layer:SetAllPoints(bar)
    state.layer:SetFrameLevel(bar:GetFrameLevel() + 10)
    if entry.unit == "player" and state.icon then
        -- Native Player looks can hide their icon independently of GUF's
        -- setting. Own its presentation without changing showIcon, look or
        -- any casting scripts. Opaque spell artwork goes straight to SetTexture.
        state.displayIcon = state.layer:CreateTexture(nil, "ARTWORK")
        state.displayIcon.goodUnitFramesOwned = true
        state.displayIcon:SetSize(16, 16)
        state.displayIcon:Hide()
        state.layer.icon = state.displayIcon
        GUF.NativeProperties.Hook("NativeCastBar:2", state.icon, "SetTexture", function(_, texture)
            if state.active then state.displayIcon:SetTexture(texture) end
        end)
    end
    for _, kind in ipairs({ "name", "time" }) do
        state[kind] = state.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        state[kind].goodUnitFramesOwned = true
    end
    for _, method in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
        local setter = method
        GUF.NativeProperties.Hook("NativeCastBar:3", bar, method, function(_, width, height)
            if state.writing then return end
            if setter == "SetHeight" then state.height = width
            elseif setter == "SetWidth" then state.width = width
            else state.width, state.height = width, height end
            if state.active then GUF.QueueNativeCastRefresh(entry) end
        end)
    end
    GUF.NativeProperties.Hook("NativeCastBar:4", bar, "ClearAllPoints", function()
        if state.writing then return end
        state.points, state.pointsReadable = {}, true
        if state.active then GUF.QueueNativeCastRefresh(entry) end
    end)
    GUF.NativeProperties.Hook("NativeCastBar:5", bar, "SetPoint", function(_, point)
        if state.writing then return end
        local saved = GUF.ReadPoints(bar)
        if saved and not GUF.Secret(point) then
            if state.geometryOwned and state.pointsReadable ~= false then
                -- An incremental native anchor update must not capture the
                -- other points currently owned by our position override.
                for _, candidate in ipairs(saved) do
                    if candidate[1] == point then
                        local replaced = false
                        state.points = state.points or {}
                        for i, original in ipairs(state.points) do
                            if original[1] == point then state.points[i] = candidate; replaced = true; break end
                        end
                        if not replaced then state.points[#state.points + 1] = candidate end
                        break
                    end
                end
            elseif not state.geometryOwned then state.points, state.pointsReadable = saved, true end
            -- After an unreadable incremental update, keep cleanup blocked
            -- until a complete readable native anchor reset is observed.
        else state.pointsReadable = false end
        if state.active then GUF.QueueNativeCastRefresh(entry) end
    end)
    GUF.NativeProperties.Hook("NativeCastBar:6", bar, "SetAllPoints", function()
        if state.writing then return end
        local saved = GUF.ReadPoints(bar)
        if saved then state.points, state.pointsReadable = saved, true
        else state.pointsReadable = false end
        if state.active then GUF.QueueNativeCastRefresh(entry) end
    end)
    GUF.NativeProperties.HookScript("NativeCastBar:script:1", bar, "OnSizeChanged", function(_, width, height)
        if state.writing or state.geometryOwned then return end
        state.width, state.height = width, height
        if state.active then GUF.QueueNativeCastRefresh(entry) end
    end)
    if state.text then
        for _, method in ipairs({ "SetFont", "SetFontObject" }) do
            GUF.NativeProperties.Hook("NativeCastBar:7", state.text, method, function() if state.active then GUF.QueueNativeCastRefresh(entry) end end)
        end
    end
    if state.icon then
        state.iconPoints = GUF.ReadPoints(state.icon)
        GUF.NativeProperties.Hook("NativeCastBar:8", state.icon, "SetPoint", function()
            if state.writing then return end
            local saved = GUF.ReadPoints(state.icon)
            if saved then state.iconPoints = saved end
            if state.active then GUF.QueueNativeCastRefresh(entry) end
        end)
    end
    local function wake()
        if state.active then driver:Show() end
    end
    GUF.NativeProperties.HookScript("NativeCastBar:wake:1", bar, "OnShow", wake)
    GUF.NativeProperties.HookScript("NativeCastBar:wake:2", bar, "OnHide", wake)
    GUF.NativeProperties.HookScript("NativeCastBar:wake:3", entry.frame, "OnShow", wake)
    state.created = true
    GUF.Runtime.Constructed()
    return state
end

local function timer(entry, label)
    local unit = entry.frame.unit or entry.unit
    local info, durationAPI = { pcall(UnitCastingInfo, unit) }, UnitCastingDuration
    if not info[1] or (not GUF.Secret(info[2]) and info[2] == nil) then
        info, durationAPI = { pcall(UnitChannelInfo, unit) }, UnitChannelDuration
        if info[1] and not GUF.Secret(info[10]) and info[10] then durationAPI = UnitEmpoweredChannelDuration or durationAPI end
    end
    if not info[1] or (not GUF.Secret(info[2]) and info[2] == nil) then label:SetText(""); return false end
    if durationAPI then
        local ok, duration = pcall(durationAPI, unit)
        if ok and duration then label:SetFormattedText("%.1f", duration:GetRemainingDuration()); return true end
    end
    -- Older clients may expose only public timestamps. Opaque timestamps never
    -- enter subtraction; modern duration objects above render opaque values.
    if number(info[5]) and number(info[6]) then
        label:SetFormattedText("%.1f", math.max(0, info[6] / 1000 - GetTime())); return true
    end
    label:SetText("")
    return false
end

local function update(entry, state)
    local cfg = GUF.Runtime.Settings("cast", entry).frames[entry.unit].bars.cast
    local shown = state.bar:IsShown()
    if GUF.Secret(shown) then return end
    if shown and cfg.enabled then
        if state.text then state.name:SetText(state.text:GetText())
        else
            local ok, name = pcall(UnitCastingInfo, entry.frame.unit or entry.unit)
            if not ok or (not GUF.Secret(name) and name == nil) then ok, name = pcall(UnitChannelInfo, entry.frame.unit or entry.unit) end
            if ok then state.name:SetText(name) else state.name:SetText("") end
        end
        if cfg.time.enabled then timer(entry, state.time) end
    end
end

function GUF.ApplyNativeCastBar(entry)
    -- A queued native callback may see requested Blizzard settings before the
    -- guarded layout handoff has released the applied owned cast view.
    if entry.castBar and entry.castBar.managed then return end
    if not GUF.UsesNativeCastBar(entry) then GUF.ReleaseNativeCastBar(entry); return end
    local bar, cfg = GUF.NativeCastBar(entry), GUF.Runtime.Settings("cast", entry).frames[entry.unit].bars.cast
    if not cfg.enabled then
        -- Disabling addon customization restores the native display. Its
        -- explicit Hide Blizzard preference is handled by BlizzardFrames.
        GUF.ReleaseNativeCastBar(entry)
        leaseAlpha(bar, nil)
        return
    end
    if (not entry.nativeCastStyle or entry.nativeCastStyle.bar ~= bar) and (GUF.Restricted() or GUF.editing) then GUF.DeferRuntime("native-cast-capture-restricted"); return end
    local state = capture(entry, bar)
    if not state then return "deferred", "native-cast-release" end
    state.runtimeBinding = GUF.Runtime.Binding("cast", entry)
    state.active = true; entries[entry] = state
    geometry(entry, state, cfg)
    local hidden = (entry.unit == "player" or entry.unit == "pet") and GUF.Runtime.Settings("cast", entry).hideBlizzard.cast
    leaseAlpha(bar, hidden and 0 or nil)
    if state.icon then leaseAlpha(state.icon, (state.displayIcon or cfg.icon == "HIDE") and 0 or nil) end
    if state.displayIcon then state.displayIcon:SetTexture(state.icon:GetTexture()) end
    if state.text then leaseAlpha(state.text, 0) end
    if state.textBorder then leaseAlpha(state.textBorder, 0) end
    if state.nativeTime then leaseAlpha(state.nativeTime, 0) end
    state.layer:SetAlpha(1)
    if writable(state.layer) then
        if state.displayIcon then
            GUF.PositionCastIcon(entry, state.layer, state.icon)
            state.displayIcon:SetShown(cfg.icon ~= "HIDE")
            GUF.CacheCastAuraGeometry(entry, bar, bar:GetWidth(), bar:GetHeight())
        end
        GUF.LayoutCastLabels(entry, bar, state.name, state.time, state.text)
        state.name:SetShown(cfg.name.enabled)
        state.layer:SetShown(cfg.enabled)
    end
    update(entry, state)
    GUF.QueueCastAuraPositions(entry)
    driver:Show()
end

local elapsed = 0
driver:SetScript("OnUpdate", function(_, delta)
    for entry, token in pairs(pending) do
        pending[entry] = nil
        if GUF.Runtime.IsBinding(token, "cast", entry) then GUF.ApplyNativeCastBar(entry) end
    end
    local visible = false
    elapsed = elapsed + delta
    if elapsed >= .05 then
        elapsed = 0
        for entry, state in pairs(entries) do
            if entry.nativeCastStyle == state and state.active and GUF.Runtime.IsBinding(state.runtimeBinding, "cast", entry) then
                local shown = state.bar:IsVisible()
                if GUF.Secret(shown) or shown then
                    visible = true
                    GUF.Runtime.Refresh(entry, "cast", update, entry, state)
                end
            end
        end
    else
        for _, state in pairs(entries) do
            local shown = state.bar:IsVisible()
            if state.active and (GUF.Secret(shown) or shown) then visible = true; break end
        end
    end
    if not visible and not next(pending) then driver:Hide() end
end)
