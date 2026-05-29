local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")

local function fmt_time(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0m" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return h .. "h " .. m .. "m"
    end
    return m .. "m"
end

local FIELD_MAP = {
    today_pages = { label = "Pages today", get = function(s) return tostring(s.today_pages or 0) end },
    today_duration = { label = "Read today", get = function(s) return fmt_time(s.today_duration or 0) end },
    streak = { label = "Day streak", get = function(s) return tostring(s.streak or 0) end },
    week_pages = { label = "Week pages", get = function(s) return tostring(s.week_pages or 0) end },
    week_duration = { label = "Week time", get = function(s) return fmt_time(s.week_duration or 0) end },
}

return {
    id = "stats_triplet",
    label = "Stats triplet",
    size = { preferred = 130, min = 110, max = 200 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local stats = ctx.data.stats or {}

        local config = ctx.config.middle_stats_triplet or { "today_pages", "today_duration", "streak" }
        local fields = {}
        for _i, fid in ipairs(config) do
            local entry = FIELD_MAP[fid] or FIELD_MAP.today_pages
            table.insert(fields, entry)
            if #fields >= 3 then break end
        end
        while #fields < 3 do
            table.insert(fields, FIELD_MAP.today_pages)
        end

        local cell_w = math.max(20, math.floor((width - 16) / 3))
        local card_h = math.max(20, height - 8)
        local row = HorizontalGroup:new{ align = "center" }

        for _i, field in ipairs(fields) do
            local card = FrameContainer:new{
                width = cell_w,
                height = card_h,
                padding = 6,
                bordersize = 0,
                radius = 8,
                background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = cell_w - 12, h = card_h - 12 },
                    VerticalGroup:new{
                        align = "center",
                        TextWidget:new{ text = field.get(stats), face = ctx.face_value, bold = true },
                        VerticalSpan:new{ width = 2 },
                        TextWidget:new{ text = field.label, face = ctx.face_label, fgcolor = Blitbuffer.COLOR_GRAY_3 },
                    },
                },
            }
            table.insert(row, card)
            if _i < 3 then
                table.insert(row, HorizontalSpan:new{ width = 4 })
            end
        end

        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, row },
        }
    end,
}
