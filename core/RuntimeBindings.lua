local _, GUF = ...
local Runtime = GUF.Runtime

-- These are mutation entry points reached from native hooks, events or owned
-- drivers. Pure selectors and synthetic specimen renderers remain ordinary
-- functions; their explicit config arguments keep their existing semantics.
Runtime.Wrap("layout", { "UpdateArtisticState", "UpdateArtisticPortrait", "UpdateArtisticPortraitArtwork",
    "SyncArtisticRenderedBar", "SyncArtisticPowerLayout", "RefreshArtisticBarPresentation",
    "RestoreArtisticBarGeometry", "RestoreArtisticPlayerNameAnchor", "LayoutArtisticRenderedLayers",
    "LayoutArtisticResources", "UpdateArtisticResources", "UpdateComboPoints", "LayoutTargetComboStack",
    "UpdateAutomaticIndicators", "AnimateRetailResourceRow" })
Runtime.Wrap("colors", { "UpdateColors" })
Runtime.Wrap("bars", { "ApplyBars" })
Runtime.Wrap("text", { "UpdateUnitName", "UpdateBarText", "StyleText", "ApplyText" })
Runtime.Wrap("predictions", { "UpdatePredictionBars", "ApplyPredictionBars" })
Runtime.Wrap("cast", { "ApplyCastBar", "ApplyNativeCastBar", "PositionCastBar", "LayoutCastLabels" })
Runtime.Wrap("auras", { "RefreshCastAuraPositions", "ApplyLiveCastAuraLayout", "RefreshUnitAuras" })
Runtime.Wrap("auras", { "UpdateAuraEnchants", "ApplyNativeAuraVisibility" }, "player")
Runtime.Wrap("visibility", { "ApplyBlizzardFrames" })
Runtime.Wrap("threat", { "ApplyThreat", "UpdateThreat" })

for _, name in ipairs({ "CreateFrameSpecimen", "RenderFrameSpecimen", "PreviewCombatText", "PreviewComboPoints", "BuildOptions" }) do
    local render = GUF[name]
    if type(render) ~= "function" then error("Missing specimen callback: " .. name) end
    GUF[name] = function(...) return Runtime.Sample(render, ...) end
end

for _, name in ipairs({ "RefreshAuraPreview", "TickSpecimenAuras" }) do
    local render = GUF[name]
    GUF[name] = function(entry, ...)
        if entry and entry.configurationPreview and entry.presentationContext then
            return GUF.Presentation.With(entry.presentationContext, render, entry, ...)
        end
        return render(entry, ...)
    end
end
