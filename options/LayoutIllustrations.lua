local _, GUF = ...
local UI = GUF.OptionsUI
local unpack = unpack or table.unpack

local function publicNumber(number)
    return not GUF.Secret(number) and type(number) == "number" and number == number and math.abs(number) ~= math.huge
end

local function indicatorMedia(icon, media)
    -- Modern READY_CHECK_*_TEXTURE constants are atlas names. Older clients
    -- use file paths; preserve that fallback without passing an atlas to SetTexture.
    if not GUF.Secret(media) and type(media) == "string" and C_Texture and C_Texture.GetAtlasInfo(media) then
        icon:SetAtlas(media)
    else
        icon:SetTexture(media, "CLAMP", "CLAMP", "LINEAR")
        icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function atlasAvailable(atlas)
    return not GUF.Secret(atlas) and type(atlas) == "string" and C_Texture and C_Texture.GetAtlasInfo(atlas)
end

-- Before/after reports confirm two distinct unfinished layouts: Forever
-- 1.60.1/70425 and Retail 12.1.5/70575. Complete only private preview metadata;
-- initialized native layouts and restore snapshots remain untouched.
local function targetStartupGeometry(native, cached, healthMasks)
    local container = native.frame.TargetFrameContainer
    local chrome = container and container.FrameTexture
    local atlas = chrome and chrome:GetAtlas()
    if GUF.Secret(atlas) or type(atlas) ~= "string" or atlas:lower() ~= "ui-hud-unitframe-target-portraiton"
        or native.main.HealthBarsContainer ~= native.healthArea or native.main.ManaBar ~= native.power then return end
    local function near(value, expected)
        return publicNumber(value) and math.abs(value - expected) < .01
    end
    local function matches(saved, width, height, anchor, relative, relativeAnchor, x, y)
        local points = saved and saved.points
        local point = points and #points == 1 and points[1]
        return saved and near(saved.width, width) and near(saved.height, height) and point
            and point[1] == anchor and point[2] == relative and point[3] == relativeAnchor
            and near(point[4], x) and near(point[5], y)
    end
    local art, area, health, power = cached[chrome], cached[native.healthArea], cached[native.health], cached[native.power]
    if not art or not matches(area, 126, 20, "BOTTOMRIGHT", container, "LEFT", 148, 2)
        or not matches(health, 126, 20, "TOPLEFT", native.healthArea, "TOPLEFT", 0, 0) then return end
    local retailStartup = GUF.isRetail and GUF.clientInterface == 120105
        and matches(art, 192, 67, "CENTER", container, "CENTER", 0, 0)
        and matches(power, 134, 10, "TOPRIGHT", native.healthArea, "BOTTOMRIGHT", 8, -1)
    local legacyStartup = near(art.width, 194) and near(art.height, 68)
        and matches(power, 134, 10, "TOPRIGHT", native.healthArea, "BOTTOMRIGHT", 4, -1)
    if not retailStartup and not legacyStartup then return end
    local confirmed = {}
    for _, mask in ipairs(healthMasks) do
        local maskAtlas = mask.GetAtlas and mask:GetAtlas()
        if not GUF.Secret(maskAtlas) and type(maskAtlas) == "string"
            and maskAtlas:lower() == "ui-hud-unitframe-target-portraiton-bar-health-mask"
            and matches(cached[mask], 128, 32, "TOPLEFT", native.healthArea, "TOPLEFT", -1, 6) then
            confirmed[#confirmed + 1] = cached[mask]
        end
    end
    if #confirmed == 0 then return end -- Require an actual, readable primary attachment.
    if retailStartup then
        -- The Retail reports differ ONLY in this Health-area anchor. Its
        -- Health and Power children follow it with their captured geometry.
        area.points = { { "BOTTOMRIGHT", container, "LEFT", 149, -10 } }
        return
    end
    area.height = 15
    area.points = { { "BOTTOMRIGHT", container, "LEFT", 147, -9 } }
    health.points = { { "TOPLEFT", native.healthArea, "TOPLEFT", 0, 3 } }
    for _, mask in ipairs(confirmed) do
        mask.points = { { "TOPLEFT", native.healthArea, "TOPLEFT", -1, 9 } }
    end
    -- Power already has the confirmed (4,-1) anchor; it follows the area.
end

-- Target may finish laying out after the addon's restore snapshots were taken.
-- Keep fresh, public geometry in the preview only; never replace those snapshots
-- or inspect a native StatusBar fill's amount-driven dimensions/anchors/UVs.
local function targetGeometry(native, cached)
    if native.unit ~= "target" or GUF.db.general.frameStyle ~= "blizzard"
        or GUF.editing or GUF.Restricted() or native.sizeOwned or native.sizeWriting
        or native.layoutWriting or native.barStyleWriting or GUF.geometryWriting
        or (GUF.Layouts.NativeOriginal(native) or {}).active then return cached end
    local observer = native.blizzardPreviewGeometry
    if not observer then
        observer = { regions = {} }
        native.blizzardPreviewGeometry = observer
        observer.changed = function()
            if native.sizeWriting or native.layoutWriting or native.barStyleWriting or GUF.geometryWriting then return end
            local window = GUF.options
            if not window or not window:IsShown() or window.page ~= "units" or window.unit ~= "target"
                or not window.preview or not window.preview.section:IsShown()
                or GUF.db.general.frameStyle ~= "blizzard" or observer.queued then return end
            observer.queued = true
            C_Timer.After(0, function()
                observer.queued = nil
                -- A native layout often writes several pieces in one callback.
                -- Redraw once after it settles, and recheck the current editor.
                local current = GUF.options
                if GUF.frames.target == native and current and current:IsShown() and current.page == "units"
                    and current.unit == "target" and GUF.db.general.frameStyle == "blizzard"
                    and current.preview and current.preview.section:IsShown()
                    and not GUF.editing and not GUF.Restricted() then GUF.UpdateOptionsPreview() end
            end)
        end
        native.frame:HookScript("OnShow", observer.changed)
    end
    local added
    local function watch(region, mediaOnly)
        if not region or GUF.Secret(region) or observer.regions[region] then return end
        observer.regions[region], added = true, true
        if not mediaOnly then
            for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetAllPoints", "SetSize", "SetWidth", "SetHeight" }) do
                hooksecurefunc(region, method, observer.changed)
            end
        end
        if region.SetAtlas then hooksecurefunc(region, "SetAtlas", observer.changed) end
    end
    local function capture(region)
        if not region or GUF.Secret(region) or region.goodUnitFramesOwned then return end
        watch(region)
        local transform = GUF.regionTransforms and GUF.regionTransforms[region]
        if transform and (transform.enabled or transform.writing) then return end
        local width, height = region:GetSize()
        local points = GUF.ReadPoints(region)
        if publicNumber(width) and width > 0 and publicNumber(height) and height > 0 and points and #points > 0 then
            cached[region] = { region = region, width = width, height = height, points = points }
        end
    end
    local container = native.frame.TargetFrameContainer
    for _, region in pairs({ container, native.frame.TargetFrameContent, native.main, native.healthArea,
        native.health, native.power, container and container.FrameTexture }) do capture(region) end
    local healthMasks = {}
    for _, kind in ipairs({ "health", "power" }) do
        local sourceFill = native[kind] and native[kind]:GetStatusBarTexture()
        -- Watch media changes only on the native fill; its geometry stays private.
        watch(sourceFill, true)
        if sourceFill and sourceFill.GetNumMaskTextures and sourceFill.GetMaskTexture then
            local count = sourceFill:GetNumMaskTextures()
            if publicNumber(count) then
                for i = 1, count do
                    local mask = sourceFill:GetMaskTexture(i)
                    capture(mask)
                    if kind == "health" and mask and not GUF.Secret(mask) and not mask.goodUnitFramesOwned then
                        healthMasks[#healthMasks + 1] = mask
                    end
                end
            end
        end
    end
    targetStartupGeometry(native, cached, healthMasks)
    if added then observer.changed() end -- One settling pass for newly copied regions.
    return cached
end

local function levelTexts(presentation, native, level, cfg)
    for _, text in ipairs(presentation.levels) do
        local source = presentation.positions[text]
        local original = native.textOriginals and native.textOriginals[source]
        if original and original.font then text:SetFont(unpack(original.font)) end
        if cfg and not cfg.text.level.nativeStyle then GUF.StylePresentationText(text, cfg, cfg.text.level) end
        -- Native level labels are auto-width. Copying their empty/hidden size
        -- into a one-pixel box turns even a single digit into an ellipsis.
        local _, size = text:GetFont()
        text:SetWidth(0); text:SetHeight((publicNumber(size) and size or 12) + 4)
        text:SetWordWrap(false); text:SetJustifyH(original and original.justify or "CENTER")
        local color = cfg and cfg.text.level.customColor and cfg.text.level.color or original and original.color
        if color and publicNumber(color[1]) and publicNumber(color[2]) and publicNumber(color[3]) then
            text:SetTextColor(color[1], color[2], color[3], 1)
        else text:SetTextColor(1, .82, 0, 1) end
        if cfg and not cfg.text.level.nativeStyle then
            -- The stock render pass restores captured anchors before this
            -- offset, so refreshes never accumulate the saved adjustment.
            local points = GUF.ReadPoints(text)
            if points then
                text:ClearAllPoints()
                for _, point in ipairs(points) do
                    text:SetPoint(point[1], point[2], point[3], point[4] + cfg.text.level.x, point[5] + cfg.text.level.y)
                end
            end
        end
        text:SetText(level); text:SetAlpha(1); text:Show()
    end
end

local function barTexts(native, kind)
    local bar = native[kind]
    local area = kind == "health" and native.healthArea or native.main.ManaBarArea or bar:GetParent()
    local prefix = native.frame:GetName() .. (kind == "health" and "HealthBarText" or "ManaBarText")
    return {
        left = bar.LeftText or area and area.LeftText or _G[prefix .. "Left"],
        right = bar.RightText or area and area.RightText or _G[prefix .. "Right"],
        center = bar.TextString or bar.HealthBarText or bar.ManaBarText
            or area and (area.TextString or area.HealthBarText or area.ManaBarText) or _G[prefix],
    }
end

local function stockBarText(presentation, native, entry, kind, data, options)
    local cfg, source = GUF.PresentationFrameSettings(entry), native[kind]
    local settings, texts = cfg.text[kind], presentation.nativeTexts[kind]
    local value, maximum, percent = kind == "health" and data.health or data.power,
        kind == "health" and data.healthMax or data.powerMax, kind == "health" and data.healthPercent or data.powerPercent
    for side, text in pairs(texts) do
        local original = native.textOriginals and native.textOriginals[presentation.positions[text]]
        if not presentation.positions[text] then
            local point = side == "center" and "CENTER" or side:upper()
            text:ClearAllPoints()
            text:SetPoint(point, entry[kind], point, side == "left" and 4 or side == "right" and -4 or 0, 0)
        end
        if settings.nativeStyle then
            if original and original.font then text:SetFont(unpack(original.font))
            else text:SetFont(GUF.Font("Default"), 12, "OUTLINE") end
            if original and original.shadow then text:SetShadowColor(unpack(original.shadow)) end
            if original and original.shadowOffset then text:SetShadowOffset(unpack(original.shadowOffset)) end
            text:SetTextColor(1, 1, 1, 1)
        else
            GUF.StylePresentationText(text, cfg, settings)
            text:SetTextColor(unpack(settings.color))
            local points = GUF.ReadPoints(text)
            if points then
                text:ClearAllPoints()
                for _, point in ipairs(points) do
                    text:SetPoint(point[1], point[2], point[3], point[4] + settings.x, point[5] + settings.y)
                end
            end
        end
        local _, size = text:GetFont()
        text:SetHeight(math.max(entry[kind]:GetHeight(), publicNumber(size) and size + 4 or 16))
        text:SetWidth(side == "center" and math.max(1, entry[kind]:GetWidth() - 8) or 0)
        text:SetJustifyH(side == "center" and "CENTER" or side:upper())
        text:SetWordWrap(false)
    end
    if kind == "health" and data.status ~= "" then texts.center:SetText(data.status); texts.center:Show(); return end
    if settings.hideFull and value == maximum then return end
    -- Same native display policy, with public sample numbers only. Font changes
    -- do not change Blizzard's format to a custom Current / maximum label.
    local mode = GetCVar("statusTextDisplay")
    local numeric = not GUF.Secret(source.showNumeric) and source.showNumeric
    local percentage = not GUF.Secret(source.showPercentage) and source.showPercentage
    if numeric and percentage then mode = "BOTH"
    elseif numeric then mode = "NUMERIC"
    elseif percentage then mode = "PERCENT" end
    if not mode or mode == "" or options.showAll then mode = "BOTH" end
    if mode == "NONE" then return end
    local token = kind == "power" and options.powerToken
    local noPercent = not GUF.Secret(source.disablePercentages) and source.disablePercentages
    if token then noPercent = token ~= "MANA" end
    if noPercent and mode == "PERCENT" then mode = "NUMERIC" end
    local function number(value)
        if not GUF.Secret(source.capNumericDisplay) and source.capNumericDisplay and AbbreviateLargeNumbers then
            return AbbreviateLargeNumbers(value)
        end
        return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
    end
    if mode == "BOTH" then
        if not token then token = not GUF.Secret(source.powerToken) and source.powerToken end
        if not noPercent and (not token or token == "MANA") then
            texts.left:SetFormattedText("%.0f%%", math.ceil(percent)); texts.left:Show()
        end
        texts.right:SetText(number(value)); texts.right:Show()
    elseif mode == "PERCENT" then
        texts.center:SetFormattedText("%.0f%%", math.ceil(percent)); texts.center:Show()
    else
        local noMaximum = not GUF.Secret(source.disableMaxValue) and source.disableMaxValue
        if token then noMaximum = token ~= "MANA" end
        texts.center:SetText(noMaximum and number(value) or number(value) .. " / " .. number(maximum)); texts.center:Show()
    end
end

-- Copy presentation metadata into an ordinary, nonsecure illustration. The
-- beta client has its own modern Player art/level medallion, so use that client's
-- captured native geometry rather than an old targeting-frame sprite or guessed
-- retail coordinates. No live bar amounts, ranges, alpha or scripts are copied;
-- stock specimen RGB uses only public components from captured presentation.
function UI.BlizzardLayoutIllustration(parent, illustration, unit, specimen)
    local native = GUF.frames[unit or "player"]
    if not native then return illustration end
    local settled = targetGeometry(native, illustration and illustration.settledGeometry or {})
    if not illustration then
        illustration = { frame = specimen and specimen.frame or CreateFrame("Frame", nil, parent), owners = {}, geometry = {},
            positions = {}, levels = {}, nativeTexts = {}, fills = {}, settledGeometry = settled }
        local frame = illustration.frame
        frame.goodUnitFramesSkin, frame.goodUnitFramesOwned = true, true
        frame:EnableMouse(false)
        local chrome = CreateFrame("Frame", nil, frame)
        -- The native frame texture includes the dark bar wells. It belongs
        -- behind the fills; drawing it above them darkens fills and labels.
        chrome:SetAllPoints(); chrome:SetFrameLevel(frame:GetFrameLevel() + 1)
        chrome:EnableMouse(false); chrome.goodUnitFramesOwned = true
        illustration.chrome = chrome
        local textLayer = CreateFrame("Frame", nil, frame)
        textLayer:SetAllPoints(); textLayer:SetFrameLevel(frame:GetFrameLevel() + 20)
        textLayer:EnableMouse(false); textLayer.goodUnitFramesOwned = true
        illustration.textLayer = textLayer
        for _, item in ipairs(native.sizeRegions or {}) do illustration.geometry[item.region] = item end
        illustration.owners[native.frame] = frame
        local function geometry(source)
            local saved = GUF.Layouts.NativeOriginal(native, source)
            return illustration.settledGeometry[source] or illustration.geometry[source] or saved and saved.geometry
        end
        local function originalParent(source)
            local saved = GUF.Layouts.NativeOriginal(native, source)
            return saved and saved.parent or source:GetParent()
        end
        local owner, position
        position = function(source, target)
            local saved = geometry(source)
            local width, height = saved and saved.width, saved and saved.height
            if not saved or source.GetFont and not saved.hasSize then width, height = source:GetSize() end
            if source == native.health and native.healthArea ~= native.main and native.healthArea ~= source then
                -- Native Health width can be amount-restricted. The stock
                -- specimen represents the full public Health-area footprint.
                local area = geometry(native.healthArea)
                if not publicNumber(width) and area and publicNumber(area.width) then width = area.width end
                if not publicNumber(height) and area and publicNumber(area.height) then height = area.height end
            end
            if publicNumber(width) and publicNumber(height) then target:SetSize(math.max(1, width), math.max(1, height)) end
            local points = saved and saved.points or GUF.ReadPoints(source)
            if not points then return end
            illustration.positions[target] = source
            target:ClearAllPoints()
            for _, point in ipairs(points or {}) do
                if publicNumber(point[4]) and publicNumber(point[5]) then
                    target:SetPoint(point[1], owner(point[2] or source:GetParent()), point[3], point[4], point[5])
                end
            end
        end
        owner = function(source)
            if not source or source == UIParent then return frame end
            if illustration.owners[source] then return illustration.owners[source] end
            local copy = CreateFrame("Frame", nil, owner(originalParent(source)))
            copy.goodUnitFramesOwned = true; copy:EnableMouse(false)
            illustration.owners[source] = copy
            position(source, copy)
            return copy
        end
        local function texture(source, target, saved, fullBar)
            -- Artistic temporarily replaces native masks with rectangular
            -- artwork. Stock copies need the captured native mask media as
            -- well as its captured geometry, never that active replacement.
            local original = GUF.Layouts.NativeOriginal(native, source)
            local mask = original and original.mask
            return GUF.CopyBlizzardTexture(source, target, saved or mask, fullBar)
        end
        local function art(source, layer)
            if not source or source:GetObjectType() ~= "Texture" then return end
            local copy = chrome:CreateTexture(nil, "OVERLAY", nil, layer or 1)
            copy.goodUnitFramesOwned = true; texture(source, copy); position(source, copy)
            return copy
        end
        illustration.position, illustration.texture = position, texture
        illustration.fillMasks = {}
        illustration.applyFillMasks = function(kind, source, target, maskKey)
            local sourceFill = source:GetStatusBarTexture()
            if not sourceFill then return end
            -- A mask may anchor to the fill. Resolve that against the complete
            -- synthetic bar, never clone/read the native amount-driven fill size.
            illustration.owners[sourceFill] = illustration[kind]
            local key = maskKey or kind
            local records = illustration.fillMasks[key] or {}
            illustration.fillMasks[key] = records
            local count = 0
            if sourceFill.GetNumMaskTextures and sourceFill.GetMaskTexture then count = sourceFill:GetNumMaskTextures() end
            if not publicNumber(count) then return end
            local seen = {}
            for i = 1, count do
                local sourceMask = sourceFill:GetMaskTexture(i)
                -- Only masks actually attached to the primary fill qualify.
                -- A named HealthBarMask/ManaBarMask can instead mask overlays.
                local saved = sourceMask and not GUF.Secret(sourceMask) and not sourceMask.goodUnitFramesOwned
                    and geometry(sourceMask)
                local readable = saved and publicNumber(saved.width) and saved.width > 0
                    and publicNumber(saved.height) and saved.height > 0 and saved.points and #saved.points > 0
                for _, point in ipairs(saved and saved.points or {}) do
                    if not publicNumber(point[4]) or not publicNumber(point[5]) then readable = false end
                end
                if readable then
                    local record = records[sourceMask]
                    if not record then
                        local mask = target:GetParent():CreateMaskTexture(nil, "ARTWORK")
                        mask.goodUnitFramesOwned = true
                        record = { mask = mask }
                        records[sourceMask] = record
                    end
                    texture(sourceMask, record.mask)
                    -- Keep the static mask's UVs while clamping outside its
                    -- rectangle to transparent, as the native mask does.
                    local file, coords = record.mask:GetTexture(), { record.mask:GetTexCoord() }
                    if file then
                        record.mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
                        record.mask:SetTexCoord(unpack(coords))
                        position(sourceMask, record.mask)
                        if record.target ~= target then
                            if record.target then record.target:RemoveMaskTexture(record.mask) end
                            target:AddMaskTexture(record.mask); record.target = target
                        end
                        seen[sourceMask] = true
                    end
                end
            end
            for sourceMask, record in pairs(records) do
                if not seen[sourceMask] and record.target then
                    record.target:RemoveMaskTexture(record.mask); record.target = nil
                end
            end
        end
        local container = native.frame.PlayerFrameContainer or native.frame.TargetFrameContainer or native.frame
        illustration.frameTexture = art(container.FrameTexture or native.frame.FrameTexture
            or native.frame.Texture or _G[native.frame:GetName() .. "Texture"])
        if native.nameBackground then illustration.nameArea = owner(native.nameBackground) end
        illustration.levelCircle = art(native.main.LevelBackgroundCircle, 2)
        illustration.portraitCorner = art(native.context.PlayerPortraitCornerIcon, 2)
        local portrait = container.PlayerPortrait or container.Portrait or native.frame.portrait or native.frame.Portrait
            or _G[native.frame:GetName() .. "Portrait"]
        if portrait then
            local face = frame:CreateTexture(nil, "ARTWORK")
            face.goodUnitFramesOwned = true; position(portrait, face)
            SetPortraitTexture(face, "player")
            local mask = frame:CreateMaskTexture(nil, "ARTWORK")
            mask.goodUnitFramesOwned = true
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(face); face:AddMaskTexture(mask)
            illustration.portrait = face
        end
        local function text(source, sample, color, existing)
            if not source or not source.GetFont then return end
            local copy = existing or textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if existing then copy:SetParent(textLayer) end
            copy.goodUnitFramesOwned = true; position(source, copy)
            copy:SetDrawLayer("OVERLAY", 7)
            -- The shared renderer has already styled an existing specimen
            -- name, including its alphabet family and outline. A native
            -- SetFont here overrides that styling on first construction.
            if not existing then
                local original = native.textOriginals and native.textOriginals[source]
                if original and original.font then copy:SetFont(unpack(original.font))
                else copy:SetFont(GUF.Font("Default"), 12, "OUTLINE") end
                if original and original.shadow then copy:SetShadowColor(unpack(original.shadow)) end
                if original and original.shadowOffset then copy:SetShadowOffset(unpack(original.shadowOffset)) end
            end
            copy:SetText(sample); copy:SetTextColor(unpack(color or { 1, 1, 1 }))
            return copy
        end
        local name = text(native.name, GUF.PreviewPlayerName(), { 1, .82, 0 }, specimen and specimen.name)
        illustration.name = name
        if name then
            local original = native.textOriginals and native.textOriginals[native.name]
            local width = original and original.width or native.name:GetWidth()
            name:SetJustifyH(original and original.justify or "LEFT")
            name:SetWidth(publicNumber(width) and width > 0 and width or 124)
        end
        local levels = {}
        for _, source in pairs(native.regions.level) do
            if not levels[source] then
                local copy = text(source, GUF.PreviewPlayerLevel())
                if copy then illustration.levels[#illustration.levels + 1] = copy end
                levels[source] = true
            end
        end
        for _, kind in ipairs({ "health", "power" }) do
            local source = native[kind]
            if source then
                local bar = specimen and specimen[kind] or CreateFrame("StatusBar", nil, owner(originalParent(source)))
                if specimen then bar:SetParent(owner(originalParent(source))); bar:SetFrameLevel(frame:GetFrameLevel() + 8) end
                bar.goodUnitFramesOwned = true; bar:EnableMouse(false)
                illustration.owners[source] = bar; position(source, bar)
                local fill = bar:CreateTexture(nil, "ARTWORK")
                fill.goodUnitFramesOwned = true
                texture(source:GetStatusBarTexture(), fill, native.barStyles and native.barStyles[kind], true)
                illustration.fills[kind] = fill
                bar:SetStatusBarTexture(fill); bar:SetMinMaxValues(0, 100); bar:SetValue(100)
                bar:SetStatusBarColor(1, 1, 1)
                -- Stock chrome supplies the bar wells. The shared renderer's
                -- rectangular backing paints over the portrait's shaped join.
                if bar.background then bar.background:Hide() end
                local texts = barTexts(native, kind)
                illustration.nativeTexts[kind] = {
                    left = text(texts.left, "100%"),
                    right = text(texts.right, kind == "health" and "317" or "546"),
                    center = specimen and text(texts.center, "") or nil,
                }
                if specimen then
                    for _, side in ipairs({ "left", "center", "right" }) do
                        if not illustration.nativeTexts[kind][side] then
                            local copy = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                            copy.goodUnitFramesOwned = true; copy:SetDrawLayer("OVERLAY", 7)
                            copy:SetFont(GUF.Font("Default"), 12, "OUTLINE")
                            local point = side == "center" and "CENTER" or side:upper()
                            copy:SetPoint(point, bar, point, side == "left" and 4 or side == "right" and -4 or 0, 0)
                            copy:SetJustifyH(point); copy:SetWordWrap(false)
                            illustration.nativeTexts[kind][side] = copy
                        end
                    end
                end
                illustration[kind] = bar
                illustration.applyFillMasks(kind, source, fill)
            end
        end
        if specimen then
            local function classification(source)
                if not source or not source.GetTexture then return end
                local holder = owner(source)
                holder:SetFrameLevel(frame:GetFrameLevel() + 23)
                local copy = holder:CreateTexture(nil, "ARTWORK")
                copy.goodUnitFramesOwned = true; copy:SetAllPoints()
                texture(source, copy); holder:Hide()
                return { frame = holder, icon = copy }
            end
            if unit == "target" then
                illustration.classification = classification(container.BossPortraitFrameTexture)
                illustration.rarity = classification(native.context.BossIcon)
            end
            -- Native indicator roots supply both the artwork and their actual
            -- anchor chains. Copy presentation only, including hidden icons;
            -- sample conditions, never native visibility/alpha, control display.
            illustration.indicators = {}
            -- Some clients put the faction emblem in the main frame's round
            -- medallion instead of the contextual banner. Copy that complete
            -- native presentation when available, including its backing.
            local pvpIcon = native.main.PvpBackgroundIcon or native.context.PvpBackgroundIcon
            local function groupRegion(kind)
                local function matches(name)
                    if GUF.Secret(name) or type(name) ~= "string" then return false end
                    local key = name:lower():gsub("[^a-z]", "")
                    if kind == "loot" then return key:find("masterloot") or key:find("mastericon") end
                    return key:find("raidtarget") or key:find("raidmarker") or key:find("raidicon")
                        or key:find("targetmarker")
                end
                local function artwork(region)
                    if GUF.Secret(region) or (type(region) ~= "table" and type(region) ~= "userdata")
                        or region.goodUnitFramesOwned or not region.GetObjectType then return false end
                    local objectType = region:GetObjectType()
                    return objectType == "Texture" or objectType == "Frame"
                end
                -- Parent keys differ across client versions and may name a
                -- marker/indicator frame rather than a texture called Icon.
                for _, root in ipairs({ native.context, native.main, native.frame, container, native.frame.TextureFrame }) do
                    if type(root) == "table" then
                        for key, region in pairs(root) do
                            if matches(key) and artwork(region) then return region end
                        end
                    end
                end
                -- Search only already captured native presentation regions;
                -- never enumerate native aura containers or their children.
                for _, saved in ipairs(native.sizeRegions or {}) do
                    local region = saved.region
                    if artwork(region) then
                        if matches(region:GetName()) then return region end
                        if region.GetAtlas and matches(region:GetAtlas()) then return region end
                        if region.GetTexture and matches(region:GetTexture()) then return region end
                    end
                end
            end
            local sources = {
                combat = native.context.AttackIcon or native.frame.AttackIcon or (unit == "player" and PlayerAttackIcon) or nil,
                resting = native.context.PlayerRestIcon or (unit == "player" and PlayerRestIcon) or native.context.PlayerRestLoop,
                pvp = pvpIcon or native.context.PVPIcon or native.context.PvpIcon or native.frame.pvpIcon
                    or (unit == "player" and PlayerPVPIcon) or (unit == "pet" and PetPVPIcon) or nil,
                pvpBackground = pvpIcon and (native.main.PvpBackgroundCircle or native.context.PvpBackgroundCircle) or nil,
                leader = native.context.LeaderIcon or native.frame.leaderIcon or (unit == "player" and PlayerLeaderIcon) or nil,
                loot = native.context.MasterIcon or native.context.MasterLootIcon or native.main.MasterIcon
                    or native.context.MasterLooterIcon or native.frame.MasterLooterIcon
                    or native.frame.MasterIcon or native.frame.masterIcon or (unit == "player" and PlayerMasterIcon)
                    or groupRegion("loot"),
                role = GUF.PlayerRoleRegions(native),
                raid = unit ~= "player" and (native.context.RaidTargetIcon or native.main.RaidTargetIcon or container.RaidTargetIcon
                    or native.context.RaidTargetIconTexture or native.frame.RaidTargetIconTexture
                    or native.context.TargetMarker or native.main.TargetMarker or native.frame.TargetMarker
                    or native.context.TargetMarkerIcon or native.frame.TargetMarkerIcon
                    or native.frame.RaidTargetIcon or native.frame.raidTargetIcon
                    or (native.frame.TextureFrame and native.frame.TextureFrame.RaidTargetIcon)
                    or _G[native.frame:GetName() .. "TextureFrameRaidTargetIcon"]
                    or groupRegion("raid")) or nil,
            }
            for kind, source in pairs(sources) do
                local root = owner(source)
                -- Aura samples start at root + 30, with timer overlays above
                -- their buttons. Keep the complete resting animation in front.
                root:SetFrameLevel(frame:GetFrameLevel() + (kind == "resting" and 45 or kind == "pvpBackground" and 24 or 25))
                local record = { source = source, frame = root, textures = {} }
                illustration.indicators[kind] = record
                local function copyArtwork(region)
                    if region.goodUnitFramesOwned then return end
                    if region:GetObjectType() == "Texture" then
                        local holder = owner(region)
                        local copy = holder:CreateTexture(nil, "ARTWORK")
                        copy.goodUnitFramesOwned = true
                        copy:SetAllPoints(); texture(region, copy)
                        local blend = region:GetBlendMode()
                        if not GUF.Secret(blend) then copy:SetBlendMode(blend) end
                        local item = { source = region, texture = copy }
                        record.textures[#record.textures + 1] = item
                        local atlas = region:GetAtlas()
                        if kind == "resting" and not GUF.Secret(atlas) and atlas == "UI-HUD-UnitFrame-Player-Rest-Flipbook" then
                            -- The native resting glyph is a 7x6 sheet, not one
                            -- static atlas image. Animate only the owned copy.
                            local group = copy:CreateAnimationGroup()
                            group:SetLooping("REPEAT")
                            local flip = group:CreateAnimation("FlipBook")
                            flip:SetTarget(copy); flip:SetDuration(1.5); flip:SetOrder(1)
                            flip:SetFlipBookRows(7); flip:SetFlipBookColumns(6); flip:SetFlipBookFrames(42)
                            flip:SetFlipBookFrameWidth(0); flip:SetFlipBookFrameHeight(0); flip:SetSmoothing("NONE")
                            item.animation = group
                        end
                    elseif region.GetRegions then
                        for _, child in ipairs({ region:GetRegions() }) do copyArtwork(child) end
                        for _, child in ipairs({ region:GetChildren() }) do copyArtwork(child) end
                    end
                end
                copyArtwork(source)
                root:HookScript("OnShow", function()
                    for _, item in ipairs(record.textures) do if item.animation then item.animation:Play() end end
                end)
                root:HookScript("OnHide", function()
                    for _, item in ipairs(record.textures) do if item.animation then item.animation:Stop() end end
                end)
                root:Hide()
            end
        end
    end
    local frame = illustration.frame
    local width, height = native.original.width, native.original.height
    if not publicNumber(width) or not publicNumber(height) then return illustration end
    frame:SetSize(width, height)
    levelTexts(illustration, native, GUF.PreviewPlayerLevel())
    if not specimen then
        frame:SetScale(math.max(.1, math.min(1, (parent:GetWidth() - 12) / width, (parent:GetHeight() - 4) / height)))
        frame:ClearAllPoints(); frame:SetPoint("CENTER", parent)
    end
    frame:Show()
    return illustration
end

-- Subject changes classification artwork only. The installed client's captured
-- geometry remains authoritative; upstream templates can differ from this beta.
local function stockTarget(presentation, native, entry, options)
    if entry.unit ~= "target" then return end
    local container = native.frame.TargetFrameContainer
    local containerCopy = container and presentation.owners[container]
    local atlas = container and container.FrameTexture and container.FrameTexture:GetAtlas()
    local families = { ["ui-hud-unitframe-target-portraiton"] = true,
        ["ui-hud-unitframe-target-rare-portraiton"] = true, ["ui-hud-unitframe-target-minusmob-portraiton"] = true }
    local regular = containerCopy and not GUF.Secret(atlas) and type(atlas) == "string"
        and families[atlas:lower()]
        and atlasAvailable("UI-HUD-UnitFrame-Target-PortraitOn")
    if regular then
        local rare = options.subject == "rare" or options.subject == "rareelite"
        local frameAtlas = rare and "UI-HUD-UnitFrame-Target-Rare-PortraitOn" or "UI-HUD-UnitFrame-Target-PortraitOn"
        if presentation.frameTexture and atlasAvailable(frameAtlas) then presentation.frameTexture:SetAtlas(frameAtlas) end
    end
    local classification = presentation.classification
    if classification then
        if regular then
            classification.frame:ClearAllPoints()
            classification.frame:SetPoint("TOPRIGHT", containerCopy, "TOPRIGHT", -11, -8)
        end
        local bossAtlas = options.subject == "rareelite" and "ui-hud-unitframe-target-portraiton-boss-rare-silver"
            or options.subject == "elite" and "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold" or nil
        local shown = atlasAvailable(bossAtlas)
        if shown then
            classification.icon:SetAtlas(bossAtlas)
            classification.frame:SetSize(shown.width, shown.height)
        end
        classification.frame:SetShown(not not shown)
    end
    local rarity = presentation.rarity
    if rarity then
        local rareAtlas = "UnitFrame-Target-PortraitOn-Boss-Rare-Star"
        if not atlasAvailable(rareAtlas) then rareAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star" end
        local shown = (options.subject == "rare" or options.subject == "rareelite") and atlasAvailable(rareAtlas)
        if shown then
            rarity.icon:SetAtlas(rareAtlas)
            rarity.frame:SetSize(shown.width, shown.height)
        end
        rarity.frame:SetShown(not not shown)
    end
end

local function stockIndicators(presentation, entry, options)
    local cfg = GUF.PresentationFrameSettings(entry)
    local states = options.states or {}
    local grouped = options.group == "party" or options.group == "raid"
    local enabledIndicators = options.enabledIndicators
    local visible = { combat = states.combat, resting = entry.unit == "player" and states.resting,
        pvp = states.pvp or enabledIndicators, leader = grouped or enabledIndicators,
        loot = grouped or enabledIndicators, role = grouped or enabledIndicators, raid = grouped }
    for _, kind in ipairs({ "combat", "resting", "pvpBackground", "pvp", "leader", "loot", "role", "raid" }) do
        local key = kind == "pvpBackground" and "pvp" or kind
        local badge = GUF.Presentation.Role(entry, "indicator:" .. key)
        if badge then badge:Hide() end
        local record = presentation.indicators and presentation.indicators[kind]
        if record then
            local holder, source = record.frame, record.source
            local settings = cfg.indicators[key] or { x = 0, y = 0, scale = 1, alpha = 1 }
            presentation.position(source, holder)
            if kind == "role" and entry.unit == "player" and presentation.portrait then
                holder:ClearAllPoints()
                for _, point in ipairs(GUF.PlayerRolePoints(presentation.portrait)) do holder:SetPoint(unpack(point)) end
            end
            local shown = visible[key] and not cfg.hide[key]
            for _, item in ipairs(record.textures) do
                -- Resetting the atlas of a running flipbook exposes its whole
                -- sheet until the animation's next update. Keep its media stable.
                if not item.animation then presentation.texture(item.source, item.texture) end
            end
            -- Group samples use only regions supplied by this client's native
            -- unit frame. Without one, keep the generated Artistic badge
            -- hidden instead of inventing a stock icon or default position.
            local item = record.textures[1]
            if shown and item and kind == "raid" then
                item.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons", "CLAMP", "CLAMP", "LINEAR")
                SetRaidTargetIconTexture(item.texture, 6)
            end
            -- A hidden native PvP icon may have no media/size yet. Select the
            -- player's public faction on the same native icon, without asking
            -- a live controller to update or reading restricted unit identity.
            if key == "pvp" then
                local faction = UnitFactionGroup("player")
                shown = shown and not GUF.Secret(faction) and (faction == "Horde" or faction == "Alliance")
                local item = record.textures[1]
                if shown and item and kind == "pvp" then
                    local atlas = item.source:GetAtlas()
                    local file = item.source:GetTexture()
                    -- Prefer this client's existing artwork family. An
                    -- uninitialized contextual banner alone needs a fallback.
                    if not GUF.Secret(atlas) and type(atlas) == "string" and atlas ~= "" then
                        atlas = atlas:gsub("Horde", faction):gsub("Alliance", faction)
                    elseif GUF.Secret(file) or file then atlas = nil
                    else atlas = "UI-HUD-UnitFrame-Player-PVP-" .. faction .. "Icon" end
                    local info = atlas and C_Texture and C_Texture.GetAtlasInfo(atlas)
                    local modern = entry.unit == "player" and GUF.frames[entry.unit].frame.PlayerFrameContent
                        or GUF.frames[entry.unit].frame.TargetFrameContent
                    if modern and info then
                        item.texture:SetAtlas(atlas)
                        -- Keep captured native geometry. Atlas dimensions may
                        -- differ from an explicitly sized native icon.
                        if holder:GetWidth() <= 1 or holder:GetHeight() <= 1 then holder:SetSize(info.width, info.height) end
                    elseif not GUF.Secret(file) and (not file or not modern) then
                        item.texture:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction, "CLAMP", "CLAMP", "LINEAR")
                        item.texture:SetTexCoord(0, 1, 0, 1)
                    end
                end
            end
            -- Match TransformRegion: textures resize around their native anchor;
            -- frame roots scale their complete native child presentation.
            if source.GetScale then
                local transform = GUF.regionTransforms and GUF.regionTransforms[source]
                local scale = source:GetScale()
                if transform then scale = transform.scale end
                if publicNumber(scale) then holder:SetScale(scale * settings.scale) end
            else holder:SetSize(holder:GetWidth() * settings.scale, holder:GetHeight() * settings.scale) end
            local points = GUF.ReadPoints(holder)
            if points then
                holder:ClearAllPoints()
                for _, point in ipairs(points) do
                    holder:SetPoint(point[1], point[2], point[3], point[4] + settings.x, point[5] + settings.y)
                end
            end
            holder:SetAlpha(settings.alpha); holder:SetShown(shown == true)
            if shown and item and kind == "role" then GUF.ApplyRoleIndicatorArtwork(item.texture, "DAMAGER") end
        end
    end
    -- Level text remains independent of role visibility and placement. Their
    -- artwork bounds touching must not blank the native level medallion.
    if presentation.portraitCorner then presentation.portraitCorner:SetShown(not states.combat) end
end

local function stockStatus(presentation, entry, options)
    local states = options.states or {}
    local native = GUF.frames[entry.unit]
    -- These are Artistic replacements, anchored to its differently sized
    -- rim. Stock ready checks overlay the real portrait without hiding it;
    -- Dead/Ghost/Offline belong in Health text, not a generated portrait badge.
    for _, kind in ipairs({ "status", "resurrect" }) do
        local badge = GUF.Presentation.Role(entry, "indicator:" .. kind)
        if badge then badge:Hide() end
    end
    if not presentation.portrait then return end
    presentation.statusSamples = presentation.statusSamples or {}
    local ready = states.ready and "ready" or states.notready and "notready" or states.waiting and "waiting" or nil
    local files = {
        ready = READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready",
        notready = READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady",
        waiting = READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting",
    }
    for _, kind in ipairs({ "status", "resurrect" }) do
        local sample = presentation.statusSamples[kind]
        if not sample then
            local holder = CreateFrame("Frame", nil, entry.frame)
            holder.goodUnitFramesOwned = true; holder:EnableMouse(false)
            holder:SetFrameLevel(entry.frame:GetFrameLevel() + 25)
            local icon = holder:CreateTexture(nil, "ARTWORK")
            icon.goodUnitFramesOwned = true; icon:SetAllPoints()
            sample = { frame = holder, icon = icon }
            presentation.statusSamples[kind] = sample
        end
        local holder = sample.frame
        local source = kind == "status" and (native.context.ReadyCheck or native.frame.ReadyCheck
                or (entry.unit == "player" and PlayerFrameReadyCheck))
            or kind == "resurrect" and (native.context.ResurrectIcon or native.frame.ResurrectIcon or native.frame.resurrectIcon)
        holder:ClearAllPoints(); holder:SetScale(1)
        if source then presentation.position(source, holder)
        else
            -- Frames without native regions use the same explicit addon sample
            -- as Player, centered on this unit's own copied portrait.
            holder:SetSize(kind == "status" and 40 or 32, kind == "status" and 40 or 32)
            holder:SetPoint("CENTER", presentation.portrait, "CENTER")
        end
        holder:SetAlpha(1)
        local file = kind == "status" and ready and files[ready] or "Interface\\RaidFrame\\Raid-Icon-Rez"
        indicatorMedia(sample.icon, file)
        if kind == "resurrect" and source and source.GetTexture then presentation.texture(source, sample.icon) end
        holder:SetShown(kind == "status" and ready ~= nil or kind == "resurrect" and states.resurrect == true)
    end
    presentation.portrait:Show()
end

-- Blizzard owns its specimen construction and presentation. Shared sample data
-- is public; native sources supply cosmetic metadata, never live amounts.
function UI.RenderBlizzardSpecimen(entry, options)
    local native = GUF.frames[entry.unit]
    if not native then return end
    local presentation = UI.BlizzardLayoutIllustration(entry.frame:GetParent(), entry.blizzardPresentation, entry.unit, entry)
    if not presentation then return end
    entry.blizzardPresentation = presentation
    local state, cfg, data = entry.specimenState, GUF.PresentationFrameSettings(entry), entry.previewData
    state.nameArea = presentation.nameArea
    -- Restore the stock copies' baseline anchors before applying saved offsets.
    for copy, source in pairs(presentation.positions) do presentation.position(source, copy) end
    stockTarget(presentation, native, entry, options)
    state.width, state.height = entry.frame:GetSize()
    levelTexts(presentation, native, data.level, cfg)
    if presentation.levelCircle then
        presentation.levelCircle:Show()
        presentation.levelCircle:SetAlpha(1)
    end
    if presentation.portrait then
        if options.subject == "player" then SetPortraitTexture(presentation.portrait, "player")
        else presentation.portrait:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Bear") end
    end
    if presentation.name then
        local name = data.name
        presentation.name:SetText(name); presentation.name:SetShown(not cfg.hide.name)
        presentation.name:SetTextColor(GUF.PreviewNameColor(entry, options.subject))
        data.name = name
        if cfg.text.name.nativeStyle then
            local original = native.textOriginals and native.textOriginals[native.name]
            if original and original.font then presentation.name:SetFont(unpack(original.font)) end
            if original and original.shadow then presentation.name:SetShadowColor(unpack(original.shadow)) end
            if original and original.shadowOffset then presentation.name:SetShadowOffset(unpack(original.shadowOffset)) end
            if original and publicNumber(original.height) and original.height > 0 then presentation.name:SetHeight(original.height) end
            presentation.name:SetJustifyH(original and original.justify or "LEFT")
        else
            GUF.StylePresentationText(presentation.name, cfg, cfg.text.name, GUF.PresentationTextSize(cfg, "name", "blizzard"))
            local _, size = presentation.name:GetFont()
            local original = native.textOriginals and native.textOriginals[native.name]
            local height = original and publicNumber(original.height) and original.height or 0
            presentation.name:SetHeight(math.max(height, size + 4))
            presentation.name:SetJustifyH(cfg.text.name.align)
            if options.layoutCard and entry.unit == "player" then
                -- Same public strip-width policy as the live Player name.
                -- Native name snapshots can predate that styling or belong
                -- to the active Artistic layout instead of this card.
                local strip = native.nameBackground
                    or native.healthArea ~= native.main and native.healthArea or native.health
                local geometry = presentation.settledGeometry[strip] or presentation.geometry[strip]
                if geometry and publicNumber(geometry.width) and geometry.width > 0 then
                    local scale = native.sizeOwned and native.sizeX or 1
                    if publicNumber(scale) then presentation.name:SetWidth(math.max(1, geometry.width - 6 * scale)) end
                end
            end
            local points = GUF.ReadPoints(presentation.name)
            if points then
                presentation.name:ClearAllPoints()
                for _, point in ipairs(points) do
                    presentation.name:SetPoint(point[1], point[2], point[3], point[4] + cfg.text.name.x, point[5] + cfg.text.name.y)
                end
            end
        end
    end
    if options.states and options.states.feign then data.status = "Feign death" end
    for _, kind in ipairs({ "health", "power" }) do
        local bar, source, fill = entry[kind], native[kind], presentation.fills[kind]
        if bar and source and fill then
            if bar.background then bar.background:Hide() end
            presentation.texture(source:GetStatusBarTexture(), fill, native.barStyles and native.barStyles[kind], true)
            bar:SetStatusBarTexture(fill)
            fill:SetDesaturated(false); fill:SetVertexColor(1, 1, 1, 1)
            fill:SetAlpha(1)
            bar:SetStatusBarColor(1, 1, 1, 1)
            -- Native RGB is presentation metadata, not a Health/Power amount.
            -- Only use public cached components; never inspect opaque colors.
            local stockColor = kind == "health" and cfg.healthColor == "blizzard"
                or kind == "power" and cfg.bars.powerMode == "blizzard"
            local selected = GUF.MediaTexture(cfg.bars[kind .. "Texture"])
            if selected then bar:SetStatusBarTexture(selected) end
            presentation.applyFillMasks(kind, source, bar:GetStatusBarTexture())
            local color = native.original[kind .. "Color"]
            if stockColor then
                local r, g, b
                if selected then r, g, b = GUF.BlizzardTextureColor(native, kind)
                elseif color then r, g, b = color[1], color[2], color[3] end
                -- Specimens accept public cached colors only; never forward
                -- opaque native RGB into a public sample.
                if publicNumber(r) and publicNumber(g) and publicNumber(b) then
                    if selected then bar:GetStatusBarTexture():SetDesaturated(true) end
                    GUF.TintPresentationBar(bar, r, g, b)
                end
            end
            local value, maximum, percent = kind == "health" and data.health or data.power,
                kind == "health" and data.healthMax or data.powerMax,
                kind == "health" and data.healthPercent or data.powerPercent
            bar:SetMinMaxValues(0, maximum); bar:SetValue(value); bar:Show()
            state.textAreas[kind]:ClearAllPoints(); state.textAreas[kind]:SetAllPoints(bar)
            state.textAreas[kind]:SetParent(bar)
            local textOptions = cfg.text[kind]
            for _, text in pairs(presentation.nativeTexts[kind] or {}) do
                text:SetTextColor(1, 1, 1, 1)
                text:SetAlpha(1)
                text:SetDrawLayer("OVERLAY", 7)
                text:Hide()
            end
            if not (kind == "health" and data.status ~= "")
                and cfg[kind .. "Text"] == "blizzard" and not textOptions.fieldLayout and not textOptions.split then
                entry[kind .. "Text"]:Hide()
                for _, text in pairs(entry[kind .. "Slots"]) do text:Hide() end
                stockBarText(presentation, native, entry, kind, data, options)
            else
                data.value, data.maximum, data.percent = value, maximum, percent
                GUF.RenderPreviewBarText(entry, kind, data, state.textAreas[kind])
            end
        end
    end
    stockIndicators(presentation, entry, options)
    stockStatus(presentation, entry, options)
    if options.layoutCard then entry.castBar:Hide()
    else GUF.StyleNativeCastSpecimen(entry, options) end
    return true
end

-- General's stock card uses the configurable specimen path, not a second
-- hard-coded demo. Resolve Blizzard's own settings without switching profiles.
function UI.BlizzardLayoutCard(parent, entry)
    if not GUF.frames.player then return entry end
    local layout = GUF.Settings.GetLayout(GUF.db, "blizzard")
    entry = entry or GUF.CreateFrameSpecimen("player", parent, "blizzard")
    entry.optionsPreview, entry.frame.goodUnitFramesSkin = true, true
    local options = { style = "blizzard", settings = layout, layoutCard = true,
        state = "normal", states = {}, group = "solo", subject = "player",
        showAll = false, health = 100 }
    if GUF.RenderFrameSpecimen(entry, nil, options) == "applied" then GUF.Presentation.FitCard(entry, parent, 4) end
    return entry
end

-- Explicit, read-only report for the installed client. Keep two snapshots in
-- memory so a cold-load/first-target comparison can be copied in one operation.
-- Never inspect native fill geometry, UVs, amounts, ranges or aura containers.
local previewReports = {}
function GUF.ShowBlizzardPreviewReport()
    local entry, native = GUF.optionsPreviewEntry, GUF.frames.target
    local window = GUF.options
    local presentation = entry and entry.blizzardPresentation
    if GUF.db.general.frameStyle ~= "blizzard" or not entry or entry.unit ~= "target"
        or not presentation or not native or not window or not window:IsShown()
        or window.page ~= "units" or window.unit ~= "target"
        or not window.preview or not window.preview.section:IsShown() then
        GUF.Print("Open the Blizzard Target interactive preview first."); return
    end
    if GUF.editing or GUF.Restricted() then
        GUF.Print("Leave combat and Edit Mode before capturing preview layout."); return
    end
    local labels, lines = {}, {}
    local function public(value)
        if GUF.Secret(value) then return "<restricted>" end
        if type(value) == "number" then return string.format("%.3f", value) end
        return type(value) == "string" and value or tostring(value)
    end
    local function reference(region)
        if GUF.Secret(region) then return "<restricted>" end
        if not region then return "nil" end
        return labels[region] or (region.GetName and public(region:GetName())) or "<unnamed>"
    end
    local function describe(label, region, saved)
        if not region or GUF.Secret(region) then lines[#lines + 1] = label .. " unavailable"; return end
        local width, height
        if saved then width, height = saved.width, saved.height else width, height = region:GetSize() end
        local points = saved and saved.points or GUF.ReadPoints(region)
        local media = region.GetAtlas and (" atlas=" .. public(region:GetAtlas())) or ""
        lines[#lines + 1] = label .. " " .. public(width) .. "x" .. public(height)
            .. " parent=" .. reference(region:GetParent()) .. media
        if not points then lines[#lines + 1] = "  anchors <restricted>"; return end
        for _, point in ipairs(points) do
            lines[#lines + 1] = "  " .. public(point[1]) .. " -> " .. reference(point[2]) .. "." .. public(point[3])
                .. " (" .. public(point[4]) .. "," .. public(point[5]) .. ")"
        end
    end
    local container = native.frame.TargetFrameContainer
    local nodes = {
        { "root", native.frame }, { "container", container },
        { "content", native.frame.TargetFrameContent }, { "main", native.main },
        { "chrome", container and container.FrameTexture }, { "healthArea", native.healthArea },
        { "powerArea", native.main.ManaBarArea }, { "health", native.health }, { "power", native.power },
    }
    for _, node in ipairs(nodes) do
        local source = node[2]
        if source and not GUF.Secret(source) then
            labels[source] = "native." .. node[1]
            local copy = presentation.owners[source]
            if source == native.frame then copy = entry.frame end
            if source == (container and container.FrameTexture) then copy = presentation.frameTexture end
            node[3] = copy
            if copy then labels[copy] = "preview." .. node[1] end
        end
    end
    local version, build, _, interface = GetBuildInfo()
    lines[#lines + 1] = "Good Target preview; client=" .. public(version)
        .. "; build=" .. public(build) .. "; interface=" .. public(interface)
        .. "; targetExists=" .. public(UnitExists("target"))
    for _, node in ipairs(nodes) do
        describe("native." .. node[1], node[2])
        describe("preview." .. node[1], node[3])
        local cached = node[2] and not GUF.Secret(node[2])
            and (presentation.settledGeometry[node[2]] or presentation.geometry[node[2]])
        if cached then describe("cached." .. node[1], node[2], cached) end
    end
    for _, kind in ipairs({ "health", "power" }) do
        local bar = native[kind]
        local fill = bar and bar:GetStatusBarTexture()
        if GUF.Secret(fill) then fill = nil end
        lines[#lines + 1] = kind .. " native fill atlas=" .. public(fill and fill:GetAtlas())
        if fill and fill.GetNumMaskTextures and fill.GetMaskTexture then
            local count = fill:GetNumMaskTextures()
            lines[#lines + 1] = kind .. " attached masks=" .. public(count)
            if publicNumber(count) then
                for i = 1, count do
                    local mask = fill:GetMaskTexture(i)
                    describe(kind .. ".nativeMask" .. i, mask)
                    local record = mask and not GUF.Secret(mask) and presentation.fillMasks[kind]
                        and presentation.fillMasks[kind][mask]
                    describe(kind .. ".previewMask" .. i, record and record.target and record.mask)
                end
            end
        end
    end
    if #previewReports == 2 then table.remove(previewReports, 1) end
    previewReports[#previewReports + 1] = table.concat(lines, "\n")
    GUF.ShowDiagnosticReport("Target preview layout", table.concat(previewReports, "\n\n--- Next snapshot ---\n\n"))
end

function GUF.ShowDiagnosticReport(title, report)
    if GUF.editing or GUF.Restricted() then GUF.Print("Open diagnostic reports outside combat and Edit Mode."); return end
    local dialog = UI.previewReportDialog
    if not dialog then
        dialog = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        dialog.goodUnitFramesOwned = true
        dialog:SetSize(760, 420); dialog:SetPoint("CENTER"); dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scroll.goodUnitFramesOwned = true
        scroll:SetPoint("TOPLEFT", 12, -32); scroll:SetPoint("BOTTOMRIGHT", -30, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit.goodUnitFramesOwned = true
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(704); edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
        dialog:SetScript("OnHide", function() edit:ClearFocus() end)
        scroll:SetScrollChild(edit)
        dialog.edit, dialog.scroll = edit, scroll
        UI.previewReportDialog = dialog
    end
    dialog.TitleText:SetText(title .. " (Ctrl+A, Ctrl+C)")
    local _, breaks = report:gsub("\n", "")
    dialog.edit:SetHeight(math.max(340, (breaks + 1) * 28))
    dialog.edit:SetText(report); dialog:Show(); dialog.scroll:SetVerticalScroll(0)
    dialog.edit:SetFocus(); dialog.edit:HighlightText()
end

