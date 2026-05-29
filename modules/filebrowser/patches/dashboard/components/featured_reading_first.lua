local shared = require("modules/filebrowser/patches/dashboard/components/featured_common")

return {
    id = "featured_reading_first",
    label = "Featured (Reading)",
    size = { preferred = 300, min = 220, max = 420 },
    build = function(ctx)
        return shared.build(ctx, "reading_first")
    end,
}
