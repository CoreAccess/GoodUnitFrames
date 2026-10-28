local _, GUF = ...
local Settings = GUF.Settings

-- Metadata describes the existing storage contract. Preparation/migrations stay
-- in Settings; factory values are resolved from the selected layout, never
-- merged into customized data. Domains describe effects, not a new scheduler.
local groups, controls = {}, {}
Settings.groups, Settings.controls = groups, controls
Settings.scopes = {
    general = { scope = "profile", default = "profile-factory", reset = "explicit-only",
        copy = "profile", migration = "PrepareProfile", domains = { "panel", "layout" } },
    hideBlizzard = { scope = "layout", default = "layout-factory", reset = "layout-factory",
        copy = "profile", migration = "PrepareLayout", domains = { "visibility", "auras" } },
    frames = { scope = "layout-unit", default = "layout-factory", reset = "layout-factory",
        copy = "unit-rules", migration = "PrepareLayout", dormant = { "pet", "targettarget" } },
}

local function group(path, domains, capability, unit, copy)
    groups[#groups + 1] = { path = path, scope = "layout-unit", domains = domains,
        capability = capability, unit = unit, copy = copy or "copy",
        default = "layout-factory", reset = "layout-factory", migration = "PrepareLayout" }
end
group({}, { "layout" })
group({ "scale" }, { "scale" })
group({ "position" }, { "position" })
group({ "fading" }, { "fading" })
group({ "bars" }, { "bars", "colors" })
group({ "bars", "width" }, { "layout", "text", "resources" }, "barGeometry")
group({ "bars", "healthSize" }, { "layout", "text", "resources" }, "barGeometry")
group({ "bars", "powerSize" }, { "layout", "text", "resources" }, "barGeometry")
group({ "bars", "cast" }, { "cast", "auras" })
group({ "bars", "cast", "texture" }, { "cast" }, "flat")
for _, key in ipairs({ "incHeal", "incAbsorb", "healAbsorb" }) do
    group({ "bars", key }, { "predictions" })
end
group({ "text" }, { "text" })
for _, key in ipairs({ "font", "fontSize", "nameSize", "outline", "healthText", "powerText", "abbreviate" }) do
    group({ key }, { "text" })
end
group({ "healthColor" }, { "colors" })
group({ "customHealth" }, { "colors" })
group({ "nameColor" }, { "text" })
group({ "customName" }, { "text" })
group({ "nameDisplay" }, { "text" }, nil, nil, "retain")
group({ "text", "threat" }, { "threat", "layout" }, "threat", "target", "retain")
group({ "text", "rank" }, { "text" }, "classification", "target", "retain")
group({ "auras" }, { "auras" })
group({ "auras", "bossDebuffs" }, { "auras" }, "bossAuras", "player", "retain")
group({ "auras", "replaceDefault" }, { "auras", "visibility" }, nil, "target", "retain")
group({ "indicators" }, { "artwork", "layout" })
group({ "hide" }, { "artwork", "layout" })
for _, key in ipairs({ "resource", "role" }) do
    local capability = key == "resource" and "classResources" or "roleIndicator"
    group({ "indicators", key }, { "resources", "layout" }, capability, nil, "retain")
    group({ "hide", key }, { "resources", "layout" }, capability, nil, "retain")
end
group({ "combatText" }, { "text" })
group({ "indicators", "feedback" }, { "text" })
group({ "design" }, { "artwork", "layout" }, "design", nil, "retain")
group({ "artistic" }, { "layout", "artwork" }, "artwork")
group({ "flat" }, { "layout", "artwork" }, "flat")
group({ "threat" }, { "threat", "layout" }, "threat", "target", "retain")
groups[#groups].scope = "layout"

local function matches(prefix, path)
    if #prefix > #path then return false end
    for i, key in ipairs(prefix) do if path[i] ~= key then return false end end
    return true
end

function Settings.Group(path)
    local result = groups[1]
    for _, definition in ipairs(groups) do
        if #definition.path >= #result.path and matches(definition.path, path) then result = definition end
    end
    return result
end

function Settings.Applicable(path, layout, unit)
    local definition = Settings.Group(path)
    if not GUF.IsManagedUnit(unit) or not GUF.Layouts.IsAvailable(layout, unit) then return false end
    if definition.unit and definition.unit ~= unit then return false end
    return not definition.capability or GUF.Layouts.Capabilities(layout, unit)[definition.capability] == true
end

local function at(root, path)
    for _, key in ipairs(path) do
        if type(root) ~= "table" then return end
        root = root[key]
    end
    return root
end

function Settings.Default(layout, unit, path)
    local defaults = GUF.GetLayoutDefaults(layout)
    if not defaults then return end
    local root = path[1] == "threat" and defaults or defaults.frames[unit]
    return GUF.Copy(at(root, path))
end

function Settings.RegisterControl(id, definition)
    if controls[id] then error("Duplicate setting control: " .. id) end
    if type(definition.path) ~= "table" or not definition.label or not definition.control then
        error("Incomplete setting control: " .. id)
    end
    definition.group = Settings.Group(definition.path)
    -- Schema fallback and factory preset are different defaults. Keep the
    -- schema's type/default attached without another handwritten value table.
    definition.schemaDefault = GUF.Copy(at(GUF.defaults.frames.player, definition.path))
    definition.type = type(definition.schemaDefault)
    controls[id] = definition
end

function Settings.Describe(layout, unit, path)
    local group = Settings.Group(path)
    local schema = at(path[1] == "threat" and GUF.defaults or GUF.defaults.frames[unit], path)
    return { path = path, type = type(schema), schemaDefault = GUF.Copy(schema),
        default = Settings.Default(layout, unit, path), scope = group.scope,
        applicable = Settings.Applicable(path, layout, unit), copy = group.copy,
        reset = group.reset, migration = group.migration, domains = group.domains }
end

local function control(id, path, label, kind, minimum, maximum, step, percent, choices)
    Settings.RegisterControl(id, { path = path, label = label, control = kind,
        minimum = minimum, maximum = maximum, step = step, percent = percent, choices = choices })
end
control("flat.portrait", { "flat", "portrait" }, "Portrait", "Select", nil, nil, nil, nil,
    { { "HIDE", "Disabled" }, { "LEFT", "Left" }, { "RIGHT", "Right" } })
control("flat.backgroundAlpha", { "flat", "backgroundAlpha" }, "Background opacity", "Slider", 0, 1, .01, true)
control("fading.enabled", { "fading", "enabled" }, "Enable combat fade", "Check")
control("fading.combat", { "fading", "combat" }, "Combat opacity", "Slider", 0, 1, .01, true)
control("fading.inactive", { "fading", "inactive" }, "Inactive opacity", "Slider", 0, 1, .01, true)
control("cast.enabled", { "bars", "cast", "enabled" }, "Enable cast bar", "Check")
control("cast.icon", { "bars", "cast", "icon" }, "Cast icon", "Select", nil, nil, nil, nil,
    { { "LEFT", "Left" }, { "RIGHT", "Right" }, { "HIDE", "Disabled" } })
control("cast.font", { "bars", "cast", "font" }, "Cast font", "Font")
control("cast.width", { "bars", "cast", "width" }, "Cast bar width", "Slider", 100, 250, 1)
control("cast.height", { "bars", "cast", "height" }, "Cast bar height", "Slider", 10, 30, 1)
for _, key in ipairs({ "x", "y" }) do
    control("cast.position." .. key, { "bars", "cast", "position", key }, key:upper() .. " Offset", "Slider", -150, 150, 1)
end
for _, item in ipairs({ { "incHeal", "Incoming heals", "Heal" }, { "incAbsorb", "Damage shields", "Absorb" },
    { "healAbsorb", "Healing absorbs", "Absorb" } }) do
    local key = item[1]
    control(key .. ".enabled", { "bars", key, "enabled" }, "Show " .. item[2]:lower(), "Check")
    control(key .. ".opacity", { "bars", key, "opacity" }, item[3] .. " opacity", "Slider", 0, 1, .01, true)
    control(key .. ".color", { "bars", key, "color" }, item[3] .. " color", "ColorSwatch")
end
control("incAbsorb.showAtFullHealth", { "bars", "incAbsorb", "showAtFullHealth" }, "Show at Full Health", "Check")

-- Validation here covers registered control edits only. Never clamp dormant
-- client/layout preferences as a side effect of availability or UI discovery.
function Settings.ValidateEdit(path, value)
    for _, definition in pairs(controls) do
        if #definition.path == #path and matches(definition.path, path) then
            if definition.control == "Check" then return type(value) == "boolean" end
            if definition.control == "Slider" then
                return type(value) == "number" and value == value and math.abs(value) ~= math.huge
                    and value >= definition.minimum and value <= definition.maximum
            end
            if definition.control == "Select" then
                for _, choice in ipairs(definition.choices) do if choice[1] == value then return true end end
                return false
            end
            if definition.control == "Font" then return type(value) == "string" and value ~= "" end
        end
    end
    return true
end

-- UI shape changes are part of the setting contract. All live changes still
-- use RequestApply; Updates owns targeted scheduling and dependency closure.
function Settings.RebuildControls(path, tab, keepControls)
    if tab == "auras" and path[1] == "auras" then
        local key = path[#path]
        return key == "enabled" or key == "anchorOn" or key == "anchorMode"
    end
    return tab == "bars" and path[1] == "healthColor"
        or tab == "text" and path[1] == "nameColor"
        or tab == "text" and path[1] == "text" and path[3] == "fields" and #path == 4 and not keepControls
end

function Settings.CopyUnit(profile, source, destination)
    if not GUF.IsManagedUnit(source) or not GUF.IsManagedUnit(destination) or source == destination then return end
    local previous, origin = profile.frames[destination], profile.frames[source]
    if not previous or not origin then return end
    local copied = GUF.Copy(origin)
    for _, definition in ipairs(groups) do
        if definition.copy == "retain" and definition.scope == "layout-unit" then
            local path, root = definition.path, copied
            for i = 1, #path - 1 do root = root[path[i]] end
            root[path[#path]] = GUF.Copy(at(previous, path))
        end
    end
    if destination ~= "target" then copied.text.threat, copied.text.rank, copied.auras.replaceDefault = nil, nil, nil end
    if destination == "player" and copied.nameColor == "reaction" then copied.nameColor = "class" end
    profile.frames[destination] = copied
    if GUF.CanAnchor(destination, copied.position.anchorTo) == false then copied.position.anchorTo = "UIParent" end
    return true
end

function Settings.ResetUnit(profile, unit)
    if not GUF.IsManagedUnit(unit) then return end
    local defaults = GUF.GetLayoutDefaults(profile.general.frameStyle)
    profile.frames[unit] = GUF.Copy(defaults.frames[unit])
    if unit == "target" then profile.threat = GUF.Copy(defaults.threat) end
end
