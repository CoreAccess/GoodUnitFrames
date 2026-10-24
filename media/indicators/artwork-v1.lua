local _, GUF = ...
-- Production alpha bounds and optical fitting for the bundled indicator textures.
local path = "Interface\\AddOns\\GoodUnitFrames\\media\\indicators\\"
-- Small indicators use these original glyphs without addon rings/backplates.
GUF.indicatorArtwork = {
    ["assistant"] = { path = path .. "assistant-v1-", left = 0.01674641, right = 0.98245614, top = 0.215311, bottom = 0.77830941, aspect = 1.71529745, span = 0.96570973 },
    ["leader"] = { path = path .. "leader-v1-", left = 0.03429027, right = 0.96411483, top = 0.15151515, bottom = 0.8261563, aspect = 1.37825059, span = 0.92982456 },
    ["loot"] = { path = path .. "loot-v1-", left = 0.12679426, right = 0.87400319, top = 0.05901116, bottom = 0.95215311, aspect = 0.83660714, span = 0.89314195 },
    ["pvp-alliance"] = { path = path .. "pvp-alliance-v1-", left = 0.22328549, right = 0.77511962, top = 0.06220096, bottom = 0.92424242, aspect = 0.64014801, span = 0.86204147 },
    ["pvp-ffa"] = { path = path .. "pvp-ffa-v1-", left = 0.23923445, right = 0.7599681, top = 0.02551834, bottom = 0.89712919, aspect = 0.59743824, span = 0.87161085 },
    ["pvp-horde"] = { path = path .. "pvp-horde-v1-", left = 0.04864434, right = 0.94896332, top = 0.0430622, bottom = 0.94019139, aspect = 1.00355556, span = 0.90031898 },
    ["role-damage"] = { path = path .. "role-damage-v1-", left = 0.15550239, right = 0.84449761, top = 0.14433812, bottom = 0.83253589, aspect = 1.00115875, span = 0.68899522 },
    ["role-healer"] = { path = path .. "role-healer-v1-", left = 0.14513557, right = 0.85406699, top = 0.14274322, bottom = 0.85167464, aspect = 1, span = 0.70893142 },
    ["role-tank"] = { path = path .. "role-tank-v1-", left = 0.18022329, right = 0.82057416, top = 0.17862839, bottom = 0.81818182, aspect = 1.00124688, span = 0.64035088 },
}
