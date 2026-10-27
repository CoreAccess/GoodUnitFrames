local _, GUF = ...
local UI = GUF.OptionsUI

UI.RegisterPage("hideBlizzard", "Hide Blizzard", function(builder)
    local introduction = builder.Row("Select the elements you would like to hide", 40, true)
    introduction.label.goodUnitFramesBodySize = 15
    introduction.label:SetFont(GUF.Font("Default"), 15, "")
    local options = GUF.blizzardFrameOptions
    for first = 1, #options, 2 do
        local host = builder.Row("", 42, true)
        host.label:Hide()
        host.cells = host.cells or {}
        for column = 1, 2 do
            local option = options[first + column - 1]
            if option then
                local cell = host.cells[column]
                if not cell then
                    cell = CreateFrame("Frame", nil, host)
                    host.cells[column] = cell
                    cell.check = CreateFrame("CheckButton", nil, cell, "UICheckButtonTemplate")
                    cell.check:SetSize(26, 26)
                    cell.check:SetPoint("LEFT", 0, 0)
                    cell.caption = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    cell.caption:SetFont(GUF.Font("Default"), 14, "")
                    cell.caption:SetTextColor(1, 1, 1)
                    cell.caption:SetJustifyH("LEFT")
                    cell.caption:SetPoint("LEFT", cell.check, "RIGHT", 1, 0)
                    cell.caption:SetPoint("RIGHT", cell, "RIGHT", -8, 0)
                end
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", host, column == 1 and "TOPLEFT" or "TOP", 0, 0)
                cell:SetPoint("BOTTOMRIGHT", host, column == 1 and "BOTTOM" or "BOTTOMRIGHT", 0, 0)
                cell.caption:SetText(option.label)
                cell.check:SetChecked(builder.Read({ option.key }))
                cell.check:SetScript("OnClick", function(self)
                    builder.Change({ option.key }, self:GetChecked() and true or false)
                end)
                UI.Tooltip(cell, option.label, option.tooltip)
                UI.Tooltip(cell.check, option.label, option.tooltip)
                cell:Show()
            end
        end
    end
    local host = builder.Row("", 40, true)
    host.label:Hide()
    host.restore = host.restore or UI.Button(host, "Restore Blizzard frames", 210)
    host.restore:SetPoint("LEFT")
    host.restore:SetEnabled(not GUF.Restricted() and not GUF.editing)
    host.restore:SetScript("OnClick", function()
        for key in pairs(GUF.db.hideBlizzard) do GUF.db.hideBlizzard[key] = false end
        GUF.RequestApply(nil, nil, "visibility-restore"); GUF.BuildOptions()
    end)
    host.restore:Show()
end)
