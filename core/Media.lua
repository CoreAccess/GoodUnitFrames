local addonName, GUF = ...
local media = LibStub("LibSharedMedia-3.0")

-- Keep the existing shared-media names so saved texture selections still work.
-- Resolve our bundled choices locally even if another addon registered them first.
GUF.barTextureChoices = { "Blizzard", "Flat", "Blizzard Raid Bar", "Charcoal", "Glaze", "Minimalist",
    "Otravi", "Smooth", "Smooth v2", "Smoother", "Striped" }
GUF.allowedBarTextures = {}
for _, name in ipairs(GUF.barTextureChoices) do GUF.allowedBarTextures[name] = true end
GUF.bundledBarTextures = {}
local textures = {
    { "Smooth", "smooth" },
    { "Smooth v2", "Smoothv2" },
    { "Smoother", "smoother" },
    { "Glaze", "glaze" },
    { "Charcoal", "Charcoal" },
    { "Otravi", "otravi" },
    { "Striped", "striped" },
    { "Minimalist", "Minimalist" },
}

for _, texture in ipairs(textures) do
    local name, file = texture[1], texture[2]
    local path = "Interface\\AddOns\\" .. addonName .. "\\media\\textures\\" .. file .. ".tga"
    GUF.bundledBarTextures[name] = path
    media:Register(media.MediaType.STATUSBAR, name, path)
end

-- LSM's extra stock aliases are not additional addon-provided choices.
local libraryDefaults = {
    ["Blizzard Character Skills Bar"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    Solid = "Interface\\Buttons\\WHITE8X8",
}

function GUF.ExternalBarTexture(name)
    if GUF.allowedBarTextures[name] then return end
    local path = media:HashTable(media.MediaType.STATUSBAR)[name]
    if not path or path == libraryDefaults[name] then return end
    local provider
    if type(path) == "string" then
        local normalized = path:gsub("/", "\\")
        if normalized:lower():find("^interface\\addons\\") then
            provider = normalized:match("^[^\\]+\\[^\\]+\\([^\\]+)\\")
        end
        -- Do not resurrect retired files from our own media directory.
        if provider and provider:lower() == addonName:lower() then return end
        -- Shared media can live in a data-only folder rather than an addon.
        -- Its live LSM registration still comes from a loaded supplier, but the
        -- folder cannot safely identify which addon must remain enabled.
        if provider and not C_AddOns.IsAddOnLoaded(provider) then provider = nil end
    end
    local title = provider and (C_AddOns.GetAddOnMetadata(provider, "Title") or provider) or "a texture addon"
    return path, title
end

function GUF.BarTextureLabel(name)
    local _, provider = GUF.ExternalBarTexture(name)
    if provider then return name .. " |cff999999(Requires: " .. provider .. ")|r" end
    if GUF.allowedBarTextures[name] then return name end
    return tostring(name) .. " |cff999999(unavailable; using Blizzard)|r"
end
