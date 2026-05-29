local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")

local function get_quote(ctx)
    local q = ctx.data:getCurrentQuote()
    if q then return q end
    return { text = "No quote available.", author = "" }
end

return {
    id = "quotes",
    label = "Quotes",
    size = { preferred = 150, min = 110, max = 220 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local quote = get_quote(ctx)
        local show_author = ctx.config.quotes and ctx.config.quotes.show_author ~= false

        local content_w = math.max(30, width - 20)
        local content = VerticalGroup:new{
            align = "center",
            TextBoxWidget:new{
                text = '"' .. (quote.text or "") .. '"',
                width = content_w,
                height = math.max(40, math.floor(height * 0.72)),
                face = ctx.face_label,
                alignment = "center",
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            },
        }

        if show_author and quote.author and quote.author ~= "" then
            table.insert(content, VerticalSpan:new{ width = 3 })
            table.insert(content, TextWidget:new{
                text = "- " .. quote.author,
                face = ctx.face_value,
                fgcolor = Blitbuffer.COLOR_GRAY_3,
            })
        end

        local body = FrameContainer:new{
            width = width,
            height = height,
            padding = 10,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            content,
        }

        local tap = InputContainer:new{
            dimen = Geom:new{ w = width, h = height },
            ges_events = {
                TapQuote = {
                    GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = width, h = height } },
                },
            },
        }
        tap.onTapQuote = function()
            if ctx.data.nextQuote then
                ctx.data:nextQuote()
            end
            return true
        end
        tap[1] = body
        return tap
    end,
}
