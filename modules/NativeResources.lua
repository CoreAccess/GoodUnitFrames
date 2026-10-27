local _, GUF = ...

-- This bridge owns cosmetic leases only. Native resource controllers stay live.
local nativeOwners, suppressed = {}, {}
local function leaseAlpha(region, value)
    return GUF.RegionAlpha(region, value, false, "ComboPoints", value == nil)
end

local function nativeFrames(entry)
    if entry.unit == "target" then
        local kind, source = GUF.SegmentedResourceSource("target")
        -- Only Forever's observer-owned Rogue combo row owns native combo art.
        -- Retail self/foreign Target rows never own the observer's controllers.
        if not GUF.LegacyTargetCombo(entry.unit, kind, source) then return {} end
    end
    if entry.comboRow and GUF.RetailResourceDefinition(entry.comboRow.kind) then
        if entry.unit ~= "player" then return {} end
        local row, frames = entry.comboRow, {}
        if row.nativeMainReady then frames = GUF.RetailResourceNativeFrames(row.kind) end
        if row.nativeAuxReady then
            for _, frame in ipairs(GUF.RetailResourceNativeFrames("ebon")) do frames[#frames + 1] = frame end
        end
        return frames
    end
    if entry.comboRow and entry.comboRow.kind == "runes" then
        return entry.unit == "player" and { RuneFrame } or {}
    end
    if entry.comboRow and entry.comboRow.kind == "shards" then
        -- Observing a Target must never claim the player's native controllers.
        return entry.unit == "player" and { WarlockPowerFrame, ShardBarFrame } or {}
    end
    return { ComboFrame, RogueComboPointBarFrame, DruidComboPointBarFrame }
end

function GUF.UpdateNativeResourceOwnership(entry, owns)
    nativeOwners[entry] = owns and nativeFrames(entry) or nil
    local desired = {}
    for _, frames in pairs(nativeOwners) do
        for _, frame in pairs(frames) do desired[frame] = true end
    end
    for frame in pairs(suppressed) do
        if not desired[frame] then
            if leaseAlpha(frame, nil) then suppressed[frame] = nil end
        end
    end
    for frame in pairs(desired) do
        suppressed[frame] = true
        leaseAlpha(frame, 0)
    end
end

function GUF.OwnsNativeComboPoints(frame)
    return suppressed[frame] == true
end

-- A narrow public controller-visibility decision for an already eligible
-- observer-owned row. Never query native amounts or a foreign unit's timing.
function GUF.NativeResourceVisible(entry, kind, source)
    if source ~= "player" then return end
    local native
    if GUF.RetailResourceDefinition(kind) then native = GUF.RetailResourceNativeFrames(kind)[1]
    elseif kind == "shards" then native = ShardBarFrame or WarlockPowerFrame
    elseif kind == "runes" then native = RuneFrame
    elseif kind == "combo" and not GUF.LegacyTargetCombo(entry.unit, kind, source) then
        local _, class = UnitClass("player")
        native = not GUF.Secret(class) and (class == "DRUID" and DruidComboPointBarFrame
            or class == "ROGUE" and RogueComboPointBarFrame) or nil
        native = native or ComboFrame
    else native = ComboFrame end
    if not native or (native.IsForbidden and native:IsForbidden()) then return end
    local shown = native:IsShown()
    if not GUF.Secret(shown) and type(shown) == "boolean" then return shown end
end


local lifecycleHooks = {}
function GUF.WatchRetailResourceLifecycle()
    if not GUF.isRetail then return end
    local anchorUpdate = "PlayerFrame_UpdatePlayerNameTextAnchor"
    if not lifecycleHooks[anchorUpdate] and type(_G[anchorUpdate]) == "function" then
        lifecycleHooks[anchorUpdate] = true
        GUF.NativeProperties.Hook("RetailResources:1", anchorUpdate, function()
            local entry = GUF.frames and GUF.frames.player
            if GUF.db and entry and GUF.Runtime.Settings("layout", entry).general.frameStyle == "artistic" then
                -- Every DH specialization can trigger this writer, including
                -- Havoc/Vengeance transitions without a Devourer bar argument.
                GUF.RestoreArtisticPlayerNameAnchor(entry)
            end
        end)
    end
    for _, name in ipairs({ "PlayerFrame_OnAlternatePowerBarEnabled", "PlayerFrame_OnAlternatePowerBarDisabled" }) do
        if not lifecycleHooks[name] and type(_G[name]) == "function" then
            lifecycleHooks[name] = true
            GUF.NativeProperties.Hook("RetailResources:2", name, function(bar)
                -- Alternate-power attach/detach rebuilds native Player artwork and
                -- resets PlayerName AFTER specialization-event listeners may
                -- have applied our layout. Reconcile once that rebuild ends.
                local relevant = DemonHunterSoulFragmentsBar and bar == DemonHunterSoulFragmentsBar
                if AlternatePowerBar and bar == AlternatePowerBar then
                    local _, class = UnitClass("player")
                    relevant = not GUF.Secret(class) and class == "PRIEST"
                end
                if not relevant then return end
                local entry = GUF.frames and GUF.frames.player
                if GUF.db and GUF.Runtime.Settings("layout", entry).general.frameStyle == "artistic"
                    and entry and GUF.Presentation.Role(entry, "resources") then
                    -- Full resource reconciliation still defers; the separate
                    -- name post-hook handles the DH-specific cosmetic repair.
                    GUF.DeferRuntime("native-readiness")
                end
            end)
        end
    end
end

