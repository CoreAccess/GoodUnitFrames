local _, GUF = ...
local UI = GUF.OptionsUI

UI.RegisterPage("design", "Design", function(builder, unit, window)
    if not UI.LayoutCapabilities(unit).design then return end
    local classNames = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest", DRUID = "Druid", HUNTER = "Hunter",
        PALADIN = "Paladin", ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock",
        DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter", MONK = "Monk", EVOKER = "Evoker" }
    local profile, generation, content = GUF.db, window.buildGeneration, window.content
    local playerClass = GUF.PlayerDesignClass()
    local monster = unit == "target"
    local function monsterSubject()
        window.sampleChecks = window.sampleChecks or { states = { resting = true }, groups = { solo = true } }
        local subjects = window.sampleChecks.subjects or {}
        if not (subjects.beast or subjects.elite or subjects.rareelite or subjects.rare) then
            window.sampleChecks.subjects, window.sampleSubject = { beast = true }, "beast"
        end
    end
    if monster then
        if not GUF.MonsterPortraitDesign(window.targetMonsterType) then window.targetMonsterType = GUF.monsterTypes[1][1] end
        monsterSubject()
    elseif not GUF.ClassPortraitDesign(window.playerPortraitClass) then
        window.playerPortraitClass = GUF.ClassPortraitDesign(playerClass) and playerClass or GUF.portraitDesigns[1].class
    end
    local class = window.playerPortraitClass
    local family = window.targetMonsterType
    local function guard(callback)
        return function(...)
            if GUF.db ~= profile or window.buildGeneration ~= generation or window.content ~= content
                or not content:IsShown() or not UI.LayoutCapabilities(unit).design or GUF.PlayerDesignClass() ~= playerClass
                or monster and window.targetMonsterType ~= family
                or not monster and window.playerPortraitClass ~= class then return end
            return callback(...)
        end
    end
    do
        builder.BeginFixedHeader(0)
        local host = builder.Row(monster and "Monster Type" or "Class")
        local choices, seen = {}, {}
        if monster then
            for _, kind in ipairs(GUF.monsterTypes) do
                if GUF.MonsterPortraitDesign(kind[1]) then choices[#choices + 1] = kind end
            end
        else
            for _, source in ipairs(GUF.portraitDesigns) do
                if not seen[source.class] then
                    choices[#choices + 1] = { source.class, classNames[source.class] }; seen[source.class] = true
                end
            end
        end
        host.designSelector = UI.Dropdown(host, choices, function() return monster and family or class end, guard(function(value)
            if monster then
                if not GUF.MonsterPortraitDesign(value) then return end
                window.targetMonsterType = value
                monsterSubject()
            else
                if not GUF.ClassPortraitDesign(value) then return end
                window.playerPortraitClass = value
            end
            GUF.BuildOptions()
        end), host.designSelector)
        host.designSelector:ClearAllPoints()
        host.designSelector:SetPoint("LEFT", host, "LEFT", UI.layout.controlOffset, 0)
        host.designSelector:SetPoint("RIGHT", -5, 0); host.designSelector:Show()
        builder.EndFixedHeader()
    end
    builder.Group()
    local choices = {}
    if monster then
        for _, choice in ipairs(GUF.monsterPortraitDesigns[family] or {}) do choices[#choices + 1] = choice end
    else
        for _, source in ipairs(GUF.portraitDesigns) do
            if source.class == class then choices[#choices + 1] = source end
        end
    end
    local selections = GUF.db.frames.target.design.creatures
    local current = monster and GUF.MonsterPortraitDesign(family, selections[family]) or GUF.PortraitDesignForClass(class)
    local selected = current and current.id
    for first = 1, #choices, 3 do
        local host = builder.Row("", 158, true)
        host.label:Hide(); host.designTiles = host.designTiles or {}
        for _, tile in ipairs(host.designTiles) do tile:Hide() end
        for col = 1, math.min(3, #choices - first + 1) do
            local choice = choices[first + col - 1]
            local source = monster and choice.ranks.normal or choice
            local tile = host.designTiles[col]
            if not tile then
                tile = CreateFrame("Button", nil, host, "BackdropTemplate"); host.designTiles[col] = tile
                tile.goodUnitFramesOwned = true
                tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
                tile.selectionEffects = UI.RaisedSelection(tile)
                tile.art = CreateFrame("Frame", nil, tile)
                tile.art.goodUnitFramesOwned, tile.art.configurationPreview = true, true
                tile.art:SetPoint("TOPLEFT", 12, -10); tile.art:SetPoint("TOPRIGHT", -12, -10); tile.art:SetHeight(94)
                tile.art:SetClipsChildren(true); tile.art:EnableMouse(false)
                tile.portrait = tile.art:CreateTexture(nil, "ARTWORK")
                tile.portrait.goodUnitFramesOwned = true
                tile.status = tile.art:CreateTexture(nil, "OVERLAY")
                tile.status.goodUnitFramesOwned = true
                tile.level = tile.art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                tile.level:SetFont(GUF.Font("Default"), 10, "OUTLINE")
                tile.level:SetTextColor(1, 1, 1)
                tile.level:SetWordWrap(false)
                tile.caption = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                tile.caption:SetPoint("TOPLEFT", 8, -108); tile.caption:SetPoint("BOTTOMRIGHT", -8, 8)
                tile.caption:SetJustifyH("CENTER"); tile.caption:SetJustifyV("TOP"); tile.caption:SetWordWrap(true)
            end
            -- Follow the available row width on every cached build/resize.
            local index = col
            tile.LayoutDesignTile = function(self)
                local width = host:GetWidth() / 3
                self:ClearAllPoints(); self:SetPoint("TOPLEFT", host, "TOPLEFT", (index - 1) * width, 0)
                self:SetSize(math.max(1, width - 10), 148)
            end
            tile:LayoutDesignTile()
            tile.portrait:Hide(); tile.level:Hide(); tile.status:Hide()
            local label = choice.name
            tile.caption:SetText(label)
            if source.textureFile or source.path then
                -- Fit the entire inseparable assembly in the existing card.
                local diameter = math.min(68, 90 * source.diameter / source.canvas)
                GUF.PlaceDesignTexture(tile.portrait, source, tile.art, diameter, unit == "target")
                local levelX, levelY = GUF.PortraitLevelGeometry(source)
                tile.level:ClearAllPoints()
                tile.level:SetPoint("CENTER", tile.art, "CENTER", diameter * levelX * (unit == "target" and not source.targetOnly and -1 or 1),
                    diameter * levelY)
                tile.level:SetSize(0, 16); tile.level:SetText(GUF.PreviewPlayerLevel()); tile.level:Show()
                if source.sockets and not source.noStatus then
                    local sockets, glyph = source.sockets, GUF.indicatorArtwork.resting
                    local x, y = diameter * sockets.statusX * (unit == "target" and -1 or 1), diameter * sockets.statusY
                    if not sockets.statusFaceRatio or not GUF.ApplySocketIndicatorArtwork(tile.status, tile.art, "resting",
                        diameter * sockets.statusFaceRatio * sockets.statusFill, x, y) then
                        tile.status:ClearAllPoints()
                        tile.status:SetPoint("CENTER", tile.art, "CENTER", x, y)
                        tile.status:SetTexture(glyph.path .. "128", "CLAMP", "CLAMP", "TRILINEAR")
                        tile.status:SetTexCoord(glyph.left, glyph.right, glyph.top, glyph.bottom)
                        local side = diameter * sockets.statusGlyphRatio
                        tile.status:SetSize(side * math.min(1, glyph.aspect), side * math.min(1, 1 / glyph.aspect))
                    end
                    tile.status:Show()
                end
            end
            local active = selected == choice.id
            tile:SetBackdropColor(.5, .3, .08, active and .14 or .04)
            tile:SetBackdropBorderColor(.50, .38, .18, active and 0 or 1)
            for _, effect in ipairs(tile.selectionEffects) do effect:SetShown(active) end
            tile:SetScript("OnClick", guard(function()
                if monster then
                    monsterSubject()
                    builder.Change({ "design", "creatures", family }, choice.id)
                else builder.Change({ "design", "portraits", class }, choice.id) end
                GUF.BuildOptions()
            end))
            UI.Tooltip(tile, label)
            tile:Show()
        end
        host:SetScript("OnSizeChanged", function(self)
            for _, tile in ipairs(self.designTiles) do if tile:IsShown() then tile:LayoutDesignTile() end end
        end)
    end
end)
