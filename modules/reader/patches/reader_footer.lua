local function apply_reader_footer()
    -- Patches genAllFooterText to implement true L/C/R layout when both
    -- "dynamic_filler" and "dynamic_filler_2" are enabled in settings.order.
    -- Single-filler presets are unaffected and fall through to the original.

    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local BD = require("ui/bidi")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = require("device").screen
    local _ = require("gettext")

    -- Register dynamic_filler_2 as an independent footer item that the user
    -- can enable/position via the footer sort widget.
    if not ReaderFooter.textGeneratorMap.dynamic_filler_2 then
        ReaderFooter.textGeneratorMap.dynamic_filler_2 =
            ReaderFooter.textGeneratorMap.dynamic_filler
    end
    if ReaderFooter.textOptionTitles then
        ReaderFooter.textOptionTitles.dynamic_filler_2 = _("Center filler (right)")
    end

    local orig_genAllFooterText = ReaderFooter.genAllFooterText

    ReaderFooter.genAllFooterText = function(self, skip_gen)
        -- Generator sub-calls (measuring remaining width) always pass
        -- themselves as skip_gen; never intercept those.
        if skip_gen ~= nil then
            return orig_genAllFooterText(self, skip_gen)
        end

        -- Need a valid mode_index to detect two-filler layout.
        if not self.mode_index or not self.mode_nb or self.mode_nb < 2 then
            return orig_genAllFooterText(self, nil)
        end

        -- Scan mode_index by key name to find the footerTextGenerators positions
        -- of dynamic_filler and dynamic_filler_2.  Key-based scan avoids stale-
        -- reference issues from other patches wrapping the filler generator.
        local filler1_gi = nil
        local filler2_gi = nil
        local gi = 0
        for mi = 0, self.mode_nb - 1 do
            local m = self.mode_index[mi]
            if m and self.settings[m] then
                gi = gi + 1
                if m == "dynamic_filler" then
                    filler1_gi = gi
                elseif m == "dynamic_filler_2" then
                    filler2_gi = gi
                end
            end
        end

        if not filler1_gi or not filler2_gi or not self.footerTextGenerators then
            return orig_genAllFooterText(self, nil)
        end

        -- Support user reordering fillers via the sort widget.
        local idx1 = math.min(filler1_gi, filler2_gi)
        local idx2 = math.max(filler1_gi, filler2_gi)

        if idx2 > #self.footerTextGenerators then
            return orig_genAllFooterText(self, nil)
        end

        -- Fillers don't work alongside the progress bar (matches original).
        if not self.settings.disable_progress_bar
                and self.settings.progress_bar_position == "alongside" then
            return orig_genAllFooterText(self, nil)
        end

        local gens = self.footerTextGenerators
        local sep_str = BD.wrap(self:genSeparator())
        local is_compact = self.settings.item_prefix == "compact_items"

        -- Generate concatenated text for a slice of footerTextGenerators,
        -- replicating genAllFooterText's compact-items and merge handling.
        local function gen_section(from_i, to_i)
            local parts = {}
            local prev_merge = false
            for i = from_i, to_i do
                local gen = gens[i]
                if gen then
                    local text, merge = gen(self)
                    if text and text ~= "" then
                        if is_compact then
                            text = text:gsub("%s", "\u{200A}")
                        end
                        if merge then
                            local pos = #parts == 0 and 1 or #parts
                            parts[pos] = (parts[pos] or "") .. text
                            prev_merge = true
                        elseif prev_merge then
                            parts[#parts] = parts[#parts] .. text
                            prev_merge = false
                        else
                            table.insert(parts, BD.wrap(text))
                        end
                    end
                end
            end
            return table.concat(parts, sep_str)
        end

        local left_text   = gen_section(1, idx1 - 1)
        local center_text = gen_section(idx1 + 1, idx2 - 1)
        local right_text  = gen_section(idx2 + 1, #gens)

        -- Compute max_width matching the original dynamic_filler formula.
        local margin = self.horizontal_margin or 0
        if not self.settings.disable_progress_bar
                and self.settings.align == "center" then
            margin = Screen:scaleBySize(self.settings.progress_margin_width or 0)
        end
        local screen_w  = self._saved_screen_width or Screen:getWidth()
        local max_width = math.floor(screen_w - 2 * margin)

        -- Measure rendered pixel widths; cache filler_space_width on the footer.
        local function measure(text)
            if not text or text == "" then return 0 end
            local w = TextWidget:new{
                text = text,
                face = self.footer_text_face,
                bold = self.settings.text_font_bold,
            }
            local width = w:getSize().w
            w:free()
            return width
        end

        if not self.filler_space_width then
            self.filler_space_width = measure(" ")
        end
        local space_w = self.filler_space_width

        local left_w   = measure(left_text)
        local center_w = measure(center_text)
        local right_w  = measure(right_text)

        -- True centering: each filler occupies (max_width - center_w)/2 minus
        -- its adjacent section's width.  Clamped to 0 when sections overflow.
        local half_outer = math.floor((max_width - center_w) / 2)
        local filler1_nb = math.max(0, math.floor((half_outer - left_w)  / space_w))
        local filler2_nb = math.max(0, math.floor((half_outer - right_w) / space_w))

        -- Assemble: sections joined by filler spaces directly (no separators
        -- around fillers, matching the original filler's "merge" behavior).
        local result = {}
        if left_text ~= ""  then table.insert(result, left_text) end
        if filler1_nb > 0   then table.insert(result, (" "):rep(filler1_nb)) end
        if center_text ~= "" then table.insert(result, center_text) end
        if filler2_nb > 0   then table.insert(result, (" "):rep(filler2_nb)) end
        if right_text ~= ""  then table.insert(result, right_text) end

        return table.concat(result)
    end
end

return apply_reader_footer
