local shared = require("modules/filebrowser/patches/dashboard/components/strip_common")

return {
    id = "strip_to_be_read",
    label = "Strip (To Be Read)",
    size = { preferred = 120, min = 90, max = 180 },
    build = function(ctx)
        return shared.build_strip(ctx, "to_be_read")
    end,
}
