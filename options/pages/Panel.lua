local addonName, GUF = ...
local UI = GUF.OptionsUI

function UI.RaisedSelection(tile)
    local frame = CreateFrame("Frame", nil, tile)
    frame.goodUnitFramesOwned, frame.goodUnitFramesSkin = true, true
    frame:EnableMouse(false); frame:SetFrameLevel(tile:GetFrameLevel() + 2)
    frame:SetPoint("TOPLEFT", -11, 11); frame:SetPoint("BOTTOMRIGHT", 11, -11)
    frame:Hide()
    -- Fixed corners preserve the chamfer/bevel. Stretch only straight edges;
    -- omit the transparent center so artwork cannot darken the paper face.
    local edge = 24
    local slices = { { 0, 160 }, { 160, 1094 }, { 1094, 1254 } }
    for y = 1, 3 do
        for x = 1, 3 do
            if x ~= 2 or y ~= 2 then
                local region = frame:CreateTexture(nil, "ARTWORK")
                region.goodUnitFramesOwned = true
                region:SetTexture("Interface\\AddOns\\" .. addonName .. "\\media\\options\\layout-selected-v1-1024.tga", "CLAMP", "CLAMP", "TRILINEAR")
                region:SetTexCoord(slices[x][1] / 1254, slices[x][2] / 1254, slices[y][1] / 1254, slices[y][2] / 1254)
                if x == 2 then
                    local side = y == 1 and "TOP" or "BOTTOM"
                    region:SetHeight(edge)
                    region:SetPoint(side .. "LEFT", edge, 0); region:SetPoint(side .. "RIGHT", -edge, 0)
                elseif y == 2 then
                    local side = x == 1 and "LEFT" or "RIGHT"
                    region:SetWidth(edge)
                    region:SetPoint("TOP" .. side, 0, -edge); region:SetPoint("BOTTOM" .. side, 0, edge)
                else
                    region:SetSize(edge, edge)
                    region:SetPoint((y == 1 and "TOP" or "BOTTOM") .. (x == 1 and "LEFT" or "RIGHT"), 0, 0)
                end
            end
        end
    end
    return { frame }
end

UI.RegisterPage("panel", "General", function(builder, unit, window)
    local introduction = builder.Row("Choose the look of your unit frames, then customize each unit in Unit Configuration.", 40, true)
    introduction.label.goodUnitFramesBodySize = 15
    introduction.label:SetFont(GUF.Font("Default"), 15, "")
    local host = builder.Row("", 254, true)
    host.label:Hide(); host.tiles = host.tiles or {}
    local specifications = GUF.Layouts.List()
    for _, tile in ipairs(host.tiles) do tile:Hide() end
    for i, item in ipairs(specifications) do
        local key, title, description = item.id, item.title, item.description
        local tile = host.tiles[i]
        if not tile then
            tile = CreateFrame("Button", nil, host, "BackdropTemplate"); host.tiles[i] = tile
            tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            tile.selectionEffects = UI.RaisedSelection(tile)
            tile.title = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal"); tile.title:SetPoint("TOP", 0, -14); UI.Heading(tile.title, 20)
            tile.artwork = CreateFrame("Frame", nil, tile)
            tile.artwork:SetPoint("TOPLEFT", 8, -44); tile.artwork:SetPoint("TOPRIGHT", -8, -44); tile.artwork:SetHeight(132); tile.artwork:SetClipsChildren(true)
            tile.description = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            local font, size = tile.description:GetFont()
            tile.description.goodUnitFramesBodySize = (size or 10) + 2
            tile.description:SetFont(font or GUF.Font("Default"), tile.description.goodUnitFramesBodySize, "")
            tile.description:SetWordWrap(true)
            tile.description:SetPoint("TOPLEFT", 14, -184); tile.description:SetPoint("BOTTOMRIGHT", -14, 12); tile.description:SetJustifyV("TOP")
        end
        local pending = GUF.GetRequestedLayout() == key
        tile.title:SetText(pending and title .. " (Pending)" or title); tile.description:SetText(description)
        local selected = GUF.db.general.frameStyle == key
        tile:SetBackdropColor(selected and 1 or .5, selected and .86 or .3, selected and .46 or .08, selected and .10 or .06)
        tile:SetBackdropBorderColor(.50, .38, .18, selected and 0 or 1)
        for _, effect in ipairs(tile.selectionEffects) do effect:SetShown(selected) end
        tile:SetEnabled(true); tile:SetAlpha(1)
        tile:SetScript("OnClick", function()
            local generation = window.buildGeneration
            GUF.SelectLayout(key)
            -- A completed handoff already rebuilt the editor. Deferred/canceled
            -- requests still need their pending card state refreshed.
            if window.buildGeneration == generation then GUF.BuildOptions() end
        end)
        tile.illustrationStyle = key
        UI.Tooltip(tile, title, description); tile:Show()
    end
    local function layout()
        if #specifications == 0 then return true end
        if not host:IsVisible() or host:GetWidth() < 210 then return end
        local width = host:GetWidth() / #specifications
        local ready = true
        for i = 1, #specifications do
            local tile = host.tiles[i]
            -- Keep specimen positions and reserve room for larger wrapped captions.
            tile:ClearAllPoints(); tile:SetPoint("TOPLEFT", (i - 1) * width, 0); tile:SetSize(math.max(70, width - 12), 244)
            tile.specimens = tile.specimens or {}
            for id, specimen in pairs(tile.specimens) do
                if id ~= tile.illustrationStyle then specimen.frame:Hide() end
            end
            tile.specimen = UI.LayoutIllustration(tile.artwork, tile.illustrationStyle, tile.specimens[tile.illustrationStyle])
            tile.specimens[tile.illustrationStyle] = tile.specimen
            if not tile.specimen or tile.specimen.presentationStatus == "deferred"
                or tile.specimen.presentationStatus == "unavailable" then ready = false end
        end
        return ready
    end
    host.QueueLayout = function()
        host.presentationAttempts, host.presentationRetryAt = 0, nil
        host:SetScript("OnUpdate", function(self)
            if self.presentationRetryAt and GetTime() < self.presentationRetryAt then return end
            if layout() then self:SetScript("OnUpdate", nil); return end
            -- Late native metadata may settle after first open. Reuse this
            -- layout driver briefly; reopening/resize supplies another attempt.
            self.presentationAttempts = self.presentationAttempts + 1
            if self.presentationAttempts >= 20 then self:SetScript("OnUpdate", nil)
            else self.presentationRetryAt = GetTime() + .1 end
        end)
    end
    host:SetScript("OnSizeChanged", host.QueueLayout)
    host:SetScript("OnShow", host.QueueLayout)
    host.QueueLayout()
end)
