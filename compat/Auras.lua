local _, GUF = ...
local Client = GUF.Client
local auraContainerAddon = "Blizzard_AuraContainer"

-- Module loading, instance readiness and API capability are separate results.
-- Do not cache failed/absent lookups: native modules and objects can arrive late.
-- None of these results grants permission to inspect aura data or mutate a host.
function Client.LoadAuraContainerModule()
    if not C_AddOns or not C_AddOns.LoadAddOn then return false, "unavailable" end
    local ok, loaded = pcall(C_AddOns.LoadAddOn, auraContainerAddon)
    if not ok then return false, "failed" end
    return loaded and true or false, loaded and "loaded" or "not-ready"
end

function Client.IsAuraContainerAddon(name)
    return name == auraContainerAddon
end

function Client.CreateAuraContainer(parent)
    -- Called from the existing guarded apply path. Keep actual construction as
    -- the readiness check; loader availability alone cannot prove template support.
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok then return nil, "failed" end
    if not container or not container.AddAuraGroup then return nil, "not-ready" end
    return container, "ready"
end

function Client.NativeAuraOwners()
    -- Focus is a native visibility preference only; it gains no managed entry.
    return { target = TargetFrame, focus = FocusFrame }
end

function Client.ResolveAuraContainer(owner)
    if not owner then return nil, "not-ready" end
    if owner.IsForbidden and owner:IsForbidden() then return nil, "restricted" end
    if not owner.GetAuraContainer then return nil, "unavailable" end
    local container = owner:GetAuraContainer()
    if not container then return nil, "not-ready" end
    if container.IsForbidden and container:IsForbidden() then return nil, "restricted" end
    return container, "ready"
end

function Client.GetPrivateAuraAPI()
    local api = C_UnitAuras
    -- Never acquire native anchors without their matching release capability.
    -- Capture function references so an acquired host can clean up its anchors
    -- even if the public namespace changes before that host is released.
    if not api or type(api.AddPrivateAuraAnchor) ~= "function"
        or type(api.RemovePrivateAuraAnchor) ~= "function" then return nil, "unavailable" end
    return { addAnchor = api.AddPrivateAuraAnchor, removeAnchor = api.RemovePrivateAuraAnchor }, "available"
end
