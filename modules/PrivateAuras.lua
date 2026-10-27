local _, GUF = ...
local Client = GUF.Client

local function clear(host)
    if not host then return end
    host.container:Hide()
    host.signature = nil
    local api = host.privateAuraAPI
    if api then
        for key, id in pairs(host.anchors) do api.removeAnchor(id); host.anchors[key] = nil end
    end
    host.anchors, host.signature, host.privateAuraAPI = {}, nil, nil
end

function GUF.ApplyPrivateAuras()
    local entry, cfg = GUF.frames.player, GUF.Runtime.Settings("auras", "player").frames.player
    local settings, host = cfg.auras.bossDebuffs, GUF.privateAuraHost
    if not entry or not settings.enabled then clear(host); return end
    local api = Client.GetPrivateAuraAPI()
    if not api then
        clear(host)
        if not GUF.privateAuraUnavailable then
            GUF.Print("Boss debuffs require Blizzard's private-aura API, which is unavailable on this client.")
            GUF.privateAuraUnavailable = true
        end
        return "unavailable", "private-aura-api"
    end
    local signature = table.concat({ settings.size, settings.perRow, settings.maxRows, settings.anchorPoint,
        settings.x, settings.y, tostring(settings.showCooldown), tostring(settings.showCooldownNumbers) }, ":")
    if host and host.signature == signature and host.privateAuraAPI
        and host.privateAuraAPI.addAnchor == api.addAnchor
        and host.privateAuraAPI.removeAnchor == api.removeAnchor then return end
    clear(host)
    if not host then
        host = { anchors = {}, container = GUF.Runtime.CreateFrame("Frame", nil, entry.frame) }
        GUF.privateAuraHost = host
        host.container.goodUnitFramesOwned = true
        host.container:SetFrameStrata("MEDIUM")
    end
    local container, baseSize = host.container, 32
    local scale = settings.size / baseSize
    -- Scale the complete native icon/countdown rather than touching private regions.
    container:SetScale(scale)
    container:SetSize(settings.perRow * 34 - 2, settings.maxRows * 34 - 2)
    container:ClearAllPoints()
    container:SetPoint("CENTER", settings.anchorPoint == "FREE" and UIParent or entry.frame,
        settings.anchorPoint == "FREE" and "CENTER" or settings.anchorPoint, settings.x / scale, settings.y / scale)
    container:SetFrameLevel(entry.frame:GetFrameLevel() + 7)
    host.privateAuraAPI = api
    local ok, err = pcall(function()
        for i = 1, settings.perRow * settings.maxRows do
            local id = api.addAnchor({
                unitToken = "player", auraIndex = i, parent = container, isContainer = false,
                showCountdownFrame = settings.showCooldown, showCountdownNumbers = settings.showCooldownNumbers,
                iconInfo = { iconWidth = baseSize, iconHeight = baseSize, borderScale = baseSize / 18,
                    iconAnchor = { point = "TOPLEFT", relativeTo = container, relativePoint = "TOPLEFT",
                        offsetX = ((i - 1) % settings.perRow) * 34,
                        offsetY = -math.floor((i - 1) / settings.perRow) * 34 } },
            })
            if id then host.anchors[i] = id end
        end
    end)
    if not ok then
        clear(host)
        if not GUF.privateAuraErrorReported then
            GUF.Print("Boss debuffs could not start. " .. tostring(err))
            GUF.privateAuraErrorReported = true
        end
        return "failed", "private-aura-registration"
    end
    host.signature = signature
    container:Show()
    -- Do not expose the baseline between configuration and the queued pass.
    GUF.RefreshCastAuraPositions(entry)
    GUF.QueueCastAuraPositions(entry)
end
