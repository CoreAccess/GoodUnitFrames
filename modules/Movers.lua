local _, GUF = ...

local function number(value)
    return not GUF.Secret(value) and type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

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
                    if GUF.Restricted() or GUF.editing then return end
                    local forbidden = entry.frame.IsForbidden and entry.frame:IsForbidden()
                    if GUF.Secret(forbidden) or forbidden then return end
                    local cfg = GUF.db.frames[unit].position
                    local x, y = entry.frame:GetCenter()
                    local frameScale, screenScale = entry.frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
                    local cursorX, cursorY = GetCursorPosition()
                    if not number(x) or not number(y) or not number(frameScale) or not number(screenScale)
                        or not number(cursorX) or not number(cursorY) or frameScale <= 0 or screenScale <= 0 then return end
                    local session = GUF.BeginFramePositionDrag(entry)
                    if not session then return end
                    self.positionSession = session
                    local scale = frameScale / screenScale
                    cfg.enabled, cfg.point, cfg.anchorTo, cfg.relativePoint = true, "CENTER", "UIParent", "BOTTOMLEFT"
                    cfg.x, cfg.y = x * scale, y * scale
                    GUF.ApplyPosition(entry, nil, session)
                    self.dragStart = { cursorX, cursorY }
                    self.origin = { cfg.x, cfg.y }
                    self:SetScript("OnUpdate", function(control)
                        if GUF.Restricted() or GUF.editing or not GUF.FramePositionDragIsCurrent(entry, session) then
                            control:SetScript("OnUpdate", nil)
                            GUF.EndFramePositionDrag(entry, session)
                            control.positionSession = nil
                            return
                        end
                        local cx, cy = GetCursorPosition()
                        local screenScale = UIParent:GetEffectiveScale()
                        if not number(cx) or not number(cy) or not number(screenScale) or screenScale <= 0 then return end
                        cfg.x = control.origin[1] + (cx - control.dragStart[1]) / screenScale
                        cfg.y = control.origin[2] + (cy - control.dragStart[2]) / screenScale
                        GUF.ApplyPosition(entry, nil, session)
                    end)
                end)
                mover:SetScript("OnDragStop", function(self)
                    self:SetScript("OnUpdate", nil)
                    local session = self.positionSession
                    if GUF.FramePositionDragIsCurrent(entry, session) then
                        local cfg = session.position
                        cfg.x, cfg.y = math.floor(cfg.x + .5), math.floor(cfg.y + .5)
                    end
                    GUF.EndFramePositionDrag(entry, session)
                    self.positionSession = nil
                    GUF.RequestApply(nil, nil, "mover")
                    if GUF.options and GUF.options:IsShown() then GUF.BuildOptions(unit) end
                end)
                mover:SetScript("OnMouseUp", function(_, mouseButton)
                    if mouseButton == "RightButton" then GUF.SetMovers(false) end
                end)
                mover:SetScript("OnHide", function(self)
                    self:SetScript("OnUpdate", nil)
                    GUF.EndFramePositionDrag(entry, self.positionSession)
                    self.positionSession = nil
                end)
            end
            if mover then
                mover:SetScript("OnUpdate", nil)
                GUF.EndFramePositionDrag(entry, mover.positionSession)
                mover.positionSession = nil
                mover:SetShown(enabled)
            end
        end
    end
    if GUF.UpdateConfigurationButton then GUF.UpdateConfigurationButton() end
end

-- Preserve existing callers, including /guf and Blizzard Edit Mode cleanup.
function GUF.SetMovers(enabled) GUF.SetConfigurationMode(enabled) end

