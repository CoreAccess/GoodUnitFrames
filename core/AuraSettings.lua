local _, GUF = ...
GUF.auraFrameCount = 6

function GUF.AuraFrameDefaults(harmful, index)
    return {
        enabled = false, size = 24, perRow = 8, maxRows = 4, spacing = 3,
        anchorPoint = "BOTTOMLEFT", x = 5, y = harmful and -42 or -12,
        growH = "RIGHT", growV = "BOTTOM", filter = "ALL", sort = "Default", reverseSort = false,
        anchorOn = false, anchorMode = "COLUMN",
        cooldown = true, debuffBorder = true,
        disableBlizzardCC = false, cooldownFontSize = 10,
        cooldownFontColor = { 1, 1, 1 }, timerAnchor = "CENTER", timerX = 0, timerY = 0,
        disableStacks = false, stackFontSize = 10, stackFontColor = { 1, 1, 1 },
        stackAnchor = "BOTTOMRIGHT", stackX = -1, stackY = 1,
        durationText = false, durationPoint = "BOTTOM", durationY = 0,
        filterMode = "all", whitelist = "", blacklist = "",
    }
end

-- One destination keeps automatic Player enchants out of duplicate legacy
-- Buffs frames. Use this same selection for live hosts and copied specimens.
function GUF.AuraEnchantSettings(unit, auras)
    if unit ~= "player" then return end
    for _, cfg in ipairs(auras.buffs) do
        if cfg.enabled then return cfg end
    end
end

function GUF.NormalizeAuraOptions(frames)
    for _, cfg in pairs(type(frames) == "table" and frames or {}) do
        local auras = type(cfg) == "table" and cfg.auras
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local group = type(auras) == "table" and auras[kind]
            if type(group) == "table" then
                -- Also retire the fields on the old single-frame schema before
                -- MigrateAuras copies it into the indexed frame settings.
                group.weaponEnchants, group.enlarge = nil, nil
                group.textOverride = nil
                for _, settings in pairs(group) do
                    if type(settings) == "table" then
                        settings.weaponEnchants, settings.enlarge, settings.textOverride = nil, nil, nil
                    end
                end
            end
        end
    end
end

function GUF.AuraDefaults()
    local auras = { buffs = {}, debuffs = {},
        bossDebuffs = { enabled = false, size = 32, perRow = 3, maxRows = 1,
            anchorPoint = "CENTER", x = 0, y = 0, showCooldown = true, showCooldownNumbers = true } }
    for i = 1, GUF.auraFrameCount do
        auras.buffs[i] = GUF.AuraFrameDefaults(false, i)
        auras.debuffs[i] = GUF.AuraFrameDefaults(true, i)
    end
    return auras
end

function GUF.MigrateAuras(auras)
    if type(auras) ~= "table" then return end
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        local old = auras[kind]
        if type(old) == "table" and old[1] == nil then
            local cfg = GUF.Copy(old)
            cfg.enabled = auras.enabled == true and old.enabled ~= false
            cfg.maxRows = math.max(1, math.ceil((cfg.maxCount or 32) / (cfg.perRow or 8)))
            cfg.anchorPoint = cfg.relativePoint or "BOTTOMLEFT"
            cfg.growH, cfg.growV = cfg.growLeft and "LEFT" or "RIGHT", cfg.growUp and "TOP" or "BOTTOM"
            -- Retain legacy icon anchors until the user chooses a new position/growth.
            cfg.legacyPoint = cfg.point
            cfg.filter = cfg.onlyMine and "PLAYER" or "ALL"
            local sorts = { default = "Default", expiration = "Expiration", duration = "ExpirationOnly",
                name = "NameOnly", stable = "AuraInstanceIDOnly" }
            cfg.sort = sorts[cfg.sort] or "Default"
            cfg.disableBlizzardCC, cfg.disableStacks = cfg.countdownNumbers == false or cfg.cooldown == false, cfg.stacks == false
            cfg.cooldownFontSize, cfg.stackFontSize = cfg.textSize or 10, cfg.textSize or 10
            cfg.maxCount, cfg.point, cfg.relativePoint, cfg.growLeft, cfg.growUp, cfg.onlyMine = nil, nil, nil, nil, nil, nil
            cfg.countdownNumbers, cfg.stacks, cfg.textSize = nil, nil, nil
            auras[kind] = { cfg }
        end
    end
    auras.enabled = nil
end
