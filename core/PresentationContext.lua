local _, GUF = ...
local Presentation = {}
GUF.Presentation = Presentation
local active, serial = nil, 0
local unpack = unpack or table.unpack

function Presentation.New(layout, unit, settings, mode, view, scenario, generation)
    local definition = GUF.Layouts.Get(layout)
    if not definition then error("Unknown presentation layout: " .. tostring(layout)) end
    if unit and not GUF.IsManagedUnit(unit) then error("Unsupported presentation unit.") end
    serial = serial + 1
    return { layout = layout, definition = definition, unit = unit, settings = settings,
        mode = mode, view = view, scenario = scenario or {}, generation = generation or serial,
        client = GUF.Client }
end

function Presentation.Current() return active end
function Presentation.Enter(context) local previous = active; active = context; return previous end
function Presentation.Leave(previous) active = previous end

function Presentation.With(context, fn, ...)
    local previous = Presentation.Enter(context)
    local function pack(...) return { n = select("#", ...), ... } end
    local result = pack(pcall(fn, ...))
    Presentation.Leave(previous)
    if not result[1] then
        if GUF.Secret(result[2]) then error("Presentation could not finish.", 0) end
        error(result[2], 0)
    end
    return unpack(result, 2, result.n)
end

-- Sample preferences are explicit, including inactive layout snapshots. Live
-- families continue using Runtime's separately acknowledged settings bindings.
function Presentation.SampleSettings(entry)
    if active and active.mode ~= "live" then return active.settings end
    if type(entry) == "table" and entry.configurationPreview and entry.presentationContext then
        return entry.presentationContext.settings
    end
end

function Presentation.State(entry)
    return entry.configurationPreview and entry.specimenState or entry.artisticLayout
end
GUF.PresentationState = Presentation.State

function Presentation.Role(entry, role)
    if not entry then return end
    local context = entry.configurationPreview and entry.presentationContext
    local layout = context and context.layout or GUF.Runtime.Settings("layout", entry).general.frameStyle
    local definition = GUF.Layouts.Get(layout)
    return definition and definition.presentation.role(entry, role)
end

-- Optional feature operations run in the owning layout. Absence is explicit;
-- a feature must not substitute another layout's housing or private state.
function GUF.SyncRenderedBar(entry, kind)
    return Presentation.Feature(entry, "syncBar", kind)
end

function Presentation.Feature(entry, operation, ...)
    local context = Presentation.ForEntry(entry)
    local callback = context.definition.presentation[operation]
    if callback then return callback(entry, ...) end
end

function Presentation.ForBinding(binding)
    if not binding.presentationContext then
        binding.presentationContext = Presentation.New(binding.layout, binding.owner.unit, binding.settings,
            "live", binding.owner, nil, binding.generation)
        binding.presentationContext.family = binding.family
    end
    return binding.presentationContext
end

function Presentation.ForEntry(entry)
    if entry.configurationPreview then return entry.presentationContext end
    local binding = GUF.Runtime.Binding("layout", entry)
    if binding and binding.owner == entry then return Presentation.ForBinding(binding) end
    local settings = GUF.Runtime.Settings("layout", entry)
    return Presentation.New(settings.general.frameStyle, entry.unit, settings, "live", entry)
end

function Presentation.Geometry(entry)
    local context = Presentation.ForEntry(entry)
    return context.definition.presentation.geometry(context)
end

function Presentation.LayoutBounds(context)
    if context.mode ~= "live" then return Presentation.OwnedBounds(context) end
    local geometry = context.definition.presentation.geometry(context)
    if geometry then return { left = 0, right = geometry.width, top = 0, bottom = -geometry.height } end
end
