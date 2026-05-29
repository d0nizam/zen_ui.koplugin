local shared = require("modules/filebrowser/patches/dashboard/components/strip_common")

return {
    id = "strip_recently_read",
    label = "Strip (Recently read)",
    size = { preferred = 120, min = 90, max = 180 },
    build = function(ctx)
        return shared.build_strip(ctx, "recently_read")
    end,
}
