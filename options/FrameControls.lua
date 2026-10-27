local _, GUF = ...
local UI = GUF.OptionsUI

function UI.BuildFrameSize(builder, unit)
    builder.Group()
    local items = UI.CompactColumns(builder, "sizeControls", 68)
    items[1]:Show()
    local minimum, maximum, step = GUF.FrameScaleLimits(unit)
    UI.CompactSlider(builder, items[1], "Scale", { "scale" }, minimum, maximum, step, true)
    local window, profile = GUF.options, GUF.db
    local generation, column = window.buildGeneration, items[1]
    window.refreshFrameScale = function(changedUnit)
        if changedUnit == unit and GUF.db == profile and window.buildGeneration == generation and column:IsShown() then
            column.refreshSetting()
        end
    end
    for i = 2, 3 do
        local column = items[i]
        if column.field then
            column.field:SetScript("OnEditFocusLost", nil)
            column.field:ClearFocus()
        end
        column:Hide()
    end
end

function GUF.RefreshOptionsFrameScale(unit)
    local window = GUF.options
    if window and window:IsShown() and window.refreshFrameScale then window.refreshFrameScale(unit) end
end

function UI.BuildBarSize(builder, unit, kind)
    if not UI.LayoutCapabilities(unit).artwork then return end
    if unit ~= "player" and unit ~= "target" then return end
    local columns = UI.CompactColumns(builder, "barDimensions", 70, 2)
    local minimum, maximum, heightMinimum, heightMaximum = GUF.ArtisticBarLimits(unit, kind)
    UI.CompactSlider(builder, columns[1], "Shared bar width", { "bars", "width" }, minimum, maximum, 1)
    local heightKeys = kind == "name" and { "artistic", "playerGeometry", "header" }
        or { "bars", kind .. "Size", "height" }
    UI.CompactSlider(builder, columns[2], "Bar height", heightKeys, heightMinimum, heightMaximum, 1)
end

function UI.BuildManualPosition(builder, unit)
    builder.Group("Manual position")
    local host = builder.Row("", 36, true)
    host.label:Hide()
    host.moveFrames = host.moveFrames or UI.Button(host, "Unlock Frames", 190)
    GUF.options.frameMoverButton = host.moveFrames
    host.moveFrames:SetPoint("LEFT")
    host.moveFrames:SetEnabled(not GUF.Restricted() and not GUF.editing)
    host.moveFrames:SetText(GUF.frameMoversUnlocked and "Lock Frames" or "Unlock Frames")
    host.moveFrames:SetScript("OnClick", function()
        GUF.SetMovers(not GUF.frameMoversUnlocked)
    end)
    host.moveFrames:Show()
    UI.Tooltip(host.moveFrames, "Unlock / Lock Frames", "Unlock the actual frames to drag them to new screen positions. Click again, right-click a mover or close this window to lock them. The options preview is controlled only by settings.")
    local items = UI.CompactColumns(builder, "anchorControls", 60)
    for i, spec in ipairs({ { "Point", "point", UI.pointChoices },
        { "Anchor to", "anchorTo", function() return GUF.AnchorChoices(unit) end },
        { "Relative point", "relativePoint", UI.pointChoices } }) do
        local column, keys = items[i], { "position", spec[2] }
        column.caption:ClearAllPoints()
        column.caption:SetPoint("TOPLEFT")
        column.caption:SetText(spec[1])
        column.dropdown = UI.Dropdown(column, spec[3], function() return builder.Read(keys) end,
            function(value) builder.Change(keys, value) end, column.dropdown)
        column.dropdown:ClearAllPoints()
        column.dropdown:SetPoint("TOPLEFT", 0, -18)
        column.dropdown:SetPoint("TOPRIGHT", 0, -18)
        UI.SettingHelp(column.dropdown, spec[1], keys)
    end
    items = UI.CompactColumns(builder, "offsetControls", 54)
    items[3]:Hide()
    for i, key in ipairs({ "x", "y" }) do
        local column, keys = items[i], { "position", key }
        column.caption:ClearAllPoints()
        column.caption:SetPoint("TOPLEFT")
        column.caption:SetText(i == 1 and "X Offset" or "Y Offset")
        column.field = column.field or CreateFrame("EditBox", nil, column, "InputBoxTemplate")
        local field = column.field
        field:SetPoint("TOPLEFT", 5, -24)
        field:SetPoint("TOPRIGHT", 0, -24)
        field:SetHeight(22)
        field:SetAutoFocus(false)
        field:SetMaxLetters(24)
        field:SetJustifyH("CENTER")
        local initialText
        local function restore()
            initialText = string.format("%.2f", builder.Read(keys)):gsub("%.?0+$", "")
            field:SetText(initialText)
        end
        local function commit(self)
            if self:GetText() == initialText then return end
            local value = tonumber(self:GetText())
            if not value or value ~= value or math.abs(value) == math.huge then
                GUF.Print("Enter a numeric offset.")
            elseif math.abs(value - builder.Read(keys)) > .000001 then
                builder.Change(keys, value)
            end
            restore()
        end
        restore()
        builder.BindEdit(field, commit, restore)
    end
end
