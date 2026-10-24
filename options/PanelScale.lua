local _, GUF = ...
local UI = GUF.OptionsUI
local minimum, maximum = .75, 1.5

function UI.PanelScaleLimit(window, preservePosition)
    local width, height = UIParent:GetWidth() - 32, UIParent:GetHeight() - 32
    if preservePosition and window:IsShown() then
        local left, top = window:GetLeft(), window:GetTop()
        if left and top then
            -- Fit the remaining screen from the pinned corner, so clamping cannot
            -- shift the window to make room for its growing right/bottom edges.
            width = math.min(width, UIParent:GetWidth() - 16 - left * window:GetScale())
            height = math.min(height, top * window:GetScale() - 16)
        end
    end
    return math.max(.4, math.min(width / window:GetWidth(), height / window:GetHeight()))
end

function UI.CreatePanelScale(window)
    local host = CreateFrame("Frame", nil, window)
    host.goodUnitFramesSkin = true
    host:SetSize(430, 36); host:SetPoint("TOPLEFT", 90, -35)
    local label = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT"); label:SetText("Window scale")
    local slider = CreateFrame("Slider", nil, host, "OptionsSliderTemplate")
    slider:SetSize(220, 18); slider:SetPoint("LEFT", 108, 0)
    slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(.01); slider:SetObeyStepOnDrag(true)
    UI.SkinSlider(slider); slider.Text:Hide()
    -- Native thumb coordinates can lag SetValue until the next layout pass.
    -- Own this one handle's position so drag geometry never depends on them.
    slider:GetThumbTexture():SetAlpha(0)
    slider.goodUnitFramesThumbArtwork:Hide()
    local handle = CreateFrame("Frame", nil, slider)
    handle:SetSize(18, 18); handle:EnableMouse(false)
    handle.artwork = UI.SliderThumbArtwork(handle)
    slider.Low:SetText("75%"); slider.High:SetText("150%")
    slider.Low:SetTextColor(1, .82, .3); slider.High:SetTextColor(1, .82, .3)
    local field = CreateFrame("EditBox", nil, host, "InputBoxTemplate")
    field:SetSize(62, 24); field:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    field:SetAutoFocus(false); field:SetMaxLetters(5); field:SetJustifyH("CENTER")
    field:SetFont(GUF.Font("Default"), 12, ""); UI.SkinEdit(field)
    local input = CreateFrame("Frame", nil, host)
    input:SetPoint("TOPLEFT", slider, "TOPLEFT", -9, 7)
    input:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 9, -7)
    input:SetFrameLevel(slider:GetFrameLevel() + 1)
    input:EnableMouse(true); input:EnableMouseWheel(true); slider:EnableMouse(false)
    window.panelScale = host
    local drag, syncing
    local function value()
        local scale = tonumber(GUF.db.general.panelScale) or 1
        if scale ~= scale then scale = 1 end
        return math.max(minimum, math.min(maximum, scale))
    end
    local function stop()
        drag = nil; input:SetScript("OnUpdate", nil)
    end
    local function display()
        syncing = true; slider:SetValue(value()); syncing = nil
        local travel = math.max(0, slider:GetWidth() - handle:GetWidth())
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", slider, "LEFT", handle:GetWidth() / 2 + travel * (value() - minimum) / (maximum - minimum), 0)
        if not field:HasFocus() then field:SetText(string.format("%.0f%%", value() * 100)) end
    end
    local function setScale(scale)
        GUF.db.general.panelScale = math.max(minimum, math.min(maximum, math.floor(scale * 100 + .5) / 100))
        GUF.ApplyPanelScale(true)
    end
    local function commit()
        local number = tonumber(field:GetText():match("^%s*(.-)%%?%s*$"))
        if number and number == number and number >= 75 and number <= 150 then setScale(number / 100) end
        field:SetText(string.format("%.0f%%", value() * 100))
    end
    function host.Refresh()
        if drag and drag.profile ~= GUF.db then stop() end
        if host.profile ~= GUF.db then
            field:SetScript("OnEditFocusLost", nil); field:ClearFocus(); host.profile = GUF.db
        end
        -- CancelControlFocus removes commit handlers when the window closes.
        field:SetScript("OnEditFocusLost", commit)
        display()
    end
    host.Stop = stop
    field:SetScript("OnEnterPressed", function() commit(); field:ClearFocus() end)
    field:SetScript("OnEscapePressed", function()
        field:SetScript("OnEditFocusLost", nil); field:ClearFocus(); host.Refresh()
    end)
    slider:SetScript("OnValueChanged", function(_, scale) if not syncing then setScale(scale) end end)
    local function updateDrag()
        if not drag or drag.profile ~= GUF.db then stop(); return end
        local cursor = GetCursorPosition()
        local distance = cursor / drag.parentScale - drag.left - drag.grab
        -- The track moves and grows with the window. Solve its screen position
        -- against the requested scale, including the screen-fit plateau. Native
        -- slider dragging maps through the already resized track and oscillates.
        local low, high = minimum, maximum
        for _ = 1, 24 do
            local scale = (low + high) / 2
            local position = math.min(scale, drag.limit) * (drag.offset + drag.travel * (scale - minimum) / (maximum - minimum))
            if position < distance then low = scale else high = scale end
        end
        setScale((low + high) / 2)
    end
    input:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        field:ClearFocus()
        local cursor = GetCursorPosition()
        local parentScale, effective = UIParent:GetEffectiveScale(), window:GetEffectiveScale()
        local left, sliderLeft = window:GetLeft(), slider:GetLeft()
        if not left or not sliderLeft then return end
        left = left * effective
        local sliderScale = slider:GetEffectiveScale()
        local offset = (sliderLeft * sliderScale - left) / effective + handle:GetWidth() / 2
        local travel = math.max(1, slider:GetWidth() - handle:GetWidth())
        local center = left + effective * (offset + travel * (value() - minimum) / (maximum - minimum))
        drag = { profile = GUF.db, parentScale = parentScale, left = left / parentScale,
            offset = offset, travel = travel, limit = UI.PanelScaleLimit(window, true),
            grab = math.abs(cursor - center) <= 12 * sliderScale and (cursor - center) / parentScale or 0 }
        updateDrag()
        input:SetScript("OnUpdate", function()
            updateDrag()
            if not IsMouseButtonDown("LeftButton") then stop() end
        end)
    end)
    input:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" and drag then updateDrag(); stop() end end)
    input:SetScript("OnHide", stop)
    input:SetScript("OnMouseWheel", function(_, delta)
        stop(); field:ClearFocus(); setScale(value() + delta * .01)
    end)
    local description = "Resizes the options window immediately, keeping its top-left corner pinned. The window fits the available screen. Enter 75-150%; unit frame scale is configured separately."
    UI.Tooltip(input, "Window scale", description); UI.Tooltip(field, "Window scale", description)
    host.Refresh()
end
