local _, GUF = ...

-- Shared sizing and feature passes already handle native presentation.
local function noLiveChanges() end

GUF.Layouts.Register({
    id = "blizzard", title = "Blizzard", order = 10,
    description = "Default blizzard frames with simple modifications",
    units = { player = true, target = true },
    defaults = GUF.factoryLayoutDefaults.blizzard,
    allowSize = false,
    scale = { minimum = 1, maximum = 1.5, step = .01, nativeSetting = true },
    capabilities = function(unit)
        return { artwork = false, design = false, barGeometry = false,
            levelIndicator = false, classResources = false,
            roleIndicator = unit == "player", raid = false, classification = false,
            threatRotation = false, bossAuras = unit == "player",
            levelText = unit == "player" or unit == "target", threat = false }
    end,
    renderCard = function(parent, entry)
        return GUF.OptionsUI.BlizzardLayoutCard(parent, entry)
    end,
    presentation = {
        nativeBarColors = true,
        createSample = function(unit, parent) return GUF.CreateBlizzardSpecimen(unit, parent) end,
        renderSample = function(entry, scenario, context) return GUF.RenderBlizzardSample(entry, scenario, context) end,
        geometry = function(context) return GUF.BlizzardPresentationGeometry(context) end,
        role = function(entry, role) return GUF.BlizzardPresentationRole(entry, role) end,
        bounds = function(context) return GUF.Presentation.LayoutBounds(context) end,
    },
    live = {
        release = function(entry) return GUF.ReleaseBlizzardPlayerRole(entry) end,
        apply = function() return "applied" end,
        finalize = noLiveChanges,
    },
})
