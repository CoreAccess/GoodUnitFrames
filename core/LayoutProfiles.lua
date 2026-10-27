local _, GUF = ...

function GUF.GetLayoutDefaults(style)
    local definition = GUF.Layouts.Get(style)
    return definition and definition.defaults
end

local function availableLayout(style)
    if GUF.Layouts.IsAvailable(style) then return GUF.GetLayoutDefaults(style) end
end

function GUF.GetRequestedLayout()
    local request = GUF.layoutRequest
    if request and request.profile == GUF.db then return request.style end
end

function GUF.SelectLayout(style)
    if not availableLayout(style) then return end
    local profile = GUF.db
    if not profile then return end
    if profile.general.frameStyle == style then
        -- Selecting the applied layout cancels a queued switch. Other pending
        -- settings/readiness work still belongs to the ordinary apply path.
        if not GUF.layoutRequest then return end
        GUF.layoutRequest = nil
    else
        -- Keep active tables/style intact while combat, Edit Mode or geometry
        -- blocks apply. Old callbacks must continue to see their own layout.
        GUF.layoutRequest = { profile = profile, style = style }
    end
    GUF.RequestApply(nil, nil, "layout-selection")
end

-- Called by RequestApply after its structural/Edit Mode synchronization gates.
-- Requests belong to one profile and coalesce to the latest user selection.
-- This commits settings; native per-region restoration retains its own state.
function GUF.CommitLayoutRequest()
    local request = GUF.layoutRequest
    if not request then return false end
    local profile = GUF.db
    if request.profile ~= profile then
        GUF.layoutRequest = nil
        return false, "discarded"
    end
    if GUF.editing or GUF.Restricted() then return false, "deferred" end
    local style = request.style
    local defaults = availableLayout(style)
    local current = profile.general.frameStyle
    if not defaults or current == style then
        GUF.layoutRequest = nil
        return false, "discarded"
    end
    -- Each account profile remembers the settings for each style. The active
    -- tables remain authoritative while controls edit them; snapshot on exit.
    if type(profile.layouts) ~= "table" then profile.layouts = {} end
    profile.layouts[current] = GUF.Settings.CaptureLayout(profile)
    local saved = GUF.Settings.GetLayout(profile, style)
    profile.frames, profile.threat = GUF.Copy(saved.frames), GUF.Copy(saved.threat)
    profile.hideBlizzard = GUF.Copy(saved.hideBlizzard)
    profile.general.frameStyle = style
    GUF.layoutRequest = nil
    return true, "committed"
end
