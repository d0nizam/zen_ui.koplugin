local shared = require("modules/filebrowser/patches/dashboard/components/strip_common")

return {
    id = "strip_reading_recent",
    label = "Strip (Reading recent)",
    size = { preferred = 120, min = 90, max = 180 },
    build = function(ctx)
        return shared.build_strip(ctx, "reading_recent")
    end,
}
