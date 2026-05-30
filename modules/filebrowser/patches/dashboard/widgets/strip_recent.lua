local shared = require("modules/filebrowser/patches/dashboard/widgets/strip_common")

return {
    id = "strip_recent",
    label = "Recently read strip widget",
    size = { preferred = 105, min = 64, max = 150 },
    build = function(ctx)
        return shared.build_strip(ctx, "recently_read")
    end,
}
