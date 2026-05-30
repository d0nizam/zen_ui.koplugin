local shared = require("modules/filebrowser/patches/dashboard/widgets/strip_common")

return {
    id = "strip_tbr",
    label = "To Be Read strip widget",
    size = { preferred = 105, min = 64, max = 150 },
    build = function(ctx)
        return shared.build_strip(ctx, "to_be_read")
    end,
}
