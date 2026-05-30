local shared = require("modules/filebrowser/patches/dashboard/widgets/featured_common")

return {
    id = "featured_tbr",
    label = "To Be Read featured widget",
    size = { preferred = 306, min = 196, max = 476 },
    build = function(ctx)
        return shared.build(ctx, "to_be_read")
    end,
}
