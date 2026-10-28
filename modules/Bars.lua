local _, GUF = ...
local unpack = unpack or table.unpack

function GUF.MediaTexture(name)
    if name == "Blizzard" then return end
    if name == "Flat" then return "Interface\\Buttons\\WHITE8X8" end
    if name == "Blizzard Raid Bar" then return "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" end
    return GUF.bundledBarTextures[name] or GUF.ExternalBarTexture(name)
end

-- Resource bars inherit the owning frame's configured Health media. Blizzard
-- fallback uses captured static artwork, never a live amount-driven texture.
function GUF.StyleClassResourceFill(entry, bar, color)
    local cfg = GUF.PresentationFrameSettings(entry)
    local selected = GUF.MediaTexture(cfg.bars.healthTexture)
    bar:SetStatusBarTexture(selected or "Interface\\TargetingFrame\\UI-StatusBar")
    local fill = bar:GetStatusBarTexture()
    fill.goodUnitFramesOwned = true
    if selected then
        fill:SetTexCoord(0, 1, 0, 1)
        fill:SetDesaturated(false)
    else
        local saved = entry.barStyles and entry.barStyles.health
        if not GUF.PaintBlizzardBarFill(fill, entry.unit, "health", saved) then
            fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMP", "CLAMP", "LINEAR")
            fill:SetTexCoord(0, 1, 0, 1)
        end
        fill:SetDesaturated(true)
    end
    GUF.TintPresentationBar(bar, color[1], color[2], color[3])
end

function GUF.ApplyBars(entry)
    if entry.barStyleWriting then return end
    entry.barStyleWriting = true
    local cfg = GUF.Runtime.Settings("bars", entry).frames[entry.unit]
    entry.barStyles = entry.barStyles or {}
    for _, kind in ipairs({ "health", "power" }) do
        local bar = entry[kind]
        if bar then
            local state = entry.barStyles[kind]
            if not state then
                local texture = bar:GetStatusBarTexture()
                state = { texture = texture and texture:GetTexture(), coords = texture and { texture:GetTexCoord() },
                    atlas = texture and texture.GetAtlas and texture:GetAtlas() }
                entry.barStyles[kind] = state
                GUF.NativeProperties.Track(bar, "barMedia", entry, state)
            end
            if not state.hooked then
                GUF.NativeProperties.Hook("Bars:1", bar, "SetStatusBarTexture", function()
                    if state.writing or entry.barStyleWriting then return end
                    local current = bar:GetStatusBarTexture()
                    state.texture = current and current:GetTexture()
                    state.coords = current and { current:GetTexCoord() }
                    state.atlas = current and current.GetAtlas and current:GetAtlas()
                    GUF.ApplyBars(entry)
                end)
                state.hooked = true
            end
            local fill = bar:GetStatusBarTexture()
            state.fillHooks = state.fillHooks or {}
            if fill and not state.fillHooks[fill] then
                GUF.NativeProperties.Hook("Bars:2", fill, "SetAtlas", function()
                    if state.writing or entry.barStyleWriting then return end
                    state.texture, state.coords, state.atlas = fill:GetTexture(), { fill:GetTexCoord() }, fill:GetAtlas()
                    if GUF.Presentation.Role(entry, "ownedBars") then
                        GUF.ApplyBars(entry)
                    elseif GUF.Runtime.Settings("bars", entry).general.frameStyle == "blizzard" and entry.unit == "target" then
                        -- Classification replaces the atlas after native color
                        -- updates. Reapply saved media/tint to the new artwork.
                        GUF.ApplyBars(entry)
                        GUF.QueueTargetColorRefresh(entry)
                    end
                end)
                if entry.unit == "target" then
                    local function tintChanged()
                        if state.writing or entry.barStyleWriting or entry.coloring or entry.powerColoring then return end
                        GUF.QueueTargetColorRefresh(entry)
                    end
                    GUF.NativeProperties.Hook("Bars:3", fill, "SetDesaturated", tintChanged)
                    GUF.NativeProperties.Hook("Bars:4", fill, "SetVertexColor", tintChanged)
                end
                state.fillHooks[fill] = true
            end
            local texture = GUF.MediaTexture(cfg.bars[kind .. "Texture"])
            state.writing = true
            local render = GUF.Presentation.Role(entry, "ownedBars") and GUF.Presentation.Role(entry, kind)
            if render then
                -- Target styling belongs to the presentation bar. Rewriting the
                -- hidden source also refreshes native feedback/copy textures at
                -- their old bounds during target changes.
                if state.owned and state.texture then
                    bar:SetStatusBarTexture(state.texture)
                    if state.atlas then bar:GetStatusBarTexture():SetAtlas(state.atlas) end
                    if state.coords then bar:GetStatusBarTexture():SetTexCoord(unpack(state.coords)) end
                    state.owned = nil
                end
                local renderFill = render:GetStatusBarTexture()
                renderFill.goodUnitFramesOwned = true
                if texture then
                    renderFill:SetDesaturated(false)
                    if state.renderTexture ~= texture or state.renderHost ~= render then
                        render.goodUnitFramesFill:SetTexture(texture)
                        state.renderTexture, state.renderHost = texture, render
                    end
                    renderFill:SetTexCoord(0, 1, 0, 1)
                else
                    state.renderTexture = nil
                    if not GUF.PaintBlizzardBarFill(renderFill, entry.unit, kind, state) then
                        renderFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMP", "CLAMP", "LINEAR")
                        renderFill:SetTexCoord(0, 1, 0, 1)
                    end
                end
            elseif texture then
                bar:SetStatusBarTexture(texture)
                bar:GetStatusBarTexture():SetTexCoord(0, 1, 0, 1)
                state.owned = true
            elseif state.owned and state.texture then
                bar:SetStatusBarTexture(state.texture)
                if state.atlas then bar:GetStatusBarTexture():SetAtlas(state.atlas) end
                if state.coords then bar:GetStatusBarTexture():SetTexCoord(unpack(state.coords)) end
                state.owned = nil
            end
            state.writing = nil
            if render then
                GUF.Presentation.Feature(entry, "suppressBars")
                GUF.SyncRenderedBar(entry, kind)
            end
        end
    end
    -- Replacing a baked-color stock atlas with neutral media also requires its
    -- Blizzard hue. Keep the independent owned Target renderer out of this path.
    if not GUF.Presentation.Role(entry, "ownedBars") then GUF.UpdateColors(entry) end
    if GUF.RefreshClassResourceTexture then GUF.RefreshClassResourceTexture(entry) end
    entry.barStyleWriting = nil
end
