local addonName, GUF = ...
-- Shared addon setup and coordination.
_G.GoodUnitFrames = GUF
GUF.name = addonName
GUF.title = "Good Unit Frames"
GUF.version = "1.1.1"
-- Transitional aliases keep existing features on the extracted client rules.
GUF.clientInterface = GUF.Client.interface
GUF.isForever = GUF.Client.isForever
GUF.isRetail = GUF.Client.isRetail
GUF.order = { "player", "target" }
-- Keep dormant configuration defaults for future support; only order is live.
local storedUnitOrder = { "player", "target", "targettarget", "pet" }
GUF.labels = { player = "Player", target = "Target", targettarget = "Target of Target", pet = "Pet" }
GUF.frames = {}
function GUF.IsManagedUnit(unit)
    return not GUF.Secret(unit) and (unit == "player" or unit == "target")
end
function GUF.CanResizeFrames()
    local style = GUF.db.general.frameStyle
    local definition = GUF.Layouts.Get(style)
    return definition ~= nil and GUF.Layouts.IsAvailable(style) and definition.allowSize
end

-- Fallback class palette; prefer the client's class-color API when available.
GUF.classColors = {
    HUNTER = { .67, .83, .45 }, WARLOCK = { .53, .53, .93 }, PRIEST = { 1, 1, 1 },
    PALADIN = { .96, .55, .73 }, MAGE = { .25, .78, .92 }, ROGUE = { 1, .96, .41 },
    DRUID = { 1, .49, .04 }, SHAMAN = { 0, .44, .87 }, WARRIOR = { .78, .61, .43 },
    DEATHKNIGHT = { .77, .12, .23 }, DEMONHUNTER = { .64, .19, .79 },
    MONK = { 0, 1, .59 }, EVOKER = { .20, .58, .50 },
}
GUF.colors = {
    hostile = { 1, 0, 0 }, neutral = { 1, 1, 0 }, friendly = { 0, 1, 0 },
    tapped = { .90, .90, .90 }, offline = { .50, .50, .50 }, pet = { 0, 1, 0 },
}
-- Soft red (#FF7171) keeps hostile NPC names readable and visibly red.
GUF.npcHostileNameColor = { 1, 113 / 255, 113 / 255 }
-- Match DinoUnitFrames' reaction Health palette without changing Name colors.
GUF.npcHealthColors = {
    hostile = { .90, 0, 0 }, neutral = { .93, .93, 0 }, friendly = { .20, .90, .20 },
}
GUF.powerColors = {
    MANA = { .30, .50, .85 }, RAGE = { .90, .20, .30 }, FOCUS = { 1, .50, .25 },
    ENERGY = { 1, .85, .10 }, AMMOSLOT = { .85, .60, .55 }, FUEL = { .85, .47, .36 },
    COMBOPOINTS = { 1, .80, 0 }, ALTERNATE = { .815, .941, 1 },
    SOULSHARDS = { .60, .32, .90 },
    RUNES = { .35, .65, 1 },
}

function GUF.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = GUF.Copy(item) end
    return copy
end

GUF.Secret = GUF.Client.IsSecret

-- A nil result means restricted geometry, not an anchorless region.
function GUF.ReadPoints(region)
    local count = region:GetNumPoints()
    if GUF.Secret(count) or type(count) ~= "number" then return end
    local points = {}
    for i = 1, count do
        local point = { region:GetPoint(i) }
        for j = 1, 5 do if GUF.Secret(point[j]) then return end end
        points[i] = point
    end
    return points
end

GUF.Restricted = GUF.Client.StructuralChangesRestricted

function GUF.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff73cfff" .. GUF.title .. ":|r " .. message)
end

-- Conservative schema fallbacks for legacy/missing settings. FactoryDefaults.lua
-- builds the official first-run preset separately, without merging it into users.
GUF.defaults = { version = 13, general = { frameStyle = "blizzard", panelScale = 1 },
    hideBlizzard = { buffs = false, debuffs = false, player = false, pet = false, target = false, targettarget = false,
        focus = false, party = false, raid = false, boss = false, arena = false,
        cast = false, endCaps = false }, frames = {}, threat = {
    enabled = true, width = 48, height = 20, x = 0, y = 0, fontSize = 12, alpha = .85,
    percent = "scaled", showZero = false, artisticDiameter = 28,
    artisticWidth = 52, artisticHeight = 22, rotateOrnament = false,
    ornamentRotation = 12,
} }
for _, unit in ipairs(storedUnitOrder) do
    GUF.defaults.frames[unit] = {
        scale = 1, width = -1, height = -1, healthColor = "class", nameDisplay = unit ~= "pet" and "full" or nil,
        customHealth = { .20, .90, .20 }, nameColor = "class",
        customName = { 1, .82, 0 }, font = "Default", fontSize = 12, nameSize = 12, outline = "OUTLINE",
        healthText = "currentmax", powerText = "currentmax", abbreviate = true,
        hide = { pvp = false, leader = false, combat = false },
        position = { enabled = false, point = "TOPLEFT", anchorTo = "UIParent", relativePoint = "TOPLEFT", x = 0, y = 0 },
        fading = { enabled = false, combat = 1, inactive = .6 },
        combatText = { enabled = false, point = "CENTER", x = 0, y = 0 },
        bars = { healthTexture = "Blizzard", powerTexture = "Blizzard", powerMode = "type",
            width = -1, healthSize = { height = -1 }, powerSize = { height = -1 },
            healAbsorb = { enabled = true, opacity = 1, color = { .68, .47, 1 } },
            incHeal = { enabled = true, opacity = 1, color = { 0, .35, .23 } },
            incAbsorb = { enabled = true, showAtFullHealth = true,
                opacity = .7, color = { 0, .35, .23 } },
            cast = { enabled = true, icon = "HIDE", font = "Default", width = 170, height = 15,
                position = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -30, y = 15 },
                name = { enabled = true, point = "LEFT", size = 0, x = 1, y = 0, outline = "OUTLINE" },
                time = { enabled = true, point = "RIGHT", size = 0, x = -1, y = 0, outline = "OUTLINE" } } },
        indicators = { feedback = { scale = 1, alpha = 1 } }, text = {},
        design = { catalogGeneration = 20261019, portraits = {}, creatures = {}, layered = { enabled = true,
            bar = "blizzard", angles = {} } },
        artistic = { nameClassColor = true, nameBackgroundAlpha = .60, portraitScale = 1, portraitSizingVersion = 1, dragons = true, portrait3D = true,
            playerGeometry = { width = 300, header = 16, health = 38, power = 22 } },
        auras = GUF.AuraDefaults(),
    }
    for _, kind in ipairs({ "name", "level", "health", "power" }) do
        GUF.defaults.frames[unit].text[kind] = { custom = false, font = "Default", size = 12,
            outline = "OUTLINE",
            color = { 1, 1, 1 }, customColor = false, align = "CENTER", x = 0, y = 0,
            split = false, left = "percent", center = "none", right = "current",
            abbreviate = true, hideFull = false }
    end
    for _, kind in ipairs({ "level", "pvp", "leader", "resting", "combat", "resource", "loot", "role" }) do
        GUF.defaults.frames[unit].indicators[kind] = { scale = 1, x = 0, y = 0, alpha = 1,
            point = "DEFAULT", anchor = "frame", size = 0 }
        if kind ~= "level" then GUF.defaults.frames[unit].hide[kind] = false end
    end
end

function GUF.DefaultTextField(kind, side, expression)
    return { enabled = side ~= "center", expression = expression or "", size = 0,
        font = "Default", customFont = false, color = { 1, 1, 1 }, customColor = false,
        point = side == "left" and "LEFT" or side == "right" and "RIGHT" or "CENTER",
        align = side == "left" and "LEFT" or side == "right" and "RIGHT" or "CENTER",
        x = 0, y = 0, padding = 4, width = side == "left" and .65 or .30,
        abbreviate = kind == "health", hideFull = false, useSpareSpace = true }
end

local expressions = { current = "[current]", maximum = "[maximum]", currentmax = "[current] / [maximum]",
    percent = "[percent]", currentpercent = "[current] ([percent])", deficit = "[deficit]", level = "[level]", none = "" }
function GUF.SeedTextFields(cfg, kind, playerDefaults)
    local options = cfg.text[kind]
    if options.fields then return end
    options.fields = {}
    for _, side in ipairs({ "left", "center", "right" }) do
        local mode = options.split and options[side] or side == "left" and cfg[kind .. "Text"] or "none"
        local field = GUF.DefaultTextField(kind, side, expressions[mode] or "")
        field.enabled = mode ~= "none" and mode ~= "blizzard"
        field.abbreviate, field.x, field.y, field.hideFull = options.abbreviate, options.x, options.y, options.hideFull
        options.fields[side] = field
    end
    if playerDefaults then
        local left, right = kind == "health" and "[curmaxhp]" or "[level]", kind == "health" and "[perhp]" or "[abscurpp]"
        options.fields.left, options.fields.right = GUF.DefaultTextField(kind, "left", left), GUF.DefaultTextField(kind, "right", right)
        options.fields.center = GUF.DefaultTextField(kind, "center", "")
        for _, side in ipairs({ "left", "right" }) do
            options.fields[side].x, options.fields[side].y = options.x or 0, options.y or 0
            options.fields[side].hideFull = options.hideFull == true
        end
    end
end

for _, unit in ipairs(storedUnitOrder) do
    local cfg = GUF.defaults.frames[unit]
    for _, kind in ipairs({ "health", "power" }) do
        GUF.SeedTextFields(cfg, kind, unit == "player")
        cfg.text[kind].fieldLayout = unit == "player"
    end
end

-- New Player installations start with the agreed one/two-row aura lanes.
for _, kind in ipairs({ "buffs", "debuffs" }) do
    local aura = GUF.defaults.frames.player.auras[kind][1]
    aura.enabled, aura.maxRows, aura.perRow = true, 2, 8
    aura.anchorPoint, aura.growV, aura.y = kind == "buffs" and "BOTTOMLEFT" or "TOPLEFT",
        kind == "buffs" and "BOTTOM" or "TOP", kind == "buffs" and -6 or 6
end

GUF.defaults.frames.target.auras.replaceDefault = true

-- Preserve both layout schema baselines before FactoryDefaults applies the preset.
-- These explicit false flags survive merging a profile with stock defaults.
for _, cfg in pairs(GUF.defaults.frames) do
    cfg.fading.native = false
    for _, options in pairs(cfg.text) do options.nativeStyle = false end
end
GUF.artisticLayoutDefaults = { frames = GUF.Copy(GUF.defaults.frames), threat = GUF.Copy(GUF.defaults.threat),
    hideBlizzard = GUF.Copy(GUF.defaults.hideBlizzard) }
for unit, cfg in pairs(GUF.defaults.frames) do
    cfg.healthColor = "blizzard"
    cfg.healthText, cfg.powerText = "blizzard", "blizzard"
    cfg.bars.powerMode = "blizzard"
    cfg.bars.cast.font, cfg.bars.cast.icon = "Default", "LEFT"
    cfg.bars.cast.name.point, cfg.bars.cast.name.x = "CENTER", 0
    cfg.bars.cast.name.outline, cfg.bars.cast.time.outline = "", ""
    cfg.bars.cast.time.enabled = false
    cfg.fading.native = true
    cfg.auras = GUF.AuraDefaults()
    if unit == "target" then cfg.auras.replaceDefault = false end
    for _, options in pairs(cfg.text) do
        options.nativeStyle, options.fieldLayout, options.split = true, false, false
        for _, field in pairs(options.fields or {}) do field.enabled = false end
    end
end
GUF.defaults.threat.enabled = false

-- Class resource appearance is fixed; Target enablement is automatic.
function GUF.NormalizeResourceIndicators(frames)
    for unit, cfg in pairs(type(frames) == "table" and frames or {}) do
        if GUF.IsManagedUnit(unit) and type(cfg) == "table" and type(cfg.indicators) == "table" then
            if unit == "target" and type(cfg.hide) == "table" then cfg.hide.resource = false end
            local resource = cfg.indicators.resource
            if type(resource) == "table" then resource.scale, resource.alpha = 1, 1 end
        end
    end
end
GUF.NormalizeResourceIndicators(GUF.defaults.frames)
GUF.NormalizeResourceIndicators(GUF.artisticLayoutDefaults.frames)

local nameOutlines = { [""] = true, OUTLINE = true, THICKOUTLINE = true, ["MONOCHROME,OUTLINE"] = true }
function GUF.NormalizeNameText(frames)
    for unit, cfg in pairs(type(frames) == "table" and frames or {}) do
        if type(cfg) == "table" and (cfg.nameColor == "blizzard" or unit == "player" and cfg.nameColor == "reaction") then
            cfg.nameColor = "class"
        end
        local name = type(cfg) == "table" and type(cfg.text) == "table" and cfg.text.name
        if type(name) == "table" then
            -- Enable direct Name controls once, retaining the effective shared
            -- font settings when the old independent-font switch was off.
            if name.custom ~= true then
                name.font, name.size, name.outline = cfg.font or "Default", cfg.nameSize or 12, cfg.outline or "OUTLINE"
            end
            name.custom, name.nativeStyle = true, false
            if type(name.font) ~= "string" or name.font == "" then
                name.font = type(cfg.font) == "string" and cfg.font ~= "" and cfg.font or "Default"
            end
            local size = name.size
            if type(size) ~= "number" or size ~= size or size == math.huge or size == -math.huge then size = 12 end
            name.size = math.max(6, math.min(16, math.floor(size + .5)))
            cfg.nameSize = name.size
            for _, bounds in ipairs({ { "x", -30, 30 }, { "y", -10, 30 } }) do
                local key, minimum, maximum = bounds[1], bounds[2], bounds[3]
                local value = name[key]
                if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then value = 0 end
                name[key] = math.max(minimum, math.min(maximum, value))
            end
            if type(name.outline) ~= "string" or not nameOutlines[name.outline] then
                name.outline = type(cfg.outline) == "string" and nameOutlines[cfg.outline] and cfg.outline or "OUTLINE"
            end
            -- The Name color dropdown is the sole owner, including legacy
            -- independently colored names.
            if name.customColor and type(name.color) == "table" then
                cfg.nameColor, cfg.customName = "custom", GUF.Copy(name.color)
            end
            name.customColor = false
        end
    end
end
GUF.NormalizeNameText(GUF.defaults.frames)
GUF.NormalizeNameText(GUF.artisticLayoutDefaults.frames)

-- Target's percentage has its own text appearance. Seed missing settings from
-- the old effective threat font once; retain them across profiles/layouts.
function GUF.NormalizeThreatText(frames, legacyThreat, style)
    local cfg = type(frames) == "table" and frames.target
    if type(cfg) ~= "table" or type(cfg.text) ~= "table" then return end
    local function number(value)
        return type(value) == "number" and value == value and math.abs(value) ~= math.huge
    end
    local legacySize = type(legacyThreat) == "table" and legacyThreat.fontSize
    if not number(legacySize) then legacySize = 12 end
    local geometry = type(cfg.artistic) == "table" and cfg.artistic.playerGeometry
    if style == "artistic" and type(geometry) == "table" and number(geometry.header) then
        legacySize = math.max(6, math.min(legacySize, geometry.header - 4))
    end
    local options = type(cfg.text.threat) == "table" and cfg.text.threat or {}
    cfg.text.threat = options
    if type(options.font) ~= "string" or options.font == "" then
        options.font = type(cfg.font) == "string" and cfg.font ~= "" and cfg.font or "Default"
    end
    if not number(options.size) then options.size = legacySize end
    options.size = math.max(6, math.min(16, math.floor(options.size + .5)))
    for _, bounds in ipairs({ { "x", -30, 30 }, { "y", -10, 30 } }) do
        local key, minimum, maximum = bounds[1], bounds[2], bounds[3]
        options[key] = number(options[key]) and math.max(minimum, math.min(maximum, options[key])) or 0
    end
    if not nameOutlines[options.outline] then options.outline = "OUTLINE" end
    if options.align ~= "LEFT" and options.align ~= "CENTER" and options.align ~= "RIGHT" then options.align = "CENTER" end
    options.custom, options.nativeStyle = true, false
    options.shadow, options.shadowX, options.shadowY = nil, nil, nil
end
GUF.NormalizeThreatText(GUF.defaults.frames, GUF.defaults.threat, "blizzard")
GUF.NormalizeThreatText(GUF.artisticLayoutDefaults.frames, GUF.artisticLayoutDefaults.threat, "artistic")

function GUF.NormalizeRankText(frames)
    local cfg = type(frames) == "table" and frames.target
    if type(cfg) ~= "table" or type(cfg.text) ~= "table" then return end
    local options = type(cfg.text.rank) == "table" and cfg.text.rank or {}
    cfg.text.rank = options
    local function number(value)
        return type(value) == "number" and value == value and math.abs(value) ~= math.huge
    end
    if type(options.font) ~= "string" or options.font == "" then options.font = "Default" end
    options.size = number(options.size) and math.max(6, math.min(16, math.floor(options.size + .5))) or 8
    for _, bounds in ipairs({ { "x", -30, 30 }, { "y", -10, 30 } }) do
        local key, minimum, maximum = bounds[1], bounds[2], bounds[3]
        options[key] = number(options[key]) and math.max(minimum, math.min(maximum, options[key])) or 0
    end
    if not nameOutlines[options.outline] then options.outline = "OUTLINE" end
    options.align, options.custom, options.nativeStyle = "CENTER", true, false
    options.shadow, options.shadowX, options.shadowY = nil, nil, nil
end
GUF.NormalizeRankText(GUF.defaults.frames)
GUF.NormalizeRankText(GUF.artisticLayoutDefaults.frames)

local textSides = { "left", "center", "right" }
local function legacyTextFields(cfg, kind, options)
    -- Convert the format that was actually displayed, rather than activating
    -- dormant fields from the old opt-in editor. No live unit data is read.
    local fields = {}
    for _, side in ipairs(textSides) do fields[side] = GUF.DefaultTextField(kind, side, "") end
    local function place(side, expression)
        local field = fields[side]
        field.expression, field.enabled = expression or "", expression ~= nil and expression ~= ""
        field.x, field.y, field.abbreviate = options.x or 0, options.y or 0, options.abbreviate ~= false
        return field
    end
    if options.split then
        for _, side in ipairs(textSides) do place(side, expressions[options[side]]) end
    elseif cfg[kind .. "Text"] == "blizzard" then
        local mode = GetCVar and GetCVar("statusTextDisplay")
        if GUF.Secret(mode) or (mode ~= "BOTH" and mode ~= "NUMERIC" and mode ~= "PERCENT" and mode ~= "NONE") then mode = "BOTH" end
        if mode == "BOTH" then
            place("left", "[percent]").width = .30
            place("right", "[current]").width = .65
        elseif mode ~= "NONE" then
            place("center", mode == "PERCENT" and "[percent]" or "[current] / [maximum]").width = 1
        end
    else
        local field = place("center", expressions[cfg[kind .. "Text"]])
        field.width, field.align = 1, options.align or "CENTER"
    end
    return fields
end

function GUF.NormalizeTextEditors(frames)
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        local text = type(cfg) == "table" and cfg.text
        if type(text) == "table" then
            -- Text shadows are retired; outline is the appearance control.
            for _, kind in ipairs({ "name", "level", "health", "power" }) do
                local options = text[kind]
                if type(options) == "table" then
                    options.shadow, options.shadowX, options.shadowY = nil, nil, nil
                end
            end
            for _, kind in ipairs({ "level", "health", "power" }) do
                local options = text[kind]
                if type(options) == "table" then
                    if options.custom ~= true then
                        options.font, options.size, options.outline = cfg.font or "Default", cfg.fontSize or 12, cfg.outline or "OUTLINE"
                    end
                    options.custom, options.nativeStyle, options.customColor = true, false, true
                    if type(options.font) ~= "string" or options.font == "" then options.font = "Default" end
                    local size = options.size
                    if type(size) ~= "number" or size ~= size or size == math.huge or size == -math.huge then size = 12 end
                    options.size = math.max(6, math.min(40, size))
                    if type(options.outline) ~= "string" or not nameOutlines[options.outline] then
                        options.outline = type(cfg.outline) == "string" and nameOutlines[cfg.outline] and cfg.outline or "OUTLINE"
                    end
                    if kind ~= "level" then
                        if options.fieldLayout ~= true then options.fields = legacyTextFields(cfg, kind, options) end
                        options.fieldLayout, options.hideFull = true, nil
                        if type(options.fields) ~= "table" then options.fields = {} end
                        for _, side in ipairs(textSides) do
                            local field = options.fields[side]
                            if type(field) ~= "table" then field = GUF.DefaultTextField(kind, side, ""); options.fields[side] = field end
                            local hidden = field.enabled == false
                            for key, value in pairs(GUF.DefaultTextField(kind, side, "")) do
                                if field[key] == nil then field[key] = GUF.Copy(value) end
                            end
                            if hidden then field.expression = "" end
                            if type(field.expression) ~= "string" then field.expression = "" end
                            if field.customFont ~= true or type(field.font) ~= "string" or field.font == "" then field.font = options.font end
                            if field.customColor ~= true or type(field.color) ~= "table" then field.color = GUF.Copy(options.color or { 1, 1, 1 }) end
                            field.enabled, field.customFont, field.customColor, field.hideFull = true, true, true, nil
                            GUF.NormalizeBarContent(field, options, side, kind)
                        end
                    end
                end
            end
        end
    end
end
GUF.NormalizeTextEditors(GUF.defaults.frames)
GUF.NormalizeTextEditors(GUF.artisticLayoutDefaults.frames)

function GUF.InitializeDB()
    -- Attach prepares every named profile and supported saved layout through
    -- the settings service before exposing the selected account profile.
    GUF.db = GUF.AttachProfile()
end

function GUF.ParseSpellIDs(text)
    local ids, seen = {}, {}
    for token in (text or ""):gmatch("[^,%s;]+") do
        local id = tonumber(token)
        if not id or id < 1 or id ~= math.floor(id) or id > 2147483647 then
            return nil, "Use positive spell IDs separated by spaces or commas."
        end
        if not seen[id] then ids[#ids + 1], seen[id] = id, true end
    end
    -- Native candidate filters expect sets keyed by spell ID, not lists.
    return seen, nil, ids
end

function GUF.Font(name)
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if name ~= "Default" and media then
        local path = media:Fetch("font", name, true)
        if path then return path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function requestApply(retry, change, source)
    local transitions = GUF.LayoutTransitions
    local request = transitions.Request(GUF.db, GUF.GetRequestedLayout() or GUF.db.general.frameStyle, retry, change, source)
    -- Root opacity remains safely updateable during combat/Edit Mode. Bind its
    -- active-layout settings explicitly before deferring structural work.
    if not GUF.ApplyFadingRequest(request) then GUF.QueueRecovery("request-fading"); return end
    if not GUF.Runtime.ApplyColors(request) then GUF.QueueRecovery("request-colors"); return end
    GUF.BindBlizzardEndCaps(request)
    if change and not retry then
        if GUF.updateQueued then GUF.Updates.stats.coalesced = GUF.Updates.stats.coalesced + 1 end
        GUF.Updates.stats.queued = GUF.Updates.stats.queued + 1
        GUF.updateQueued = request
        return
    end
    GUF.updateQueued = nil
    local targeted, fullReason = GUF.Updates.CanApply(request)
    if GUF.editing or GUF.Restricted() or not GUF.SyncEditModePositions() then
        -- End caps are decorative textures; their visibility also applies in Edit Mode.
        GUF.ApplyBlizzardEndCaps()
        GUF.QueueRecovery("structural-gate")
        transitions.Defer(request, "structural-gate")
        return
    end
    if retry and GUF.Updates.CanRetryCleanup(request) then
        GUF.Updates.RetryCleanup(request)
        return
    end
    local layoutChanged, layoutStatus = GUF.CommitLayoutRequest()
    if layoutStatus == "deferred" then
        GUF.QueueRecovery("layout-commit")
        transitions.Defer(request, "layout-commit")
        return
    end
    -- A discarded/revalidated selection may differ from the queued intent.
    request = transitions.Request(GUF.db, GUF.db.general.frameStyle, true, nil, request.source)
    GUF.BindBlizzardEndCaps(request)
    request.phase, request.reason = "applying", nil
    GUF.Updates.TakeRecovery(request)
    GUF.pending = nil
    if not GUF.Runtime.Capture(request) then GUF.QueueRecovery("request-capture"); return end
    if targeted and not layoutChanged then
        if not GUF.Updates.Apply(request) then
            request.updates.full, request.updates.fullReason = true, "targeted-incomplete"
            GUF.QueueRecovery("targeted-incomplete")
            return
        end
        if transitions.FinishRequest(request) and request.phase == "ready" then GUF.Runtime.Commit(request) end
        return
    end
    request.updates.full = true
    local reason = layoutChanged and "layout-commit" or fullReason or "unclassified"
    request.updates.fullReason = request.updates.fullReason or reason
    GUF.Updates.RecordFull(request, reason)
    local framesReady = GUF.ApplyFrames(request)
    if not transitions.IsCurrent(request, GUF.db.general.frameStyle) then GUF.QueueRecovery("request-superseded"); return end
    if framesReady then
        for _, item in ipairs({ { "auras", GUF.ApplyAuras }, { "visibility", GUF.ApplyBlizzardFrames },
            { "threat", GUF.ApplyThreat } }) do
            if not GUF.Runtime.Apply(nil, item[1], request, item[2]) then break end
            if not transitions.IsCurrent(request, GUF.db.general.frameStyle) then GUF.QueueRecovery("request-superseded"); return end
        end
    end
    if not transitions.FinishRequest(request) then GUF.QueueRecovery("request-incomplete"); return end
    if request.phase == "ready" then GUF.Runtime.Commit(request)
    else GUF.Updates.ParkCleanup(request) end
    local refreshOptions = layoutChanged or layoutStatus == "discarded"
    if GUF.editPositionRefresh then
        GUF.editPositionRefresh = nil
        if GUF.options and GUF.options.page == "units" and GUF.options.tab == "frame" then refreshOptions = true end
    end
    if refreshOptions and GUF.options and GUF.options:IsShown() then GUF.BuildOptions() end
end

function GUF.RequestApply(retry, change, source)
    return GUF.Runtime.Request(requestApply, retry, change, source)
end
