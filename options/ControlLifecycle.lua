local _, GUF = ...
local UI = GUF.OptionsUI

-- Page leases cover callbacks that outlive their click (menus, color pickers,
-- dialogs) as well as cached widgets. Layout identity matters even when the
-- selected account profile table itself has not changed.
function UI.PageLease(window, content)
    window = window or GUF.options
    return { window = window, content = content, profile = GUF.db,
        layout = GUF.db and GUF.db.general.frameStyle,
        generation = window and window.buildGeneration, session = window and window.controlSession }
end

function UI.IsCurrent(lease)
    local window = lease and lease.window
    return window and window:IsShown() and GUF.db == lease.profile
        and GUF.db.general.frameStyle == lease.layout
        and window.controlSession == lease.session
        and window.buildGeneration == lease.generation
        and (not lease.content or window.content == lease.content and lease.content:IsShown())
end

function UI.Guard(lease, callback)
    return function(...)
        if UI.IsCurrent(lease) then return callback(...) end
    end
end

function UI.BindEditCallbacks(field, lease, commit, restore)
    local cancelling
    field:SetScript("OnEnterPressed", UI.Guard(lease, function(self)
        commit(self)
        -- A commit can rebuild/rebind this very field.
        if UI.IsCurrent(lease) then self:ClearFocus() end
    end))
    field:SetScript("OnEditFocusLost", UI.Guard(lease, function(self)
        if not cancelling then commit(self) end
    end))
    field:SetScript("OnEscapePressed", UI.Guard(lease, function(self)
        cancelling = true
        restore(self)
        self:ClearFocus()
        cancelling = nil
    end))
end

-- Bind after the builder finishes assigning scripts/values. Never hook pooled
-- scripts on each reuse, and never wrap a previous generation's wrapper.
local events = { "OnClick", "OnDoubleClick", "OnValueChanged", "OnMouseWheel",
    "OnMouseDown", "OnMouseUp", "OnEnterPressed", "OnEscapePressed",
    "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged" }
function UI.BindControlTree(frame, lease)
    frame.goodUnitFramesPageLease = lease
    frame.goodUnitFramesCallbacks = frame.goodUnitFramesCallbacks or {}
    for _, event in ipairs(events) do
        if frame:HasScript(event) then
            local callback = frame:GetScript(event)
            local previous = frame.goodUnitFramesCallbacks[event]
            if previous and callback == previous.wrapper then callback = previous.callback end
            if callback then
                local wrapper = function(...)
                    if UI.IsCurrent(lease) and frame:IsShown() then return callback(...) end
                end
                frame.goodUnitFramesCallbacks[event] = { callback = callback, wrapper = wrapper }
                frame:SetScript(event, wrapper)
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do UI.BindControlTree(child, lease) end
end

function UI.ParentLease(frame)
    while frame do
        if frame.goodUnitFramesPageLease then return frame.goodUnitFramesPageLease end
        frame = frame:GetParent()
    end
end
