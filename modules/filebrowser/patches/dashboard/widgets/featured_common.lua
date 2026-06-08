local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Font = require("ui/font")
local util = require("util")
local zen_utils = require("common/utils")
local cover_common = require("modules/filebrowser/patches/dashboard/widgets/cover_common")
local _ = require("gettext")

local M = {}
M.SIZE = { preferred_pct = 0.36, min_pct = 0.22, max_pct = 0.50, grow_priority = 1 }

local function clamp(v, min_v, max_v)
    if v < min_v then return min_v end
    if v > max_v then return max_v end
    return v
end

local function paint_pill(bb, x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    if h <= 1 then
        bb:paintRect(x, y, w, h, color)
        return
    end
    local r = math.floor(h / 2)
    if w <= h then
        local cx = x + math.floor(w / 2)
        for row = 0, h - 1 do
            local dy = row - r + 0.5
            local half = math.floor(math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
            local x0 = math.max(x, cx - half)
            local rw = math.min(w, half * 2)
            if rw > 0 then bb:paintRect(x0, y + row, rw, 1, color) end
        end
        return
    end
    for row = 0, h - 1 do
        local dy = row - r + 0.5
        local inset = math.floor(r - math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
        local rw = w - inset * 2
        if rw > 0 then bb:paintRect(x + inset, y + row, rw, 1, color) end
    end
end

local function render_progress(percent, w, h)
    local pct = percent or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end

    local fill_w = math.floor(w * pct)
    return {
        dimen = Geom:new{ w = w, h = h },
        getSize = function(self)
            return self.dimen
        end,
        handleEvent = function()
            return false
        end,
        paintTo = function(_self, bb, x, y)
            paint_pill(bb, x, y, w, h, Blitbuffer.COLOR_LIGHT_GRAY)
            if fill_w > 0 then
                paint_pill(bb, x, y, fill_w, h, Blitbuffer.COLOR_DARK_GRAY)
            end
        end,
    }
end

local function fmt_duration(secs)
    secs = math.floor(tonumber(secs) or 0)
    if secs <= 0 then return "" end
    local hours = math.floor(secs / 3600)
    local mins = math.floor((secs % 3600) / 60)
    if hours > 0 then
        return tostring(hours) .. "h " .. tostring(mins) .. "m"
    end
    return tostring(math.max(1, mins)) .. "m"
end

local function build_progress_text(book, pct, progress_meta)
    progress_meta = type(progress_meta) == "table" and progress_meta or {}
    local left = {}
    local right = {}
    local total_pages = tonumber(book.pages)
    local current_page = tonumber(book.current_page)
    local time_left = fmt_duration(book.time_left_secs)
    local entries = {
        total_pages = total_pages and zen_utils.formatPageCount(total_pages, true) or "",
        current_total = total_pages and current_page and (tostring(current_page) .. " / " .. tostring(total_pages)) or "",
        percent = tostring(pct) .. "%",
        time_left = time_left ~= "" and string.format(_("%s left"), time_left) or "",
    }
    local order = { "total_pages", "current_total", "percent", "time_left" }
    for _i, key in ipairs(order) do
        local text = entries[key]
        if text and text ~= "" then
            if progress_meta.left == key then
                left[#left + 1] = text
            end
            if progress_meta.right == key then
                right[#right + 1] = text
            end
        end
    end
    return table.concat(left, "  \194\183  "), table.concat(right, "  \194\183  ")
end

function M.build(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local interactive = module_cfg.interactive ~= false
    local source = source_key or "recently_read"
    local order = module_cfg.order or "default"
    local book = ctx.data:getFeaturedBook(source, order)
    local Screen = Device.screen
    local show_description = module_cfg.show_description ~= false
    local show_status_bar = module_cfg.show_status_bar == true and type(ctx.buildStatusRow) == "function"

    local cover_v_pad = math.max(1, math.floor(height * 0.015))
    local gap = math.max(4, math.floor(width * 0.025))

    if not book then
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

    local cover_slot_h = math.max(1, height - cover_v_pad * 2)
    local min_text_w = math.max(40, math.floor(width * 0.36))
    local max_cover_w = math.max(1, width - gap - min_text_w)
    local cover_max_w = math.max(1, math.min(math.floor(width * 0.46), math.floor(cover_slot_h * 0.76), max_cover_w))
    local cover_widget, cover_w = cover_common.make_cover_widget(
        book,
        cover_max_w,
        cover_slot_h,
        { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY }
    )
    local cover_slot_w = cover_w or cover_max_w
    local cover_size = cover_widget and cover_widget.getSize and cover_widget:getSize() or nil
    local cover_content_h = cover_size and cover_size.h or cover_slot_h
    if cover_content_h < 1 then cover_content_h = cover_slot_h end
    if cover_content_h > cover_slot_h then cover_content_h = cover_slot_h end
    local detail_top_pad = math.max(0, math.floor((cover_slot_h - cover_content_h) / 2))
    local detail_content_h = math.max(1, cover_content_h)
    gap = math.min(gap, math.max(0, width - cover_slot_w - 1))

    local text_w = math.max(1, width - (cover_slot_w + gap))
    local pct = math.floor((book.percent or 0) * 100 + 0.5)
    local left_progress_text, right_progress_text = build_progress_text(book, pct, module_cfg.progress_meta)
    local has_progress_text = left_progress_text ~= "" or right_progress_text ~= ""

    local progress_h = math.min(detail_content_h, math.max(1, math.floor(height * 0.022)))
    local scale = clamp(cover_slot_h / 300, 0.55, 1.28)
    local title_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(11 * scale + 0.5)))
    local meta_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(9 * scale + 0.5)))
    local desc_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(7 * scale + 0.5)))
    local stats_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(6.5 * scale + 0.5)))
    local text_h = has_progress_text and (TextWidget:new{ text = "A", face = stats_face }:getSize().h or 8) or 0
    local stats_h = math.max(progress_h, text_h)

    local status_widget = show_status_bar and ctx.buildStatusRow(text_w, {
        padding = 0,
        font_name = "xx_smallinfofont",
        font_size_delta = -2,
        row_height = 14,
        bold_text = module_cfg.status_bar_bold_text ~= false,
        show_bottom_border = module_cfg.status_bar_show_bottom_border ~= false,
    }) or nil
    local status_h = status_widget and (status_widget:getSize().h or 0) or 0
    local status_top_pad = status_h > 0 and math.max(2, math.floor(detail_content_h * 0.012)) or 0
    local status_gap = status_h > 0 and math.max(1, math.floor(detail_content_h * 0.015)) or 0

    local title_line_h = math.max(1, math.floor((tonumber(title_face.size) or 12) * 1.05 + 0.5))
    local author_line_h = math.max(1, math.floor((tonumber(meta_face.size) or 10) * 1.05 + 0.5))
    local desc_line_h = TextWidget:new{ text = "A", face = desc_face }:getSize().h or 8
    local author_text = book.authors or ""
    local has_author = show_description and author_text ~= ""
    local title_h = show_description
        and math.min(detail_content_h, title_line_h)
        or math.max(math.min(title_line_h, detail_content_h), math.floor(detail_content_h * 0.22))
    local author_h = has_author and math.min(detail_content_h, author_line_h) or 0
    local title_author_gap = author_h > 0 and math.max(1, Screen:scaleBySize(1)) or 0
    local before_desc_gap = show_description and math.max(1, math.floor(detail_content_h * 0.02)) or 0
    local after_desc_gap = show_description and math.max(1, math.floor(detail_content_h * 0.01)) or 0
    local bottom_block_h = math.max(progress_h, stats_h)
    if bottom_block_h > detail_content_h then
        bottom_block_h = detail_content_h
    end
    local top_block_h = status_top_pad + status_h + status_gap
    if top_block_h + bottom_block_h > detail_content_h then
        status_widget = nil
        status_h = 0
        status_top_pad = 0
        status_gap = 0
        top_block_h = 0
    end
    if top_block_h + title_h + title_author_gap + author_h + bottom_block_h > detail_content_h then
        local text_budget = math.max(0, detail_content_h - top_block_h - bottom_block_h)
        if text_budget < 1 then
            title_h = 0
            author_h = 0
            title_author_gap = 0
        else
            local author_budget = has_author and math.min(author_h, math.floor(text_budget * 0.35)) or 0
            title_h = math.min(title_h, math.max(1, text_budget - title_author_gap - author_budget))
            author_h = has_author and math.max(0, text_budget - title_author_gap - title_h) or 0
            if title_h <= 0 or author_h <= 0 then title_author_gap = 0 end
        end
    end
    local fixed_h = top_block_h + title_h + title_author_gap + author_h + bottom_block_h
    local desc_text = book.description and util.htmlToPlainTextIfHtml(book.description) or ""
    local can_show_desc = show_description
        and type(desc_text) == "string"
        and desc_text ~= ""
        and detail_content_h >= fixed_h + before_desc_gap + after_desc_gap + desc_line_h
    local progress_row = nil
    if stats_h > 0 then
        if has_progress_text then
            local left_widget = TextWidget:new{ text = left_progress_text, face = stats_face, fgcolor = Blitbuffer.COLOR_GRAY_3 }
            local right_widget = TextWidget:new{ text = right_progress_text, face = stats_face, fgcolor = Blitbuffer.COLOR_GRAY_3 }
            local left_w = left_widget:getSize().w
            local right_w = right_widget:getSize().w
            local text_gap = math.max(4, math.floor(text_w * 0.02))
            local bar_w = math.max(20, text_w - left_w - right_w - text_gap * 2)
            progress_row = HorizontalGroup:new{
                align = "center",
                left_widget,
                HorizontalSpan:new{ width = text_gap },
                render_progress(book.percent, bar_w, progress_h),
                HorizontalSpan:new{ width = text_gap },
                right_widget,
            }
        else
            progress_row = render_progress(book.percent, text_w, progress_h)
        end
    end
    local has_desc = false
    local detail_children = { align = "left" }
    if detail_top_pad > 0 then
        table.insert(detail_children, VerticalSpan:new{ width = detail_top_pad })
    end
    if status_widget and status_h > 0 then
        if status_top_pad > 0 then
            table.insert(detail_children, VerticalSpan:new{ width = status_top_pad })
        end
        table.insert(detail_children, status_widget)
        if status_gap > 0 then
            table.insert(detail_children, VerticalSpan:new{ width = status_gap })
        end
    end
    if title_h > 0 then
        table.insert(detail_children, TextBoxWidget:new{
            text = book.title or "",
            width = text_w,
            height = title_h,
            face = title_face,
            bold = true,
            line_height = 0,
            height_overflow_show_ellipsis = true,
        })
    end
    if title_author_gap > 0 then
        table.insert(detail_children, VerticalSpan:new{ width = title_author_gap })
    end
    if has_author and author_h > 0 then
        table.insert(detail_children, TextBoxWidget:new{
            text = author_text,
            width = text_w,
            height = author_h,
            face = meta_face,
            line_height = 0,
            fgcolor = Blitbuffer.COLOR_GRAY_3,
            height_overflow_show_ellipsis = true,
        })
        if can_show_desc then
            local desc_h = detail_content_h - (fixed_h + before_desc_gap + after_desc_gap)
            table.insert(detail_children, VerticalSpan:new{ width = before_desc_gap })
            table.insert(detail_children, TextBoxWidget:new{
                text = desc_text,
                width = text_w,
                height = desc_h,
                face = desc_face,
                fgcolor = Blitbuffer.COLOR_GRAY_3,
                height_overflow_show_ellipsis = true,
            })
            table.insert(detail_children, VerticalSpan:new{ width = after_desc_gap })
            has_desc = true
        end
    end
    if not has_desc then
        local used_h = top_block_h + title_h + title_author_gap + author_h + bottom_block_h
        local spare_h = detail_content_h - used_h
        if spare_h > 0 then
            table.insert(detail_children, VerticalSpan:new{ width = spare_h })
        end
    end
    if progress_row then
        table.insert(detail_children, progress_row)
    end
    local detail = FrameContainer:new{
        width = text_w,
        height = cover_slot_h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new(detail_children),
    }

    local body = HorizontalGroup:new{
        CenterContainer:new{
            dimen = Geom:new{ w = cover_slot_w, h = cover_slot_h },
            cover_widget,
        },
        HorizontalSpan:new{ width = gap },
        detail,
    }

    local frame = FrameContainer:new{
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

    if not Device:isTouchDevice() or not interactive then
        return frame
    end
    local tap = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            TapFeatured = {
                GestureRange:new{ ges = "tap", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
            HoldFeatured = {
                GestureRange:new{ ges = "hold", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
        },
    }
    tap.onTapFeatured = function(tap_self, _arg, ges)
        if not tap_self.dimen or not ges or not ges.pos then return false end
        if ctx.openTopMenu and ctx.openTopMenu(ges) then return true end
        if not tap_self.dimen:contains(ges.pos) then return false end
        ctx.openBook(book.path)
        return true
    end
    tap.onHoldFeatured = function(tap_self, _arg, ges)
        if not tap_self.dimen or not ges or not ges.pos then return false end
        if not tap_self.dimen:contains(ges.pos) then return false end
        if ctx.showBookMenu then return ctx.showBookMenu(book.path) end
        return false
    end
    tap[1] = frame
    return tap
end

return M
