local _, GUF = ...

-- Independent first-use settings. Existing profiles and other layout snapshots
-- are never reseeded when this definition becomes available.
local defaults = { frames = GUF.Copy(GUF.defaults.frames), threat = GUF.Copy(GUF.defaults.threat),
    hideBlizzard = GUF.Copy(GUF.defaults.hideBlizzard) }
defaults.threat.enabled = false
defaults.hideBlizzard.cast = false
for _, unit in ipairs(GUF.order) do
    local cfg = defaults.frames[unit]
    cfg.flat = { portrait = unit == "player" and "LEFT" or "RIGHT", backgroundAlpha = .35 }
    cfg.scale, cfg.fontSize, cfg.nameSize = 1, 12, 12
    cfg.bars.width, cfg.bars.healthSize.height, cfg.bars.powerSize.height = 280, 34, 18
    cfg.bars.healthTexture, cfg.bars.powerTexture = "Flat", "Flat"
    cfg.position = { enabled = true, point = "CENTER", anchorTo = "UIParent", relativePoint = "CENTER",
        x = unit == "player" and -320 or 320, y = -140 }
    cfg.bars.cast.enabled, cfg.bars.cast.height, cfg.bars.cast.icon = true, 14, "HIDE"
    cfg.bars.cast.texture = "Flat"
    cfg.bars.cast.position = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 0, y = 0 }
    cfg.text.name.align, cfg.text.name.x, cfg.text.name.y = "LEFT", 0, 0
    for _, kind in ipairs({ "health", "power" }) do
        local text = cfg.text[kind]
        text.fieldLayout, text.nativeStyle, text.custom = true, false, true
        text.fields = {}
        for _, side in ipairs({ "left", "center", "right" }) do
            local expression = side == "right" and "[current] / [maximum]"
                or side == "left" and kind == "power" and "[level] [percent]" or ""
            local field = GUF.DefaultTextField(kind, side, expression)
            field.enabled, field.width = true, side == "right" and .52 or .48
            text.fields[side] = field
        end
    end
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        local aura = cfg.auras[kind][1]
        aura.enabled, aura.size, aura.perRow, aura.maxRows = true, 22, 10, 2
        aura.anchorPoint, aura.growV = kind == "buffs" and "TOPLEFT" or "BOTTOMLEFT", kind == "buffs" and "TOP" or "BOTTOM"
        aura.x, aura.y = 0, kind == "buffs" and 6 or -6
    end
end

GUF.Layouts.Register({
    id = "flat", title = "Flat", order = 30,
    description = "Clean rectangular bars with optional square portraits and integrated resources and casting.",
    units = { player = true, target = true }, defaults = defaults, allowSize = false,
    scale = { minimum = .75, maximum = 1.5, step = .01, nativeSetting = false },
    capabilities = function(unit)
        local private = GUF.Client.GetPrivateAuraAPI()
        return { flat = true, artwork = false, design = false, barGeometry = true,
            classResources = GUF.UsesSegmentedResources(unit, true), roleIndicator = true,
            raid = true, classification = false, levelText = false, threat = false,
            bossAuras = unit == "player" and private ~= nil }
    end,
    renderCard = function(parent, entry) return GUF.FlatLayoutCard(parent, entry) end,
    presentation = {
        nativeBarColors = false,
        dimensions = function(unit, cfg) local g = GUF.FlatGeometry(cfg); return g.width, g.height end,
        createSample = function(unit, parent) return GUF.CreateFlatSpecimen(unit, parent) end,
        renderSample = function(entry, scenario, context) return GUF.RenderFlatSample(entry, scenario, context) end,
        geometry = function(context) return GUF.FlatGeometry(context.settings.frames[context.unit]) end,
        role = function(entry, role) return GUF.FlatPresentationRole(entry, role) end,
        bounds = function(context) return GUF.FlatPresentationBounds(context) end,
        syncBar = function(entry, kind) return GUF.SyncFlatBar(entry, kind) end,
        suppressBars = function(entry) return GUF.SuppressFlatNative(entry) end,
        refreshText = function(entry) return GUF.RefreshFlatName(entry) end,
        layoutResources = function(entry) return GUF.LayoutFlatResources(entry) end,
        anchorCast = function(entry, bar) return GUF.AnchorFlatCast(entry, bar) end,
        nativeOriginal = function(entry, region) return GUF.FlatNativeOriginal(entry, region) end,
    },
    live = {
        apply = function(entry) return GUF.ApplyFlatLayout(entry) end,
        release = function(entry) return GUF.ReleaseFlatLayout(entry) end,
        finalize = function(entry) return GUF.FinalizeFlatLayout(entry) end,
        recover = function(entry) return GUF.ReleaseFlatLayout(entry) end,
        pending = function(entry) return entry.flatLayout and entry.flatLayout.restorePending end,
        cleanupReady = function(entry) return GUF.FlatCleanupReady(entry) end,
        refreshGeometry = function(entry, region, geometry) return GUF.RefreshFlatNativeGeometry(entry, region, geometry) end,
        writerStates = function(entry) return entry.flatLayout and { entry.flatLayout } or {} end,
    },
})
