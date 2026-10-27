local _, GUF = ...

local function leaseAlpha(region, value, relative)
    return GUF.RegionAlpha(region, value, relative, "BarText")
end
local unpack = unpack or table.unpack

GUF.textModes = { { "blizzard", "Blizzard" }, { "current", "Current" }, { "maximum", "Maximum" },
    { "currentmax", "Current / maximum" }, { "percent", "Percentage" }, { "currentpercent", "Current + percentage" },
    { "deficit", "Missing amount" }, { "none", "Hidden" } }

local function format(text, mode, value, maximum, percent, abbreviate)
    local function number(value)
        if abbreviate and AbbreviateNumbers then return AbbreviateNumbers(value) end
        return value
    end
    if mode == "none" or mode == "blizzard" then text:Hide(); return end
    text:Show()
    if mode == "current" then text:SetText(number(value))
    elseif mode == "maximum" then text:SetText(number(maximum))
    elseif mode == "currentmax" then text:SetFormattedText("%s / %s", number(value), number(maximum))
    elseif mode == "deficit" then
        if not GUF.Secret(value) and not GUF.Secret(maximum) then text:SetFormattedText("-%s", number(maximum - value))
        else text:SetText(number(value)) end
    elseif not GUF.Secret(percent) and percent == nil then text:SetText(number(value))
    elseif mode == "currentpercent" then text:SetFormattedText("%s (%.0f%%)", number(value), percent)
    else text:SetFormattedText("%.0f%%", percent) end
end

local function centeredStatusText(entry, kind, anchor, status)
    local cfg = GUF.TextFrameSettings(entry)
    local options, text = cfg.text[kind], entry[kind .. "Text"]
    if entry.configurationPreview then
        GUF.StylePresentationText(text, cfg, options)
        text:SetTextColor(unpack(options.color))
    else GUF.StyleText(entry, text, kind, true) end
    -- Public saved font size and natural width avoid reading native bar bounds.
    text:ClearAllPoints(); text:SetPoint("CENTER", anchor, "CENTER")
    text:SetSize(0, (options.custom and options.size or cfg.fontSize) + 4)
    text:SetJustifyH("CENTER"); text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false); text:SetText(status); text:Show()
end

function GUF.UpdateBarText(entry, kind)
    local bar, cfg = entry[kind], GUF.Runtime.Settings("text", entry).frames[entry.unit]
    local owned = entry[kind .. "Text"]
    if not bar or not owned then return end
    GUF.SyncArtisticRenderedBar(entry, kind)
    local anchor = GUF.Presentation.Role(entry, kind .. "Anchor") or bar
    local options = cfg.text[kind]
    if entry[kind .. "Slots"] then for _, text in pairs(entry[kind .. "Slots"]) do text:Hide() end end
    owned:Hide()
    local exists = UnitExists(entry.frame.unit or entry.unit)
    if not GUF.Secret(exists) and not exists then return end
    if kind == "power" and GUF.Presentation.Role(entry, "powerAbsent") then return end
    local unit = entry.frame.unit or entry.unit
    if kind == "health" then
        local status = GUF.UnitHealthStatus(unit)
        if status or entry.healthStatusText then
            entry.healthStatusText = status
            local hideNative = status or options.fieldLayout or options.split or cfg.healthText ~= "blizzard"
            for _, text in pairs(GUF.NativeTexts(entry, kind)) do leaseAlpha(text, hideNative and 0 or nil) end
            -- Blizzard's separate Dead/Unconscious labels retain their native
            -- anchors. Only our centered label belongs over the custom fields.
            for _, text in pairs(GUF.NativeHealthStatusTexts(entry)) do leaseAlpha(text, status and 0 or nil) end
        end
        if status then
            -- The owned text area follows the current Health host on both
            -- edges, so NPCs without Power center within expanded Health.
            centeredStatusText(entry, kind, anchor, status)
            return
        end
    end
    local powerType
    if kind == "power" then powerType = UnitPowerType(unit) end
    local value, maximum
    if kind == "health" then value, maximum = UnitHealth(unit), UnitHealthMax(unit)
    else value, maximum = UnitPower(unit, powerType), UnitPowerMax(unit, powerType) end
    if options.fieldLayout then
        local health, healthMax, power, powerMax
        if kind == "health" then
            health, healthMax, power, powerMax = value, maximum, UnitPower(unit), UnitPowerMax(unit)
        else health, healthMax, power, powerMax = UnitHealth(unit), UnitHealthMax(unit), value, maximum end
        local function percentage(current, max, callback, resource)
            local scale = CurveConstants and CurveConstants.ScaleTo100
            if callback and scale then
                if resource then
                    local resourceType = powerType
                    if not GUF.Secret(resourceType) and resourceType == nil then resourceType = UnitPowerType(unit) end
                    return callback(unit, resourceType, false, scale)
                end
                return callback(unit, false, scale)
            end
            if not GUF.Secret(current) and not GUF.Secret(max) and type(max) == "number" and max > 0 then return current / max * 100 end
        end
        local healthPercent = percentage(health, healthMax, UnitHealthPercent)
        local powerPercent = percentage(power, powerMax, UnitPowerPercent, true)
        local level = UnitLevel(unit)
        if not GUF.Secret(level) and type(level) == "number" and level < 0 then level = "??" end
        local status = GUF.UnitHealthStatus(unit) or ""
        local percent, name
        if kind == "health" then percent = healthPercent else percent = powerPercent end
        if GetUnitName then name = GetUnitName(unit, true) else name = UnitName(unit) end
        local data = GUF.ExtendBarTextData({ value = value, maximum = maximum,
            percent = percent,
            health = health, healthMax = healthMax, healthPercent = healthPercent,
            power = power, powerMax = powerMax, powerPercent = powerPercent,
            level = level, name = name, status = status }, unit, options)
        GUF.RenderBarFields(entry, kind, data, anchor)
        return
    end
    if not GUF.Secret(maximum) and (not maximum or maximum <= 0) then return end
    local full = options.hideFull and not GUF.Secret(value) and not GUF.Secret(maximum) and value == maximum
    if not options.split and cfg[kind .. "Text"] == "blizzard" then
        for _, text in pairs(GUF.NativeTexts(entry, kind)) do leaseAlpha(text, full and 0 or nil) end
        return
    end
    if full then return end
    local percent
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if kind == "health" and UnitHealthPercent and scale then percent = UnitHealthPercent(unit, false, scale)
    elseif kind == "power" and UnitPowerPercent and scale then percent = UnitPowerPercent(unit, powerType, false, scale)
    elseif not GUF.Secret(value) and not GUF.Secret(maximum) then percent = value / maximum * 100 end
    if options.split then
        local slots = entry[kind .. "Slots"] or {}
        entry[kind .. "Slots"] = slots
        for _, side in ipairs({ "left", "center", "right" }) do
            local text = slots[side]
            if not text then
                if not entry.configurationPreview and (GUF.editing or GUF.Restricted()) then GUF.DeferRuntime("text-fields"); return end
                text = GUF.Runtime.TrackRegion(GUF.BarTextHost(entry, kind):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
                text.goodUnitFramesOwned = true
                slots[side] = text
                text:SetDrawLayer("OVERLAY", 7)
            end
            GUF.StyleText(entry, text, kind, true)
            text:ClearAllPoints()
            local point = side == "center" and "CENTER" or side:upper()
            local inset = side == "left" and 4 or side == "right" and -4 or 0
            text:SetPoint(point, anchor, point, inset + options.x, options.y)
            text:SetJustifyH(point)
            -- Reused Text/Tags slots may retain a narrow explicit field width.
            -- Legacy outer slots grow inward from their own edge at natural width.
            text:SetWidth(0)
            format(text, options[side], value, maximum, percent, options.abbreviate)
        end
    else
        GUF.StyleText(entry, owned, kind, true)
        owned:ClearAllPoints()
        owned:SetPoint("LEFT", anchor, "LEFT", 4 + options.x, options.y)
        owned:SetPoint("RIGHT", anchor, "RIGHT", -4 + options.x, options.y)
        owned:SetJustifyH(options.align)
        format(owned, cfg[kind .. "Text"], value, maximum, percent, options.abbreviate)
    end
end

function GUF.RenderPreviewBarText(entry, kind, data, anchor)
    local cfg = GUF.TextFrameSettings(entry)
    local options = cfg.text[kind]
    local owned = entry[kind .. "Text"]
    owned:Hide()
    for _, text in pairs(entry[kind .. "Slots"]) do text:Hide() end
    -- Synthetic status replaces every field/format, even when all fields are
    -- disabled. Do not let saved alignment, offsets or hide-full move/hide it.
    if kind == "health" and data.status and data.status ~= "" then
        centeredStatusText(entry, kind, anchor, data.status)
        return
    end
    if options.fieldLayout then GUF.RenderBarFields(entry, kind, GUF.ExtendSampleTextData(data), anchor); return end
    if options.hideFull and data.value == data.maximum then return end
    local function layout(text, point, mode)
        text:ClearAllPoints()
        local inset = point == "LEFT" and 4 or point == "RIGHT" and -4 or 0
        text:SetPoint(point, anchor, point, inset + options.x, options.y)
        GUF.StylePresentationText(text, cfg, options)
        text:SetSize(options.split and 0 or math.max(1, anchor:GetWidth() - 8), anchor:GetHeight())
        text:SetJustifyH(options.split and point or options.align)
        text:SetTextColor(unpack(options.color))
        format(text, mode == "blizzard" and "currentmax" or mode, data.value, data.maximum, data.percent, options.abbreviate)
    end
    if options.split then
        for _, side in ipairs({ "left", "center", "right" }) do layout(entry[kind .. "Slots"][side], side == "center" and "CENTER" or side:upper(), options[side]) end
    else layout(owned, "CENTER", cfg[kind .. "Text"]) end
end
