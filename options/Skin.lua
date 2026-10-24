local addonName, GUF = ...
local UI = GUF.OptionsUI
local optionsArt = "Interface\\AddOns\\" .. addonName .. "\\media\\options\\"
UI.ink = { .20, .12, .055 }
UI.mutedInk = { .40, .28, .15 }
UI.gold = { 1, .82, .30 }

function UI.Ink(text, muted)
    text:SetTextColor(unpack(muted and UI.mutedInk or UI.ink))
    text:SetShadowColor(0, 0, 0, 0)
    text:SetShadowOffset(0, 0)
end

function UI.Heading(text, size)
    text.goodUnitFramesHeading = true
    text:SetFont(GUF.Font("Default"), size or 18, "")
    UI.Ink(text)
end

function UI.Selection(button, dark)
    local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border.goodUnitFramesSkin = true
    border:SetAllPoints(); border:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)); border:EnableMouse(false)
    border:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    border:SetBackdropColor(.8, .5, .12, dark and .22 or .12)
    border:SetBackdropBorderColor(.95, .70, .25, .95)
    border:Hide()
    return border
end

function UI.Atlas(texture, atlas, fallback)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
    elseif fallback then texture:SetTexture(fallback)
    else texture:SetColorTexture(.42, .27, .11, .45) end
end

function UI.Rule(parent, y)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    UI.Atlas(texture, "spellbook-divider", "Interface\\QuestFrame\\UI-QuestTitleHighlight")
    texture:SetVertexColor(.48, .29, .10, .65)
    texture:SetHeight(7)
    texture:SetPoint("TOPLEFT", 0, y or 0)
    texture:SetPoint("TOPRIGHT", 0, y or 0)
    return texture
end

-- Owned sliced artwork keeps small bevels/corners fixed at any control width.
function UI.ArtSurface(parent, name, outset, edge, columns, rows, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame.goodUnitFramesOwned, frame.goodUnitFramesSkin = true, true
    frame:EnableMouse(false); frame:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
    frame:SetPoint("TOPLEFT", -outset, outset); frame:SetPoint("BOTTOMRIGHT", outset, -outset)
    frame.pieces = {}
    for y = 1, 3 do
        for x = 1, 3 do
            local region = frame:CreateTexture(nil, "ARTWORK")
            region.goodUnitFramesOwned = true
            region:SetTexture(optionsArt .. name .. ".tga", "CLAMP", "CLAMP", "TRILINEAR")
            region:SetTexCoord(columns[x][1] / width, columns[x][2] / width, rows[y][1] / height, rows[y][2] / height)
            if x == 2 and y == 2 then
                region:SetPoint("TOPLEFT", edge, -edge); region:SetPoint("BOTTOMRIGHT", -edge, edge)
            elseif x == 2 then
                local side = y == 1 and "TOP" or "BOTTOM"
                region:SetHeight(edge)
                region:SetPoint(side .. "LEFT", edge, 0); region:SetPoint(side .. "RIGHT", -edge, 0)
            elseif y == 2 then
                local side = x == 1 and "LEFT" or "RIGHT"
                region:SetWidth(edge)
                region:SetPoint("TOP" .. side, 0, -edge); region:SetPoint("BOTTOM" .. side, 0, edge)
            else
                region:SetSize(edge, edge)
                region:SetPoint((y == 1 and "TOP" or "BOTTOM") .. (x == 1 and "LEFT" or "RIGHT"))
            end
            frame.pieces[#frame.pieces + 1] = region
        end
    end
    return frame
end

local function controlSurface(parent, outset, edge)
    return UI.ArtSurface(parent, "control-frame-v1-1024", outset, edge or 8,
        { { 0, 96 }, { 96, 1948 }, { 1948, 2044 } },
        { { 0, 96 }, { 96, 188 }, { 188, 284 } }, 2044, 284)
end

local function tintControl(frame, active, disabled)
    frame:SetAlpha(disabled and .6 or 1)
    for i, region in ipairs(frame.pieces) do
        region:SetDesaturated(disabled and true or false)
        if active and not disabled and i ~= 5 then region:SetVertexColor(1, .86, .52)
        else region:SetVertexColor(1, 1, 1) end
    end
end

local function refreshTab(button)
    local selected = button.goodUnitFramesTabSelected
    button.active:SetShown(selected); button.inactive:SetShown(not selected)
    local brightness = button:IsMouseOver() and 1 or .86
    for _, piece in ipairs(button.inactive.pieces) do piece:SetVertexColor(brightness, brightness, brightness) end
    button.label:SetTextColor(1, selected and .95 or .90, selected and .78 or .74)
end

function UI.SkinTab(button)
    button.goodUnitFramesDark = true
    local columns = { { 0, 96 }, { 96, 1376 }, { 1376, 1472 } }
    local rows = { { 0, 96 }, { 96, 296 }, { 296, 392 } }
    button.active = UI.ArtSurface(button, "tab-selected-v1-1024", 3, 9, columns, rows, 1472, 392)
    button.inactive = UI.ArtSurface(button, "tab-normal-v1-1024", 3, 9, columns, rows, 1472, 392)
    button:HookScript("OnEnter", refreshTab); button:HookScript("OnLeave", refreshTab)
end

function UI.SelectTab(button, selected)
    button.goodUnitFramesTabSelected = selected and true or false
    button:SetEnabled(not selected)
    refreshTab(button)
end

function UI.SkinEdit(control)
    if control.goodUnitFramesSkinned then return end
    control.goodUnitFramesSkinned, control.goodUnitFramesDark = true, true
    if control.NineSlice then control.NineSlice:Hide() end
    if control.SetBackdrop then control:SetBackdrop(nil) end
    for _, region in ipairs({ control:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    control.goodUnitFramesBorder = controlSurface(control, 3)
    control:SetTextInsets(6, 6, 0, 0)
    control:SetTextColor(1, .92, .76)
    local function refresh()
        tintControl(control.goodUnitFramesBorder, control:HasFocus(), not control:IsEnabled())
    end
    for _, event in ipairs({ "OnEditFocusGained", "OnEditFocusLost", "OnEnable", "OnDisable", "OnShow" }) do
        control:HookScript(event, refresh)
    end
    refresh()
end

function UI.SliderThumbArtwork(parent, anchor)
    local region = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    region.goodUnitFramesOwned = true
    region:SetTexture(optionsArt .. "slider-knob-v1-128.tga", "CLAMP", "CLAMP", "TRILINEAR")
    -- The visible disk is ~18 units inside a 24-unit transparent/shadow canvas.
    -- Keep the native 18-unit thumb geometry and existing endpoint mapping.
    region:SetSize(24, 24); region:SetPoint("CENTER", anchor or parent, "CENTER")
    return region
end

local function sliderTrack(control)
    local frame = CreateFrame("Frame", nil, control)
    frame.goodUnitFramesOwned, frame.goodUnitFramesSkin = true, true
    frame:EnableMouse(false); frame:SetFrameLevel(math.max(0, control:GetFrameLevel() - 1))
    frame:SetPoint("LEFT"); frame:SetPoint("RIGHT"); frame:SetHeight(16)
    local slices = { { 0, 80 }, { 80, 1376 }, { 1376, 1456 } }
    for i, slice in ipairs(slices) do
        local region = frame:CreateTexture(nil, "ARTWORK")
        region.goodUnitFramesOwned = true
        region:SetTexture(optionsArt .. "slider-track-v1-1024.tga", "CLAMP", "CLAMP", "TRILINEAR")
        region:SetTexCoord(slice[1] / 1456, slice[2] / 1456, 0, 1)
        if i == 2 then
            region:SetPoint("TOPLEFT", 16, 0); region:SetPoint("BOTTOMRIGHT", -16, 0)
        else
            region:SetSize(16, 16); region:SetPoint(i == 1 and "LEFT" or "RIGHT")
        end
    end
    return frame
end

local function verticalScrollArtwork(parent, name, edge, cap)
    local frame = CreateFrame("Frame", nil, parent)
    frame.goodUnitFramesOwned, frame.goodUnitFramesSkin = true, true
    frame:EnableMouse(false)
    local sections = { { 0, cap }, { cap, 1 - cap }, { 1 - cap, 1 } }
    frame.pieces = {}
    for i, section in ipairs(sections) do
        local region = frame:CreateTexture(nil, "ARTWORK")
        region.goodUnitFramesOwned = true
        region:SetTexture(optionsArt .. name .. ".tga", "CLAMP", "CLAMP", "TRILINEAR")
        region:SetTexCoord(0, 1, section[1], section[2])
        if i == 2 then
            region:SetPoint("TOPLEFT", 0, -edge); region:SetPoint("BOTTOMRIGHT", 0, edge)
        else
            region:SetHeight(edge)
            local side = i == 1 and "TOP" or "BOTTOM"
            region:SetPoint(side .. "LEFT"); region:SetPoint(side .. "RIGHT")
        end
        frame.pieces[i] = region
    end
    return frame
end

function UI.SkinSlider(control, vertical)
    if control.goodUnitFramesSkinned then return end
    control.goodUnitFramesSkinned = true
    if control.NineSlice then control.NineSlice:Hide() end
    if control.SetBackdrop then control:SetBackdrop(nil) end
    local thumb = control:GetThumbTexture()
    for _, region in ipairs({ control:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region ~= thumb then region:SetAlpha(0) end
    end
    local track, knob
    if vertical then
        track = verticalScrollArtwork(control, "scrollbar-track-v1-128", 8, 64 / 1024)
        track:SetAllPoints(control)
        control:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        thumb = control:GetThumbTexture()
        thumb:SetSize(12, 32); thumb:SetAlpha(0)
        knob = verticalScrollArtwork(control, "scrollbar-thumb-v1-64", 6, 40 / 512)
        knob:SetFrameLevel(control:GetFrameLevel() + 1)
        knob:SetAllPoints(control.goodUnitFramesScrollHandle or thumb)
        control.goodUnitFramesThumbArtwork = knob
    else
        track = sliderTrack(control)
        control:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        thumb = control:GetThumbTexture()
        thumb:SetSize(18, 18); thumb:SetAlpha(0)
        knob = UI.SliderThumbArtwork(control, thumb)
        control.goodUnitFramesThumbArtwork = knob
    end
    control.goodUnitFramesTrack = track
    for _, key in ipairs({ "Text", "Low", "High" }) do
        if control[key] then UI.Ink(control[key]); control[key]:SetFont(GUF.Font("Default"), 11, "") end
    end
    control:HookScript("OnDisable", function()
        thumb:SetDesaturated(true)
        if knob then
            if knob.SetDesaturated then knob:SetDesaturated(true) end
            knob:SetAlpha(.55)
        end
        track:SetAlpha(.5)
    end)
    control:HookScript("OnEnable", function()
        thumb:SetDesaturated(false)
        if knob then
            if knob.SetDesaturated then knob:SetDesaturated(false) end
            knob:SetAlpha(1)
        end
        track:SetAlpha(1)
    end)
end

function UI.SkinDropdown(control)
    if control.goodUnitFramesSkinned then return end
    control.goodUnitFramesSkinned, control.goodUnitFramesDark = true, true
    if control.Background then control.Background:SetAlpha(0) end
    if control.Arrow then control.Arrow:SetAlpha(0) end
    control.goodUnitFramesBorder = controlSurface(control, 1)
    local arrowHost = CreateFrame("Frame", nil, control)
    arrowHost.goodUnitFramesSkin = true; arrowHost:EnableMouse(false)
    arrowHost:SetSize(23, 20); arrowHost:SetPoint("RIGHT", -3, 0)
    local arrowSurface = controlSurface(arrowHost, 0, 5)
    local arrow = arrowHost:CreateTexture(nil, "OVERLAY", nil, 7)
    -- Legacy arrow sprites have blank lower padding; center the painted chevron.
    arrow:SetPoint("CENTER", 0, -5); arrow:SetSize(18, 18)
    arrow:SetVertexColor(1, .82, .35)
    control.goodUnitFramesArrow = arrow
    local function refresh()
        if control.Background then control.Background:SetAlpha(0) end
        if control.Arrow then control.Arrow:SetAlpha(0) end
        local disabled = not control:IsEnabled()
        arrow:SetTexture(disabled and "Interface\\Buttons\\Arrow-Down-Disabled"
            or control.goodUnitFramesPressed and "Interface\\Buttons\\Arrow-Down-Down" or "Interface\\Buttons\\Arrow-Down-Up")
        local over = control:IsMouseOver() or control.IsMenuOpen and control:IsMenuOpen()
        tintControl(control.goodUnitFramesBorder, over, disabled)
        tintControl(arrowSurface, over or control.goodUnitFramesPressed, disabled)
        arrow:SetAlpha(disabled and .55 or 1)
        if control.Text then
            control.Text:ClearAllPoints()
            control.Text:SetPoint("LEFT", 8, 0); control.Text:SetPoint("RIGHT", arrowHost, "LEFT", -4, 0)
            control.Text:SetFont(GUF.Font("Default"), 12, "")
            control.Text:SetTextColor(disabled and .50 or 1, disabled and .45 or .92, disabled and .35 or .76)
        end
    end
    if type(control.OnButtonStateChanged) == "function" then hooksecurefunc(control, "OnButtonStateChanged", refresh) end
    for _, event in ipairs({ "OnEnter", "OnLeave", "OnEnable", "OnDisable", "OnShow" }) do control:HookScript(event, refresh) end
    control:HookScript("OnMouseDown", function() control.goodUnitFramesPressed = true; refresh() end)
    control:HookScript("OnMouseUp", function() control.goodUnitFramesPressed = nil; refresh() end)
    control:HookScript("OnHide", function() control.goodUnitFramesPressed = nil end)
    refresh()
end

function UI.SkinScrollBar(control)
    if control.goodUnitFramesScrollSkinned then return end
    control.goodUnitFramesScrollSkinned = true
    UI.SkinSlider(control, true)
    local input = control.goodUnitFramesScrollInput or control
    local function refreshThumb()
        local artwork = control.goodUnitFramesThumbArtwork
        if artwork then
            for _, piece in ipairs(artwork.pieces) do
                local active = control.goodUnitFramesThumbPressed or input:IsMouseOver()
                piece:SetVertexColor(active and 1 or .92, active and 1 or .92, active and 1 or .92)
            end
        end
    end
    input.RefreshThumb = refreshThumb
    input:HookScript("OnMouseDown", function(_, button) if button == "LeftButton" then control.goodUnitFramesThumbPressed = true; refreshThumb() end end)
    input:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then control.goodUnitFramesThumbPressed = nil; refreshThumb() end end)
    input:HookScript("OnHide", function() control.goodUnitFramesThumbPressed = nil; refreshThumb() end)
    input:HookScript("OnEnter", refreshThumb); input:HookScript("OnLeave", refreshThumb)
    refreshThumb()
    for _, item in ipairs({ { control.ScrollUpButton, "Up" }, { control.ScrollDownButton, "Down" } }) do
        local button, direction = item[1], item[2]
        if button then
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
                local region = button[getter] and button[getter](button)
                if region then region:SetAlpha(0) end
            end
            local arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
            arrow.goodUnitFramesOwned = true
            arrow:SetTexture(optionsArt .. "scrollbar-" .. direction:lower() .. "-v1-64.tga", "CLAMP", "CLAMP", "TRILINEAR")
            arrow:SetSize(18, 18)
            local function refresh()
                local enabled = button:IsEnabled()
                local pressed = button.goodUnitFramesArrowPressed and enabled
                local brightness = enabled and (button:IsMouseOver() and 1 or .92) or .6
                arrow:ClearAllPoints(); arrow:SetPoint("CENTER", 0, pressed and -1 or 0)
                arrow:SetVertexColor(brightness, brightness, brightness)
                arrow:SetDesaturated(not enabled); arrow:SetAlpha(enabled and 1 or .55)
            end
            button:HookScript("OnMouseDown", function() button.goodUnitFramesArrowPressed = true; refresh() end)
            button:HookScript("OnMouseUp", function() button.goodUnitFramesArrowPressed = nil; refresh() end)
            button:HookScript("OnHide", function() button.goodUnitFramesArrowPressed = nil; refresh() end)
            for _, event in ipairs({ "OnEnter", "OnLeave", "OnEnable", "OnDisable", "OnShow" }) do button:HookScript(event, refresh) end
            refresh()
        end
    end
end

-- Focus must be cancelled before a cached page is hidden or rebound.
function UI.CancelControlFocus(frame)
    if not frame then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "EditBox" then
            child:SetScript("OnEditFocusLost", nil)
            child:ClearFocus()
        end
        UI.CancelControlFocus(child)
    end
end

function UI.SkinTree(frame, dark)
    if not frame or frame.goodUnitFramesSkin then return end
    dark = dark or frame.goodUnitFramesDark
    local kind = frame:GetObjectType()
    if kind == "EditBox" then UI.SkinEdit(frame); dark = true
    elseif kind == "Slider" then UI.SkinSlider(frame) end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and not dark then
            if not region.goodUnitFramesHeading then
                local font, size = region:GetFont()
                if font then region:SetFont(font, region.goodUnitFramesBodySize or math.min(size or 13, 13), "") end
            end
            UI.Ink(region)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do UI.SkinTree(child, dark) end
end

UI.layout = { windowWidth = 1160, windowHeight = 760, sidebarWidth = 180, paneLeft = 210,
    contentWidth = 590, controlOffset = 160, controlWidth = 260,
    panePadding = 16, unitPanePadding = 14, paneTop = 80, unitPaneTop = 80,
    scrollBarWidth = 16, scrollBarGap = 8, previewWidth = 292, categoryWidth = 152 }
UI.unitOrder = GUF.order

function UI.LayoutName()
    local style = GUF.db.general.frameStyle
    for _, layout in ipairs(GUF.frameStyles) do
        if layout[1] == style then
            local name = layout[2]:gsub(" Layout$", "")
            return name
        end
    end
    return style
end

function UI.LayoutCapabilities(unit)
    local artistic = GUF.db.general.frameStyle == "artistic"
    local blizzard = GUF.db.general.frameStyle == "blizzard"
    return { artwork = artistic, design = artistic and (unit == "player" or unit == "target"),
        barGeometry = artistic and (unit == "player" or unit == "target"),
        levelIndicator = false,
        classResources = artistic and GUF.UsesSegmentedResources(unit, true),
        roleIndicator = unit == "player" and (blizzard or artistic) or unit == "target" and artistic,
        raid = artistic, classification = artistic and unit == "target", threatRotation = false, bossAuras = unit == "player" }
end

function UI.LayoutIllustration(parent, style, entry)
    if style == "blizzard" then return UI.BlizzardLayoutCard(parent, entry) end
    if style ~= "artistic" then return end
    entry = entry or GUF.CreateFrameSpecimen("player", parent, true)
    entry.optionsPreview, entry.frame.goodUnitFramesSkin = true, true
    entry.previewIdentity = GUF.ArtisticPortraitIdentity("player", "player") or "class-hunter"
    -- Resolve the advertised layout independently of which one is active.
    -- These settings are read only; never switch the profile to render a card.
    local profile = GUF.db
    local layout = profile.general.frameStyle == style and profile
        or profile.layouts and profile.layouts[style] or GUF.GetLayoutDefaults(style)
    local cfg = layout.frames.player
    local class = GUF.PlayerDesignClass()
    local source = cfg.design.layered.enabled and class and GUF.ClassPortraitDesign(class, cfg.design.portraits[class])
        or GUF.BlizzardRingArtwork("player")
    GUF.RenderFrameSpecimen(entry, nil, { style = style, config = cfg, portraitSource = source,
        layoutCard = true, state = "resting", states = { resting = true },
        group = "solo", subject = "player", health = 55 })
    GUF.TintPresentationBar(entry.health, GUF.PreviewHealthColor(entry, "player", 55))
    local _, token = UnitPowerType("player")
    local color = not GUF.Secret(token) and GUF.powerColors[token] or GUF.powerColors.MANA
    if cfg.bars.powerMode == "class" then GUF.TintPresentationBar(entry.power, GUF.ClassColor("player"))
    else GUF.TintPresentationBar(entry.power, unpack(color or GUF.powerColors.MANA)) end
    local frame, state = entry.frame, entry.artisticLayout
    frame:SetScale(1)
    local frameHeight = frame:GetHeight()
    local left, right, bottom, top = 0, frame:GetWidth(), -frameHeight, 0
    -- Measure only this owned specimen, including its overhanging ornament,
    -- Level and status glyph. Never derive card bounds from a live unit frame.
    local function include(region)
        if region:GetObjectType() == "MaskTexture" then return end
        local rect = GUF.FrameRectInUnit(entry, region)
        if not rect then return end
        local upper, lower = rect.top - frameHeight, rect.bottom - frameHeight
        if region == state.rim.art and source.combined then
            local factor = state.portraitWidth / source.diameter
            upper = state.py + (source.centerY - source.paintTop) * factor
            lower = state.py + (source.centerY - source.paintBottom) * factor
        end
        left, right = math.min(left, rect.left), math.max(right, rect.right)
        bottom, top = math.min(bottom, lower), math.max(top, upper)
    end
    local function collect(host)
        for _, region in ipairs({ host:GetRegions() }) do if region:IsShown() then include(region) end end
        for _, child in ipairs({ host:GetChildren() }) do
            if child:IsShown() then include(child); collect(child) end
        end
    end
    collect(frame)
    local width, height = math.max(1, right - left), math.max(1, top - bottom)
    local scale = math.max(.1, math.min(1, (parent:GetWidth() - 12) / width, (parent:GetHeight() - 12) / height))
    frame:SetScale(scale); frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT",
        (parent:GetWidth() - width * scale) / (2 * scale) - left,
        -(parent:GetHeight() - height * scale) / (2 * scale) - top)
    return entry
end

function UI.PrimaryAuraIndex(unit, kind)
    local groups = GUF.db.frames[unit].auras[kind]
    for i, cfg in ipairs(groups) do if cfg.enabled then return i end end
    return 1
end

function UI.SelectedCategory(window)
    if window.tab == "bars" then return window.barCategory end
    if window.tab == "auras" then return window.auraKind end
    if window.tab == "indicators" then return window.indicatorCategory end
    if window.tab == "text" then return window.textCategory end
end

function UI.CreateCategoryPanel(window)
    local nav = CreateFrame("Frame", nil, window.editor)
    nav:SetPoint("TOPLEFT", 0, 0); nav:SetPoint("BOTTOMLEFT", 0, 0)
    nav:SetWidth(UI.layout.categoryWidth)
    local rule = nav:CreateTexture(nil, "BACKGROUND")
    rule:SetColorTexture(.43, .28, .12, .35); rule:SetWidth(1)
    rule:SetPoint("TOPRIGHT", -8, 0); rule:SetPoint("BOTTOMRIGHT", -8, 0)
    nav.rule, nav.buttons = rule, {}
    return nav
end

local explanations = {
    scale = "Resizes the entire unit frame, including its bars, portrait, text and indicators. The preview above the settings uses your configured frame size.",
    panelScale = "Resizes this options window. The window automatically fits within the screen; unit frame scale is configured separately.",
    portraitScale = "Resizes the portrait around its fixed center and shifts the bars to its edge. It does not stretch the portrait artwork.",
    width = "Sets the width in frame coordinates. Health and Power share their width in the Artistic style.",
    customFont = "Use a separate font for this label. Otherwise it inherits the unit's font.",
    customColor = "Use a separate color for this label. Otherwise it inherits its default text color.",
    anchorOn = "Attach this aura row after the opposite aura row. New row stacks them; Sequential shares the available row space.",
    filter = "Choose which real auras Blizzard displays. Preview icons demonstrate appearance and placement; they do not simulate filtering private aura data.",
    sort = "Choose the order of real auras. Sample icons demonstrate layout and text styling.",
    healthColor = "Choose class or reaction colors, colors based on current Health, or a fixed color. Sample health demonstrates percentage coloring.",
    powerMode = "Choose the unit's class color or its Power type color.",
    nameColor = "Class uses class colors for players and reaction colors for NPCs. Reaction, available outside the Player frame, uses green for friendly, yellow for neutral and red for hostile units. Custom uses your selected color.",
}

function UI.SettingDescription(keys)
    local key = keys[#keys]
    if explanations[key] then return explanations[key] end
    if keys[1] == "position" then return "Adjust the unit's screen anchor and offsets. Use Move frames on screen for direct whole-frame positioning; the preview stays centered." end
    if keys[1] == "indicators" then return "Adjust this indicator's presentation. Check matching State or Group conditions to reveal it." end
    if keys[1] == "threat" then return "Customize Target threat. Choose In combat in the preview; actual threat appears only when Blizzard reports threat for the hostile target." end
    if keys[1] == "auras" then return "Customize the selected aura row. The preview uses sample icons and the same styling as real auras." end
    if keys[1] == "text" then return "Customize this text label. The preview updates its font, placement and sample output as you change settings." end
    if keys[1] == "fading" then return "Control frame opacity inside and outside combat. Check In combat in the preview to compare the two conditions." end
    return "Changes save automatically. The preview updates as you adjust the setting."
end

function UI.SettingHelp(control, title, keys)
    UI.Tooltip(control, title, UI.SettingDescription(keys))
end

