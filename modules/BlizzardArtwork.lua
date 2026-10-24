local _, GUF = ...
local unpack = unpack or table.unpack

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Shared with the Blizzard specimen: copy cosmetic metadata only. A native
-- StatusBar's amount-driven UVs must never become an owned full-fill baseline.
function GUF.CopyBlizzardTexture(source, target, saved, fullBar)
    local atlas, file
    if saved then atlas, file = saved.atlas, saved.texture end
    if source then
        if not GUF.Secret(atlas) and not atlas and source.GetAtlas then atlas = source:GetAtlas() end
        if not GUF.Secret(file) and not file and source.GetTexture then file = source:GetTexture() end
    end
    if not GUF.Secret(atlas) and atlas and C_Texture and C_Texture.GetAtlasInfo(atlas) then
        target:SetTexture(nil, "CLAMP", "CLAMP", "LINEAR")
        target:SetAtlas(atlas)
        return true
    elseif not GUF.Secret(file) and file then
        target:SetTexture(file, "CLAMP", "CLAMP", "LINEAR")
        local coords = fullBar and { 0, 1, 0, 1 } or saved and saved.coords or source and { source:GetTexCoord() }
        local readable = coords ~= nil
        for _, value in ipairs(coords or {}) do if not number(value) then readable = false end end
        if readable then target:SetTexCoord(unpack(coords)) end
        return true
    end
    return false
end

local function record(source)
    if not source or not source.GetTexture then return end
    local result = { atlas = source.GetAtlas and source:GetAtlas(), texture = source:GetTexture(), coords = { source:GetTexCoord() } }
    if GUF.Secret(result.atlas) or GUF.Secret(result.texture) then return end
    for _, value in ipairs(result.coords) do if not number(value) then return end end
    if not result.texture and not result.atlas then return end
    return result
end

local function crop(surface, outer, left, bottom, right, top)
    local width, height = outer.right - outer.left, outer.top - outer.bottom
    if width <= 0 or height <= 0 then return end
    local function clamp(value) return math.max(0, math.min(1, value)) end
    local result = { surface = surface, left = clamp((left - outer.left) / width), right = clamp((right - outer.left) / width),
        top = clamp((outer.top - top) / height), bottom = clamp((outer.top - bottom) / height) }
    if result.right <= result.left or result.bottom <= result.top then return end
    return result
end

-- Called before Artistic changes unit geometry. The rectangles are static
-- artwork/bar frames, never native fill textures, amounts, ranges or alpha.
function GUF.CaptureBlizzardArtwork(entry)
    if entry.blizzardArtwork or GUF.Restricted() or GUF.editing then return end
    -- Read the existing native restore snapshots; never overwrite them or
    -- recapture the geometry currently owned by Artistic. This also permits
    -- a late native initialization to complete an initially unavailable capture.
    local geometry = {}
    for _, saved in ipairs(entry.sizeRegions or {}) do geometry[saved.region] = saved end
    geometry[entry.frame] = { width = entry.original.width, height = entry.original.height, points = {} }
    local container = entry.frame.PlayerFrameContainer or entry.frame.TargetFrameContainer or entry.frame
    local chrome = container.FrameTexture or entry.frame.FrameTexture or entry.frame.Texture
        or _G[entry.frame:GetName() .. "Texture"]
    local face = container.PlayerPortrait or container.Portrait or entry.frame.portrait or entry.frame.Portrait
        or _G[entry.frame:GetName() .. "Portrait"]
    local surface = record(chrome)
    local outer = surface and GUF.FrameRectInUnit(entry, chrome, geometry)
    local portrait = face and GUF.FrameRectInUnit(entry, face, geometry)
    local health = entry.health and GUF.FrameRectInUnit(entry, entry.health, geometry)
    local power = entry.power and GUF.FrameRectInUnit(entry, entry.power, geometry)
    if not outer or not portrait or not health or not power
        or outer.right <= outer.left or outer.top <= outer.bottom then return end
    local faceSize = math.min(portrait.right - portrait.left, portrait.top - portrait.bottom)
    if faceSize <= 0 or health.right <= health.left or health.top <= health.bottom
        or power.right <= power.left or power.top <= power.bottom then return end
    local diameter = faceSize + 10
    local x, y = (portrait.left + portrait.right) / 2, (portrait.top + portrait.bottom) / 2
    local artwork = { portrait = crop(surface, outer, x - diameter / 2, y - diameter / 2,
        x + diameter / 2, y + diameter / 2), openingRatio = faceSize / diameter, fills = {} }
    local left, right = math.min(health.left, power.left) - 3, math.max(health.right, power.right) + 3
    local bottom, top = math.min(health.bottom, power.bottom) - 3, math.max(health.top, power.top) + 3
    artwork.bars = crop(surface, outer, left, bottom, right, top)
    if not artwork.portrait or not artwork.bars then return end
    artwork.bars.edgeX = math.min(.25, 3 / (right - left))
    artwork.bars.edgeY = math.min(.25, 3 / (top - bottom))
    -- A stack's full side contains the native Health/Power junction. Keep
    -- that original crop for existing callers, but give the Artistic stack
    -- short straight samples from the far end of the native Power row. These
    -- are static chrome/frame rectangles, never amount-driven fill geometry.
    local powerWidth, powerHeight = power.right - power.left, power.top - power.bottom
    local sampleX = power.left + powerWidth * (entry.unit == "target" and .25 or .75)
    local sampleY = (power.top + power.bottom) / 2
    local halfX, halfY = math.min(2, powerWidth / 8), math.min(.5, powerHeight / 8)
    local farX = entry.unit == "target" and power.left - 3 or power.right
    artwork.bars.stack = { farLeft = entry.unit == "target",
        edgeLeft = (farX - left) / (right - left), edgeRight = (farX + 3 - left) / (right - left),
        edgeTop = (top - power.bottom) / (top - bottom), edgeBottom = (top - power.bottom + 3) / (top - bottom),
        left = (sampleX - halfX - left) / (right - left),
        right = (sampleX + halfX - left) / (right - left),
        top = (top - sampleY - halfY) / (top - bottom),
        bottom = (top - sampleY + halfY) / (top - bottom) }
    local level = entry.main and entry.main.LevelBackgroundCircle
    local levelSurface = record(level)
    if levelSurface then artwork.level = { surface = levelSurface, left = 0, right = 1, top = 0, bottom = 1 } end
    for _, kind in ipairs({ "health", "power" }) do
        local bar = entry[kind]
        local fill = bar and bar:GetStatusBarTexture()
        if fill then
            local saved = entry.barStyles and entry.barStyles[kind]
            local atlas, texture
            if saved then atlas, texture = saved.atlas, saved.texture
            else atlas, texture = fill.GetAtlas and fill:GetAtlas(), fill:GetTexture() end
            if not GUF.Secret(atlas) and not GUF.Secret(texture) then
                artwork.fills[kind] = { atlas = atlas, texture = texture }
            end
        end
    end
    local content = entry.frame.TargetFrameContent
    local context = content and content.TargetFrameContentContextual
    local threat = context and context.NumericalThreat or entry.frame.NumericalThreat
    if threat and threat.GetRegions then
        for _, region in ipairs({ threat:GetRegions() }) do
            if region:GetObjectType() == "Texture" and region ~= threat.bg and region:GetDrawLayer() == "ARTWORK" then
                artwork.threat = record(region)
                if artwork.threat then break end
            end
        end
    end
    entry.blizzardArtwork = artwork
end

local function artwork(unit)
    local entry = GUF.frames[unit or "player"]
    if entry then GUF.CaptureBlizzardArtwork(entry) end
    if entry and entry.blizzardArtwork then return entry.blizzardArtwork end
    local player = GUF.frames.player
    if player then GUF.CaptureBlizzardArtwork(player) end
    if player and player.blizzardArtwork then return player.blizzardArtwork end
    GUF.pending = true
end

local rings = {}
function GUF.BlizzardRingArtwork(unit, level)
    local key = (unit or "player") .. (level and "-level" or "-portrait")
    local source = rings[key]
    local art = artwork(unit)
    if not source or source.snapshot ~= art then
        source = { id = "blizzard", native = true, unit = unit, level = level,
            snapshot = art, canvas = 1, diameter = 1, centerX = .5, centerY = .5, paintTop = 0, paintBottom = 1,
            openingRatio = level and .76 or art and art.openingRatio or .84 }
        rings[key] = source
    end
    return source
end

-- Crop the client's captured chrome. Bilinear UV interpolation also preserves
-- flipped atlas/legacy textures, without reading native bar fill coordinates.
local function draw(target, piece, left, top, right, bottom)
    if not piece then target:Hide(); return false end
    left, top, right, bottom = left or 0, top or 0, right or 1, bottom or 1
    if target.goodUnitFramesBlizzardPiece == piece
        and target.goodUnitFramesBlizzardCrop == table.concat({ left, top, right, bottom }, ":") then
        target:Show(); return true
    end
    if not GUF.CopyBlizzardTexture(nil, target, piece.surface) then target:Hide(); return false end
    local coords = piece.surface.coords or { target:GetTexCoord() }
    for _, value in ipairs(coords) do if not number(value) then target:Hide(); return false end end
    if #coords == 4 then coords = { coords[1], coords[3], coords[1], coords[4], coords[2], coords[3], coords[2], coords[4] } end
    if #coords ~= 8 then target:Hide(); return false end
    local function uv(x, y)
        x, y = piece.left + (piece.right - piece.left) * x, piece.top + (piece.bottom - piece.top) * y
        local u = coords[1] * (1-x) * (1-y) + coords[3] * (1-x) * y + coords[5] * x * (1-y) + coords[7] * x * y
        local v = coords[2] * (1-x) * (1-y) + coords[4] * (1-x) * y + coords[6] * x * (1-y) + coords[8] * x * y
        return u, v
    end
    local a,b = uv(left,top); local c,d = uv(left,bottom); local e,f = uv(right,top); local g,h = uv(right,bottom)
    target:SetTexCoord(a,b,c,d,e,f,g,h)
    target.goodUnitFramesBlizzardPiece = piece
    target.goodUnitFramesBlizzardCrop = table.concat({ left, top, right, bottom }, ":")
    target:Show()
    return true
end

function GUF.PlaceBlizzardRing(target, source, parent, diameter)
    local art = artwork(source.unit)
    local piece = art and art.portrait
    if source.level then
        local player = artwork("player")
        piece = art and art.level or player and player.level or piece
    end
    target:ClearAllPoints(); target:SetPoint("CENTER", parent, "CENTER"); target:SetSize(diameter, diameter)
    if not draw(target, piece) then return end
    local mask = target.goodUnitFramesBlizzardMask
    if not mask then
        if not parent.configurationPreview and (GUF.Restricted() or GUF.editing) then
            GUF.pending = true; target:Hide(); return
        end
        mask = target:GetParent():CreateMaskTexture(nil, "ARTWORK")
        mask.goodUnitFramesOwned = true
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
        mask:SetAllPoints(target)
        target.goodUnitFramesBlizzardMask = mask
    end
    if not target.goodUnitFramesBlizzardMaskAttached then
        target:AddMaskTexture(mask); target.goodUnitFramesBlizzardMaskAttached = true
    end
end

function GUF.PaintBlizzardBarSlice(target, unit, row, column)
    local art = artwork(unit)
    if not art then target:Hide(); return end
    local piece = art.bars
    local xs, ys = { 0, piece.edgeX, 1 - piece.edgeX, 1 }, { 0, piece.edgeY, 1 - piece.edgeY, 1 }
    draw(target, piece, xs[column], ys[row], xs[column+1], ys[row+1])
end

-- Only the Artistic Name/Health/Power stack opts into these clean strips.
-- Reuse the captured far bottom corner, reflected for the other corners, so
-- every join has the same native metal colors rather than unrelated crops.
function GUF.PaintBlizzardStackSlice(target, unit, row, column)
    -- Player's native chrome is the approved stack reference. Target's native
    -- end-cap crop has a different profile, so reuse Player's samples and let
    -- the column reflection below mirror them onto Target's owned border.
    -- This does not change Target's native capture, portrait, fills or bounds.
    local art = artwork(unit == "target" and "player" or unit)
    local piece = art and art.bars
    local stack = piece and piece.stack
    if not stack then target:Hide(); return end
    local left, right = stack.left, stack.right
    if column ~= 2 then
        left, right = stack.edgeLeft, stack.edgeRight
        if (column == 1) ~= stack.farLeft then left, right = right, left end
    end
    local top, bottom = stack.top, stack.bottom
    if row == 1 then top, bottom = stack.edgeBottom, stack.edgeTop
    elseif row == 3 then top, bottom = stack.edgeTop, stack.edgeBottom end
    draw(target, piece, left, top, right, bottom)
end

function GUF.PaintBlizzardBarFill(target, unit, kind, saved)
    local art = artwork(unit)
    local fill = saved or art and art.fills[kind]
    if fill and GUF.CopyBlizzardTexture(nil, target, fill, true) then
        -- Match the existing configurable/native bar tint path. Baked atlas hue
        -- must not multiply the requested class/reaction/custom fill color.
        target:SetDesaturated(true)
        return true
    end
end

function GUF.PaintBlizzardThreatBorder(target)
    local art = artwork("target")
    return art and art.threat and GUF.CopyBlizzardTexture(nil, target, art.threat)
end
