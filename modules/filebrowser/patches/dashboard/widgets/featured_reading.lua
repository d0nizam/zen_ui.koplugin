local shared = require("modules/filebrowser/patches/dashboard/widgets/featured_common")

return {
    id = "featured_reading",
    label = "Reading featured widget",
    size = { preferred = 306, min = 196, max = 476 },
    build = function(ctx)
        return shared.build(ctx, "currently_reading")
    end,
}
