local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "Fonts")
end
local unpack = unpack or table.unpack

function GUF.UnitNamePart(name, mode)
    -- Restricted identities can be rendered directly but cannot be parsed in Lua.
    if GUF.Secret(name) then return name end
    if type(name) ~= "string" then return end
    if mode ~= "first" and mode ~= "last" then return name end
    local separator = Constants and Constants.CharacterNameSeparatorConsts
        and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or "-"
    local split = name:find(separator, 1, true)
    local length = #separator
    if not split or split <= 1 then
        local first, last = name:find("%s+")
        split, length = first, first and last - first + 1 or 0
    end
    if not split or split <= 1 then return name end
    if mode == "first" then return name:sub(1, split - 1) end
    local surname = name:sub(split + length):match("^%s*(.-)%s*$")
    return surname ~= "" and surname or name
end

local function playerDisplayName(mode)
    local name
    if GetUnitName then name = GetUnitName("player", true) end
    if GUF.Secret(name) then return name end
    if type(name) ~= "string" or name == "" then name = UnitName("player") end
    return GUF.UnitNamePart(name, mode)
end

local function targetPlayerDisplayName(entry, mode)
    local unit = entry.frame.unit
    if GUF.Secret(unit) then return end
    if type(unit) ~= "string" then unit = "target" end
    local player = UnitIsPlayer(unit)
    if GUF.Secret(player) or not player then return end
    -- GetUnitName abbreviates an off-realm identity with FOREIGN_SERVER_LABEL.
    -- UnitName's first result is the character name, with realm kept separate.
    local name = UnitName(unit)
    if not GUF.Secret(name) and (type(name) ~= "string" or name == "") then return end
    return GUF.UnitNamePart(name, mode), true
end

function GUF.UpdateUnitName(entry)
    if not entry.name or entry.nameWriting then return end
    local cfg = GUF.Runtime.Settings("text", entry).frames[entry.unit]
    local name, playerTarget
    if entry.unit == "target" then name, playerTarget = targetPlayerDisplayName(entry, cfg.nameDisplay) end
    if entry.unit == "pet" or (cfg.nameDisplay == "full" and not playerTarget)
        or (entry.unit == "player" and entry.frame.unit and entry.frame.unit ~= "player") then
        if entry.unitNameOwned then
            entry.nameWriting = true
            entry.name:SetText(entry.original.nameText)
            entry.nameWriting = nil
            entry.unitNameOwned = nil
        end
        return
    end
    if not playerTarget then
        if entry.unit == "player" then name = playerDisplayName(cfg.nameDisplay)
        else name = GUF.UnitNamePart(entry.original.nameText, cfg.nameDisplay) end
    end
    if not GUF.Secret(name) and name == nil then return end
    entry.nameWriting = true
    entry.name:SetText(name)
    entry.nameWriting = nil
    entry.unitNameOwned = true
end

local function playerNameStrip(entry)
    return GUF.Presentation.Role(entry, "name") or entry.health
end

local function playerNameWidth(entry, text, original, enabled)
    if entry.unit ~= "player" or text ~= entry.name or GUF.editing then return end
    if GUF.Restricted() then GUF.DeferRuntime("native-readiness"); return end
    if not enabled then
        if original.widthOwned then text:SetWidth(original.width); original.widthOwned = nil end
        return
    end
    local strip = playerNameStrip(entry)
    if not strip then return end
    if GUF.Secret(original.width) or original.width == nil then original.width = text:GetWidth() end
    local width = strip:GetWidth()
    local nameWidth = GUF.Presentation.Role(entry, "nameWidth")
    local inset = 3 * (entry.sizeOwned and entry.sizeX or 1)
    if nameWidth then width, inset = nameWidth, 0 end
    if GUF.Secret(original.width) or GUF.Secret(width) or type(width) ~= "number" or width <= 0 then
        GUF.DeferRuntime("native-readiness")
        return
    end
    -- Artistic excludes the hidden portrait underlap from its readable name span.
    -- Other styles use the name strip/health area as their horizontal span.
    original.widthOwned = true
    text:SetWidth(math.max(1, width - inset * 2))
end

function GUF.StyleText(entry, text, kind, enabled)
    if not text or not text.GetFont then return end
    enabled = enabled and not GUF.Runtime.Settings("text", entry).frames[entry.unit].text[kind].nativeStyle
    if enabled and (GUF.editing or GUF.Restricted()) then GUF.DeferRuntime("native-readiness"); return end
    entry.textOriginals = entry.textOriginals or {}
    local original = entry.textOriginals[text]
    if not original then
        original = { font = { text:GetFont() }, fontObject = kind == "name" and text:GetFontObject() or nil,
            shadow = { text:GetShadowColor() },
            shadowOffset = { text:GetShadowOffset() }, color = { text:GetTextColor() },
            height = text:GetHeight(), justify = text:GetJustifyH() }
        entry.textOriginals[text] = original
        GUF.NativeProperties.Track(text, "fontStyle", entry, original)
    end
    if not original.hooked then
        if kind == "name" and entry.unit == "player" then
            original.width = text:GetWidth()
            local function refreshWidth()
                if original.writing or entry.sizeWriting then return end
                original.writing = true
                playerNameWidth(entry, text, original, not GUF.Runtime.Settings("text", "player").frames.player.text.name.nativeStyle)
                original.writing = nil
            end
            -- Keep the latest native width for restoration without capturing our own writes.
            GUF.NativeProperties.Hook("Fonts:1", text, "SetWidth", function(_, width)
                if original.writing then return end
                if GUF.Secret(width) then GUF.DeferRuntime("native-readiness"); return end
                original.width = width
                refreshWidth()
            end)
            GUF.NativeProperties.Hook("Fonts:2", text, "SetSize", function(_, width)
                if original.writing then return end
                if GUF.Secret(width) then GUF.DeferRuntime("native-readiness"); return end
                original.width = width
                refreshWidth()
            end)
            local strip = playerNameStrip(entry)
            if strip then
                if strip.HookScript then GUF.NativeProperties.HookScript("Fonts:script:1", strip, "OnSizeChanged", refreshWidth)
                else
                    GUF.NativeProperties.Hook("Fonts:3", strip, "SetWidth", refreshWidth)
                    GUF.NativeProperties.Hook("Fonts:4", strip, "SetSize", refreshWidth)
                end
            end
        end
        local function nativeStyleWrite()
            local transform = GUF.regionTransforms and GUF.regionTransforms[text]
            return original.writing or (transform and transform.writing)
        end
        -- Native refreshes can change shadows independently of SetFont, or
        -- replace the font object altogether. Keep their restore snapshots
        -- current, then reapply our presentation through the normal guards.
        for _, property in ipairs({
            { "SetFont", "GetFont", "font" },
            { "SetShadowColor", "GetShadowColor", "shadow" },
            { "SetShadowOffset", "GetShadowOffset", "shadowOffset" },
        }) do
            local setter, getter, key = property[1], property[2], property[3]
            GUF.NativeProperties.Hook("Fonts:5", text, setter, function()
                if nativeStyleWrite() then return end
                original[key] = { text[getter](text) }
                if kind == "name" and setter == "SetFont" then original.fontObject = nil end
                GUF.StyleText(entry, text, kind, true)
            end)
        end
        GUF.NativeProperties.Hook("Fonts:6", text, "SetFontObject", function()
            if nativeStyleWrite() then return end
            original.font = { text:GetFont() }
            if kind == "name" then original.fontObject = text:GetFontObject() end
            original.shadow = { text:GetShadowColor() }
            original.shadowOffset = { text:GetShadowOffset() }
            if kind == "name" then
                original.justify = text:GetJustifyH()
                original.nameAlignment = nil
            end
            GUF.StyleText(entry, text, kind, true)
        end)
        if kind == "name" then
            GUF.NativeProperties.Hook("Fonts:7", text, "SetJustifyH", function()
                -- Skin placement/restoration must not become the native baseline.
                if nativeStyleWrite() or entry.layoutWriting or entry.sizeWriting or GUF.geometryWriting then return end
                original.justify = text:GetJustifyH()
                original.nameAlignment = nil
                GUF.StyleText(entry, text, kind, true)
            end)
        end
        if kind ~= "name" then
            GUF.NativeProperties.Hook("Fonts:8", text, "SetTextColor", function()
                if original.writing then return end
                original.color = { text:GetTextColor() }
                local cfg = GUF.Runtime.Settings("text", entry).frames[entry.unit]
                if kind == "health" or kind == "power" or cfg.text[kind].customColor then
                    GUF.StyleText(entry, text, kind, true)
                end
            end)
        end
        original.hooked = true
    end
    original.writing = true
    local cfg, options = GUF.Runtime.Settings("text", entry).frames[entry.unit], GUF.Runtime.Settings("text", entry).frames[entry.unit].text[kind]
    if kind == "health" then GUF.LayerHealthText(entry, text) end
    if enabled then
        original.owned = true
        local size = GUF.PresentationTextSize(cfg, kind, GUF.Runtime.Settings("text", entry).general.frameStyle)
        local nameColoring = entry.nameColoring
        if kind == "name" then entry.nameColoring = true end
        GUF.StylePresentationText(text, cfg, options, size)
        entry.nameColoring = nameColoring
        if kind == "name" then text:SetJustifyH(options.align) end
        -- Native text can inherit secret geometry from its health/power bar, even at login.
        -- Leave that height under Blizzard's control instead of using it in arithmetic.
        if not GUF.Secret(original.height) then
            original.heightOwned = true
            text:SetHeight(math.max(original.height, size + 4))
        end
        if kind == "health" or kind == "power" or options.customColor then
            original.colorOwned = true
            text:SetTextColor(unpack(options.color))
        elseif original.colorOwned then
            text:SetTextColor(unpack(original.color))
            original.colorOwned = nil
        end
        original.owned = true
    elseif original.owned then
        if kind == "name" and original.fontObject then
            text:SetFontObject(original.fontObject)
            if text.SetFontHeight and not GUF.Secret(original.font[2]) then text:SetFontHeight(original.font[2]) end
        else text:SetFont(unpack(original.font)) end
        if original.heightOwned then
            text:SetHeight(original.height)
            original.heightOwned = nil
        end
        text:SetShadowColor(unpack(original.shadow))
        text:SetShadowOffset(unpack(original.shadowOffset))
        text:SetTextColor(unpack(original.color))
        text:SetJustifyH(original.justify)
        original.owned = nil
        original.colorOwned = nil
    end
    if kind == "name" then
        playerNameWidth(entry, text, original, enabled)
        if enabled then
            if original.nameAlignment ~= options.align then
                -- Setting identical text can retain the old glyph layout.
                -- Clear and restore it synchronously after changing alignment;
                -- do not require a font/outline change to trigger the redraw.
                -- Forward opaque text unchanged and exclude both writes from
                -- native name capture. Only the public alignment key is compared.
                local value, writing = text:GetText(), entry.nameWriting
                entry.nameWriting = true
                text:SetText(nil)
                text:SetText(value)
                entry.nameWriting = writing
            end
            original.nameAlignment = options.align
        else original.nameAlignment = nil end
    end
    original.writing = nil
end

function GUF.CaptureText(entry)
    if entry.textCaptured then return end
    if entry.name then GUF.StyleText(entry, entry.name, "name", false) end
    for _, region in pairs(entry.regions.level) do
        if region.GetFont then GUF.StyleText(entry, region, "level", false) end
    end
    for _, kind in ipairs({ "health", "power" }) do
        if entry[kind] then
            GUF.StyleText(entry, entry[kind .. "Text"], kind, false)
            for _, text in pairs(GUF.NativeTexts(entry, kind)) do GUF.StyleText(entry, text, kind, false) end
        end
    end
    entry.textCaptured = true
end

function GUF.ApplyText(entry)
    local cfg = GUF.Runtime.Settings("text", entry).frames[entry.unit]
    if entry.name then
        -- The name-color hook is handled by Frames; protect its original color while restoring fonts.
        entry.nameColoring = true
        GUF.StyleText(entry, entry.name, "name", true)
        entry.nameColoring = nil
        local styled = not cfg.text.name.nativeStyle
        GUF.TransformRegion(entry.name, { scale = 1, x = cfg.text.name.x, y = cfg.text.name.y }, styled)
        GUF.UpdateUnitName(entry)
    end
    for _, region in pairs(entry.regions.level) do
        if region.GetFont then GUF.StyleText(entry, region, "level", true) end
    end
    for _, kind in ipairs({ "health", "power" }) do
        if entry[kind] then
            if cfg.text[kind].fieldLayout then GUF.PrepareBarFields(entry, kind) end
            for _, text in pairs(GUF.NativeTexts(entry, kind)) do
                leaseAlpha(text, (cfg.text[kind].fieldLayout or cfg.text[kind].split or cfg[kind .. "Text"] ~= "blizzard") and 0 or nil)
                GUF.StyleText(entry, text, kind, true)
            end
            GUF.StyleText(entry, entry[kind .. "Text"], kind, true)
            GUF.UpdateBarText(entry, kind)
        end
    end
    GUF.Presentation.Feature(entry, "refreshText")
end
