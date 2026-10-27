local _, GUF = ...
local UI = GUF.OptionsUI
local unpack = unpack or table.unpack
local positions = { { "left", "Left text" }, { "center", "Center text" }, { "right", "Right text" } }
local outlines = { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" }, { "MONOCHROME,OUTLINE", "Monochrome outline" } }
local formats = { { "short", "Short form (10k)" }, { "long", "Long form (10,000)" } }
local groupLabels = { health = "Health values", power = "Power values", unit = "Unit information" }
local valueHelp = {
    threat = "How close you are to pulling aggro from this enemy, scaled for your distance. 100% means the enemy targets you.",
    afk = "Shows AFK or DND when the unit has that status, otherwise nothing. The interactive preview uses a sample AFK status.",
}

-- Callback controls belong to the current cached page generation only.
local function guarded(window, callback)
    return UI.Guard(UI.PageLease(window, window.content), callback)
end

local function checklistRow(builder, window, items, selected, toggle, controls)
    local row = builder.Row("", 36, true)
    row.label:Hide()
    row.valueCells = row.valueCells or {}
    for column = 1, 2 do
        local item = items[column]
        local cell = row.valueCells[column]
        if item then
            if not cell then
                cell = CreateFrame("Frame", nil, row)
                row.valueCells[column] = cell
                cell.check = CreateFrame("CheckButton", nil, cell, "UICheckButtonTemplate")
                cell.check:SetSize(26, 26)
                cell.check:SetPoint("LEFT")
                cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                cell.label:SetFont(GUF.Font("Default"), 13, "")
                cell.label:SetPoint("LEFT", cell.check, "RIGHT", 2, 0)
                cell.label:SetPoint("RIGHT", -8, 0)
                cell.label:SetJustifyH("LEFT")
                cell.label:SetWordWrap(true)
                cell.label:SetMaxLines(2)
                cell:SetScript("OnSizeChanged", function(self, width)
                    if not GUF.Secret(width) then self.check:SetHitRectInsets(0, -math.max(0, width - 28), 0, 0) end
                end)
            end
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", row, column == 1 and "TOPLEFT" or "TOP", 0, 0)
            cell:SetPoint("BOTTOMRIGHT", row, column == 1 and "BOTTOM" or "BOTTOMRIGHT", 0, 0)
            cell.label:SetText(item[2]); UI.Ink(cell.label)
            cell.check:SetChecked(selected[item[1]] == true)
            local key = item[1]
            controls[key] = cell.check
            UI.Tooltip(cell.check, item[2], valueHelp[key] or "Include this value in the selected text position.")
            cell.check:SetScript("OnClick", guarded(window, function(self) toggle(key, self:GetChecked() and true or false) end))
            cell:Show()
        elseif cell then cell:Hide() end
    end
end

function UI.BarTextEditor(builder, unit, kind, window)
    window.barTextPosition = window.barTextPosition or {}
    local side = window.barTextPosition[kind] or "left"
    local base = { "text", kind, "fields", side }
    local function keys(key)
        local result = GUF.Copy(base); result[#result + 1] = key; return result
    end
    local function field() return GUF.db.frames[unit].text[kind].fields[side] end
    builder.BeginFixedHeader()
    local row = builder.Row("", 42, true)
    row.label:Hide(); row.positionTabs = row.positionTabs or {}
    local previous
    for _, position in ipairs(positions) do
        local key, label = position[1], position[2]
        local button = row.positionTabs[key]
        if not button then
            button = CreateFrame("Button", nil, row); row.positionTabs[key] = button
            button:SetSize(112, 32)
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.label:SetPoint("CENTER"); button.label:SetFont(GUF.Font("Default"), 13, "")
            button.label:SetText(label); UI.SkinTab(button)
        end
        button:ClearAllPoints()
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else button:SetPoint("TOPLEFT", 0, 0) end
        UI.SelectTab(button, side == key)
        button:SetScript("OnClick", guarded(window, function()
            window.barTextPosition[kind] = key; GUF.BuildOptions()
        end))
        button:Show(); previous = button
    end

    local controls = {}
    local layout = builder.Row("Text layout")
    local input = layout.layoutInput or CreateFrame("EditBox", nil, layout, "InputBoxTemplate")
    layout.layoutInput = input
    input:SetScript("OnTextChanged", nil)
    input:SetAutoFocus(false); input:SetHeight(24); input:SetJustifyH("LEFT")
    -- The label ends 15 units before the shared dropdown control column.
    input:ClearAllPoints(); input:SetPoint("LEFT", layout.label, "RIGHT", 15, 0); input:SetPoint("RIGHT", -5, 0)
    local initial = GUF.BarTextLayout(field())
    input:SetMaxLetters(math.max(1024, #initial)); input:SetText(initial)
    UI.SkinEdit(input); input:SetTextColor(.65, .85, .60); input:Show()
    -- Match the dropdown's horizontal artwork outset, retaining input height.
    local border = input.goodUnitFramesBorder
    border:ClearAllPoints(); border:SetPoint("TOPLEFT", input, "TOPLEFT", -1, 3)
    border:SetPoint("BOTTOMRIGHT", input, "BOTTOMRIGHT", 1, -3)
    local original, edited
    input:SetScript("OnEditFocusGained", guarded(window, function()
        original, edited = GUF.Copy(field()), false
    end))
    input:SetScript("OnTextChanged", guarded(window, function(self, userInput)
        if not userInput then return end
        if not original then original = GUF.Copy(field()) end
        local value = GUF.Copy(field())
        value.parts = GUF.ParseBarTextLayout(self:GetText(), original)
        value.manualLayout, value.hidden = true, false
        edited = true
        -- Apply immediately without rebuilding the focused input. The actual
        -- preview renders values, while the editor always keeps stable tags.
        builder.Change(base, value, true)
        local checked = GUF.BarTextSelection(field())
        for key, control in pairs(controls) do control:SetChecked(checked[key] == true) end
    end))
    input:SetScript("OnEditFocusLost", guarded(window, function()
        original = nil
        if edited then edited = false; GUF.BuildOptions() end
    end))
    input:SetScript("OnEnterPressed", guarded(window, function(self) self:ClearFocus() end))
    input:SetScript("OnEscapePressed", guarded(window, function(self)
        if not original or not edited then self:ClearFocus(); return end
        local value = GUF.Copy(field())
        value.parts, value.manualLayout, value.hidden = GUF.Copy(original.parts), original.manualLayout, original.hidden
        original, edited = nil, false
        self:SetScript("OnEditFocusLost", nil); self:ClearFocus()
        builder.Change(base, value)
    end))
    UI.Tooltip(input, "Text layout", "Checkboxes insert value tags such as [Current health] and [Level]. Add spaces, words or brackets around them, for example [Current health] ([Level]). The interactive preview shows the result as you type. Unknown or unfinished tags are plain text. Enter finishes editing; Escape restores the layout from before editing.")
    builder.Select("Format", formats, unpack(keys("numberFormat")))
    builder.Slider("Decimal places", 0, 2, 1, false, unpack(keys("decimals")))
    builder.EndFixedHeader()

    local selected = GUF.BarTextSelection(field())
    local function toggle(key, checked)
        local value = GUF.Copy(field())
        local selection = GUF.BarTextSelection(value)
        selection[key] = checked or nil
        value.parts, value.hidden = GUF.ChecklistBarParts(selection, kind, value), false
        builder.Change(base, value)
    end
    for _, group in ipairs(GUF.BarTextValueGroups(kind)) do
        builder.Group(groupLabels[group])
        local pair = {}
        for _, item in ipairs(GUF.barTextValues) do
            if item[3] == group then
                pair[#pair + 1] = item
                if #pair == 2 then checklistRow(builder, window, pair, selected, toggle, controls); pair = {} end
            end
        end
        if #pair > 0 then checklistRow(builder, window, pair, selected, toggle, controls) end
    end

    builder.Group("Position")
    builder.Slider("X offset", -200, 200, 1, false, unpack(keys("x")))
    builder.Slider("Y offset", -200, 200, 1, false, unpack(keys("y")))
    builder.Group("Appearance")
    builder.Slider("Font size", 6, 40, 1, false, unpack(keys("size")))
    builder.Select("Font", UI.FontChoices, unpack(keys("font")))
    builder.Select("Font outline", outlines, unpack(keys("outline")))
    builder.ColorSwatch("Text color", unpack(keys("color")))
end
