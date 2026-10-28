local _, GUF = ...

GUF.Layouts.Register({
    id = "artistic", title = "Artistic", order = 20,
    description = "Class and Monster Specific Artwork. Flexible Bars. Highly Customizable",
    units = { player = true, target = true },
    defaults = GUF.factoryLayoutDefaults.artistic,
    allowSize = false,
    scale = { minimum = .75, maximum = 1.5, step = .01, nativeSetting = false },
    capabilities = function(unit)
        return { artwork = true, design = unit == "player" or unit == "target",
            barGeometry = unit == "player" or unit == "target", levelIndicator = false,
            classResources = GUF.UsesSegmentedResources(unit, true),
            roleIndicator = unit == "player" or unit == "target", raid = true,
            classification = unit == "target", threatRotation = false,
            bossAuras = unit == "player", levelText = false, threat = unit == "target" }
    end,
    renderCard = function(parent, entry)
        return GUF.OptionsUI.ArtisticLayoutCard(parent, entry)
    end,
    presentation = {
        nativeBarColors = false,
        syncBar = function(entry, kind) return GUF.SyncArtisticRenderedBar(entry, kind) end,
        suppressBars = function(entry) return GUF.SuppressArtisticNativeBars(entry) end,
        dimensions = function(unit, config) return GUF.ArtisticDimensions(unit, config) end,
        createSample = function(unit, parent) return GUF.CreateArtisticSpecimen(unit, parent) end,
        renderSample = function(entry, scenario, context) return GUF.RenderArtisticSample(entry, scenario, context) end,
        geometry = function(context) return GUF.ArtisticGeometryFromContext(context) end,
        role = function(entry, role) return GUF.ArtisticPresentationRole(entry, role) end,
        bounds = function(context) return GUF.Presentation.LayoutBounds(context) end,
        layoutResources = function(entry, force) return GUF.LayoutArtisticResourceStack(entry, force) end,
        positionThreat = function(entry, frame) return GUF.PositionArtisticThreat(entry, frame) end,
        threatVisibility = function(entry, frame, show) return GUF.SetArtisticThreatVisible(entry, frame, show) end,
        renderThreatSample = function(entry, shown) return GUF.RenderArtisticThreatSample(entry, shown) end,
        nativeOriginal = function(entry, region) return GUF.ArtisticNativeOriginal(entry, region) end,
        paintedBounds = function(entry, region) return GUF.ArtisticPaintedBounds(entry, region) end,
    },
    live = {
        release = function(entry) return GUF.ReleaseArtisticLayout(entry) end,
        apply = function(entry) return GUF.ApplyArtisticLayout(entry) end,
        finalize = function(entry) return GUF.FinalizeArtisticLayout(entry) end,
        writerStates = function(entry, shallow) return GUF.ArtisticWriterStates(entry, shallow) end,
        recover = function(entry)
            if entry.artisticLayout and entry.artisticLayout.created then GUF.ReleaseArtisticLayout(entry) end
        end,
        pending = function(entry) return entry.artisticLayout and entry.artisticLayout.restorePending end,
        cleanupReady = function(entry) return GUF.ArtisticCleanupReady(entry) end,
        refreshGeometry = function(entry, region, geometry) return GUF.RefreshArtisticNativeGeometry(entry, region, geometry) end,
    },
})
