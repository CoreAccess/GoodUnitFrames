local _, GUF = ...

local function clear(host)
    if not host then return end
    if C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor then
        for _, id in pairs(host.anchors) do C_UnitAuras.RemovePrivateAuraAnchor(id) end
    end
    host.anchors, host.signature = {}, nil
    host.container:Hide()
end

function GUF.ApplyPrivateAuras()
    local entry, cfg = GUF.frames.player, GUF.db.frames.player
    local settings, host = cfg.auras.bossDebuffs, GUF.privateAuraHost
    if not entry or not settings.enabled then clear(host); return end
    if not C_UnitAuras or not C_UnitAuras.AddPrivateAuraAnchor then
        clear(host)
        if not GUF.privateAuraUnavailable then
            GUF.Print("Boss debuffs require Blizzard's private-aura API, which is unavailable on this client.")
            GUF.privateAuraUnavailable = true
        end
        return
    end
    local signature = table.concat({ settings.size, settings.perRow, settings.maxRows, settings.anchorPoint,
        settings.x, settings.y, tostring(settings.showCooldown), tostring(settings.showCooldownNumbers) }, ":")
    if host and host.signature == signature then return end
    clear(host)
    if not host then
        host = { anchors = {}, container = CreateFrame("Frame", nil, entry.frame) }
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
    local ok, err = pcall(function()
        for i = 1, settings.perRow * settings.maxRows do
            local id = C_UnitAuras.AddPrivateAuraAnchor({
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
        return
    end
    host.signature = signature
    container:Show()
    -- Do not expose the baseline between configuration and the queued pass.
    GUF.RefreshCastAuraPositions(entry)
    GUF.QueueCastAuraPositions(entry)
end
