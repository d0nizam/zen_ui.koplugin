local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")

local function progress_row(width, label, current, target, face_value, face_label)
    local pct = 0
    if target > 0 then
        pct = math.min(1, math.max(0, current / target))
    end
    local bar_h = 8
    local bar_w = width
    local fill = math.floor(bar_w * pct)

    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = bar_w, h = bar_h },
        LineWidget:new{ dimen = Geom:new{ w = bar_w, h = bar_h }, background = Blitbuffer.COLOR_LIGHT_GRAY },
    }
    if fill > 0 then
        table.insert(bar, LineWidget:new{ dimen = Geom:new{ w = fill, h = bar_h }, background = Blitbuffer.COLOR_DARK_GRAY })
    end

    return VerticalGroup:new{
        TextWidget:new{ text = label, face = face_label, fgcolor = Blitbuffer.COLOR_GRAY_3 },
        VerticalSpan:new{ width = 2 },
        HorizontalGroup:new{
            TextWidget:new{ text = tostring(current), face = face_value, bold = true },
            TextWidget:new{ text = " / " .. tostring(target), face = face_label },
        },
        VerticalSpan:new{ width = 2 },
        bar,
    }
end

return {
    id = "reading_goals",
    label = "Reading goals",
    size = { preferred = 150, min = 120, max = 220 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local stats = ctx.data.stats or {}
        local goals = ctx.config.goals or {}
        local metric = goals.metric == "time" and "time" or "pages"

        local daily_target = tonumber(goals.daily_target) or 30
        if daily_target < 1 then daily_target = 1 end
        local weekly_target = tonumber(goals.weekly_target) or (daily_target * 7)
        if weekly_target < 1 then weekly_target = 1 end

        local daily_current
        local weekly_current
        if metric == "time" then
            daily_current = math.floor((stats.today_duration or 0) / 60)
            weekly_current = math.floor((stats.week_duration or 0) / 60)
        else
            daily_current = math.floor(stats.today_pages or 0)
            weekly_current = math.floor(stats.week_pages or 0)
        end

        local label_suffix = metric == "time" and " min" or " pages"
        local content_w = math.max(20, width - 16)
        local body = VerticalGroup:new{
            VerticalSpan:new{ width = 4 },
            progress_row(content_w, "Daily goal" .. label_suffix, daily_current, daily_target, ctx.face_value, ctx.face_label),
            VerticalSpan:new{ width = 8 },
            progress_row(content_w, "Weekly goal" .. label_suffix, weekly_current, weekly_target, ctx.face_value, ctx.face_label),
        }

        return FrameContainer:new{
            width = width,
            height = height,
            padding = 8,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            body,
        }
    end,
}
