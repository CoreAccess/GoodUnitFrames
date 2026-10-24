local _, GUF = ...
local UI = GUF.OptionsUI
GUF.profileDraft = { name = "", source = "", deleteName = "", useDefaults = true }

local confirmation
function UI.ConfirmProfileAction(message, action)
    if not confirmation then
        confirmation = CreateFrame("Frame", "GoodUnitFramesConfirmation", GUF.options, "BackdropTemplate")
        GUF.options.confirmation = confirmation
        confirmation:SetAllPoints(GUF.options); confirmation:SetFrameStrata("DIALOG")
        confirmation:SetFrameLevel(GUF.options:GetFrameLevel() + 100); confirmation:EnableMouse(true)
        local shade = confirmation:CreateTexture(nil, "BACKGROUND"); shade:SetAllPoints(); shade:SetColorTexture(0, 0, 0, .5)
        local dialog = CreateFrame("Frame", nil, confirmation, "BackdropTemplate")
        dialog:SetSize(420, 200); dialog:SetPoint("CENTER")
        dialog:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24 })
        UI.Parchment(dialog)
        confirmation.message = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        confirmation.message:SetPoint("TOPLEFT", 28, -28); confirmation.message:SetPoint("BOTTOMRIGHT", -28, 72)
        confirmation.message:SetJustifyV("MIDDLE"); UI.Ink(confirmation.message)
        local accept = UI.Button(dialog, "Confirm", 145, function()
            local callback, profile = confirmation.action, confirmation.profile
            confirmation:Hide()
            if GUF.db ~= profile then GUF.Print("The current profile changed. Choose the action again."); return end
            if GUF.Restricted() or GUF.editing then GUF.Print("Finish combat or Edit Mode before applying this action."); return end
            if callback then callback() end
        end)
        accept:SetPoint("BOTTOMLEFT", 45, 28)
        local cancel = UI.Button(dialog, "Cancel", 145, function() confirmation:Hide() end)
        cancel:SetPoint("BOTTOMRIGHT", -45, 28)
        confirmation:SetScript("OnHide", function() confirmation.action = nil end)
        tinsert(UISpecialFrames, "GoodUnitFramesConfirmation")
    end
    confirmation.message:SetText(message); confirmation.action, confirmation.profile = action, GUF.db
    confirmation:Show()
end
local function caption(parent, text, x, y, size)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y); label:SetText(text); label:SetJustifyH("LEFT")
    if size then UI.Heading(label, size) else UI.Ink(label) end
    return label
end

UI.RegisterPage("profiles", "Profiles", function(builder)
    local draft, profiles = GUF.profileDraft, GUF.profileStorage.profiles
    -- Cached picker selections must still refer to eligible inactive profiles.
    if not profiles[draft.source] or draft.source == GUF.profileName then draft.source = "" end
    if not profiles[draft.deleteName] or draft.deleteName == GUF.profileName or draft.deleteName == "Default" then draft.deleteName = "" end
    local row = builder.Row("", 246, true); row.label:Hide()
    row.forms = row.forms or {}
    for i = 1, 2 do
        local form = row.forms[i]
        if not form then
            form = CreateFrame("Frame", nil, row); row.forms[i] = form
            form:SetPoint("TOPLEFT", row, i == 1 and "TOPLEFT" or "TOP", i == 1 and 0 or 18, 0)
            form:SetPoint("BOTTOMRIGHT", row, i == 1 and "BOTTOM" or "BOTTOMRIGHT", -18, 0)
        end
        form:Show()
    end
    local create, copy = row.forms[1], row.forms[2]
    if not create.title then
        create.title = caption(create, "Create profile", 0, 0, 18)
        create.hint = caption(create, "Save your setup under a new name.", 0, -28)
        create.nameLabel = caption(create, "Profile name", 0, -61)
        create.name = CreateFrame("EditBox", nil, create, "InputBoxTemplate")
        create.name:SetAutoFocus(false); create.name:SetMaxLetters(80); create.name:SetPoint("TOPLEFT", 4, -83); create.name:SetPoint("TOPRIGHT", -5, -83); create.name:SetHeight(24)
        create.defaults = CreateFrame("CheckButton", nil, create, "UICheckButtonTemplate")
        create.defaults:SetSize(26, 26); create.defaults:SetPoint("TOPLEFT", 0, -122)
        create.defaultsLabel = caption(create, "Start with default settings", 30, -127)
        create.defaults:SetHitRectInsets(0, -190, 0, 0)
        create.action = UI.Button(create, "Create and select", 190); create.action:SetPoint("TOPLEFT", 0, -170)
        copy.title = caption(copy, "Copy into current profile", 0, 0, 18)
        copy.hint = caption(copy, "Replaces settings in the active profile.", 0, -28)
        copy.sourceLabel = caption(copy, "Copy from", 0, -61)
        copy.action = UI.Button(copy, "Copy profile settings", 190); copy.action:SetPoint("TOPLEFT", 0, -122)
        copy.note = caption(copy, "Create a profile first to keep a separate setup.", 0, -170)
        copy.note:SetPoint("TOPRIGHT", -4, -170)
    end
    create.name:SetText(GUF.profileDraft.name)
    local function commitName(self) GUF.profileDraft.name = self:GetText() end
    create.name:SetScript("OnEnterPressed", function(self) commitName(self); self:ClearFocus() end)
    create.name:SetScript("OnEditFocusLost", commitName)
    create.name:SetScript("OnEscapePressed", function(self) self:SetText(GUF.profileDraft.name); self:ClearFocus() end)
    create.defaults:SetChecked(GUF.profileDraft.useDefaults)
    create.defaults:SetScript("OnClick", function(self) GUF.profileDraft.useDefaults = self:GetChecked() and true or false end)
    create.action:SetScript("OnClick", function()
        commitName(create.name)
        if GUF.CreateProfile(GUF.profileDraft.name, GUF.profileDraft.useDefaults) then
            GUF.profileDraft.name = ""
            GUF.profileDraft.useDefaults = true
            create.defaults:SetChecked(true)
            create.name:SetText(""); create.name:ClearFocus()
        end
    end)
    create.action:SetEnabled(not GUF.Restricted() and not GUF.editing)
    UI.Tooltip(create.name, "Profile name", "Enter a new profile name. Uncheck Start with default settings to copy your current setup.")
    copy.source = UI.Dropdown(copy, function() return GUF.ProfileNames(true) end, function() return GUF.profileDraft.source == "" and "Choose a profile" or GUF.profileDraft.source end,
        function(value) GUF.profileDraft.source = value end, copy.source)
    copy.source:ClearAllPoints(); copy.source:SetPoint("TOPLEFT", 0, -83); copy.source:SetPoint("TOPRIGHT", -5, -83)
    copy.action:SetEnabled(#GUF.ProfileNames(true) > 0 and not GUF.Restricted() and not GUF.editing)
    copy.action:SetScript("OnClick", function()
        local source = GUF.profileDraft.source
        if not GUF.profileStorage.profiles[source] then GUF.Print("Choose a source profile."); return end
        UI.ConfirmProfileAction("Replace settings in " .. GUF.profileName .. " with settings from " .. source .. "?", function() GUF.CopyProfile(source) end)
    end)
    builder.Group("Reset or delete")
    row = builder.Row("", 132, true); row.label:Hide()
    row.reset = row.reset or UI.Button(row, "Reset current profile", 190)
    row.reset:SetPoint("TOPLEFT", 0, -6); row.reset:Show()
    row.reset:SetEnabled(not GUF.Restricted() and not GUF.editing)
    row.reset:SetScript("OnClick", function() UI.ConfirmProfileAction("Reset " .. GUF.profileName .. " to default settings?", GUF.ResetCurrentProfile) end)
    row.resetNote = row.resetNote or caption(row, "Restores defaults for the active profile.", 0, -44)
    local names = {}
    for _, name in ipairs(GUF.ProfileNames(true)) do if name ~= "Default" then names[#names + 1] = name end end
    row.delete = UI.Dropdown(row, names, function() return GUF.profileDraft.deleteName == "" and "Choose an inactive profile" or GUF.profileDraft.deleteName end,
        function(value) GUF.profileDraft.deleteName = value end, row.delete)
    row.delete:ClearAllPoints(); row.delete:SetPoint("TOPLEFT", row, "TOP", 18, -6); row.delete:SetPoint("TOPRIGHT", -23, -6)
    row.deleteAction = row.deleteAction or UI.Button(row, "Delete selected profile", 190)
    row.deleteAction:SetPoint("TOPLEFT", row, "TOP", 18, -44); row.deleteAction:Show()
    row.deleteAction:SetEnabled(#names > 0 and not GUF.Restricted() and not GUF.editing)
    row.deleteAction:SetScript("OnClick", function()
        local name = GUF.profileDraft.deleteName
        if name == "" or name == "Default" or name == GUF.profileName or not GUF.profileStorage.profiles[name] then GUF.Print("Choose an inactive profile to delete."); return end
        UI.ConfirmProfileAction("Delete " .. name .. "?", function() GUF.DeleteProfile(name) end)
    end)
end)
