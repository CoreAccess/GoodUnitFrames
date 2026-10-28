local _, GUF = ...
local UI = GUF.OptionsUI
local filters = {
    buffs = { { "ALL", "All Auras" }, { "PLAYER", "My Auras" }, { "RAID", "Class-filtered auras" },
        { "PLAYER|RAID", "My class auras" }, { "BIG_DEFENSIVE", "Big defensive cooldowns" },
        { "PLAYER|BIG_DEFENSIVE", "My big defensives" }, { "EXTERNAL_DEFENSIVE", "External defensives" },
        { "PLAYER|EXTERNAL_DEFENSIVE", "My external defensives" },
        { "RAID_PLAYER_DISPELLABLE", "Purgeable/Stealable" }, { "DISPELLABLE", "Any dispellable" },
        { "RAID_IN_COMBAT", "HoTs & raid frames buffs" }, { "PLAYER|RAID_IN_COMBAT", "My HoTs & raid frames buffs" },
        { "IMPORTANT", "Important auras" } },
    debuffs = { { "ALL", "All Auras" }, { "PLAYER", "My Auras" }, { "RAID", "Dispellable by me" },
        { "RAID_PLAYER_DISPELLABLE", "Dispellable by group" }, { "DISPELLABLE", "Any dispellable" },
        { "CROWD_CONTROL", "Crowd control effects" }, { "IMPORTANT", "Important auras" } },
}
local sorts = { { "Default", "Default" }, { "BigDefensive", "Big defensives first" },
    { "UnitFrameDebuff", "Unit frame debuff order" }, { "ImportantOnly", "Important only" },
    { "Expiration", "Expiration (yours first)" }, { "ExpirationOnly", "Expiration" },
    { "Name", "Name (yours first)" }, { "NameOnly", "Name" }, { "AuraInstanceIDOnly", "Application order" } }

local function tabs(builder, window)
    local row = builder.Row("", 42, true)
    row.label:Hide()
    row.auraTabs = row.auraTabs or {}
    local previous
    for _, item in ipairs({ { "general", "Layout" }, { "filters", "Filters" }, { "text", "Text" } }) do
        local key, label = item[1], item[2]
        local button = row.auraTabs[key]
        if not button then
            button = CreateFrame("Button", nil, row)
            row.auraTabs[key] = button
            button:SetSize(94, 32)
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.label:SetFont(GUF.Font("Default"), 13, "")
            button.label:SetPoint("CENTER")
            button.label:SetText(label)
            UI.SkinTab(button)
        end
        button:ClearAllPoints()
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else button:SetPoint("TOPLEFT", 0, 0) end
        local selected = window.auraTab == key
        UI.SelectTab(button, selected)
        button:SetScript("OnClick", function()
            if window.auraTab == key then return end
            window.auraTab = key
            GUF.BuildOptions()
        end)
        button:Show()
        previous = button
    end
end

UI.RegisterPage("auras", "Auras", function(builder, unit, window)
    local kind, index = window.auraKind, window.auraIndex
    local base = kind == "bossDebuffs" and { "auras", kind } or { "auras", kind, index }
    local function keys(key)
        local result = GUF.Copy(base)
        result[#result + 1] = key
        return result
    end
    local function check(label, key, tooltip)
        local host, control = builder.Check(label, unpack(keys(key)))
        control:SetPoint("LEFT", 0, 0)
        host.label:SetPoint("LEFT", control, "RIGHT", 1, 0)
        host.label:SetPoint("RIGHT", -5, 0)
        host.label:SetTextColor(1, 1, 1)
        control:SetHitRectInsets(0, -130, 0, 0)
        if tooltip then UI.Tooltip(control, label, tooltip) end
        return host
    end
    local function selects(rowKey, entries)
        local columns = UI.CompactColumns(builder, rowKey, 58, #entries)
        for i, item in ipairs(entries) do
            local column, path = columns[i], keys(item[2])
            column.caption:ClearAllPoints()
            column.caption:SetPoint("TOPLEFT")
            column.caption:SetText(item[1])
            column.select = UI.Dropdown(column, item[3], function() return builder.Read(path) end,
                function(value) builder.Change(path, value) end, column.select)
            column.select:ClearAllPoints()
            column.select:SetPoint("TOPLEFT", 0, -21)
            column.select:SetPoint("TOPRIGHT", 0, -21)
            UI.SettingHelp(column.select, item[1], path)
        end
    end
    local function sliders(rowKey, entries)
        local columns = UI.CompactColumns(builder, rowKey, 72, #entries)
        for i, item in ipairs(entries) do
            local minimum, maximum = item[3], item[4]
            if minimum == -1000 and maximum == 1000 then minimum, maximum = -100, 100 end
            UI.CompactSlider(builder, columns[i], item[1], keys(item[2]), minimum, maximum, 1, false, false, { item[3], item[4] })
        end
    end
    local positions = GUF.Copy(UI.pointChoices)
    if unit == "player" then positions[#positions + 1] = { "FREE", "Free (screen)" } end
    local firstDetail
    if kind == "bossDebuffs" then
        builder.Group("Boss debuffs")
        builder.Row("Private encounter auras displayed by Blizzard's secure API.", 44, true)
        check("Enable", "enabled")
        firstDetail = builder.RowCount() + 1
        selects("bossPosition", { { "Position", "anchorPoint", positions } })
        sliders("bossSize", { { "Icon size", "size", 16, 64 }, { "Per row", "perRow", 1, 10 } })
        sliders("bossRows", { { "Max rows", "maxRows", 1, 5 } })
        sliders("bossOffsets", { { "X Offset", "x", -1000, 1000 }, { "Y Offset", "y", -1000, 1000 } })
        check("Show cooldown", "showCooldown")
        check("Show cooldown numbers", "showCooldownNumbers")
    else
        tabs(builder, window)
        if window.auraTab == "general" then
            builder.Group((kind == "buffs" and "Buffs" or "Debuffs") .. " layout")
            check("Enable", "enabled")
            firstDetail = builder.RowCount() + 1
            local other = kind == "buffs" and "debuffs" or "buffs"
            check("Anchor to " .. other, "anchorOn", "Positions these auras after the corresponding " .. other .. " frame when both frames are enabled.")
            if builder.Read(keys("anchorOn")) then
                builder.Select("Anchor mode", { { "COLUMN", "New row" }, { "SEQUENTIAL", "Sequential" } }, unpack(keys("anchorMode")))
            end
            builder.Group("Position", 2)
            selects("position", { { "Position", "anchorPoint", positions },
                { "Row growth", "growH", { { "RIGHT", "Right" }, { "LEFT", "Left" }, { "CENTER", "Center" } } } })
            selects("growth", { { "Column growth", "growV", { { "BOTTOM", "Down" }, { "TOP", "Up" } } } })
            sliders("size", { { "Icon size", "size", 8, 50 }, { "Icon spacing", "spacing", 0, 20 } })
            sliders("rows", { { "Per row", "perRow", 1, 20 }, { "Max rows", "maxRows", 1, 10 } })
            sliders("offsets", { { "X Offset", "x", -1000, 1000 }, { "Y Offset", "y", -1000, 1000 } })
            builder.Group("Appearance")
            if unit == "target" and not UI.LayoutCapabilities(unit).flat then
                local _, stockControl = builder.Check("Replace stock aura display", "auras", "replaceDefault")
                UI.Tooltip(stockControl, "Replace stock aura display", "Suppresses Blizzard's target auras when at least one Buffs frame and one Debuffs frame are enabled and working. Player buffs and debuffs are controlled separately under Hide Blizzard.")
            end
            check("Cooldown swipe", "cooldown")
            if kind == "debuffs" then check("Debuff type borders", "debuffBorder") end
        elseif window.auraTab == "filters" then
            builder.Group("Aura filters")
            firstDetail = builder.RowCount() + 1
            selects("filter", { { "Filter", "filter", filters[kind] } })
            selects("sort", { { "Sort method", "sort", sorts } })
            check("Reverse sort order", "reverseSort")
            builder.Select("Spell ID filter", { { "all", "All" }, { "blacklist", "Blacklist" },
                { "whitelist", "Whitelist + blacklist" } }, unpack(keys("filterMode")))
            builder.Edit("Whitelist spell IDs", nil, nil, unpack(keys("whitelist")))
            builder.Edit("Blacklist spell IDs", nil, nil, unpack(keys("blacklist")))
            builder.Row("Lists accept spell IDs separated by commas. Blacklist wins. Blizzard limits spell ID filtering to friendly buffs and hostile debuffs.", 56, true)
        else
            firstDetail = builder.RowCount() + 1
            builder.Group("Timer")
            check("Disable Blizzard Cooldown Count", "disableBlizzardCC")
            sliders("timerSize", { { "Size", "cooldownFontSize", 1, 50 } })
            builder.ColorSwatch("Default color", unpack(keys("cooldownFontColor")))
            selects("timerAnchor", { { "Anchor point", "timerAnchor", UI.pointChoices } })
            sliders("timerOffsets", { { "X Offset", "timerX", -100, 100 }, { "Y Offset", "timerY", -100, 100 } })
            check("Separate duration text", "durationText")
            selects("durationAnchor", { { "Duration text anchor", "durationPoint", UI.pointChoices } })
            sliders("durationOffset", { { "Duration text Y Offset", "durationY", -50, 50 } })
            builder.Group("Stacks")
            check("Disable stack counts", "disableStacks")
            sliders("stackSize", { { "Size", "stackFontSize", 1, 50 } })
            builder.ColorSwatch("Default color", unpack(keys("stackFontColor")))
            selects("stackAnchor", { { "Anchor point", "stackAnchor", UI.pointChoices } })
            sliders("stackOffsets", { { "X Offset", "stackX", -100, 100 }, { "Y Offset", "stackY", -100, 100 } })
        end
    end
    local enabled = builder.Read(keys("enabled"))
    local function enableChildren(host)
        for _, child in ipairs({ host:GetChildren() }) do
            if child.SetEnabled then child:SetEnabled(enabled) end
            if child:GetObjectType() == "Slider" then
                child:EnableMouse(enabled)
                child:EnableMouseWheel(enabled)
            elseif child:GetObjectType() == "EditBox" then
                child:EnableMouse(enabled)
                child:EnableKeyboard(enabled)
                if not enabled then child:ClearFocus() end
            end
            enableChildren(child)
        end
    end
    for i = firstDetail, builder.RowCount() do
        local row = window.rows[i]
        row:SetAlpha(enabled and 1 or .5)
        enableChildren(row)
    end
end)
