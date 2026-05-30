local shared = require("modules/filebrowser/patches/dashboard/widgets/featured_common")

return {
    id = "featured",
    label = "Featured widget",
    size = { preferred = 306, min = 196, max = 476 },
    build = function(ctx)
        return shared.build(ctx)
    end,
}
