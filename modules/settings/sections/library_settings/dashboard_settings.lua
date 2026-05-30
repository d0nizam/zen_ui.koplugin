local _ = require("gettext")
local UIManager = require("ui/uimanager")

local Registry = require("modules/filebrowser/patches/dashboard/components/registry")

local M = {}

local DEFAULT_ORDER = {
    "datetime",
    "featured_recent",
    "stats_triplet",
    "strip_tbr",
}

local function copy_default_order()
    local out = {}
    for _i, id in ipairs(DEFAULT_ORDER) do
        out[#out + 1] = id
    end
    return out
end

local function normalize_order(order)
    if order == "reverse" then return "reverse" end
    return "default"
end

local function ensure_module_cfg(dcfg, module_id)
    if type(dcfg.modules) ~= "table" then dcfg.modules = {} end
    if type(dcfg.modules[module_id]) ~= "table" then dcfg.modules[module_id] = {} end
    local mcfg = dcfg.modules[module_id]
    if module_id == "datetime" then
        mcfg.show_module_title = false
    elseif mcfg.show_module_title == nil then
        mcfg.show_module_title = false
    end
    return mcfg
end

local function ensure_featured_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.show_description == nil then mcfg.show_description = true end
    return mcfg
end

local function ensure_strip_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if type(mcfg.count) ~= "number" then mcfg.count = 5 end
    if mcfg.count < 3 then mcfg.count = 3 end
    if mcfg.count > 5 then mcfg.count = 5 end
    if mcfg.show_strip_titles == nil then mcfg.show_strip_titles = false end
    return mcfg
end

local function ensure_dashboard_widget_cfg(dcfg)
    ensure_featured_cfg(dcfg, "featured_reading")
    ensure_featured_cfg(dcfg, "featured_tbr")
    ensure_featured_cfg(dcfg, "featured_recent")
    ensure_strip_cfg(dcfg, "strip_reading")
    ensure_strip_cfg(dcfg, "strip_tbr")
    ensure_strip_cfg(dcfg, "strip_recent")
end

local function ensure_cfg(config)
    if type(config.group_view) ~= "table" then config.group_view = {} end
    if type(config.group_view.dashboard_page) ~= "table" then config.group_view.dashboard_page = {} end
    local dcfg = config.group_view.dashboard_page

    if type(dcfg.rows) ~= "table" then dcfg.rows = {} end
    if type(dcfg.rows.order) ~= "table" then dcfg.rows.order = {} end
    local normalized_order = {}
    local seen_order = {}
    for _i, id in ipairs(dcfg.rows.order) do
        if Registry.get(id) and not seen_order[id] then
            seen_order[id] = true
            table.insert(normalized_order, id)
        end
    end
    if #normalized_order == 0 then
        dcfg.rows.order = copy_default_order()
    else
        dcfg.rows.order = normalized_order
    end
    if type(dcfg.rows.enabled) ~= "table" then dcfg.rows.enabled = {} end
    local normalized_enabled = {}
    local had_enabled = false
    for key, val in pairs(dcfg.rows.enabled) do
        if Registry.get(key) and val == true then
            normalized_enabled[key] = true
            had_enabled = true
        elseif Registry.get(key) and normalized_enabled[key] == nil then
            normalized_enabled[key] = false
        end
    end
    if not had_enabled then
        normalized_enabled = {}
        for _i, id in ipairs(DEFAULT_ORDER) do
            normalized_enabled[id] = true
        end
    end
    for _i, comp in ipairs(Registry.list()) do
        if normalized_enabled[comp.id] == nil then
            normalized_enabled[comp.id] = false
        end
    end
    dcfg.rows.enabled = normalized_enabled
    dcfg.rows.max_rows = 5

    if type(dcfg.middle_stats_triplet) ~= "table" then
        dcfg.middle_stats_triplet = { "today_pages", "today_duration", "streak" }
    end

    if type(dcfg.goals) ~= "table" then dcfg.goals = {} end
    if dcfg.goals.metric ~= "time" and dcfg.goals.metric ~= "pages" then
        dcfg.goals.metric = "pages"
    end
    if dcfg.goals.period ~= "weekly" and dcfg.goals.period ~= "daily" then
        dcfg.goals.period = "daily"
    end
    if type(dcfg.goals.daily_pages_target) ~= "number" then dcfg.goals.daily_pages_target = 30 end
    if type(dcfg.goals.weekly_pages_target) ~= "number" then dcfg.goals.weekly_pages_target = 210 end
    if type(dcfg.goals.daily_time_target_min) ~= "number" then dcfg.goals.daily_time_target_min = 30 end
    if type(dcfg.goals.weekly_time_target_min) ~= "number" then dcfg.goals.weekly_time_target_min = 210 end

    if type(dcfg.quotes) ~= "table" then dcfg.quotes = {} end
    if dcfg.quotes.show_author == nil then dcfg.quotes.show_author = true end

    for _i, comp in ipairs(Registry.list()) do
        ensure_module_cfg(dcfg, comp.id)
    end
    ensure_dashboard_widget_cfg(dcfg)

    return dcfg
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
    local dashboard_rebuild_pending = false
    local dashboard_rebuild_poll_active = false
    local schedule_dashboard_rebuild_on_menu_close

    local function save_dashboard()
        plugin:saveConfig()
        dashboard_rebuild_pending = true
        schedule_dashboard_rebuild_on_menu_close()
    end

    local function is_filemanager_menu_open()
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        if not ok_fm or not FileManager or not FileManager.instance then return false end
        local fm = FileManager.instance
        return fm.menu ~= nil and fm.menu.menu_container ~= nil
    end

    schedule_dashboard_rebuild_on_menu_close = function()
        if dashboard_rebuild_poll_active then return end
        dashboard_rebuild_poll_active = true
        local function tick()
            if is_filemanager_menu_open() then
                UIManager:scheduleIn(0.25, tick)
                return
            end
            dashboard_rebuild_poll_active = false
            if not dashboard_rebuild_pending then return end
            dashboard_rebuild_pending = false
            local dash = ctx.plugin
                and ctx.plugin._zen_shared
                and ctx.plugin._zen_shared.dashboard
            if dash and dash.rebuildActive then
                dash.rebuildActive()
            end
        end
        UIManager:scheduleIn(0.25, tick)
    end

    local function component_label(id)
        local comp = Registry.get(id)
        if comp and comp.label then return comp.label end
        return id
    end

    local order_options = {
        { id = "default", text = _("Default") },
        { id = "reverse", text = _("Reverse") },
    }

    local function build_order_items(mcfg)
        local items = {}
        for _i, opt in ipairs(order_options) do
            local order_id = opt.id
            items[#items + 1] = {
                text = opt.text,
                radio = true,
                checked_func = function()
                    return normalize_order(mcfg.order) == order_id
                end,
                callback = function()
                    mcfg.order = order_id
                    save_dashboard("reinit")
                end,
            }
        end
        return items
    end

    local function build_featured_widget_items(module_id)
        local mcfg = ensure_featured_cfg(dcfg, module_id)
        return {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return mcfg.show_module_title == true
                end,
                callback = function()
                    mcfg.show_module_title = not (mcfg.show_module_title == true)
                    save_dashboard("reinit")
                end,
            },
            {
                text = _("Order"),
                sub_item_table = build_order_items(mcfg),
            },
            {
                text = _("Show description"),
                checked_func = function()
                    return mcfg.show_description ~= false
                end,
                callback = function()
                    mcfg.show_description = mcfg.show_description == false
                    save_dashboard("reinit")
                end,
            },
        }
    end

    local function build_strip_widget_items(module_id)
        local mcfg = ensure_strip_cfg(dcfg, module_id)
        return {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return mcfg.show_module_title == true
                end,
                callback = function()
                    mcfg.show_module_title = not (mcfg.show_module_title == true)
                    save_dashboard("reinit")
                end,
            },
            {
                text = _("Order"),
                sub_item_table = build_order_items(mcfg),
            },
            {
                text_func = function()
                    return _("Books shown: ") .. tostring(mcfg.count or 5)
                end,
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Books shown"),
                        value = mcfg.count or 5,
                        value_min = 3,
                        value_max = 5,
                        callback = function(spin)
                            mcfg.count = spin.value
                            save_dashboard("reinit")
                        end,
                    })
                end,
            },
            {
                text = _("Show strip item titles"),
                checked_func = function()
                    return mcfg.show_strip_titles == true
                end,
                callback = function()
                    mcfg.show_strip_titles = not (mcfg.show_strip_titles == true)
                    save_dashboard("reinit")
                end,
            },
        }
    end

    local function build_widgets_items()
        local items = {}

        for _i, comp in ipairs(Registry.list()) do
            local cid = comp.id
            items[#items + 1] = {
                text = comp.label,
                checked_func = function()
                    return dcfg.rows.enabled[cid] == true
                end,
                callback = function()
                    if dcfg.rows.enabled[cid] == true then
                        if enabled_count(dcfg.rows.enabled) <= 1 then return end
                        dcfg.rows.enabled[cid] = false
                    else
                        dcfg.rows.enabled[cid] = true
                    end
                    save_dashboard("reinit")
                end,
            }
        end

        return items
    end

    local function arrange_widgets()
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
            title = _("Arrange widgets"),
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
        (function()
            local goals_cfg = ensure_module_cfg(dcfg, "reading_goals")
            return {
                text = _("Show widget title"),
                checked_func = function()
                    return goals_cfg.show_module_title == true
                end,
                callback = function()
                    goals_cfg.show_module_title = not (goals_cfg.show_module_title == true)
                    save_dashboard("reinit")
                end,
            }
        end)(),
        {
            text = _("Goal shown: Daily"),
            radio = true,
            checked_func = function() return dcfg.goals.period ~= "weekly" end,
            callback = function()
                dcfg.goals.period = "daily"
                save_dashboard("reinit")
            end,
        },
        {
            text = _("Goal shown: Weekly"),
            radio = true,
            checked_func = function() return dcfg.goals.period == "weekly" end,
            callback = function()
                dcfg.goals.period = "weekly"
                save_dashboard("reinit")
            end,
        },
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
            text_func = function() return _("Daily pages goal: ") .. tostring(dcfg.goals.daily_pages_target or 30) end,
            keep_menu_open = true,
            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    title_text = _("Daily pages goal"),
                    value = dcfg.goals.daily_pages_target or 30,
                    value_min = 1,
                    value_max = 5000,
                    callback = function(spin)
                        dcfg.goals.daily_pages_target = spin.value
                        save_dashboard("reinit")
                    end,
                })
            end,
        },
        {
            text_func = function() return _("Weekly pages goal: ") .. tostring(dcfg.goals.weekly_pages_target or 210) end,
            keep_menu_open = true,
            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    title_text = _("Weekly pages goal"),
                    value = dcfg.goals.weekly_pages_target or 210,
                    value_min = 1,
                    value_max = 20000,
                    callback = function(spin)
                        dcfg.goals.weekly_pages_target = spin.value
                        save_dashboard("reinit")
                    end,
                })
            end,
        },
        {
            text_func = function() return _("Daily time goal (min): ") .. tostring(dcfg.goals.daily_time_target_min or 30) end,
            keep_menu_open = true,
            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    title_text = _("Daily time goal (min)"),
                    value = dcfg.goals.daily_time_target_min or 30,
                    value_min = 1,
                    value_max = 1440,
                    callback = function(spin)
                        dcfg.goals.daily_time_target_min = spin.value
                        save_dashboard("reinit")
                    end,
                })
            end,
        },
        {
            text_func = function() return _("Weekly time goal (min): ") .. tostring(dcfg.goals.weekly_time_target_min or 210) end,
            keep_menu_open = true,
            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                UIManager:show(SpinWidget:new{
                    title_text = _("Weekly time goal (min)"),
                    value = dcfg.goals.weekly_time_target_min or 210,
                    value_min = 1,
                    value_max = 10080,
                    callback = function(spin)
                        dcfg.goals.weekly_time_target_min = spin.value
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

    local stats_cfg = ensure_module_cfg(dcfg, "stats_triplet")
    local stats_triplet_items = {
        {
            text = _("Show widget title"),
            checked_func = function()
                return stats_cfg.show_module_title == true
            end,
            callback = function()
                stats_cfg.show_module_title = not (stats_cfg.show_module_title == true)
                save_dashboard("reinit")
            end,
        },
    }
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
                text = _("Widgets"),
                sub_item_table = build_widgets_items(),
            },
            {
                text = _("Arrange widgets"),
                keep_menu_open = true,
                callback = arrange_widgets,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Featured widgets"),
                        sub_item_table = {
                            {
                                text = _("Reading featured widget"),
                                sub_item_table = build_featured_widget_items("featured_reading"),
                            },
                            {
                                text = _("To Be Read featured widget"),
                                sub_item_table = build_featured_widget_items("featured_tbr"),
                            },
                            {
                                text = _("Recently read featured widget"),
                                sub_item_table = build_featured_widget_items("featured_recent"),
                            },
                        },
                    },
                    {
                        text = _("Strip widgets"),
                        sub_item_table = {
                            {
                                text = _("Reading strip widget"),
                                sub_item_table = build_strip_widget_items("strip_reading"),
                            },
                            {
                                text = _("To Be Read strip widget"),
                                sub_item_table = build_strip_widget_items("strip_tbr"),
                            },
                            {
                                text = _("Recently read strip widget"),
                                sub_item_table = build_strip_widget_items("strip_recent"),
                            },
                        },
                    },
                    {
                        text = _("Reading goals"),
                        sub_item_table = goals_items,
                    },
                    {
                        text = _("Reading stats widget"),
                        sub_item_table = stats_triplet_items,
                    },
                    {
                        text = _("Quotes widget"),
                        sub_item_table = {
                            (function()
                                local quotes_cfg = ensure_module_cfg(dcfg, "quotes")
                                return {
                                    text = _("Show widget title"),
                                    checked_func = function()
                                        return quotes_cfg.show_module_title == true
                                    end,
                                    callback = function()
                                        quotes_cfg.show_module_title = not (quotes_cfg.show_module_title == true)
                                        save_dashboard("reinit")
                                    end,
                                }
                            end)(),
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
            },
        },
    }
end

return M
