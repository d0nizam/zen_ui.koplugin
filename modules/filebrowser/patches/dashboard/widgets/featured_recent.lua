local shared = require("modules/filebrowser/patches/dashboard/widgets/featured_common")

return {
    id = "featured_recent",
    label = "Recently read featured widget",
    size = { preferred = 306, min = 196, max = 476 },
    build = function(ctx)
        return shared.build(ctx, "recently_read")
    end,
}
