local _, GUF = ...

-- Shared options layout, page registration, and reusable controls.
GUF.OptionsUI = { pageLabels = {}, pages = {} }
local UI = GUF.OptionsUI
local windowWidth = 895
local windowHeight = 570
local sidebarWidth = 175
local paneLeft = 16 + sidebarWidth + 10
local panePadding = 12
local unitPanePadding = 20
local paneTop = 38
-- Align the active tab's top with the sidebar, allowing its three-unit border overlap.
local unitPaneTop = paneTop + 24 - 3
local scrollBarWidth = 16
local scrollBarGap = panePadding
local contentWidth = windowWidth - paneLeft - 16 - panePadding * 2 - scrollBarWidth - scrollBarGap
local controlOffset = 215
local controlWidth = contentWidth - controlOffset - 5

UI.layout = { windowWidth = windowWidth, windowHeight = windowHeight, sidebarWidth = sidebarWidth, paneLeft = paneLeft,
    contentWidth = contentWidth, controlOffset = controlOffset, controlWidth = controlWidth,
    panePadding = panePadding, unitPanePadding = unitPanePadding, paneTop = paneTop, unitPaneTop = unitPaneTop,
    scrollBarWidth = scrollBarWidth, scrollBarGap = scrollBarGap }
UI.points = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
UI.unitTabs = { "general", "frame", "design", "bars", "auras", "indicators", "text" }

function UI.RegisterPage(key, label, build)
    UI.pageLabels[key] = label
    UI.pages[key] = build
end

function UI.PaneBackdrop(frame, alpha)
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 } })
    frame:SetBackdropColor(.1, .1, .1, alpha or .5)
    frame:SetBackdropBorderColor(.4, .4, .4)
end

function UI.Button(parent, label, width, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control.goodUnitFramesDark = true
    control:SetSize(width or 140, 24)
    control:SetText(label)
    control:SetScript("OnClick", callback)
    return control
end

function UI.Tooltip(control, title, description)
    control:EnableMouse(true)
    if control.SetMotionScriptsWhileDisabled then control:SetMotionScriptsWhileDisabled(true) end
    control.goodUnitFramesTooltipTitle, control.goodUnitFramesTooltipText = title, description
    if control.goodUnitFramesTooltipBound then return end
    control.goodUnitFramesTooltipBound = true
    control:HookScript("OnEnter", function(self)
        local heading, body = self.goodUnitFramesTooltipTitle, self.goodUnitFramesTooltipText
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(heading)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    local function hide(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    control:HookScript("OnLeave", hide)
    control:HookScript("OnHide", hide)
end

function UI.StyleScrollBar(scrollBar)
    UI.SkinScrollBar(scrollBar)
end

local function choices(values)
    local output = {}
    for _, value in ipairs(values) do output[#output + 1] = type(value) == "table" and value or { value, value } end
    return output
end

function UI.Dropdown(parent, values, getValue, setValue, existing)
    local control = existing or CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    UI.SkinDropdown(control)
    control:Show()
    control:SetSize(controlWidth, 24)
    local function refresh()
        local current = getValue()
        local label = tostring(current)
        if values == UI.TextureChoices then
            label = GUF.BarTextureLabel(current)
        end
        for _, entry in ipairs(choices(type(values) == "function" and values() or values)) do
            if entry[1] == current then label = entry[2]; break end
        end
        control:SetDefaultText(label)
        -- Default text alone does not replace a native cached selection label.
        control:Update()
    end
    control:SetupMenu(function(_, root)
        for _, entry in ipairs(choices(type(values) == "function" and values() or values)) do
            local value, label = entry[1], entry[2]
            local option = root:CreateRadio(label, function() return getValue() == value end, function()
                if entry.disabled then return end
                setValue(value)
                refresh()
            end)
            option:SetEnabled(not entry.disabled)
            if entry.tooltip then
                option:SetTooltip(function(tooltip)
                    tooltip:SetText(value)
                    tooltip:AddLine(entry.tooltip, 1, 1, 1, true)
                end)
            end
        end
    end)
    refresh()
    return control
end

function UI.FontChoices()
    local values = { "Default" }
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then for _, name in ipairs(media:List("font")) do values[#values + 1] = name end end
    return values
end

local function appendExternalTextures(values)
    local media = LibStub("LibSharedMedia-3.0")
    for _, name in ipairs(media:List(media.MediaType.STATUSBAR)) do
        local _, provider = GUF.ExternalBarTexture(name)
        if provider then
            values[#values + 1] = { name, GUF.BarTextureLabel(name),
                tooltip = "Requires: " .. provider .. ". Disabling the supplying addon makes this texture unavailable. "
                    .. "The bar uses its default texture until the provider is loaded again; your selection is remembered." }
        end
    end
    return values
end

function UI.TextureChoices()
    return appendExternalTextures(GUF.Copy(GUF.barTextureChoices))
end

local function getPath(root, keys)
    for i = 1, #keys - 1 do root = root[keys[i]] end
    return root, keys[#keys]
end

function UI.SetScroll(window, value)
    local content, scroll = window.content, window.scroll
    if not content then return end
    local range = math.max(0, content:GetHeight() - scroll:GetHeight())
    local offset = math.floor(math.max(0, math.min(range, value)) + .5)
    window.scrollContent:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, offset)
    window.scrollContent:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, offset)
end

function UI.BindScrollBar(window)
    local scrollbar = window.scroll.ScrollBar
    -- Map pointers and the visible thumb from the rail's top, avoiding the
    -- reported inherited drag inversion. Keep Slider values/callbacks/arrows.
    local input = CreateFrame("Frame", nil, scrollbar)
    input.goodUnitFramesOwned = true
    input:SetAllPoints(); input:SetFrameLevel(scrollbar:GetFrameLevel() + 3)
    input:EnableMouse(true); input:EnableMouseWheel(true)
    local handle = CreateFrame("Frame", nil, input)
    handle.goodUnitFramesOwned = true; handle:EnableMouse(false)
    handle:SetSize(12, 32); handle:SetPoint("TOP", scrollbar, "TOP")
    scrollbar.goodUnitFramesScrollInput = input
    scrollbar.goodUnitFramesScrollHandle = handle
    scrollbar:SetOrientation("VERTICAL"); scrollbar:EnableMouse(false)
    local drag
    local function geometry()
        local top, scale, height = scrollbar:GetTop(), scrollbar:GetEffectiveScale(), scrollbar:GetHeight()
        local minimum, maximum = scrollbar:GetMinMaxValues()
        if not top or scale <= 0 or height <= 0 or maximum <= minimum then return end
        local thumb = math.min(height, input.thumbHeight or 32)
        return top, scale, thumb, math.max(0, height - thumb), minimum, maximum
    end
    function input.Refresh()
        local _, _, thumb, travel, minimum, maximum = geometry()
        if not thumb then return end
        local fraction = math.max(0, math.min(1, (scrollbar:GetValue() - minimum) / (maximum - minimum)))
        handle:SetSize(12, thumb)
        handle:ClearAllPoints(); handle:SetPoint("TOP", scrollbar, "TOP", 0, -travel * fraction)
    end
    function input.Stop()
        drag = nil; input:SetScript("OnUpdate", nil)
        scrollbar.goodUnitFramesThumbPressed = nil
        if input.RefreshThumb then input.RefreshThumb() end
    end
    local function updateDrag()
        if not drag then return end
        if drag.content ~= window.content or drag.generation ~= window.buildGeneration or not scrollbar:IsEnabled() then input.Stop(); return end
        local top, scale, thumb, travel, minimum, maximum = geometry()
        if not top or travel <= 0 then input.Stop(); return end
        local _, cursor = GetCursorPosition()
        local fraction = math.max(0, math.min(1, (top - cursor / scale - drag.grab * thumb) / travel))
        scrollbar:SetValue(math.floor(minimum + fraction * (maximum - minimum) + .5))
    end
    input:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not scrollbar:IsEnabled() or window.buildingOptions then return end
        local top, scale, thumb, travel, minimum, maximum = geometry()
        if not top or travel <= 0 then return end
        local _, cursor = GetCursorPosition()
        local distance = top - cursor / scale
        local thumbTop = travel * math.max(0, math.min(1, (scrollbar:GetValue() - minimum) / (maximum - minimum)))
        -- Keep the grab point when pressing the thumb; center it on a track click.
        local grab = distance >= thumbTop and distance <= thumbTop + thumb and (distance - thumbTop) / thumb or .5
        drag = { content = window.content, generation = window.buildGeneration, grab = grab }
        updateDrag()
        if drag then
            input:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then input.Stop(); return end
                updateDrag()
            end)
        end
    end)
    input:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then updateDrag(); input.Stop() end end)
    input:SetScript("OnHide", input.Stop)
    input:SetScript("OnMouseWheel", function(_, delta)
        input.Stop()
        if scrollbar:IsEnabled() then scrollbar:SetValue(scrollbar:GetValue() - delta * 36) end
    end)
    scrollbar:HookScript("OnDisable", input.Stop)
end

function UI.QueueScrollUpdate(window)
    window.scroll:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        UI.UpdateScroll(window)
    end)
end

function UI.UpdateScroll(window)
    if window.updatingScroll or window.buildingOptions then return end
    local scroll, content = window.scroll, window.content
    local scrollBar = scroll and scroll.ScrollBar
    if not scrollBar or not content then return end
    window.updatingScroll = true
    local range = math.max(0, content:GetHeight() - scroll:GetHeight())
    local canScroll = range > 1
    if window.page == "units" then
        -- Short pages use the full padded width; scrolling pages reserve a gutter inside it.
        local gutter = canScroll and (UI.layout.scrollBarWidth + UI.layout.scrollBarGap) or 0
        scroll:SetPoint("BOTTOMRIGHT", window.editor, "BOTTOMRIGHT", -gutter, 0)
        if content.fixedHeader and content.fixedHeader:IsShown() then
            content.fixedHeader:SetPoint("TOPRIGHT", window.editor, "TOPRIGHT", -gutter, 0)
        end
    end
    window.scrollContent:SetHeight(content:GetHeight())
    scrollBar:SetMinMaxValues(0, range)
    if canScroll and scrollBar.goodUnitFramesScrollSkinned then
        local trackHeight = scrollBar:GetHeight()
        if trackHeight > 0 then
            local visibleFraction = scroll:GetHeight() / math.max(1, content:GetHeight())
            local thumbHeight = math.min(trackHeight, math.max(32, trackHeight * visibleFraction))
            scrollBar:GetThumbTexture():SetSize(12, thumbHeight)
            if scrollBar.goodUnitFramesScrollInput then scrollBar.goodUnitFramesScrollInput.thumbHeight = thumbHeight end
        end
    end
    scrollBar:SetShown(canScroll)
    scroll:EnableMouseWheel(canScroll)
    local value = math.max(0, math.min(range, scrollBar:GetValue()))
    scrollBar:SetValue(value)
    if scrollBar.goodUnitFramesScrollInput then scrollBar.goodUnitFramesScrollInput.Refresh() end
    UI.SetScroll(window, value)
    if scrollBar.ScrollUpButton then scrollBar.ScrollUpButton:SetEnabled(canScroll and value > 0) end
    if scrollBar.ScrollDownButton then scrollBar.ScrollDownButton:SetEnabled(canScroll and value < range) end
    window.updatingScroll = nil
end

function UI.CreateBuilder(window, cfg, context)
    local profile, content, generation = GUF.db, window.content, window.buildGeneration
    local rowParent = content
    local unitPage = window.page == "units"
    local flatGroups = true
    local controlOffset = math.min(UI.layout.controlOffset, math.max(130, window.scroll:GetWidth() * .40))
    local count, groupCount, y = 0, 0, flatGroups and 0 or -8
    local activeGroup, groupTop
    -- A page can pin its opening rows outside the clipped scrolling body.
    -- Keep the same row cache and setting callbacks for both areas.
    local function beginFixedHeader(leftInset)
        local header = content.fixedHeader
        if not header then
            header = CreateFrame("Frame", nil, window.editor)
            header.goodUnitFramesOwned = true
            content.fixedHeader = header
            header:EnableMouseWheel(true)
            header:SetScript("OnMouseWheel", function(_, delta)
                if window.content ~= content or window.buildingOptions then return end
                local scrollBar = window.scroll.ScrollBar
                if scrollBar:IsEnabled() then scrollBar:SetValue(scrollBar:GetValue() - delta * 36) end
            end)
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", window.editor, "TOPLEFT", leftInset or UI.layout.categoryWidth, 0)
        header:SetPoint("TOPRIGHT", window.editor, "TOPRIGHT", -24, 0)
        rowParent = header
    end
    local function endFixedHeader()
        local header = content.fixedHeader
        header:SetHeight(math.max(1, -y))
        window.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -12)
        header:Show()
        rowParent, y = content, 0
    end
    local function endGroup(final)
        if not activeGroup then return end
        y = y - (flatGroups and (final and 0 or 6) or 10)
        activeGroup:SetHeight(groupTop - y)
        activeGroup = nil
        if not (flatGroups and final) then y = y - 18 end
    end
    local function group(label, afterTitleGap)
        endGroup()
        groupCount = groupCount + 1
        local host = window.groups[groupCount]
        if not host then
            host = CreateFrame("Frame", nil, window.content, "BackdropTemplate")
            host:SetFrameLevel(window.content:GetFrameLevel())
            host.title = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            UI.Heading(host.title, 18)
            host.rule = UI.Rule(host, -25)
            window.groups[groupCount] = host
        end
        if not flatGroups then y = y - 20 end
        groupTop, activeGroup = y, host
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, y)
        host:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, y)
        host.title:ClearAllPoints()
        if flatGroups then
            host:SetBackdrop(nil)
            host.title:SetPoint("TOPLEFT", 0, 0)
        else
            UI.PaneBackdrop(host)
            host.title:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 12, 3)
        end
        -- A section without a title retains normal spacing between groups,
        -- without repeating the category already selected in navigation.
        host.rule:SetShown(flatGroups and label ~= nil)
        host.title:SetText(label or "")
        host.title:SetShown(label ~= nil)
        UI.Ink(host.title)
        host:Show()
        y = y - (label and (flatGroups and 36 or 10) + (afterTitleGap or 0) or 0)
    end
    local function row(label, height, fullWidth)
        count = count + 1
        local host = window.rows[count]
        if not host then
            host = CreateFrame("Frame", nil, rowParent)
            host.label = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            host.label:SetPoint("LEFT", 0, 0)
            host.label:SetFont(GUF.Font("Default"), 13, "")
            host.label:SetJustifyH("LEFT")
            window.rows[count] = host
        end
        UI.CancelControlFocus(host)
        if host:GetParent() ~= rowParent then host:SetParent(rowParent) end
        for _, child in ipairs({ host:GetChildren() }) do child:Hide() end
        if host.heading then host.heading:Hide() end
        if host.line1 then host.line1:Hide(); host.line2:Hide() end
        local inset = activeGroup and not flatGroups and 12 or 0
        host.label:ClearAllPoints()
        host.label:SetPoint("LEFT", 0, 0)
        -- The bar-text example centers its cached row. Ordinary labels must
        -- recover their normal alignment/wrapping when that row is reused.
        host.label:SetJustifyH("LEFT")
        host.label:SetWordWrap(true)
        host.label:SetMaxLines(0)
        if fullWidth then host.label:SetPoint("RIGHT", -8, 0)
        else host.label:SetWidth(controlOffset - 15) end
        host.label:Show()
        host:SetAlpha(1)
        host:SetHeight(height or 36)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", rowParent, "TOPLEFT", inset, y)
        host:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -inset, y)
        host.label:SetText(label)
        UI.Ink(host.label, fullWidth)
        host:Show()
        y = y - (height or 36)
        return host
    end
    local function read(keys)
        if context and context.Read then return context.Read(keys) end
        local target, key = getPath(cfg, keys)
        return target[key]
    end
    local function change(keys, value, keepControls)
        if GUF.db ~= profile or window.content ~= content or window.buildGeneration ~= generation then return end
        local target, key = getPath(cfg, keys)
        target[key] = value
        if context and context.Write then context.Write(keys, value) end
        GUF.RequestApply()
        if GUF.UpdateOptionsPreview then GUF.UpdateOptionsPreview() end
        if unitPage and window.tab == "auras" and keys[1] == "auras"
            and (keys[#keys] == "enabled" or keys[#keys] == "anchorOn" or keys[#keys] == "anchorMode") then
            GUF.BuildOptions()
        elseif unitPage and window.tab == "bars" and keys[1] == "healthColor" then
            GUF.BuildOptions()
        elseif unitPage and window.tab == "text" and keys[1] == "nameColor" then
            GUF.BuildOptions()
        elseif unitPage and window.tab == "text" and keys[1] == "text" and keys[3] == "fields" and #keys == 4 and not keepControls then
            GUF.BuildOptions()
        end
    end
    local function check(label, ...)
        local keys, host = { ... }, row(label, unitPage and window.tab == "auras" and 28 or nil)
        local control = host.check or CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
        host.check = control
        control:Show()
        control:ClearAllPoints()
        control:SetPoint("LEFT", host, "LEFT", 0, 0)
        host.label:ClearAllPoints(); host.label:SetPoint("LEFT", control, "RIGHT", 4, 0); host.label:SetPoint("RIGHT", -5, 0)
        control:SetSize(26, 26)
        control:SetHitRectInsets(0, -math.max(0, host:GetWidth() - 30), 0, 0)
        control:SetChecked(read(keys))
        control:SetScript("OnClick", function(self)
            change(keys, self:GetChecked() and true or false)
        end)
        UI.SettingHelp(control, label, keys)
        return host, control
    end
    local function slider(label, minimum, maximum, step, percent, ...)
        local keys, host = { ... }, row(label, 58)
        local control = host.valueSlider or CreateFrame("Slider", nil, host, "OptionsSliderTemplate")
        host.valueSlider = control
        control:SetScript("OnValueChanged", nil)
        -- Row controls are reused by other pages. Clear page-specific drag scripts.
        control:SetScript("OnMouseDown", nil)
        control:SetScript("OnMouseUp", nil)
        control:SetScript("OnHide", nil)
        control:ClearAllPoints()
        control:SetPoint("LEFT", host, "LEFT", controlOffset + 5, 0)
        control:SetPoint("RIGHT", host, "RIGHT", -74, 0)
        control:SetHeight(18)
        control:SetOrientation("HORIZONTAL")
        control:SetMinMaxValues(minimum, maximum)
        control:SetValueStep(step)
        control:SetObeyStepOnDrag(true)
        local function display(value)
            return percent and string.format("%.0f%%", value * 100) or string.format("%.2f", value):gsub("%.?0+$", "")
        end
        local field = host.sliderField or CreateFrame("EditBox", nil, host, "InputBoxTemplate")
        host.sliderField = field
        field:SetAutoFocus(false); field:SetMaxLetters(12); field:SetSize(60, 22)
        field:SetJustifyH("CENTER")
        field:ClearAllPoints(); field:SetPoint("RIGHT", -4, 0)
        UI.SkinEdit(field)
        control.Low:SetText(display(minimum))
        control.High:SetText(display(maximum))
        control.Text:SetFont(GUF.Font("Default"), 12, "")
        local value = read(keys)
        control:SetValue(value)
        control.Text:SetText(display(value)); control.Text:Hide()
        field:SetText(display(value))
        if not unitPage then
            control:ClearAllPoints(); control:SetPoint("LEFT", controlOffset + 5, 0); control:SetWidth(420)
            field:ClearAllPoints(); field:SetPoint("LEFT", control, "RIGHT", 12, 0)
        end
        control:SetScript("OnValueChanged", function(self, value)
            local rounded = math.max(minimum, math.min(maximum, math.floor((value - minimum) / step + .5) * step + minimum))
            self.Text:SetText(display(rounded))
            field:SetText(display(rounded))
            if math.abs(read(keys) - rounded) > step / 10 then change(keys, rounded) end
        end)
        local function restore() field:SetText(display(read(keys))) end
        local function commit(self)
            local text = tonumber(self:GetText():match("^%s*(.-)%%?%s*$"))
            if text and percent then text = text / 100 end
            if not text or text ~= text or text < minimum or text > maximum then restore(); return end
            control:SetValue(text)
            restore()
        end
        field:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
        field:SetScript("OnEditFocusLost", commit)
        field:SetScript("OnEscapePressed", function(self) restore(); self:SetScript("OnEditFocusLost", nil); self:ClearFocus(); self:SetScript("OnEditFocusLost", commit) end)
        control:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
        control:EnableMouseWheel(true)
        UI.SkinSlider(control)
        UI.SettingHelp(control, label, keys); UI.SettingHelp(field, label, keys)
        field:Show()
        control:Show()
        return host, control
    end
    local function combatFader()
        check("Enable combat fade", "fading", "enabled")
        slider("Combat opacity", 0, 1, .01, true, "fading", "combat")
        slider("Inactive opacity", 0, 1, .01, true, "fading", "inactive")
        -- Trim only this section's trailing blank space before Copy settings.
        y = y + 4
    end
    local function selectValue(label, values, ...)
        local keys, host = { ... }, row(label)
        local control = UI.Dropdown(host, values, function() return read(keys) end,
            function(value) change(keys, value) end, host.select)
        host.select = control
        control:ClearAllPoints()
        control:SetPoint("LEFT", host, "LEFT", controlOffset, 0)
        control:SetPoint("RIGHT", host, "RIGHT", -5, 0)
        if not unitPage then control:ClearAllPoints(); control:SetPoint("LEFT", controlOffset, 0); control:SetWidth(360) end
        UI.SettingHelp(control, label, keys)
        return host, control
    end
    local function edit(label, minimum, maximum, ...)
        local keys, host = { ... }, row(label)
        local _, key = getPath(cfg, keys)
        local control = host.edit or CreateFrame("EditBox", nil, host, "InputBoxTemplate")
        host.edit = control
        control:Show()
        control:SetHeight(22)
        control:ClearAllPoints()
        control:SetPoint("LEFT", host, "LEFT", controlOffset + 5, 0)
        control:SetPoint("RIGHT", host, "RIGHT", -5, 0)
        if minimum then control:ClearAllPoints(); control:SetPoint("LEFT", controlOffset + 5, 0); control:SetWidth(96) end
        control:SetAutoFocus(false)
        control:SetMaxLetters(minimum and 12 or 4096)
        control:SetJustifyH(minimum and "CENTER" or "LEFT")
        local initialText = tostring(read(keys))
        control:SetText(initialText)
        local function commit(self)
            local value = self:GetText()
            if value == initialText then self:ClearFocus(); return end
            if minimum then
                value = tonumber(value)
                if not value or value ~= value or value < minimum or value > maximum then
                    GUF.Print("Enter a number from " .. minimum .. " to " .. maximum .. ".")
                    self:SetText(initialText); return
                end
                -- Pixel offsets and sizes are integers; scale and opacity permit decimals.
                if key ~= "scale" and key ~= "alpha" then value = math.floor(value + .5) end
            else
                local ids, err = GUF.ParseSpellIDs(value)
                if not ids then GUF.Print(err); return end
            end
            change(keys, value)
            initialText = tostring(value)
            self:SetText(initialText)
            self:ClearFocus()
        end
        control:SetScript("OnEnterPressed", commit)
        control:SetScript("OnEditFocusLost", commit)
        control:SetScript("OnEscapePressed", function(self) self:SetText(initialText); self:ClearFocus() end)
        if not unitPage then control:ClearAllPoints(); control:SetPoint("LEFT", controlOffset, 0); control:SetWidth(360) end
        UI.SettingHelp(control, label, keys)
    end
    local function input(label, validate, ...)
        local keys, host = { ... }, row(label)
        local control = host.tagInput or CreateFrame("EditBox", nil, host, "InputBoxTemplate")
        host.tagInput = control
        control:SetAutoFocus(false)
        control:SetMaxLetters(250)
        control:SetHeight(24)
        control:ClearAllPoints()
        control:SetPoint("LEFT", host, "LEFT", controlOffset + 5, 0)
        control:SetPoint("RIGHT", host, "RIGHT", -5, 0)
        local original = read(keys) or ""
        control:SetText(original)
        local function commit(self)
            local value = self:GetText()
            if value == original then return end
            if validate then
                local ok, message = validate(value)
                if not ok then GUF.Print(message); self:SetText(original); return end
            end
            change(keys, value)
            original = value
        end
        control:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
        control:SetScript("OnEditFocusLost", commit)
        control:SetScript("OnEscapePressed", function(self) self:SetText(original); self:ClearFocus() end)
        UI.SettingHelp(control, label, keys)
        control:Show()
        return host, control
    end
    local function colorControl(label, swatch, ...)
        local keys, host = { ... }, row(label)
        local control
        if swatch then
            control = host.colorSwatch
            if not control then
                control = CreateFrame("Button", nil, host)
                host.colorSwatch = control
                control:SetSize(24, 24)
                control.border = control:CreateTexture(nil, "BACKGROUND")
                control.border:SetSize(16, 16)
                control.border:SetPoint("CENTER")
                control.border:SetColorTexture(1, 1, 1)
                control.swatch = control:CreateTexture(nil, "ARTWORK")
                control.swatch:SetSize(19, 19)
                control.swatch:SetPoint("CENTER")
                control.swatch:SetTexture(130939) -- Interface\ChatFrame\ChatFrameColorSwatch, as in Dino's color widget.
                control:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
                control:GetHighlightTexture():SetAllPoints(control.swatch)
                control:GetHighlightTexture():SetVertexColor(1, 1, 1, .15)
            end
            UI.Tooltip(control, label, "Click to change this color.")
        else
            control = host.colorControl or UI.Button(host, "Choose color", controlWidth)
            host.colorControl = control
            control:SetText("Choose color")
        end
        local function refresh()
            if control.swatch then
                local value = read(keys)
                control.swatch:SetVertexColor(value[1], value[2], value[3])
            end
        end
        control:Show()
        refresh()
        control:SetScript("OnClick", function()
            local previous = GUF.Copy(read(keys))
            ColorPickerFrame:SetupColorPickerAndShow({ r = previous[1], g = previous[2], b = previous[3],
                hasOpacity = false,
                swatchFunc = function()
                    change(keys, { ColorPickerFrame:GetColorRGB() })
                    refresh()
                end,
                cancelFunc = function()
                    change(keys, previous)
                    refresh()
                end,
            })
        end)
        control:ClearAllPoints()
        control:SetPoint("LEFT", host, "LEFT", controlOffset, 0)
        if not swatch then control:SetPoint("RIGHT", host, "RIGHT", -5, 0) end
    end
    local function color(label, ...)
        colorControl(label, false, ...)
    end
    local function colorSwatch(label, ...)
        colorControl(label, true, ...)
    end
    local function heading(label)
        local host = row("", 30, true)
        host.label:Hide()
        host.heading = host.heading or host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        host.heading:SetFont(GUF.Font("Default"), 14, "")
        host.heading:SetPoint("CENTER")
        host.heading:SetText(label)
        host.heading:Show()
        for i = 1, 2 do
            local line = host["line" .. i] or host:CreateTexture(nil, "ARTWORK")
            host["line" .. i] = line
            line:SetColorTexture(.45, .45, .45, .8)
            line:SetHeight(1)
            line:ClearAllPoints()
            if i == 1 then
                line:SetPoint("LEFT", host, "LEFT")
                line:SetPoint("RIGHT", host.heading, "LEFT", -8, 0)
            else
                line:SetPoint("LEFT", host.heading, "RIGHT", 8, 0)
                line:SetPoint("RIGHT", host, "RIGHT")
            end
            line:Show()
        end
    end
    local function checkGrid(units, getValue, setValue)
        local host = row("", math.ceil(#units / 2) * 34, true)
        host.label:Hide()
        host.gridButtons = host.gridButtons or {}
        for i, unit in ipairs(units) do
            local control = host.gridButtons[i]
            if not control then
                control = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
                control:SetSize(26, 26)
                control.caption = control:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                control.caption:SetPoint("LEFT", control, "RIGHT", 2, 0)
                control.caption:SetFont(GUF.Font("Default"), 14, "")
                host.gridButtons[i] = control
            end
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", host, (i - 1) % 2 == 0 and "TOPLEFT" or "TOP", 0, -math.floor((i - 1) / 2) * 34)
            control.caption:SetText(GUF.labels[unit])
            control:SetChecked(getValue(unit))
            control:SetScript("OnClick", function(self) setValue(unit, self:GetChecked() and true or false) end)
            control:Show()
        end
    end
    return {
        Read = read, Change = change,
        BeginFixedHeader = beginFixedHeader, EndFixedHeader = endFixedHeader,
        RowCount = function() return count end,
        Row = row, Check = check, Slider = slider, CombatFader = combatFader,
        Select = selectValue, Edit = edit, Input = input, Color = color, ColorSwatch = colorSwatch,
        Group = group, EndGroup = endGroup, Heading = heading, CheckGrid = checkGrid,
        Finish = function()
            endGroup(true)
            window.content:SetHeight(math.max(1, -y + (flatGroups and 0 or 10)))
            local scrollBar = window.scroll.ScrollBar
            if scrollBar then scrollBar:SetValue(window.content.scrollOffset or 0) end
            window.content:Show()
            UI.SkinTree(window.content)
            if content.fixedHeader and content.fixedHeader:IsShown() then UI.SkinTree(content.fixedHeader) end
            window.buildingOptions = nil
            UI.UpdateScroll(window)
            UI.QueueScrollUpdate(window)
        end,
    }
end
