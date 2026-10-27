local _, GUF = ...
local Client = {}
GUF.Client = Client

-- Forever also reports Mainline. Preserve its public interface-band check
-- before Retail classification; this is the existing supported-client rule.
Client.interface = select(4, GetBuildInfo())
Client.isForever = type(Client.interface) == "number" and Client.interface >= 16000 and Client.interface < 17000
Client.isRetail = not Client.isForever and WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    and type(Client.interface) == "number" and Client.interface >= 100000

function Client.IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Preserve the existing conservative structural-apply gate. This does not
-- establish permission for an arbitrary API, value read or frame mutation.
function Client.StructuralChangesRestricted()
    return InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret
        and C_Secrets.ShouldAurasBeSecret()) or false
end

-- Discovery only: ready means a reference exists, not that it may be changed.
-- The caller supplies a live native root for Target, including when rendering
-- a specimen. No settings, preview lookup, hooks or controller writes belong
-- here. Recheck globals on every call so late/replaced objects can be found.
function Client.ResolveCastBar(unit, frame)
    if Client.IsSecret(unit) then return nil, "restricted" end
    local bar
    if unit == "player" then bar = PlayerCastingBarFrame or CastingBarFrame
    elseif unit == "pet" then bar = PetCastingBarFrame
    elseif unit == "target" then
        bar = frame and (frame.spellbar or frame.SpellBar) or TargetFrameSpellBar
    else return nil, "unsupported-unit" end
    if not bar then return nil, "not-ready" end
    return bar, "ready"
end

-- Druid's temporary summons use the native totem display. Resolve the host
-- without reading summon slots, durations or counts; other classes retain it.
function Client.ResolveDruidSummonFrame()
    local _, class = UnitClass("player")
    if Client.IsSecret(class) or class ~= "DRUID" then return end
    return TotemFrame
end
