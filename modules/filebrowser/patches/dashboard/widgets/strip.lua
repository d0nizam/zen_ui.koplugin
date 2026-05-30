local shared = require("modules/filebrowser/patches/dashboard/widgets/strip_common")

return {
    id = "strip",
    label = "Strip widget",
    size = { preferred = 105, min = 64, max = 150 },
    build = function(ctx)
        return shared.build_strip(ctx)
    end,
}
