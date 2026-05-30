local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Font = require("ui/font")
local Device = require("device")

local function progress_bar(width, current, target, bar_h)
    local pct = 0
    if target > 0 then
        pct = math.min(1, math.max(0, current / target))
    end
    local bar_w = width
    local fill = math.floor(bar_w * pct)

    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = bar_w, h = bar_h },
        LineWidget:new{ dimen = Geom:new{ w = bar_w, h = bar_h }, background = Blitbuffer.COLOR_LIGHT_GRAY },
    }
    if fill > 0 then
        table.insert(bar, LineWidget:new{ dimen = Geom:new{ w = fill, h = bar_h }, background = Blitbuffer.COLOR_DARK_GRAY })
    end

    return bar, math.floor(pct * 100 + 0.5)
end

return {
    id = "reading_goals",
    label = "Reading goals widget",
    size = { preferred = 90, min = 56, max = 130 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local stats = ctx.data.stats or {}
        local goals = ctx.config.goals or {}
        local metric = goals.metric == "time" and "time" or "pages"
        local period = goals.period == "weekly" and "weekly" or "daily"
        local Screen = Device.screen

        local daily_pages_target = tonumber(goals.daily_pages_target) or 30
        if daily_pages_target < 1 then daily_pages_target = 1 end
        local weekly_pages_target = tonumber(goals.weekly_pages_target) or 210
        if weekly_pages_target < 1 then weekly_pages_target = 1 end
        local daily_time_target_min = tonumber(goals.daily_time_target_min) or 30
        if daily_time_target_min < 1 then daily_time_target_min = 1 end
        local weekly_time_target_min = tonumber(goals.weekly_time_target_min) or 210
        if weekly_time_target_min < 1 then weekly_time_target_min = 1 end

        local daily_current
        local weekly_current
        if metric == "time" then
            daily_current = math.floor((stats.today_duration or 0) / 60)
            weekly_current = math.floor((stats.week_duration or 0) / 60)
        else
            daily_current = math.floor(stats.today_pages or 0)
            weekly_current = math.floor(stats.week_pages or 0)
        end

        local target
        if metric == "time" then
            target = period == "weekly" and weekly_time_target_min or daily_time_target_min
        else
            target = period == "weekly" and weekly_pages_target or daily_pages_target
        end
        local current = period == "weekly" and weekly_current or daily_current
        local label = period == "weekly" and "Weekly goal" or "Daily goal"
        local unit = metric == "time" and "min" or "pages"
        local value_probe_text = tostring(current) .. " / " .. tostring(target) .. " " .. unit .. " (100%)"
        local pad_h = math.max(4, math.floor(width * 0.012))
        local content_w = math.max(20, width - pad_h * 2)
        local max_px = math.max(7, math.min(10, math.floor(height * 0.13)))
        local min_px = 6
        local min_bar_w = math.max(24, math.floor(content_w * 0.16))
        local gap = math.max(2, math.floor(content_w * 0.01))
        local chosen_face
        local left_text_w = 0
        local right_text_w = 0

        for px = max_px, min_px, -1 do
            local face = Font:getFace("smallinfofont", Screen:scaleBySize(px))
            local left_probe = TextWidget:new{ text = label, face = face }
            local right_probe = TextWidget:new{ text = value_probe_text, face = face }
            local lw = left_probe:getSize().w or 0
            local rw = right_probe:getSize().w or 0
            if left_probe.free then left_probe:free() end
            if right_probe.free then right_probe:free() end
            if lw + rw + (gap * 2) + min_bar_w <= content_w then
                chosen_face = face
                left_text_w = lw
                right_text_w = rw
                break
            end
        end
        if not chosen_face then
            chosen_face = Font:getFace("smallinfofont", Screen:scaleBySize(min_px))
            local left_probe = TextWidget:new{ text = label, face = chosen_face }
            local right_probe = TextWidget:new{ text = value_probe_text, face = chosen_face }
            left_text_w = left_probe:getSize().w or 0
            right_text_w = right_probe:getSize().w or 0
            if left_probe.free then left_probe:free() end
            if right_probe.free then right_probe:free() end
        end

        local line_probe = TextWidget:new{ text = "A", face = chosen_face }
        local line_h = line_probe:getSize().h or math.max(10, min_px)
        if line_probe.free then line_probe:free() end
        local bar_h = math.max(3, math.min(6, math.floor(line_h * 0.35)))

        local left_w = math.max(1, left_text_w + 2)
        local right_w = math.max(1, right_text_w + 2)
        local whitespace_w = math.max(1, content_w - left_w - right_w)
        gap = math.max(1, math.floor(whitespace_w * 0.05))
        local bar_w = whitespace_w - gap * 2
        if bar_w < min_bar_w and whitespace_w > min_bar_w then
            bar_w = min_bar_w
            gap = math.max(1, math.floor((whitespace_w - bar_w) / 2))
        end
        if bar_w < 1 then bar_w = 1 end
        local bar, pct = progress_bar(bar_w, current, target, bar_h)
        local value_text = tostring(current) .. " / " .. tostring(target) .. " " .. unit .. " (" .. tostring(pct) .. "%)"

        local body = HorizontalGroup:new{
            LeftContainer:new{
                dimen = Geom:new{ w = left_w, h = line_h },
                TextWidget:new{ text = label, face = chosen_face, fgcolor = Blitbuffer.COLOR_GRAY_3 },
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = bar_w, h = line_h },
                bar,
            },
            HorizontalSpan:new{ width = gap },
            RightContainer:new{
                dimen = Geom:new{ w = right_w, h = line_h },
                TextWidget:new{
                    text = value_text,
                    face = chosen_face,
                    fgcolor = Blitbuffer.COLOR_GRAY_3,
                },
            },
        }

        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                body,
            },
        }
    end,
}
