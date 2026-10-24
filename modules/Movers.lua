local _, GUF = ...

-- Temporary drag handles for positioning the existing Blizzard unit frames.
local function backdrop(frame)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(.055, .065, .085, .98)
    frame:SetBackdropBorderColor(.30, .40, .52)
end

function GUF.SetFrameMovers(enabled)
    if enabled and GUF.Restricted() then GUF.Print("Frame dragging is available outside combat."); return end
    if enabled and GUF.editing then GUF.Print("Exit Blizzard Edit Mode before using addon frame dragging."); return end
    GUF.frameMoversUnlocked = enabled and true or nil
    GUF.movers = GUF.movers or {}
    for _, unit in ipairs(GUF.order) do
        local entry = GUF.frames[unit]
        if entry then
            local mover = GUF.movers[unit]
            if not mover and enabled then
                mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                GUF.movers[unit] = mover
                mover:SetAllPoints(entry.frame)
                mover:SetFrameStrata("HIGH")
                mover:SetFrameLevel(1)
                mover:EnableMouse(true)
                mover:RegisterForDrag("LeftButton")
                backdrop(mover)
                mover:SetBackdropColor(.12, .40, .55, .5)
                local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                label:SetPoint("TOPLEFT", 8, -6)
                label:SetJustifyH("LEFT")
                label:SetText(GUF.labels[unit])
                mover:SetScript("OnDragStart", function(self)
                    if InCombatLockdown() then return end
                    local cfg = GUF.db.frames[unit].position
                    local x, y = entry.frame:GetCenter()
                    if not x then return end
                    local scale = entry.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    cfg.enabled, cfg.point, cfg.anchorTo, cfg.relativePoint = true, "CENTER", "UIParent", "BOTTOMLEFT"
                    cfg.x, cfg.y = x * scale, y * scale
                    GUF.ApplyPosition(entry)
                    self.dragStart = { GetCursorPosition() }
                    self.origin = { cfg.x, cfg.y }
                    self:SetScript("OnUpdate", function(control)
                        if InCombatLockdown() then control:SetScript("OnUpdate", nil); return end
                        local cx, cy = GetCursorPosition()
                        cfg.x = control.origin[1] + (cx - control.dragStart[1]) / UIParent:GetEffectiveScale()
                        cfg.y = control.origin[2] + (cy - control.dragStart[2]) / UIParent:GetEffectiveScale()
                        GUF.ApplyPosition(entry)
                    end)
                end)
                mover:SetScript("OnDragStop", function(self)
                    self:SetScript("OnUpdate", nil)
                    local cfg = GUF.db.frames[unit].position
                    cfg.x, cfg.y = math.floor(cfg.x + .5), math.floor(cfg.y + .5)
                    GUF.RequestApply()
                    if GUF.options and GUF.options:IsShown() then GUF.BuildOptions(unit) end
                end)
                mover:SetScript("OnMouseUp", function(_, mouseButton)
                    if mouseButton == "RightButton" then GUF.SetFrameMovers(false); GUF.SetMovers(false) end
                end)
            end
            if mover then
                mover:SetScript("OnUpdate", nil)
                mover:SetShown(enabled)
            end
        end
    end
    if GUF.UpdateConfigurationButton then GUF.UpdateConfigurationButton() end
end

-- Preserve existing callers, including /guf and Blizzard Edit Mode cleanup.
function GUF.SetMovers(enabled) GUF.SetConfigurationMode(enabled) end

