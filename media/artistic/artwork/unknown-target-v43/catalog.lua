local _, GUF = ...
-- Type-independent fallback. No creature type ID is inferred or fabricated.
GUF.creaturePortraitDesigns = GUF.creaturePortraitDesigns or {}
local root = "Interface\\AddOns\\GoodUnitFrames\\media\\artistic\\artwork\\unknown-target-v43\\"
local level = { levelX = 0.3535533905932738, levelY = -0.3535533905932738, levelRatio = 0.3464566929133858 }
local sources = {}
GUF.creaturePortraitDesigns.unknown = sources
local bounds = { normal = { 102, 1022 }, rare = { 100, 1021 }, elite = { 86, 1021 }, rareelite = { 93, 1021 } }
for _, rank in ipairs({ "normal", "rare", "elite", "rareelite" }) do
    sources[rank] = { id = "unknown-" .. rank .. "-v43", name = "Unknown " .. rank,
        creature = true, unknown = true, rank = rank, combined = true, targetOnly = true, noStatus = true,
        sockets = level, textureFile = root .. rank .. "\\portrait-mipmapped.blp",
        mask = root .. rank .. "\\portrait-mask-target.tga",
        canvas = 1254, centerX = 474, centerY = 530, diameter = 650, openingRatio = 1.02,
        paintTop = bounds[rank][1], paintBottom = bounds[rank][2] }
end
