local _ = require("gettext")
local UIManager = require("ui/uimanager")

local Registry = require("modules/filebrowser/patches/dashboard/components/registry")

local M = {}

local DEFAULT_ORDER = {
    "featured_most_recent",
    "stats_triplet",
    "strip_to_be_read",
}

local function ensure_cfg(config)
    if type(config.group_view) ~= "table" then config.group_view = {} end
    if type(config.group_view.dashboard_page) ~= "table" then config.group_view.dashboard_page = {} end
    local dcfg = config.group_view.dashboard_page

    if type(dcfg.rows) ~= "table" then dcfg.rows = {} end
    if type(dcfg.rows.order) ~= "table" or #dcfg.rows.order == 0 then
        dcfg.rows.order = { "featured_most_recent", "stats_triplet", "strip_to_be_read" }
    end
    if type(dcfg.rows.enabled) ~= "table" then
        dcfg.rows.enabled = {
            featured_most_recent = true,
            stats_triplet = true,
            strip_to_be_read = true,
        }
    end
    dcfg.rows.max_rows = 5

    if type(dcfg.middle_stats_triplet) ~= "table" then
        dcfg.middle_stats_triplet = { "today_pages", "today_duration", "streak" }
    end

    if type(dcfg.goals) ~= "table" then dcfg.goals = {} end
    if dcfg.goals.metric ~= "time" and dcfg.goals.metric ~= "pages" then
        dcfg.goals.metric = "pages"
    end
    if type(dcfg.goals.daily_target) ~= "number" then dcfg.goals.daily_target = 30 end
    if type(dcfg.goals.weekly_target) ~= "number" then dcfg.goals.weekly_target = 210 end

    if type(dcfg.bottom_count) ~= "number" then dcfg.bottom_count = 5 end
    if dcfg.bottom_count < 3 then dcfg.bottom_count = 3 end
    if dcfg.bottom_count > 5 then dcfg.bottom_count = 5 end

    if type(dcfg.quotes) ~= "table" then dcfg.quotes = {} end
    if dcfg.quotes.show_author == nil then dcfg.quotes.show_author = true end

    return dcfg
end

local function get_max_rows(dcfg)
    local n = tonumber(dcfg.rows and dcfg.rows.max_rows) or 5
    if n < 1 then n = 1 end
    if n > 5 then n = 5 end
    return n
end

local function enabled_count(enabled)
    local n = 0
    for _k, v in pairs(enabled) do
        if v == true then n = n + 1 end
    end
    return n
end

local function list_ids()
    local ids = {}
    for _i, comp in ipairs(Registry.list()) do
        table.insert(ids, comp.id)
    end
    return ids
end

local function sort_order_with_defaults(order)
    local ids = list_ids()
    local seen = {}
    local out = {}

    for _i, id in ipairs(order) do
        if Registry.get(id) and not seen[id] then
            seen[id] = true
            table.insert(out, id)
        end
    end

    for _i, id in ipairs(ids) do
        if not seen[id] then
            table.insert(out, id)
            seen[id] = true
        end
    end

    for _i, id in ipairs(DEFAULT_ORDER) do
        if Registry.get(id) and not seen[id] then
            table.insert(out, id)
            seen[id] = true
        end
    end

    return out
end

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local dcfg = ensure_cfg(config)

    local function save_dashboard(refresh_mode)
        plugin:saveConfig()
        if refresh_mode == "reinit" and ctx.settings_apply then
            ctx.settings_apply.reinit_filemanager()
        else
            UIManager:setDirty(nil, "ui")
        end
    end

    local function component_label(id)
        local comp = Registry.get(id)
        if comp and comp.label then return comp.label end
        return id
    end

    local function build_visibility_items()
        local items = {}
        local max_rows = get_max_rows(dcfg)

        for _i, comp in ipairs(Registry.list()) do
            local cid = comp.id
            items[#items + 1] = {
                text = comp.label,
                checked_func = function()
                    return dcfg.rows.enabled[cid] == true
                end,
                enabled_func = function()
                    if dcfg.rows.enabled[cid] == true then return true end
                    return enabled_count(dcfg.rows.enabled) < max_rows
                end,
                callback = function()
                    if dcfg.rows.enabled[cid] == true then
                        if enabled_count(dcfg.rows.enabled) <= 1 then return end
                        dcfg.rows.enabled[cid] = false
                    else
                        if enabled_count(dcfg.rows.enabled) >= max_rows then return end
                        dcfg.rows.enabled[cid] = true
                    end
                    save_dashboard("reinit")
                end,
            }
        end

        return items
    end

    local function arrange_rows()
        local SortWidget = require("ui/widget/sortwidget")
        local order = sort_order_with_defaults(dcfg.rows.order)
        local sort_items = {}
        for _i, id in ipairs(order) do
            sort_items[#sort_items + 1] = {
                text = component_label(id),
                orig_item = id,
                dim = dcfg.rows.enabled[id] ~= true,
            }
        end
        UIManager:show(SortWidget:new{
            title = _("Arrange dashboard rows"),
            item_table = sort_items,
            callback = function()
                local new_order = {}
                for _i, item in ipairs(sort_items) do
                    new_order[#new_order + 1] = item.orig_item
                end
                dcfg.rows.order = new_order
                save_dashboard("reinit")
            end,
        })
    end

    local goals_items = {
        {
            text = _("Goals metric: Pages"),
            radio = true,
            checked_func = function() return dcfg.goals.metric ~= "time" end,
            callback = function()
                dcfg.goals.metric = "pages"
                save_dashboard("reinit")
            end,
        },
        {
            text = _("Goals metric: Time"),
            radio = true,
            checked_func = function() return dcfg.goals.metric == "time" end,
            callback = function()
                dcfg.goals.metric = "time"
                save_dashboard("reinit")
            end,
        },
        {
            text_func = function() return _("Daily goal: ") .. tostring(dcfg.goals.daily_target or 30) end,
            keep_menu_open = true,
            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    title_text = _("Daily goal"),
                    value = dcfg.goals.daily_target or 30,
                    value_min = 1,
                    value_max = 5000,
                    callback = function(spin)
                        dcfg.goals.daily_target = spin.value
                        save_dashboard("reinit")
                    end,
                })
            end,
        },
        {
            text_func = function() return _("Weekly goal: ") .. tostring(dcfg.goals.weekly_target or 210) end,
            keep_menu_open = true,
            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    title_text = _("Weekly goal"),
                    value = dcfg.goals.weekly_target or 210,
                    value_min = 1,
                    value_max = 20000,
                    callback = function(spin)
                        dcfg.goals.weekly_target = spin.value
                        save_dashboard("reinit")
                    end,
                })
            end,
        },
    }

    local stats_field_options = {
        { id = "today_pages", text = "Pages today" },
        { id = "today_duration", text = "Read today" },
        { id = "streak", text = "Day streak" },
        { id = "week_pages", text = "Week pages" },
        { id = "week_duration", text = "Week time" },
    }

    local stats_triplet_items = {}
    for slot = 1, 3 do
        stats_triplet_items[#stats_triplet_items + 1] = {
            text_func = function()
                local cur = dcfg.middle_stats_triplet[slot] or "today_pages"
                return _("Stat slot ") .. tostring(slot) .. ": " .. cur
            end,
            sub_item_table = (function()
                local items = {}
                for _i, opt in ipairs(stats_field_options) do
                    local oid = opt.id
                    items[#items + 1] = {
                        text = opt.text,
                        radio = true,
                        checked_func = function()
                            return (dcfg.middle_stats_triplet[slot] or "today_pages") == oid
                        end,
                        callback = function()
                            dcfg.middle_stats_triplet[slot] = oid
                            save_dashboard("reinit")
                        end,
                    }
                end
                return items
            end)(),
        }
    end

    return {
        text = _("Dashboard"),
        sub_item_table = {
            {
                text = _("Rows"),
                sub_item_table = {
                    {
                        text = _("Visible rows"),
                        sub_item_table = build_visibility_items(),
                    },
                    {
                        text = _("Arrange rows"),
                        keep_menu_open = true,
                        callback = arrange_rows,
                    },
                    {
                        text_func = function()
                            return _("Bottom strip count: ") .. tostring(dcfg.bottom_count or 5)
                        end,
                        keep_menu_open = true,
                        callback = function()
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                title_text = _("Bottom strip count"),
                                value = dcfg.bottom_count or 5,
                                value_min = 3,
                                value_max = 5,
                                callback = function(spin)
                                    dcfg.bottom_count = spin.value
                                    save_dashboard("reinit")
                                end,
                            })
                        end,
                    },
                },
            },
            {
                text = _("Reading goals"),
                sub_item_table = goals_items,
            },
            {
                text = _("Stats triplet"),
                sub_item_table = stats_triplet_items,
            },
            {
                text = _("Quotes"),
                sub_item_table = {
                    {
                        text = _("Show author"),
                        checked_func = function()
                            return dcfg.quotes.show_author ~= false
                        end,
                        callback = function()
                            dcfg.quotes.show_author = dcfg.quotes.show_author == false
                            save_dashboard("reinit")
                        end,
                    },
                },
            },
        },
    }
end

return M
