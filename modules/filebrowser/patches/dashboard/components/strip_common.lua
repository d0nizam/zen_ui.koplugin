local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local VerticalGroup = require("ui/widget/verticalgroup")

local M = {}

function M.build_strip(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local count = tonumber(ctx.config.bottom_count) or 5
    if count < 3 then count = 3 end
    if count > 5 then count = 5 end

    local books = ctx.data:getBooksForStrip(source_key, count)
    if #books == 0 then
        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                TextWidget:new{ text = "No books found", face = ctx.face_label },
            },
        }
    end

    local gap = 6
    local total_gap = gap * (#books - 1)
    local slot_w = math.max(24, math.floor((width - total_gap) / #books))
    local slot_h = math.max(40, height - 2)

    local row = HorizontalGroup:new{ align = "center" }

    for _i, book in ipairs(books) do
        local cover_w = math.max(20, math.floor(slot_h * (2 / 3)))
        if cover_w > slot_w then
            cover_w = slot_w
        end

        local cover
        if book.cover_bb then
            cover = ImageWidget:new{
                image = book.cover_bb,
                width = cover_w,
                height = slot_h,
                scale_factor = 1,
            }
        else
            cover = FrameContainer:new{
                width = cover_w,
                height = slot_h,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                bordersize = 1,
            }
        end

        local tap = InputContainer:new{
            dimen = Geom:new{ w = slot_w, h = slot_h },
            ges_events = {
                TapCover = {
                    GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = slot_w, h = slot_h } },
                },
            },
        }
        local path = book.path
        tap.onTapCover = function()
            ctx.openBook(path)
            return true
        end

        tap[1] = CenterContainer:new{ dimen = Geom:new{ w = slot_w, h = slot_h }, cover }

        table.insert(row, tap)
        if _i < #books then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
    end

    return FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, row },
        },
    }
end

return M
