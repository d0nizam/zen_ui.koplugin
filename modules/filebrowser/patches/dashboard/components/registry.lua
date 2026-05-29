local components = {
    require("modules/filebrowser/patches/dashboard/components/featured_most_recent"),
    require("modules/filebrowser/patches/dashboard/components/featured_reading_first"),
    require("modules/filebrowser/patches/dashboard/components/featured_tbr_first"),
    require("modules/filebrowser/patches/dashboard/components/stats_triplet"),
    require("modules/filebrowser/patches/dashboard/components/reading_goals"),
    require("modules/filebrowser/patches/dashboard/components/strip_to_be_read"),
    require("modules/filebrowser/patches/dashboard/components/strip_reading_recent"),
    require("modules/filebrowser/patches/dashboard/components/strip_recently_read"),
    require("modules/filebrowser/patches/dashboard/components/quotes"),
}

local by_id = {}
for _i, comp in ipairs(components) do
    by_id[comp.id] = comp
end

local M = {}

function M.list()
    return components
end

function M.get(id)
    return by_id[id]
end

return M
