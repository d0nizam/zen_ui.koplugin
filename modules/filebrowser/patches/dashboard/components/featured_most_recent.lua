local shared = require("modules/filebrowser/patches/dashboard/components/featured_common")

return {
    id = "featured_most_recent",
    label = "Featured (Most recent)",
    size = { preferred = 300, min = 220, max = 420 },
    build = function(ctx)
        return shared.build(ctx, "most_recent")
    end,
}
