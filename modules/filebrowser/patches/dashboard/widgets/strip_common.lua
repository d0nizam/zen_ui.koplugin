local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local cover_common = require("modules/filebrowser/patches/dashboard/widgets/cover_common")
local Font = require("ui/font")
local Device = require("device")

local M = {}

function M.build_strip(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local Screen = Device.screen
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local source = source_key or "recently_read"
    local order = module_cfg.order or "default"
    local count = tonumber(module_cfg.count) or 5
    if count < 3 then count = 3 end
    if count > 5 then count = 5 end
    local show_strip_titles = module_cfg.show_strip_titles == true

    local books = ctx.data:getBooksForStrip(source, count, order)
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

    local gap = math.max(4, math.min(10, math.floor(width * 0.012)))
    local total_gap = gap * (#books - 1)
    local cover_v_pad = math.max(2, math.floor(height * 0.06))
    local slot_w = math.max(24, math.floor((width - total_gap) / #books))
    local slot_h = math.max(1, height - cover_v_pad * 2)
    local title_gap = show_strip_titles and math.max(1, math.floor(slot_h * 0.04)) or 0
    local title_h = show_strip_titles and math.max(14, math.floor(slot_h * 0.24)) or 0
    local cover_h = slot_h - title_h - title_gap
    if cover_h < 28 then
        cover_h = slot_h
        title_h = 0
        title_gap = 0
    end

    local strip_title_face = Font:getFace("smallinfofont", Screen:scaleBySize(10))

    local row = HorizontalGroup:new{ align = "center" }

    for _i, book in ipairs(books) do
        local cover = cover_common.make_cover_widget(
            book,
            slot_w,
            cover_h,
            { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY }
        )

        local tap = InputContainer:new{
            dimen = Geom:new{ w = slot_w, h = slot_h },
            ges_events = {
                TapCover = {
                    GestureRange:new{ ges = "tap", range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(), h = Screen:getHeight(),
                    } },
                },
            },
        }
        local path = book.path
        tap.onTapCover = function(tap_self, _arg, ges)
            if not tap_self.dimen or not ges or not ges.pos then
                return false
            end
            if not tap_self.dimen:contains(ges.pos) then
                return false
            end
            ctx.openBook(path)
            return true
        end

        if show_strip_titles and title_h > 0 then
            tap[1] = VerticalGroup:new{
                align = "center",
                CenterContainer:new{
                    dimen = Geom:new{ w = slot_w, h = cover_h },
                    cover,
                },
                VerticalSpan:new{ width = title_gap },
                TextBoxWidget:new{
                    text = book.title or "",
                    width = slot_w,
                    height = title_h,
                    face = strip_title_face,
                    alignment = "center",
                    fgcolor = Blitbuffer.COLOR_GRAY_3,
                    height_overflow_show_ellipsis = true,
                },
            }
        else
            tap[1] = CenterContainer:new{ dimen = Geom:new{ w = slot_w, h = slot_h }, cover }
        end

        table.insert(row, tap)
        if _i < #books then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
    end

    local row_w = slot_w * #books + total_gap
    return FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            LeftContainer:new{
                dimen = Geom:new{ w = width, h = height },
                CenterContainer:new{ dimen = Geom:new{ w = row_w, h = height }, row },
            },
        },
    }
end

return M
