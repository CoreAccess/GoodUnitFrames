local _, GUF = ...

GUF.Layouts.Register({
    id = "flat", title = "Flat", order = 30,
    description = "Clean rectangular bars with optional square portraits and integrated resources and casting.",
    units = { player = true, target = true }, defaults = GUF.factoryLayoutDefaults.flat, allowSize = false,
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
