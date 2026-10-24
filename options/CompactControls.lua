local _, GUF = ...
local UI = GUF.OptionsUI

-- Compact columns, with captions above controls, as in Dino's Frame page.
function UI.CompactColumns(builder, key, height, count)
    count = count or 3
    local row = builder.Row("", height, true)
    row.label:Hide()
    local host = row[key]
    if not host then
        host = CreateFrame("Frame", nil, row)
        row[key] = host
        host:SetAllPoints(row)
        host.columns = {}
        for i = 1, count do
            local column = CreateFrame("Frame", nil, host)
            host.columns[i] = column
            column.caption = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            column.caption:SetFont(GUF.Font("Default"), 14, "")
        end
        local function layout(self)
            local width = self:GetWidth() / count
            for i, column in ipairs(self.columns) do
                column:ClearAllPoints()
                column:SetPoint("TOPLEFT", (i - 1) * width, 0)
                column:SetSize(math.max(1, width - 10), height)
            end
        end
        host:SetScript("OnSizeChanged", layout)
        layout(host)
    end
    host:Show()
    return host.columns
end

local function valueField(column)
    local field = CreateFrame("EditBox", nil, column, "BackdropTemplate")
    field:SetSize(76, 20)
    field:SetPoint("TOP", 0, -40)
    field:SetFont(GUF.Font("Default"), 12, "")
    field:SetJustifyH("CENTER")
    field:SetAutoFocus(false)
    field:SetMaxLetters(12)
    field:SetTextInsets(2, 2, 0, 0)
    field:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    field:SetBackdropColor(0, 0, 0, .35)
    field:SetBackdropBorderColor(.3, .3, .3, 1)
    return field
end

function UI.CompactSlider(builder, column, label, keys, minimum, maximum, step, percent, softMaximum, inputLimits)
    local inputMinimum = inputLimits and inputLimits[1] or minimum
    local inputMaximum = inputLimits and inputLimits[2] or maximum
    column.caption:ClearAllPoints()
    column.caption:SetPoint("TOP")
    column.caption:SetText(label)
    if not column.slider then
        column.slider = CreateFrame("Slider", nil, column, "OptionsSliderTemplate")
        column.slider:SetPoint("TOPLEFT", 5, -18)
        column.slider:SetPoint("TOPRIGHT", -5, -18)
        column.slider:SetHeight(18)
        column.slider:SetOrientation("HORIZONTAL")
        column.slider:EnableMouseWheel(true)
        column.slider.Text:Hide()
        column.field = valueField(column)
    end
    local slider, field = column.slider, column.field
    local function display(value)
        return percent and string.format("%.0f%%", value * 100) or string.format("%.0f", value)
    end
    local function refresh(value)
        -- Height/width have Dino's soft limits: typed values can extend the track.
        slider:SetScript("OnValueChanged", nil)
        local lower, upper = math.min(minimum, value), math.max(maximum, value)
        slider:SetMinMaxValues(lower, upper)
        slider.Low:SetText(display(lower))
        slider.High:SetText(display(upper))
        slider:SetValue(value)
        field:SetText(display(value))
    end
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local function onValueChanged(_, value)
        local rounded = math.floor(value / step + .5) * step
        field:SetText(display(rounded))
        if math.abs(builder.Read(keys) - rounded) > step / 10 then builder.Change(keys, rounded) end
    end
    refresh(builder.Read(keys))
    slider:SetScript("OnValueChanged", onValueChanged)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
    local function restore()
        refresh(builder.Read(keys))
        slider:SetScript("OnValueChanged", onValueChanged)
    end
    local function commit(self)
        if self:GetText() == display(builder.Read(keys)) then return end
        local value = tonumber(self:GetText():match("^%s*(.-)%%?%s*$"))
        if value and percent then value = value / 100 end
        if not value or value ~= value or value == math.huge or value < inputMinimum or ((percent or not softMaximum) and value > inputMaximum) then
            GUF.Print("Enter a value from " .. display(inputMinimum) .. (softMaximum and " upward." or " to " .. display(inputMaximum) .. "."))
            restore()
            return
        end
        value = math.floor(value / step + .5) * step
        builder.Change(keys, value)
        restore()
    end
    field:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
    field:SetScript("OnEditFocusLost", commit)
    field:SetScript("OnEscapePressed", function(self) restore(); self:ClearFocus() end)
    -- Native Edit Mode updates reuse this control without rebuilding the page
    -- or leaving an old profile/unit callback attached to a cached column.
    column.refreshSetting = function()
        if not field:HasFocus() then restore() end
    end
    UI.SettingHelp(slider, label, keys); UI.SettingHelp(field, label, keys)
end

UI.pointChoices = { { "TOPLEFT", "Top Left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top Right" },
    { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" },
    { "BOTTOMLEFT", "Bottom Left" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom Right" } }
