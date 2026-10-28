local _, GUF = ...

-- Monster rank is expressed by four independently painted variants. No plaque
-- or dedicated rank label is drawn; retain this release path for cached hosts.
function GUF.HideCreatureRank(entry)
    local rank = entry.artisticLayout and entry.artisticLayout.creatureRank
    if rank then rank:Hide() end
end

function GUF.LayoutCreatureRank(entry)
    GUF.HideCreatureRank(entry)
end
