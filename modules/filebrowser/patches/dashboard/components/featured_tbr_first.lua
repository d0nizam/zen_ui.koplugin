local shared = require("modules/filebrowser/patches/dashboard/components/featured_common")

return {
    id = "featured_tbr_first",
    label = "Featured (To Be Read)",
    size = { preferred = 300, min = 220, max = 420 },
    build = function(ctx)
        return shared.build(ctx, "tbr_first")
    end,
}
