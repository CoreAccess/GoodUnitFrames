local addonName, GUF = ...
local UI = GUF.OptionsUI
local path = "Interface\\AddOns\\" .. addonName .. "\\media\\options\\"

local function artwork(parent, name, layer, level)
    local region = parent:CreateTexture(nil, layer or "BACKGROUND", nil, level or -7)
    region.goodUnitFramesOwned = true
    region:SetTexture(path .. name .. ".tga", "CLAMP", "CLAMP", "TRILINEAR")
    return region
end

function UI.WindowShell(window, preview)
    -- Keep the template's title, close button and behavior; replace only its art.
    if window.NineSlice then window.NineSlice:Hide() end
    if window.PortraitContainer then window.PortraitContainer:Hide() end
    for _, region in ipairs({ window:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:Hide() end
    end
    window.shellArtwork = {}
    if preview then
        -- Reuse the options artwork with fixed corners and a stretchable center.
        -- This window has no toolbar, navigation divider, footer or medallion.
        local columns = { { 0, 64 }, { 64, 1472 }, { 1472, 1536 } }
        local rows = { { 0, 56 }, { 122, 940 }, { 992, 1024 } }
        for y = 1, 3 do
            for x = 1, 3 do
                local region = artwork(window, "window-shell-v1")
                local col, row = columns[x], rows[y]
                region:SetTexCoord(col[1] / 1536, col[2] / 1536, row[1] / 1024, row[2] / 1024)
                local left, right = x == 1 and 0 or x == 2 and 48 or -48, x == 1 and 48 or x == 2 and -48 or 0
                if y == 1 then
                    region:SetHeight(28)
                    region:SetPoint("TOPLEFT", window, x == 3 and "TOPRIGHT" or "TOPLEFT", left, 0)
                    region:SetPoint("TOPRIGHT", window, x == 1 and "TOPLEFT" or "TOPRIGHT", right, 0)
                elseif y == 3 then
                    region:SetHeight(16)
                    region:SetPoint("BOTTOMLEFT", window, x == 3 and "BOTTOMRIGHT" or "BOTTOMLEFT", left, 0)
                    region:SetPoint("BOTTOMRIGHT", window, x == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT", right, 0)
                else
                    region:SetPoint("TOPLEFT", window, x == 3 and "TOPRIGHT" or "TOPLEFT", left, -28)
                    region:SetPoint("BOTTOMRIGHT", window, x == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT", right, 16)
                end
                window.shellArtwork[#window.shellArtwork + 1] = region
            end
        end
        return
    end
    local function piece(x, y, width, height, left, right, top, bottom)
        local region = artwork(window, "window-shell-v1")
        region:SetPoint("TOPLEFT", x, -y); region:SetSize(width, height)
        region:SetTexCoord(left / 1536, right / 1536, top / 1024, bottom / 1024)
        window.shellArtwork[#window.shellArtwork + 1] = region
    end
    local width, height = UI.layout.windowWidth, UI.layout.windowHeight
    local sidebarRight, toolbarBottom, footerTop = UI.layout.paneLeft - 12, 76, height - 42
    -- Measured rules in the source PNG. Separate strips align them with existing
    -- controls without moving content or baking labels/buttons into the texture.
    piece(0, 0, width, 28, 0, 1536, 0, 56)
    piece(0, 28, width, toolbarBottom - 28, 0, 1536, 56, 122)
    piece(0, toolbarBottom, sidebarRight, footerTop - toolbarBottom, 0, 282, 122, 940)
    piece(sidebarRight, toolbarBottom, width - sidebarRight, footerTop - toolbarBottom, 282, 1536, 122, 940)
    piece(0, footerTop, width, height - footerTop, 0, 1536, 940, 1024)

    window.settingsMedallion = artwork(window, "settings-medallion-v1-256", "OVERLAY", 7)
    window.settingsMedallion:SetSize(80, 80)
    window.settingsMedallion:SetPoint("TOPLEFT", -10, 16)
end

function UI.Parchment(frame)
    -- Fixed paper corners/edges retain their worn silhouette on both the main
    -- page and shorter confirmations. Only the quiet paper center stretches.
    local edge, pieces = 22, {}
    local coords = { { 0, 64 }, { 64, 1472 }, { 1472, 1536 } }
    local rows = { { 0, 64 }, { 64, 960 }, { 960, 1024 } }
    for y = 1, 3 do
        for x = 1, 3 do
            local region = artwork(frame, "parchment-v1")
            region:SetTexCoord(coords[x][1] / 1536, coords[x][2] / 1536, rows[y][1] / 1024, rows[y][2] / 1024)
            if x == 2 and y == 2 then
                region:SetPoint("TOPLEFT", edge, -edge); region:SetPoint("BOTTOMRIGHT", -edge, edge)
            elseif x == 2 then
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
            pieces[#pieces + 1] = region
        end
    end
    frame.goodUnitFramesPage, frame.goodUnitFramesPaperPieces = pieces[5], pieces
end
