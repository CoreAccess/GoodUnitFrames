local _, GUF = ...
local unpack = unpack or table.unpack

-- Public configuration expressions compile into SetFormattedText arguments.
-- Unit values are passed to the renderer; never concatenate or inspect secrets.
GUF.textTagChoices = {
    { "[curmaxhp]", "Current / maximum health (short)" }, { "[perhp]", "Health percentage" },
    { "[current]", "Current bar value" }, { "[maximum]", "Maximum bar value" },
    { "[percent]", "Bar percentage" }, { "[deficit]", "Missing bar value" },
    { "[curhp]", "Current health (short)" }, { "[maxhp]", "Maximum health (short)" },
    { "[abscurhp]", "Current health (whole)" }, { "[absmaxhp]", "Maximum health (whole)" },
    { "[curpp]", "Current power (short)" }, { "[maxpp]", "Maximum power (short)" },
    { "[curmaxpp]", "Current / maximum power (short)" }, { "[perpp]", "Power percentage" },
    { "[abscurpp]", "Current power (whole)" }, { "[level]", "Level" },
    { "[name]", "Unit name" }, { "[status]", "Dead / ghost / offline" },
}
local known = {}
for _, choice in ipairs(GUF.textTagChoices) do known[choice[1]:sub(2, -2)] = true end

function GUF.ValidateTextExpression(expression)
    if #expression > 250 then return false, "Use at most 250 characters." end
    for token in expression:gmatch("%[([^%]]+)%]") do
        if not known[token] then return false, "Unknown text tag: [" .. token .. "]" end
    end
    local literal = expression:gsub("%[[^%]]+%]", "")
    if literal:find("[", 1, true) or literal:find("]", 1, true) then return false, "Close each tag with ]." end
    return true
end

function GUF.ShortNumber(value)
    if GUF.Secret(value) then
        if AbbreviateNumbers then return AbbreviateNumbers(value) end
        return value
    end
    if type(value) ~= "number" then return value or "" end
    local magnitude, divisor, suffix = math.abs(value), 1, ""
    if magnitude >= 1000000000 then divisor, suffix = 1000000000, "b"
    elseif magnitude >= 1000000 then divisor, suffix = 1000000, "m"
    elseif magnitude >= 1000 then divisor, suffix = 1000, "k" end
    if divisor == 1 then return string.format("%.0f", value) end
    return string.format("%.1f", value / divisor):gsub("%.0$", "") .. suffix
end

local function present(value, fallback)
    if GUF.Secret(value) then return value end
    if value == nil then return fallback end
    return value
end
local function number(value, short)
    if short then return GUF.ShortNumber(value) end
    return present(value, "")
end
local function tokenFormat(token, data, abbreviate)
    local value, maximum, percent = data.value, data.maximum, data.percent
    if token == "level" then return "%s", { present(data.level, "??") } end
    if token == "name" then return "%s", { present(data.name, "") } end
    if token == "status" then return "%s", { data.status or "" } end
    local short = abbreviate
    if token:find("hp", 1, true) then value, maximum, percent = data.health, data.healthMax, data.healthPercent end
    if token:find("pp", 1, true) then value, maximum, percent = data.power, data.powerMax, data.powerPercent end
    if token == "curmaxhp" or token == "curmaxpp" then return "%s / %s", { number(value, true), number(maximum, true) } end
    if token == "percent" or token == "perhp" or token == "perpp" then
        if not GUF.Secret(percent) and percent == nil then return "%s", { "" } end
        return "%.0f%%", { percent }
    end
    if token == "deficit" then
        if not GUF.Secret(value) and not GUF.Secret(maximum) and type(value) == "number" and type(maximum) == "number" then
            return "-%s", { number(maximum - value, short) }
        end
        return "%s", { "" }
    end
    if token == "curhp" or token == "curpp" or token == "maxhp" or token == "maxpp" then short = true end
    if token == "abscurhp" or token == "absmaxhp" or token == "abscurpp" then short = false end
    if token == "maximum" or token == "maxhp" or token == "maxpp" or token == "absmaxhp" then value = maximum end
    return "%s", { number(value, short) }
end

function GUF.SetTaggedText(text, expression, data, abbreviate)
    local format, args, cursor = {}, {}, 1
    for start, token, finish in expression:gmatch("()%[([^%]]+)%]()") do
        format[#format + 1] = expression:sub(cursor, start - 1):gsub("%%", "%%%%")
        if known[token] then
            local tokenPattern, values = tokenFormat(token, data, abbreviate)
            format[#format + 1] = tokenPattern
            for i = 1, #values do args[#args + 1] = values[i] end
        else format[#format + 1] = "[" .. token .. "]" end
        cursor = finish
    end
    format[#format + 1] = expression:sub(cursor):gsub("%%", "%%%%")
    text:SetFormattedText(table.concat(format), unpack(args))
end

local shortOptions = {}
for precision = 0, 2 do
    local fraction = 10 ^ precision
    local breakpoints = {}
    for _, magnitude in ipairs({ { 1000000000, "b" }, { 1000000, "m" }, { 1000, "k" } }) do
        breakpoints[#breakpoints + 1] = { breakpoint = magnitude[1], abbreviation = magnitude[2],
            significandDivisor = magnitude[1] / fraction, fractionDivisor = fraction, abbreviationIsGlobal = false }
    end
    shortOptions[precision] = { breakpointData = breakpoints, locale = "enUS" }
end

local function formatBarNumber(value, style, precision)
    local opaque = GUF.Secret(value)
    if not opaque and type(value) ~= "number" then return "%s", value end
    if style == "short" then
        if AbbreviateNumbers then
            local result = AbbreviateNumbers(value, shortOptions[precision])
            -- Use the same native magnitude/truncation for live and samples.
            -- Padding is permitted only when the returned string is public.
            if not GUF.Secret(result) and type(result) == "string" then
                local integer, fraction, suffix = result:match("^(%-?%d+)%.?(%d*)([kmb]?)$")
                if integer then
                    local decimals = precision > 0 and "." .. (fraction .. string.rep("0", precision)):sub(1, precision) or ""
                    return "%s", integer .. decimals .. suffix
                end
            end
            return "%s", result
        end
        if opaque then
            return "%." .. precision .. "f", value
        end
        local magnitude, divisor, suffix = math.abs(value), 1, ""
        if magnitude >= 1000000000 then divisor, suffix = 1000000000, "b"
        elseif magnitude >= 1000000 then divisor, suffix = 1000000, "m"
        elseif magnitude >= 1000 then divisor, suffix = 1000, "k" end
        local fraction = 10 ^ precision
        local scaled = value < 0 and math.ceil(value * fraction / divisor) or math.floor(value * fraction / divisor)
        return "%s", string.format("%." .. precision .. "f", scaled / fraction) .. suffix
    end
    if BreakUpLargeNumbers then
        -- Health/resource amounts are integer counts. The native grouping
        -- function accepts opaque counts; decimal padding is public text.
        local padding = precision > 0 and "." .. string.rep("0", precision) or ""
        return "%s" .. padding, BreakUpLargeNumbers(value)
    end
    if opaque then return "%." .. precision .. "f", value end
    local whole = string.format("%.0f", value)
    local grouped, replacements = whole, 1
    while replacements > 0 do grouped, replacements = grouped:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
    return "%s", grouped .. (precision > 0 and "." .. string.rep("0", precision) or "")
end

local classificationLabels = {
    elite = "Elite", rare = "Rare", rareelite = "Rare Elite",
}

-- Compose public format strings, forwarding unit values to the client renderer.
-- In particular, never concatenate, compare or round an opaque value in Lua.
function GUF.SetBarContent(text, parts, data, settings)
    local formats, args, emitted = {}, {}, {}
    local function literal(value)
        if value and value ~= "" then formats[#formats + 1] = value:gsub("|", "||"):gsub("%%", "%%%%") end
    end
    for _, part in ipairs(parts) do
        if part.type == "literal" then literal(part.text)
        else
            local info = GUF.barTextValueInfo[part.value]
            local value = info and data[part.value]
            if part.value == "classification" and not GUF.Secret(value) and type(value) == "string" then
                value = classificationLabels[value:lower()] or ""
            end
            local opaque = GUF.Secret(value)
            local missing = not opaque and (value == nil or value == "" or value == false
                or part.condition == "nonzero" and type(value) == "number" and value == 0)
            if missing and part.fallback == "name" then
                formats[#formats + 1] = "%s"; args[#args + 1] = present(data.name, "")
            elseif not missing then
                local linked = part.joinAfter and emitted[part.joinAfter]
                if part.join and #formats > 0 then literal(linked and part.join or " ") end
                literal(part.prefix)
                local pattern = "%s"
                local precision = settings and settings.decimals or part.precision
                precision = precision == 1 and 1 or precision == 2 and 2 or 0
                if info[4] == "percent" then
                    pattern = "%." .. precision .. "f%%"
                elseif info[4] == "number" then
                    if settings and settings.numberFormat and part.value ~= "level" then
                        pattern, value = formatBarNumber(value, settings.numberFormat, precision)
                    elseif part.format == "short" and part.value ~= "level" then value = GUF.ShortNumber(value)
                    elseif opaque or type(value) == "number" then pattern = "%.0f" end
                end
                formats[#formats + 1] = pattern; args[#args + 1] = value
                literal(part.suffix)
                if linked then literal(part.joinSuffix) end
                emitted[part.value] = true
            end
        end
    end
    text:SetFormattedText(table.concat(formats), unpack(args))
    return #formats > 0
end

local function difference(maximum, current)
    if not GUF.Secret(maximum) and not GUF.Secret(current)
        and type(maximum) == "number" and type(current) == "number" then return maximum - current end
end

function GUF.ExtendBarTextData(data, unit, options)
    data.healthMissing, data.powerMissing = difference(data.healthMax, data.health), difference(data.powerMax, data.power)
    local wanted = {}
    for _, field in pairs(options.fields) do
        if GUF.BarFieldActive(field) then
            for _, part in ipairs(field.parts or {}) do if part.value then wanted[part.value] = true end end
        end
    end
    if wanted.absorb and UnitGetTotalAbsorbs then data.absorb = UnitGetTotalAbsorbs(unit) end
    if wanted.incoming and UnitGetIncomingHeals then data.incoming = UnitGetIncomingHeals(unit) end
    if wanted.healAbsorb and UnitGetTotalHealAbsorbs then data.healAbsorb = UnitGetTotalHealAbsorbs(unit) end
    if wanted.mana or wanted.manaMax or wanted.manaPercent then
        local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
        data.mana, data.manaMax = UnitPower(unit, mana), UnitPowerMax(unit, mana)
        if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
            data.manaPercent = UnitPowerPercent(unit, mana, false, CurveConstants.ScaleTo100)
        elseif not GUF.Secret(data.mana) and not GUF.Secret(data.manaMax)
            and type(data.mana) == "number" and type(data.manaMax) == "number" and data.manaMax > 0 then
            data.manaPercent = data.mana / data.manaMax * 100
        end
    end
    if wanted.class then data.class = UnitClass(unit) end
    if wanted.race then data.race = UnitRace(unit) end
    if wanted.classification then data.classification = UnitClassification(unit) end
    if wanted.guild and GetGuildInfo then data.guild = GetGuildInfo(unit) end
    if wanted.faction then data.faction = UnitFactionGroup(unit) end
    if wanted.afk then
        local afk, dnd = UnitIsAFK and UnitIsAFK(unit), UnitIsDND and UnitIsDND(unit)
        if not GUF.Secret(afk) and afk then data.afk = "AFK"
        elseif not GUF.Secret(dnd) and dnd then data.afk = "DND" end
    end
    if (wanted.threat or wanted.threatRaw) and UnitDetailedThreatSituation then
        local _, _, scaled, raw = UnitDetailedThreatSituation("player", unit == "player" and "target" or unit)
        data.threat, data.threatRaw = scaled, raw
    end
    return data
end

function GUF.ExtendSampleTextData(data)
    data.healthMissing, data.powerMissing = difference(data.healthMax, data.health), difference(data.powerMax, data.power)
    data.absorb, data.incoming, data.healAbsorb = 800, 600, 200
    data.mana, data.manaMax, data.manaPercent = 550, 1000, 55
    data.class, data.race, data.classification = "Hunter", "Night elf", "Elite"
    data.guild, data.faction, data.afk, data.threat, data.threatRaw = "Good", "Alliance", "AFK", 35, 45.5
    return data
end

function GUF.StyleBarField(entry, text, kind, field)
    local cfg = GUF.TextFrameSettings(entry)
    local options = cfg.text[kind]
    local size = field.size > 0 and field.size or options.custom and options.size or cfg.fontSize
    size = math.max(6, size)
    local font = field.customFont and field.font or options.custom and options.font or cfg.font
    -- Slots reused from legacy split text retain StyleText's font/color hooks.
    -- Protect our field overrides from being replaced by the bar-wide style.
    local original = entry.textOriginals and entry.textOriginals[text]
    local writing = original and original.writing
    if original then original.writing = true end
    text:SetFont(GUF.Font(font), size, field.outline or (options.custom and options.outline or cfg.outline))
    text:SetShadowColor(0, 0, 0, 0)
    text:SetShadowOffset(0, 0)
    text:SetTextColor(unpack(field.customColor and field.color or options.color))
    text:SetWordWrap(false)
    text:SetNonSpaceWrap(false); text:SetMaxLines(1)
    text:SetJustifyH(field.align)
    text:SetJustifyV("MIDDLE")
    if original then original.writing = writing end
    return size
end

function GUF.PrepareBarFields(entry, kind)
    local slots = entry[kind .. "Slots"] or {}
    entry[kind .. "Slots"] = slots
    local host = GUF.BarTextHost(entry, kind)
    for _, side in ipairs({ "left", "center", "right" }) do
        if not slots[side] then
            if not entry.configurationPreview and (GUF.editing or GUF.Restricted()) then GUF.DeferRuntime("text-fields"); return end
            local text = GUF.Runtime.TrackRegion(host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
            slots[side] = text
            text.goodUnitFramesOwned = true
            text:SetDrawLayer("OVERLAY", 7)
            text:Hide()
        end
        -- Fields can predate predictions or the current layout. Adopt the
        -- visible text host on every apply, not only at first creation.
        if slots[side]:GetParent() ~= host then
            if not entry.configurationPreview and (GUF.editing or GUF.Restricted()) then GUF.DeferRuntime("text-fields"); return end
            slots[side]:SetParent(host)
        end
    end
    return slots
end

local function publicFieldWidth(text)
    -- Measure only our rendered, readable content. Restricted text and
    -- geometry keep the renderer-only fallback; never inspect their widths.
    if GUF.Secret(text:GetText()) then return end
    local width = text:GetStringWidth()
    if not GUF.Secret(width) and type(width) == "number" and width >= 0 then
        return math.ceil(width) + 1
    end
end

function GUF.RenderBarFields(entry, kind, data, anchor)
    local options = GUF.TextFrameSettings(entry).text[kind]
    local slots = GUF.PrepareBarFields(entry, kind)
    if not slots then return end
    local width, height = anchor:GetWidth(), anchor:GetHeight()
    local metrics = GUF.Presentation.Role(entry, "barMetrics")
    if metrics then width, height = metrics.width, metrics[kind] end
    local publicWidth = not GUF.Secret(width) and type(width) == "number" and width > 0
    local publicHeight = not GUF.Secret(height) and type(height) == "number" and height > 0
    if not publicHeight then height = 0 end
    local active, natural, count = {}, {}, 0
    for _, side in ipairs({ "left", "center", "right" }) do
        local field, text = options.fields[side], slots[side]
        text:Hide()
        if GUF.BarFieldActive(field) then
            local fontSize = GUF.StyleBarField(entry, text, kind, field)
            text:SetJustifyH(side:upper())
            text:ClearAllPoints()
            local inset = side == "left" and 4 or side == "right" and -4 or 0
            text:SetPoint(side:upper(), anchor, side:upper(), inset + field.x, field.y)
            text:SetSize(0, math.max(height, fontSize + 4))
            if field.parts then active[side] = GUF.SetBarContent(text, field.parts, data, field)
            else GUF.SetTaggedText(text, field.expression, data, field.abbreviate); active[side] = true end
            if active[side] then
                count = count + 1; text:Show()
                if publicWidth then natural[side] = publicFieldWidth(text) end
            end
        end
    end
    for _, side in ipairs({ "left", "center", "right" }) do
        if active[side] then
            slots[side]:SetWidth(publicWidth and count == 1 and math.max(1, width - 8) or 0)
        end
    end
    -- If widths are unavailable, let the client resolve peer edges without
    -- reading or doing arithmetic on opaque text/geometry.
    local function constrain(side, peer)
        local field, other = options.fields[side], options.fields[peer]
        slots[side]:SetWidth(0)
        slots[side]:SetPoint(side == "left" and "RIGHT" or "LEFT", slots[peer],
            side == "left" and "LEFT" or "RIGHT", side == "left" and -4 or 4, field.y - other.y)
    end
    if active.center then
        if publicWidth then
            local centerX = width / 2 + options.fields.center.x
            local leftX, rightX = 4 + options.fields.left.x, width - 4 + options.fields.right.x
            local maximum = math.max(1, math.min(width - 8, 2 * (centerX - 4), 2 * (width - 4 - centerX)))
            local uncontested = maximum
            if active.left then
                local needed = natural.left
                local available = needed and 2 * (centerX - leftX - 4 - needed) or (width - 8) / 2
                uncontested = math.min(uncontested, available)
            end
            if active.right then
                local needed = natural.right
                local available = needed and 2 * (rightX - centerX - 4 - needed) or (width - 8) / 2
                uncontested = math.min(uncontested, available)
            end
            -- Short middle text occupies only its glyph width. Long middle
            -- text can exceed half the bar when both outer labels still fit;
            -- competing long labels retain a balanced share of the row.
            local limit = math.min(maximum, math.max((width - 8) / 2, uncontested))
            local centerWidth = math.max(1, math.min(natural.center or limit, limit))
            slots.center:SetWidth(centerWidth)
            if active.left then
                slots.left:SetWidth(math.max(1, centerX - centerWidth / 2 - 4 - leftX))
            end
            if active.right then
                slots.right:SetWidth(math.max(1, rightX - centerX - centerWidth / 2 - 4))
            end
        else
            if active.left then constrain("left", "center") end
            if active.right then constrain("right", "center") end
        end
    elseif active.left and active.right then
        if publicWidth and natural.left and natural.right then
            local span = math.max(2, width - 12 + options.fields.right.x - options.fields.left.x)
            local share = span / 2
            if natural.left + natural.right <= span then
                slots.left:SetWidth(natural.left); slots.right:SetWidth(natural.right)
            elseif natural.left <= share then
                slots.left:SetWidth(natural.left); slots.right:SetWidth(math.max(1, span - natural.left))
            elseif natural.right <= share then
                slots.right:SetWidth(natural.right); slots.left:SetWidth(math.max(1, span - natural.right))
            else
                slots.left:SetWidth(share); slots.right:SetWidth(share)
            end
            return
        end
        -- Short/simple values keep natural width; the longer composition fits
        -- beside them. Public configuration supplies this fallback's priority
        -- when rendered widths are restricted, including mirrored layouts.
        local function score(field)
            local result = 0
            for _, part in ipairs(field.parts or {}) do
                local info = part.value and GUF.barTextValueInfo[part.value]
                result = result + (info and (info[4] == "percent" and 1 or info[4] == "text" and 8 or 4)
                    or #(part.text or "") / 6 + .5)
            end
            return result
        end
        local leftScore, rightScore = score(options.fields.left), score(options.fields.right)
        if publicWidth and leftScore >= 8 and rightScore >= 8 then
            -- Two substantial compositions share the row; neither may claim
            -- the whole bar and push the other outside its bounds.
            local share = math.max(1, (width - 12) / 2)
            slots.left:SetWidth(share); slots.right:SetWidth(share)
        elseif leftScore <= rightScore then constrain("right", "left")
        else constrain("left", "right") end
    end
end
