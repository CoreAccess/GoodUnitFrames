local _, GUF = ...
local UI = GUF.OptionsUI

local function path(root, keys)
    for i = 1, #keys - 1 do root = root[keys[i]] end
    return root, keys[#keys]
end

function UI.UnitContext(window)
    local unit = window.unit
    local profile = GUF.db
    local cfg = GUF.Copy(GUF.db.frames[unit])
    local position = GUF.PositionValues(unit)
    cfg.threat = GUF.Copy(GUF.db.threat)
    local function target(keys)
        if keys[1] == "design" and keys[2] == "portraits" then return path(GUF.db.frames.player, keys) end
        return path(keys[1] == "threat" and GUF.db or GUF.db.frames[unit], keys)
    end
    -- The builder lease cancels edits when this profile/layout/page is retired.
    return cfg, {
        Read = function(keys)
            if keys[1] == "design" and keys[2] == "layered" and keys[3] == "angles" then
                return GUF.LayeredOrbitAngle(unit, keys[4])
            end
            if keys[1] == "position" and not GUF.db.frames[unit].position.enabled then return position[keys[2]] end
            local root, key = target(keys)
            if #keys == 3 and keys[1] == "indicators" and GUF.IsPortraitIndicator(keys[2])
                and GUF.db.general.frameStyle == "artistic" then
                if key == "size" then return GUF.PortraitIndicatorSize(unit, keys[2]) end
                if key == "point" and (root[key] == nil or root[key] == "DEFAULT") then return "CENTER" end
            end
            if #keys == 1 and key == "nameSize" then return GUF.db.frames[unit].text.name.size end
            -- The control's 1-4 scale maps to the renderer's 0.5-2 multiplier.
            if #keys == 3 and keys[1] == "indicators" and keys[2] == "feedback" and key == "scale" then return root[key] * 2 end
            if #keys == 3 and keys[1] == "bars" and keys[2] == "cast" and (key == "width" or key == "height") then
                local width, height = GUF.CastBarDimensions(unit)
                return key == "width" and width or height
            end
            if #keys == 2 and keys[1] == "bars" and key == "width" then
                local width = GUF.ArtisticBarSize(unit, "health")
                return width
            end
            if #keys == 3 and keys[1] == "bars" and key == "height" and (keys[2] == "healthSize" or keys[2] == "powerSize") then
                local _, height = GUF.ArtisticBarSize(unit, keys[2] == "healthSize" and "health" or "power")
                return height
            end
            if #keys == 1 and (key == "width" or key == "height") and GUF.db.general.frameStyle == "artistic" then
                return GUF.FrameDimension(unit, key)
            end
            if (key == "width" or key == "height") and #keys == 1
                and (root[key] < 0 or not GUF.CanResizeFrames()) then return GUF.FrameDimension(unit, key) end
            return root[key]
        end,
        Write = function(keys, value)
            if GUF.db ~= profile then return end
            if keys[1] == "design" and keys[2] == "portraits" then
                if unit ~= "player" then return end
                local class = window.playerPortraitClass or GUF.PlayerDesignClass()
                local source = GUF.ClassPortraitDesign(class, value)
                if #keys ~= 3 or keys[3] ~= class or not source or source.id ~= value then return end
            elseif keys[1] == "design" and keys[2] == "creatures" then
                if unit ~= "target" then return end
                local family = window.targetMonsterType
                local choice = GUF.MonsterPortraitDesign(family, value)
                if #keys ~= 3 or keys[3] ~= family or not choice or choice.id ~= value then return end
            end
            if #keys == 3 and keys[1] == "artistic" and keys[2] == "playerGeometry" and keys[3] == "header" then
                if not UI.LayoutCapabilities(unit).barGeometry then return end
                local _, _, minimum, maximum = GUF.ArtisticBarLimits(unit, "name")
                value = math.max(minimum, math.min(maximum, value))
            end
            if #keys == 2 and keys[1] == "artistic" and keys[2] == "portraitScale" then
                local minimum, maximum = GUF.ArtisticPortraitScaleLimits(unit)
                value = math.max(minimum, math.min(maximum, value))
            end
            if #keys == 1 and (keys[1] == "width" or keys[1] == "height") and not GUF.CanResizeFrames() then return end
            if #keys == 2 and keys[1] == "bars" and keys[2] == "width" then
                if GUF.db.general.frameStyle ~= "artistic" or (unit ~= "player" and unit ~= "target") then return end
                local minimum, maximum = GUF.ArtisticBarLimits(unit, "health")
                value = math.max(minimum, math.min(maximum, value))
            end
            if #keys == 3 and keys[1] == "bars" and keys[3] == "height" and (keys[2] == "healthSize" or keys[2] == "powerSize") then
                if GUF.db.general.frameStyle ~= "artistic" or (unit ~= "player" and unit ~= "target") then return end
                local kind = keys[2] == "healthSize" and "health" or "power"
                local _, _, minimum, maximum = GUF.ArtisticBarLimits(unit, kind)
                value = math.max(minimum, math.min(maximum, value))
            end
            local barHeight = #keys == 3 and ((keys[1] == "artistic" and keys[2] == "playerGeometry" and keys[3] == "header")
                or (keys[1] == "bars" and keys[3] == "height" and (keys[2] == "healthSize" or keys[2] == "powerSize")))
            -- Capture the effective width before the height changes the fitted
            -- portrait diameter. The stored bars.width may predate that fit.
            local preservedBarWidth = barHeight and GUF.ArtisticBarSize(unit, "health")
            local portraitExtra
            if barHeight then
                local current = GUF.db.frames[unit]
                portraitExtra = math.max(0, current.artistic.portraitScale - GUF.ArtisticMinimumPortraitScale(current))
            end
            if keys[1] == "position" and not GUF.db.frames[unit].position.enabled then
                GUF.db.frames[unit].position = GUF.Copy(position)
                GUF.db.frames[unit].position.enabled = true
            end
            local root, key = target(keys)
            local enableCastPreview = #keys == 3 and keys[1] == "bars" and keys[2] == "cast"
                and key == "enabled" and value == true and root[key] ~= true
            if #keys == 3 and keys[1] == "indicators" and keys[2] == "feedback" and key == "scale" then
                value = math.max(.5, math.min(2, math.floor(value * 2 + .5) / 4))
            end
            root[key] = GUF.Copy(value)
            if enableCastPreview then GUF.EnableOptionsCastingPreview(unit) end
            if #keys == 1 and key == "scale" then GUF.SetFrameScale(unit, value) end
            local active = GUF.db.frames[unit]
            if keys[1] == "text" and keys[2] == "name" and key == "size" then
                active.nameSize = value
            elseif #keys == 1 and key == "nameSize" then active.text.name.size = value end
            if keys[1] == "text" and key ~= "nativeStyle" then
                active.text[keys[2]].nativeStyle = false
            elseif keys[1] == "font" or keys[1] == "fontSize" or keys[1] == "outline" then
                for _, options in pairs(active.text) do options.nativeStyle = false end
            elseif keys[1] == "nameSize" then active.text.name.nativeStyle = false end
            if keys[1] == "fading" then active.fading.native = false end
            if (unit == "player" or unit == "target") and GUF.db.general.frameStyle == "artistic" and keys[1] == "bars" then
                local geometry = GUF.db.frames[unit].artistic.playerGeometry
                if #keys == 2 and key == "width" then geometry.width = value + GUF.ArtisticBasePortraitWidth(unit) + 6 end
                if #keys == 3 and key == "height" then
                    if keys[2] == "healthSize" then geometry.health = value
                    elseif keys[2] == "powerSize" then geometry.power = value end
                end
            end
            if preservedBarWidth then
                active.bars.width = preservedBarWidth
                active.artistic.playerGeometry.width = preservedBarWidth + GUF.ArtisticBasePortraitWidth(unit) + 6
                active.artistic.portraitScale = math.min(1.5, GUF.ArtisticMinimumPortraitScale(active) + portraitExtra)
            end
            if keys[1] == "auras" and #keys == 4 then
                local auras, kind, index = GUF.db.frames[unit].auras, keys[2], keys[3]
                if key == "anchorOn" and value then
                    auras[kind == "buffs" and "debuffs" or "buffs"][index].anchorOn = false
                elseif key == "anchorPoint" or key == "growH" or key == "growV" then
                    root.legacyPoint = nil
                end
            end
        end,
    }
end

local function canCopyFrom(source, destination)
    local cfg = GUF.db.frames[source]
    return source ~= destination and cfg ~= nil
end

local function copySettings(source, destination)
    if not canCopyFrom(source, destination) then return end
    if not GUF.Settings.CopyUnit(GUF.db, source, destination) then return end
    GUF.RequestApply(nil, nil, "unit-copy")
    GUF.BuildOptions()
end

function UI.BuildCopySettings(builder, unit)
    builder.Group("Copy settings")
    local host = builder.Row("Copy settings from")
    local sources = {}
    for _, source in ipairs(GUF.order) do
        if canCopyFrom(source, unit) then sources[#sources + 1] = { source, GUF.labels[source] } end
    end
    if not canCopyFrom(host.copyFromUnit, unit) then host.copyFromUnit = nil end
    host.copyButton = host.copyButton or UI.Button(host, "Copy settings", 130)
    host.copyButton:ClearAllPoints()
    host.copyButton:SetPoint("RIGHT", -5, 0)
    host.copyButton:SetEnabled(host.copyFromUnit ~= nil)
    host.copyButton:SetScript("OnClick", function()
        if host.copyFromUnit and host.copyFromUnit ~= unit then copySettings(host.copyFromUnit, unit) end
    end)
    host.copyButton:Show()
    host.copySource = UI.Dropdown(host, sources,
        function() return host.copyFromUnit or "Choose a frame" end,
        function(source)
            if not canCopyFrom(source, unit) then return end
            host.copyFromUnit = source
            host.copyButton:Enable()
        end, host.copySource)
    host.copySource:SetEnabled(#sources > 0)
    host.copySource:ClearAllPoints()
    host.copySource:SetPoint("LEFT", host, "LEFT", UI.layout.controlOffset, 0)
    host.copySource:SetPoint("RIGHT", host.copyButton, "LEFT", -8, 0)
end
