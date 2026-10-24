local _, GUF = ...

-- Configuration-only vocabulary. No user code is evaluated by the editor.
GUF.barTextValues = {
    { "health", "Current health", "health", "number" },
    { "healthMax", "Maximum health", "health", "number" },
    { "healthPercent", "Health percentage", "health", "percent" },
    { "power", "Current power", "power", "number" },
    { "powerMax", "Maximum power", "power", "number" },
    { "powerPercent", "Power percentage", "power", "percent" },
    { "powerMissing", "Missing power", "power", "number" },
    { "mana", "Current mana", "power", "number" },
    { "manaMax", "Maximum mana", "power", "number" },
    { "manaPercent", "Mana percentage", "power", "percent" },
    { "name", "Unit name", "unit", "text" },
    { "level", "Level", "unit", "number" },
    { "class", "Class", "unit", "text" },
    { "race", "Race", "unit", "text" },
    { "classification", "Classification", "unit", "text" },
    { "guild", "Guild name", "unit", "text" },
    { "faction", "Faction", "unit", "text" },
    { "afk", "AFK / DND", "unit", "text" },
    { "threat", "Threat", "unit", "percent" },
}
GUF.barTextValueInfo = {}
for _, item in ipairs(GUF.barTextValues) do GUF.barTextValueInfo[item[1]] = item end
-- Retired checklist choices remain readable in saved compositions. Removing a
-- checkbox must not silently erase existing content or prediction settings.
for _, item in ipairs({
    { "status", "Dead / ghost / offline", "unit", "text" },
    { "healthMissing", "Missing health", "health", "number" },
    { "absorb", "Damage shields", "health", "number" },
    { "incoming", "Incoming healing", "health", "number" },
    { "healAbsorb", "Healing absorbs", "health", "number" },
    { "threatRaw", "Your raw threat percentage", "unit", "percent" },
}) do GUF.barTextValueInfo[item[1]] = item end

function GUF.NewTextValue(key, style)
    return { type = "value", value = key, format = style or "short", precision = 0,
        prefix = "", suffix = "", condition = "available", fallback = "none" }
end

function GUF.ParseBarText(expression, kind, abbreviate)
    local parts = {}
    local function literal(value)
        if value ~= "" then parts[#parts + 1] = { type = "literal", text = value } end
    end
    local function value(key, style)
        parts[#parts + 1] = GUF.NewTextValue(key, style or (abbreviate and "short" or "whole"))
    end
    local aliases = { curhp = "health", maxhp = "healthMax", perhp = "healthPercent",
        abscurhp = "health", absmaxhp = "healthMax", curpp = "power", maxpp = "powerMax",
        abscurpp = "power", perpp = "powerPercent", current = kind == "health" and "health" or "power",
        maximum = kind == "health" and "healthMax" or "powerMax",
        percent = kind == "health" and "healthPercent" or "powerPercent",
        deficit = kind == "health" and "healthMissing" or "powerMissing",
        level = "level", name = "name", status = "status" }
    local cursor = 1
    for start, token, finish in expression:gmatch("()%[([^%]]+)%]()") do
        literal(expression:sub(cursor, start - 1))
        if token == "curmaxhp" or token == "curmaxpp" then
            local hp = token == "curmaxhp"
            value(hp and "health" or "power", "short"); literal(" / ")
            value(hp and "healthMax" or "powerMax", "short")
        elseif aliases[token] then
            local style = token:find("^abs") and "whole" or (token:find("^cur[hp]p$") or token:find("^max[hp]p$")) and "short" or nil
            value(aliases[token], style)
            if token == "deficit" then parts[#parts].prefix = "-" end
        else literal("[" .. token .. "]") end
        cursor = finish
    end
    literal(expression:sub(cursor))
    return parts
end

function GUF.NormalizeBarContent(field, options, side, kind)
    if type(field.parts) ~= "table" then
        field.parts = GUF.ParseBarText(field.expression or "", kind, field.abbreviate)
    end
    -- Keep the saved composition; seed the new position-wide numeric controls
    -- from its existing number style instead of replacing its selected values.
    local style, precision
    for _, part in ipairs(field.parts) do
        local info = part.value and GUF.barTextValueInfo[part.value]
        if info and info[4] == "number" and part.value ~= "level" then
            style = part.format == "short" and "short" or "long"
            precision = style == "short" and 1 or 0
            break
        elseif info and info[4] == "percent" and not precision then precision = part.precision end
    end
    if field.numberFormat ~= "short" and field.numberFormat ~= "long" then
        field.numberFormat = style or (kind == "health" and "short" or "long")
    end
    local decimals = field.decimals
    if type(decimals) ~= "number" or decimals ~= decimals or decimals == math.huge or decimals == -math.huge then
        decimals = precision == 1 and 1 or precision == 2 and 2 or 0
    end
    field.decimals = math.max(0, math.min(2, math.floor(decimals + .5)))
    -- Slot names now define horizontal placement. Keep content and fine offsets.
    field.point, field.align = side:upper(), side:upper()
    if type(field.outline) ~= "string" then field.outline = options.outline end
    if type(field.size) ~= "number" or field.size ~= field.size or field.size == math.huge
        or field.size == -math.huge or field.size <= 0 then field.size = options.size end
    field.size = math.max(6, math.min(40, field.size))
    for _, key in ipairs({ "x", "y" }) do
        local value = field[key]
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then value = 0 end
        field[key] = value
    end
end

function GUF.BarFieldActive(field)
    return field and field.hidden ~= true and field.enabled ~= false
        and (type(field.parts) == "table" and #field.parts > 0 or type(field.parts) ~= "table" and field.expression ~= "")
end

function GUF.BarTextSelection(field)
    local selected = {}
    if GUF.BarFieldActive(field) then
        for _, part in ipairs(field.parts or {}) do
            if part.type == "value" and GUF.barTextValueInfo[part.value] then selected[part.value] = true end
        end
    end
    return selected
end

function GUF.BarTextValueGroups(kind)
    return { kind, kind == "health" and "power" or "health", "unit" }
end

-- The layout editor contains public configuration tags, never rendered unit
-- values. Unrecognized/incomplete tags remain ordinary text while editing.
function GUF.BarTextLayout(field)
    if field.hidden then return "" end
    local text, included = {}, {}
    for _, part in ipairs(field.parts or {}) do
        if part.type == "literal" then text[#text + 1] = part.text or ""
        else
            local info = GUF.barTextValueInfo[part.value]
            if info then
                local linked = part.joinAfter and included[part.joinAfter]
                if part.join and #text > 0 then text[#text + 1] = linked and part.join or " " end
                text[#text + 1] = part.prefix or ""
                text[#text + 1] = "[" .. info[2] .. "]"
                text[#text + 1] = part.suffix or ""
                if linked then text[#text + 1] = part.joinSuffix or "" end
                included[part.value] = true
            end
        end
    end
    return table.concat(text)
end

local layoutValues = {}
for key, info in pairs(GUF.barTextValueInfo) do
    layoutValues[key:lower()], layoutValues[info[2]:lower()] = key, key
end

function GUF.ParseBarTextLayout(text, previous)
    local parts, existing, cursor, last = {}, {}, 1
    for _, part in ipairs(previous.parts or {}) do
        if part.type == "value" then existing[part.value] = part end
    end
    for first, token, finish in text:gmatch("()%[([^%[%]]+)%]()") do
        local key = layoutValues[token:match("^%s*(.-)%s*$"):lower()]
        if key then
            local before = text:sub(cursor, first - 1)
            if last then
                -- Closing brackets belong to the preceding value, so an AFK
                -- wrapper disappears with AFK rather than leaving a stray ).
                local closing, rest = before:match("^(%s*[%)%]%}>]+)(.*)$")
                if closing then
                    last.suffix = (last.suffix or "") .. closing
                    before = rest
                end
            end
            local part = existing[key] and GUF.Copy(existing[key]) or GUF.NewTextValue(key)
            part.prefix, part.suffix = before, ""
            part.join, part.joinAfter, part.joinSuffix = nil, nil, nil
            parts[#parts + 1], last, cursor = part, part, finish
        end
    end
    if last then last.suffix = text:sub(cursor)
    elseif text ~= "" then parts[1] = { type = "literal", text = text } end
    return parts
end

-- Fresh layouts follow checklist order. Manually edited layouts retain their
-- order/affixes and append newly checked values.
-- Join metadata belongs to each value so unavailable information cannot leave
-- behind a slash, empty parentheses or a trailing separator.
function GUF.ChecklistBarParts(selected, kind, previous)
    local parts = {}
    local currentForMaximum = { healthMax = "health", powerMax = "power", manaMax = "mana" }
    local percentages = { healthPercent = "health", powerPercent = "power", manaPercent = "mana" }
    for _, group in ipairs(GUF.BarTextValueGroups(kind)) do
        for _, item in ipairs(GUF.barTextValues) do
            local key = item[1]
            if item[3] == group and selected[key] then
                local part = GUF.NewTextValue(key)
                part.join = " "
                if currentForMaximum[key] and selected[currentForMaximum[key]] then
                    part.join, part.joinAfter = " / ", currentForMaximum[key]
                elseif percentages[key] then
                    local current = percentages[key]
                    local peer = selected[current .. "Max"] and current .. "Max" or selected[current] and current
                    if peer then part.join, part.joinAfter, part.joinSuffix = " (", peer, ")" end
                end
                if key == "healthMissing" or key == "powerMissing" then part.prefix = "-" end
                parts[#parts + 1] = part
            end
        end
    end
    if previous and previous.manualLayout then
        local retained, allowed, included, literal = {}, {}, {}, ""
        for _, part in ipairs(parts) do allowed[part.value] = true end
        for _, part in ipairs(previous.parts or {}) do
            if part.type == "value" and allowed[part.value] then
                retained[#retained + 1] = GUF.Copy(part); included[part.value] = true
            elseif part.type == "literal" then literal = literal .. (part.text or "") end
        end
        for _, part in ipairs(parts) do
            if not included[part.value] then
                if #retained == 0 and literal ~= "" then part.prefix = literal .. part.prefix end
                retained[#retained + 1] = part
            end
        end
        return retained
    end
    return parts
end
