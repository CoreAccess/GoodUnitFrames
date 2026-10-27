local addonName, GUF = ...
-- Shared addon setup and coordination.
local events = CreateFrame("Frame")
local resourceRecoverySources = { PLAYER_SPECIALIZATION_CHANGED = "specialization-changed",
    PLAYER_TALENT_UPDATE = "talents-changed", TRAIT_CONFIG_UPDATED = "traits-changed", SPELLS_CHANGED = "spells-changed" }

local function refreshUnits()
    for _, entry in pairs(GUF.frames) do
        GUF.UpdateColors(entry)
        GUF.UpdateBarText(entry, "health")
        GUF.UpdateBarText(entry, "power")
    end
    GUF.UpdateThreat()
    GUF.UpdateArtisticStates()
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then GUF.InitializeDB() end
        if GUF.db then
            GUF.WatchRetailResourceLifecycle()
            GUF.QueueBlizzardFrameRefresh()
            -- Reconcile late native aura support through the normal guarded
            -- apply tick; never recurse into layout during LoadAddOn callbacks.
            if GUF.Client.IsAuraContainerAddon(arg1) then GUF.QueueRecovery("aura-addon") end
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        GUF.InitializeDB()
        GUF.WatchRetailResourceLifecycle()
        GUF.RequestApply(nil, nil, "login")
        for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
            "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
            "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED",
            "PLAYER_FLAGS_CHANGED", "PLAYER_GUILD_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
            "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UNIT_DISPLAYPOWER", "UNIT_FACTION",
            "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "PLAYER_LEVEL_UP", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
            "UNIT_TARGET", "UNIT_PET",
            "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UPDATE_SHAPESHIFT_FORM",
            "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
            "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE",
            "ARENA_OPPONENT_UPDATE", "ARENA_PREP_OPPONENT_SPECIALIZATIONS", "PLAYER_SPECIALIZATION_CHANGED" }) do events:RegisterEvent(name) end
        -- Legacy combo controllers expose this event on some clients only.
        pcall(events.RegisterEvent, events, "COMBO_TARGET_CHANGED")
        if GUF.isRetail then
            events:RegisterEvent("RUNE_POWER_UPDATE")
            events:RegisterUnitEvent("UNIT_AURA", "player", "target")
            events:RegisterEvent("PLAYER_TALENT_UPDATE")
            events:RegisterEvent("TRAIT_CONFIG_UPDATED")
            events:RegisterEvent("SPELLS_CHANGED")
            events:RegisterEvent("INSPECT_READY")
        end
        if EventRegistry then
            EventRegistry:RegisterCallback("EditMode.Enter", GUF.BeginEditMode, GUF)
            EventRegistry:RegisterCallback("EditMode.SavedLayouts", GUF.SaveEditModePositions, GUF)
            EventRegistry:RegisterCallback("EditMode.Exit", GUF.EndEditMode, GUF)
        end
        local elapsed = 0
        events:SetScript("OnUpdate", function(_, delta)
            GUF.FlushQueuedUpdates()
            GUF.UpdateFading(delta)
            elapsed = elapsed + delta
            if elapsed < .25 then return end
            elapsed = 0
            if GUF.pending and not GUF.editing and not GUF.Restricted() and not GUF.Updates.CleanupWaiting() then
                GUF.RequestApply(true, nil, "pending-tick")
            end
            if GUF.resourceOptionsPending and not GUF.pending and not GUF.editing and not GUF.Restricted() then
                GUF.resourceOptionsPending = nil
                if GUF.options and GUF.options:IsShown() then GUF.BuildOptions() end
            end
            if GUF.blizzardVisibilityPending and not GUF.editing and not GUF.Restricted() then GUF.ApplyBlizzardFrames() end
            GUF.UpdateAuraEnchants()
            GUF.UpdateThreat()
            GUF.UpdateArtisticStates()
            if GUF.options and GUF.options:IsShown() then GUF.UpdateConfigurationButton() end
        end)
        SLASH_GUF1 = "/guf"
        SLASH_GUF2 = "/goodunitframes"
        SLASH_GOODDIVIDER1 = "/gufdivider"
        SlashCmdList.GOODDIVIDER = function() GUF.ShowTargetDividerReport() end
        SLASH_GOODRESOURCES1 = "/gufresources"
        SlashCmdList.GOODRESOURCES = function() GUF.ShowResourceReport() end
        SlashCmdList.GUF = function(message)
            local command = (message or ""):lower():match("^%s*(.-)%s*$")
            if command == "unlock" then GUF.SetMovers(true)
            elseif command == "lock" then GUF.SetMovers(false)
            elseif command == "reset" then
                if GUF.ResetCurrentProfile() then GUF.Print("Current " .. GUF.title .. " profile reset.") end
            elseif command == "status" then
                GUF.Print("v" .. GUF.version .. "; options: /guf"
                    .. "; pending changes: " .. ((GUF.pending or GUF.updateQueued) and "yes" or "no")
                    .. "; aura error: " .. (GUF.auraError or "none"))
            elseif command == "targetdebug" then GUF.PrintArtisticTargetBars()
            elseif command == "portraitdebug" then GUF.PrintPortraitArtworkStatus()
            elseif command == "dividerdebug" then GUF.ShowTargetDividerReport()
            elseif command == "resourcesdebug" then GUF.ShowResourceReport()
            elseif command == "layoutdebug" then GUF.ShowLayoutReport()
            elseif command == "updatedebug" then GUF.ShowUpdateReport()
            elseif command == "previewdebug" then GUF.ShowBlizzardPreviewReport()
            elseif command == "" or GUF.IsManagedUnit(command) then GUF.OpenOptions(GUF.IsManagedUnit(command) and command or nil)
            else GUF.Print("/guf [player|target|unlock|lock|reset|status|targetdebug|portraitdebug|dividerdebug|resourcesdebug|layoutdebug|updatedebug|previewdebug]") end
        end
        return
    end
    if not GUF.db then return end
    if GUF.isRetail and (event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" or event == "SPELLS_CHANGED") then
        GUF.ResetRetailResourceCaches()
        -- Several spell/trait notifications may describe the same build change.
        -- Reuse the existing pending-apply tick and rebuild stale spec controls once.
        GUF.QueueRecovery(resourceRecoverySources[event])
        GUF.resourceOptionsPending = true
    elseif GUF.isRetail and event == "INSPECT_READY" then
        GUF.ResetTargetResources()
        GUF.QueueRecovery("inspect-ready")
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "ARENA_OPPONENT_UPDATE"
        or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        GUF.QueueBlizzardFrameRefresh()
    end
    if event == "PLAYER_REGEN_DISABLED" then GUF.SetMovers(false)
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then GUF.ResetTargetResources() end
        GUF.RequestApply(nil, nil, event == "PLAYER_REGEN_ENABLED" and "combat-ended" or "entering-world")
    elseif event == "PLAYER_TARGET_CHANGED" then
        GUF.ResetTargetResources()
        GUF.QueueBlizzardFrameRefresh()
        if GUF.frames.target then
            GUF.RefreshArtisticBarPresentation(GUF.frames.target)
            GUF.QueueTargetColorRefresh(GUF.frames.target)
        end
        GUF.RefreshUnitAuras("target")
    elseif event == "UNIT_FACTION" then GUF.RefreshUnitAuras(arg1)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player") then GUF.UpdateAuraEnchants()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or (event == "UNIT_DISPLAYPOWER" and arg1 == "player") then
        GUF.RequestApply(nil, nil, event == "UPDATE_SHAPESHIFT_FORM" and "shapeshift" or "power-type")
    elseif event:find("^UNIT_") and arg1 and not GUF.IsManagedUnit(arg1) then
        if arg1 == "vehicle" and (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER") then
            GUF.UpdateArtisticStates()
            return
        end
        -- Pet/party/raid evidence may change Target's combat color. Refresh
        -- managed entries only; these units still have no addon frame owner.
        if event ~= "UNIT_TARGET" and event ~= "UNIT_PET" and event ~= "UNIT_FLAGS"
            and event ~= "UNIT_THREAT_LIST_UPDATE" and event ~= "UNIT_THREAT_SITUATION_UPDATE" then return end
    end
    local health = event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
    local power = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER"
    local prediction = event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_PREDICTION"
    if health or power or prediction then
        local entry = GUF.IsManagedUnit(arg1) and GUF.frames[arg1]
        if entry then
            local counts = GUF.Updates.stats.values
            counts[arg1] = (counts[arg1] or 0) + 1
            if health then GUF.UpdateColors(entry) end
            GUF.UpdateBarText(entry, "health")
            GUF.UpdateBarText(entry, "power")
            if power then
                GUF.SyncArtisticPowerLayout(entry)
                GUF.UpdateComboPoints(entry)
                local target = GUF.frames.target
                if arg1 == "player" and target and (GUF.ComboPointUnit() == "target"
                    or target.segmentedCapacitySource == "player") then GUF.UpdateComboPoints(target) end
            end
        end
        return
    end
    refreshUnits()
end)
