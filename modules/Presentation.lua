local _, GUF = ...

GUF.ArtisticClassificationCrops = { { 136, 0, 256, 20 }, { 216, 20, 256, 80 },
    { 136, 80, 256, 104 }, { 136, 70, 182, 80 } }

function GUF.ArtisticClassificationGeometry(state, crop)
    local scale = state.portraitWidth / 92
    return state.px + (crop[1] - 182) * scale, state.portraitTop + (20 - crop[2]) * scale,
        (crop[3] - crop[1]) * scale, (crop[4] - crop[2]) * scale
end

-- Pure Artistic geometry shared by live frames and synthetic options specimens.
function GUF.ArtisticPresentationGeometry(unit, liveUnit, config, portraitSource)
    local cfg = config or GUF.Runtime.Settings("layout", unit).frames[unit]
    local scale = unit == "pet" and .78 or unit == "targettarget" and .62 or 1
    local width, height = GUF.ArtisticDimensions(unit, config)
    local reference = GUF.ArtisticBasePortraitWidth(unit, config)
    local portrait = GUF.ArtisticPortraitWidth(unit, config)
    local offset = GUF.ArtisticBarOffset(unit, config)
    local center = reference / 2 + (unit == "player" and 0 or 2 * scale)
    local px, py = unit == "target" and width - center or center, -height / 2
    local barWidth, health = GUF.ArtisticBarSize(unit, "health", config)
    local _, power = GUF.ArtisticBarSize(unit, "power", config)
    local barX = (unit == "target" and 2 * scale or px + reference / 2 - 2 * scale) + offset
    local source = portraitSource or GUF.ArtisticPortraitArtwork(unit, liveUnit)
    local refSource = GUF.ArtisticPortraitReferenceArtwork(unit)
    local headerTop = py + (refSource.centerY - refSource.paintTop) * reference / refSource.diameter
    local header = (unit == "player" or unit == "target") and cfg.artistic.playerGeometry.header or 15 * scale
    local healthY = headerTop - header
    local healthRow, powerRow = health + scale, power + 3 * scale
    local powerY = healthY - healthRow
    local g = { width = width, height = height, scale = scale, px = px, py = py,
        referencePortraitWidth = reference, portraitWidth = portrait, portraitHeight = portrait,
        barOffset = offset, barX = barX, barWidth = barWidth + 8 * scale,
        housingX = barX - (unit == "target" and 0 or 28 * scale),
        housingWidth = barWidth + 36 * scale,
        housingEdge = 3 * scale, castBorderInset = 2 * scale, castGap = 6 * scale,
        dividerHeight = scale, healthTopInset = scale, healthFillHeight = health,
        healthRowHeight = healthRow, powerRowHeight = powerRow,
        healthY = healthY, powerY = powerY, powerFillHeight = power,
        statusY = (healthY - scale + powerY - scale - power) / 2,
        headerTop = headerTop, portraitTop = py + portrait / 2,
        portraitBottom = py - portrait / 2, portraitLeft = px - portrait / 2,
        portraitPaintTop = py + (source.centerY - source.paintTop) * portrait / source.diameter,
        portraitPaintBottom = py + (source.centerY - source.paintBottom) * portrait / source.diameter,
        castAnchorBottom = powerY - scale - power }
    local radius, dy = reference / 2, g.castAnchorBottom - py
    local reach = math.sqrt(math.max(0, radius * radius - dy * dy))
    g.castLeft = unit == "target" and barX or px + reach + offset
    g.castRight = unit == "target" and px - reach + offset or barX + g.barWidth
    if unit == "player" then g.statusY = healthY - (healthRow + powerRow) / 2; g.castAnchorBottom = -height + 2 * scale end
    return g
end

-- Header chrome and readable name span have the same public geometry on
-- live and sample surfaces. The caller retains native-write permission checks.
function GUF.LayoutPresentationHeader(entry, state, cfg)
    local scale = state.scale
    local left = entry.unit == "target" and state.barX or state.px + state.barOffset
    local right = entry.unit == "target" and state.px + state.barOffset or state.barX + state.barWidth
    local height = state.headerTop - state.healthY
    local textLeft, textRight = state.barX + 4 * scale, state.barX + state.barWidth - 4 * scale
    state.nameStrip:ClearAllPoints()
    state.nameStrip:SetPoint("TOPLEFT", entry.frame, "TOPLEFT", left, state.headerTop)
    state.nameStrip:SetSize(math.max(1, right - left), height)
    state.nameStrip:LayoutHeader(math.max(1, right - left), height, entry.unit == "target", 6 * scale)
    state.nameStrip:SetAlpha(cfg.artistic.nameBackgroundAlpha)
    GUF.LayoutArtisticThreatName(entry)
    state.nameArea:ClearAllPoints()
    state.nameArea:SetPoint("TOPLEFT", state.nameStrip, "TOPLEFT", textLeft - left, 0)
    state.nameArea:SetPoint("BOTTOMRIGHT", state.nameStrip, "BOTTOMRIGHT", textRight - right, 0)
    state.nameTextWidth = math.max(1, state.barWidth - 16 * scale)
    return height
end

function GUF.PresentationTextSize(cfg, kind, style)
    local options = cfg.text[kind]
    local size = options.custom and options.size or kind == "name" and cfg.nameSize or cfg.fontSize
    if kind == "level" and style ~= "blizzard" then size = size * cfg.indicators.level.scale end
    return size
end

-- One tint operation for live owned bars and public specimen bars.
function GUF.TintPresentationBar(bar, r, g, b)
    bar:SetStatusBarColor(1, 1, 1, 1)
    local fill = bar:GetStatusBarTexture()
    fill:SetAlpha(1)
    if GUF.Secret(r) or r ~= nil then fill:SetVertexColor(r, g, b, 1) end
end

local nameFontFamilies, nameFontSerial = {}, 0
local nameAlphabets = { "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local function nameFontFamily(path, size, flags)
    local base = GameFontNormal
    if not CreateFontFamily or not base or not base.GetFontObjectForAlphabet then return end
    local key = path .. "\031" .. tostring(size) .. "\031" .. flags
    if nameFontFamilies[key] ~= nil then return nameFontFamilies[key] or nil end
    local members = { { alphabet = "roman", file = path, height = size, flags = flags } }
    for _, alphabet in ipairs(nameAlphabets) do
        local ok, font = pcall(base.GetFontObjectForAlphabet, base, alphabet)
        if ok and font and font.GetFont then
            local file = font:GetFont()
            if not GUF.Secret(file) and type(file) == "string" and file ~= "" then
                members[#members + 1] = { alphabet = alphabet, file = file, height = size, flags = flags }
            end
        end
    end
    nameFontSerial = nameFontSerial + 1
    local ok, family = pcall(CreateFontFamily, "GoodUnitFramesNameFont" .. nameFontSerial, members)
    nameFontFamilies[key] = ok and family or false
    return ok and family or nil
end

function GUF.StylePresentationText(text, cfg, options, defaultSize)
    local path = GUF.Font(options.custom and options.font or cfg.font)
    local size = defaultSize or (options.custom and options.size or cfg.fontSize)
    local flags = (options.custom and options.outline or cfg.outline) or ""
    local family = cfg.text and options == cfg.text.name and nameFontFamily(path, size, flags)
    if family then
        -- Preserve the FontString's current tint when replacing its font object.
        -- Alphabet selection belongs to the renderer, including for opaque names.
        local r, g, b, a = text:GetTextColor()
        text:SetFontObject(family)
        text:SetTextColor(r, g, b, a)
    else text:SetFont(path, size, flags) end
    text:SetShadowColor(0, 0, 0, 0)
    text:SetShadowOffset(0, 0)
end

-- Public specimen identity/reaction, never the current live Target's identity.
function GUF.PresentationFrameSettings(entry)
    return entry.configurationPreview and entry.presentationConfig or GUF.Runtime.Settings("layout", entry).frames[entry.unit]
end

-- Text fields can reconcile independently of geometry. Shared text helpers
-- explicitly use the text binding even when called inside another live family.
function GUF.TextFrameSettings(entry)
    return entry.configurationPreview and entry.presentationConfig or GUF.Runtime.Settings("text", entry).frames[entry.unit]
end

function GUF.PreviewPlayerName()
    local name = GetUnitName and GetUnitName("player", true) or UnitName("player")
    if not GUF.Secret(name) and type(name) == "string" and name ~= "" then return name end
    return "Player"
end

function GUF.PreviewNameColor(entry, subject)
    local cfg = GUF.PresentationFrameSettings(entry)
    if cfg.nameColor == "custom" then return unpack(cfg.customName) end
    if cfg.nameColor == "class" and subject == "player" then
        local r, g, b = GUF.ClassColor("player")
        if not GUF.Secret(r) and not GUF.Secret(g) and not GUF.Secret(b)
            and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    local hostile = entry.unit == "target" and subject ~= "player"
    return unpack(hostile and GUF.npcHostileNameColor or GUF.colors.friendly)
end

function GUF.PreviewHealthColor(entry, subject, health, offline)
    local cfg = GUF.PresentationFrameSettings(entry)
    if offline then return .5, .5, .5 end
    if cfg.healthColor == "static" then return unpack(cfg.customHealth) end
    if cfg.healthColor == "percent" then
        return GUF.HealthPercentColor(health / 100)
    end
    if subject ~= "player" and cfg.healthColor == "class" then
        if entry.unit == "pet" then return GUF.ClassColor("player") end
        -- Synthetic creatures match their existing hostile Target Name sample;
        -- never read the currently selected live Target's reaction for a preview.
        return unpack(entry.unit == "target" and GUF.npcHealthColors.hostile or GUF.npcHealthColors.friendly)
    end
    if cfg.healthColor == "blizzard" and entry.unit == "player" then return 0, 1, 0 end
    if subject ~= "player" then return unpack(entry.unit == "target" and GUF.colors.hostile or GUF.colors.friendly) end
    return GUF.ClassColor("player")
end

