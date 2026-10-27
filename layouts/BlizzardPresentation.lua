local _, GUF = ...

function GUF.CreateBlizzardSpecimen(unit, parent)
    return GUF.CreateSpecimenBase(unit, parent, "blizzard")
end

function GUF.RenderBlizzardSample(entry, options)
    if options.subject ~= "player" then options.powerToken = "MANA" end
    local geometry = GUF.Presentation.Geometry(entry)
    if not geometry or geometry.width <= 0 or geometry.height <= 0 then return "deferred", "native-geometry" end
    if not GUF.OptionsUI.RenderBlizzardSpecimen(entry, options) then return "unavailable", "native-presentation" end
    local cfg, bar = GUF.PresentationFrameSettings(entry), entry.castBar
    local casting = options.states.casting or options.states.channel
    entry.previewCasting = casting and true or nil
    bar:SetMinMaxValues(0, 1); bar:SetValue(casting and .65 or 0)
    bar.name:SetText(casting and (options.states.channel and "Channeling" or "Aimed Shot") or "")
    bar.time:SetText(casting and "2.1" or "")
    bar.spark:SetShown(casting == true)
    bar:SetShown(not options.layoutCard and (casting or options.showAll and cfg.bars.cast.enabled) or false)
    entry.frame:SetAlpha(options.layoutCard and 1 or cfg.fading.enabled
        and (options.states.combat and cfg.fading.combat or cfg.fading.inactive) or 1)
    entry.frame:Show()
    return "applied"
end

function GUF.BlizzardPresentationGeometry(context)
    local entry = context.view
    local native = context.mode == "live" and entry or GUF.frames[context.unit]
    local original = native and native.original
    local width, height = original and original.width, original and original.height
    if GUF.Secret(width) or GUF.Secret(height) or type(width) ~= "number" or type(height) ~= "number"
        or width ~= width or height ~= height or math.abs(width) == math.huge or math.abs(height) == math.huge then return end
    return { width = width, height = height, scale = 1 }
end

function GUF.BlizzardPresentationRole(entry, role)
    local presentation = entry.blizzardPresentation
    if role == "root" then return entry.frame end
    if role == "castAnchor" then return entry.power or entry.health or entry.frame end
    if role == "health" or role == "power" then return entry[role] end
    if role == "healthText" or role == "powerText" then
        local kind = role == "healthText" and "health" or "power"
        return entry[kind]
    end
    if role == "healthAnchor" or role == "powerAnchor" then return entry[role == "healthAnchor" and "health" or "power"] end
    if role == "name" then
        return presentation and presentation.nameArea or entry.nameBackground
            or entry.healthArea ~= entry.main and entry.healthArea or entry.health
    end
    if role == "auraTop" or role == "auraBottom" then return entry.frame end
    if role == "cast" then return entry.configurationPreview and entry.castBar or GUF.NativeCastBar(entry) end
    if role == "portrait" then
        if presentation then return presentation.portrait end
        local frame = entry.frame
        local container = frame.PlayerFrameContainer or frame.TargetFrameContainer or frame
        return container.PlayerPortrait or container.Portrait or frame.portrait or frame.Portrait
    end
end
