local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Device = require("device")

local M = {}

local function render_progress(percent, w, h)
    local pct = percent or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end

    local fill_w = math.floor(w * pct)
    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        LineWidget:new{ dimen = Geom:new{ w = w, h = h }, background = Blitbuffer.COLOR_LIGHT_GRAY },
    }
    if fill_w > 0 then
        table.insert(bar, LineWidget:new{ dimen = Geom:new{ w = fill_w, h = h }, background = Blitbuffer.COLOR_DARK_GRAY })
    end
    return bar
end

function M.build(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local book = ctx.data:getFeaturedBook(source_key)

    local pad = math.max(6, math.floor(height * 0.05))
    local gap = math.max(8, math.floor(height * 0.04))

    if not book then
        return FrameContainer:new{
            width = width,
            height = height,
            padding = pad,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = width - pad * 2, h = height - pad * 2 },
                TextWidget:new{ text = "No books found", face = ctx.face_label },
            },
        }
    end

    local cover_h = math.max(50, height - pad * 2)
    local cover_w = math.max(30, math.floor(cover_h * (2 / 3)))

    local cover_widget
    if book.cover_bb then
        cover_widget = ImageWidget:new{
            image = book.cover_bb,
            width = cover_w,
            height = cover_h,
            scale_factor = 1,
        }
    else
        cover_widget = FrameContainer:new{
            width = cover_w,
            height = cover_h,
            bordersize = 1,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
    end

    local text_w = math.max(40, width - (pad * 2 + cover_w + gap))
    local pct = math.floor((book.percent or 0) * 100 + 0.5)
    local pages_text = book.pages and (tostring(book.pages) .. " pages") or ""

    local progress_h = math.max(4, math.floor(height * 0.04))
    local progress_w = text_w

    local detail = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = book.title or "",
            width = text_w,
            height = math.max(30, math.floor(height * 0.38)),
            face = ctx.face_title,
            bold = true,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = math.max(2, math.floor(height * 0.03)) },
        TextBoxWidget:new{
            text = book.authors or "",
            width = text_w,
            height = math.max(22, math.floor(height * 0.18)),
            face = ctx.face_label,
            fgcolor = Blitbuffer.COLOR_GRAY_3,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = math.max(4, math.floor(height * 0.05)) },
        render_progress(book.percent, progress_w, progress_h),
        VerticalSpan:new{ width = math.max(3, math.floor(height * 0.03)) },
        HorizontalGroup:new{
            TextWidget:new{ text = tostring(pct) .. "%", face = ctx.face_value },
            HorizontalSpan:new{ width = 10 },
            TextWidget:new{ text = pages_text, face = ctx.face_label, fgcolor = Blitbuffer.COLOR_GRAY_3 },
        },
    }

    local body = HorizontalGroup:new{
        HorizontalSpan:new{ width = pad },
        cover_widget,
        HorizontalSpan:new{ width = gap },
        detail,
    }

    local tap = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            TapFeatured = {
                GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = width, h = height } },
            },
        },
    }
    tap.onTapFeatured = function()
        ctx.openBook(book.path)
        return true
    end
    tap[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        body,
    }

    if not Device:isTouchDevice() then
        return tap[1]
    end
    return tap
end

return M
