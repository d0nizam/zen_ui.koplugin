local logger = require("logger")
local ConfigManager = require("config/manager")
local book_status = require("common/book_status")
local Registry = require("modules/filebrowser/patches/dashboard/components/registry")
local StandalonePage = require("modules/filebrowser/patches/standalone_page")

local M = {}

local _dashboard_menu = nil
local _zen_shared = nil
local _zen_plugin = nil

local QUOTES = {
    { text = "Read in order to live.", author = "Gustave Flaubert" },
    { text = "A reader lives a thousand lives before he dies.", author = "George R.R. Martin" },
    { text = "There is no friend as loyal as a book.", author = "Ernest Hemingway" },
    { text = "Today a reader, tomorrow a leader.", author = "Margaret Fuller" },
    { text = "Books are a uniquely portable magic.", author = "Stephen King" },
    { text = "Reading is to the mind what exercise is to the body.", author = "Joseph Addison" },
    { text = "One glance at a book and you hear the voice of another person.", author = "Carl Sagan" },
    { text = "If you only read the books everyone else is reading, you can only think what everyone else is thinking.", author = "Haruki Murakami" },
    { text = "No entertainment is so cheap as reading.", author = "Mary Wortley Montagu" },
    { text = "To learn to read is to light a fire.", author = "Victor Hugo" },
    { text = "Books are mirrors: you only see in them what you already have inside you.", author = "Carlos Ruiz Zafon" },
    { text = "Reading gives us someplace to go when we have to stay where we are.", author = "Mason Cooley" },
}

local DEFAULT_ROW_ORDER = {
    "featured_most_recent",
    "stats_triplet",
    "strip_to_be_read",
}

local function load_zen_config()
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        return _zen_plugin.config
    end
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" then
        return cfg
    end
end

local function save_zen_config(cfg)
    if type(cfg) ~= "table" then return end
    if _zen_plugin and _zen_plugin.config == cfg and type(_zen_plugin.saveConfig) == "function" then
        _zen_plugin:saveConfig()
        return
    end
    pcall(ConfigManager.save, cfg)
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        _zen_plugin.config = cfg
    end
end

local function ensure_dashboard_cfg(cfg)
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.dashboard_page) ~= "table" then cfg.group_view.dashboard_page = {} end
    local dcfg = cfg.group_view.dashboard_page

    if type(dcfg.rows) ~= "table" then dcfg.rows = {} end
    local rows = dcfg.rows

    if type(rows.order) ~= "table" or #rows.order == 0 then
        rows.order = { "featured_most_recent", "stats_triplet", "strip_to_be_read" }
    end
    if type(rows.enabled) ~= "table" then
        rows.enabled = {
            featured_most_recent = true,
            stats_triplet = true,
            strip_to_be_read = true,
        }
    end
    rows.max_rows = 5

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
    if type(dcfg.quotes.manual_index) ~= "number" then dcfg.quotes.manual_index = 1 end

    return dcfg
end

local function resolve_rows(dcfg)
    local rows_cfg = dcfg.rows or {}
    local order = rows_cfg.order or DEFAULT_ROW_ORDER
    local enabled = rows_cfg.enabled or {}
    local max_rows = tonumber(rows_cfg.max_rows) or 5
    if max_rows < 1 then max_rows = 1 end
    if max_rows > 5 then max_rows = 5 end

    local seen = {}
    local out = {}

    local function try_push(id)
        if seen[id] then return end
        if enabled[id] ~= true then return end
        local comp = Registry.get(id)
        if not comp then return end
        seen[id] = true
        table.insert(out, comp)
    end

    for _i, id in ipairs(order) do
        try_push(id)
        if #out >= max_rows then break end
    end

    if #out < max_rows then
        for _i, comp in ipairs(Registry.list()) do
            try_push(comp.id)
            if #out >= max_rows then break end
        end
    end

    if #out == 0 then
        for _i, id in ipairs(DEFAULT_ROW_ORDER) do
            local comp = Registry.get(id)
            if comp then table.insert(out, comp) end
        end
    end

    while #out > max_rows do
        table.remove(out)
    end

    return out
end

local function get_quote_day_index()
    local now = os.date("*t")
    return ((now.year * 366) + now.yday)
end

local function get_daily_quote_index()
    if #QUOTES == 0 then return 1 end
    return (get_quote_day_index() % #QUOTES) + 1
end

local function build_data_provider(cfg, dcfg)
    local provider = {}
    local stats_cached = nil
    local history_cached = nil
    local tbr_cached = nil

    local function get_stats()
        if stats_cached then return stats_cached end
        local ok_stats, StatsDB = pcall(require, "common/db_stats")
        if ok_stats and StatsDB and type(StatsDB.queryStats) == "function" then
            stats_cached = StatsDB.queryStats() or {}
        else
            stats_cached = {}
        end
        return stats_cached
    end

    local function get_history()
        if history_cached then return history_cached end
        history_cached = {}
        local ok_rh, ReadHistory = pcall(require, "readhistory")
        if not ok_rh or not ReadHistory then
            return history_cached
        end

        if type(ReadHistory.reload) == "function" then
            pcall(ReadHistory.reload, ReadHistory, false)
        end

        local hist = ReadHistory.hist or {}
        local lfs = require("libs/libkoreader-lfs")
        local paths = require("common/paths")

        for _i, entry in ipairs(hist) do
            local path = entry and entry.file
            if type(path) == "string"
                    and path ~= ""
                    and paths.isInHomeDir(path)
                    and lfs.attributes(path, "mode") == "file" then
                table.insert(history_cached, path)
            end
        end

        return history_cached
    end

    local function get_book(path)
        if not path then return nil end
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local cover_bb, title, authors, pages
        if ok_bim and BookInfoManager then
            local bi = BookInfoManager:getBookInfo(path, true)
            if bi then
                title = bi.title
                authors = bi.authors
                pages = bi.pages
                if bi.cover_bb and bi.has_cover and bi.cover_fetched and not bi.ignore_cover then
                    cover_bb = bi.cover_bb:copy()
                end
            end
        end

        local pct = nil
        local status = nil
        local ok_ds, DocSettings = pcall(require, "docsettings")
        if ok_ds and DocSettings and DocSettings:hasSidecarFile(path) then
            local ok_doc, doc = pcall(DocSettings.open, DocSettings, path)
            if ok_doc and doc then
                pct = doc:readSetting("percent_finished")
                local summary = doc:readSetting("summary")
                status = summary and summary.status
                if not pages then
                    local stats = doc:readSetting("stats")
                    pages = stats and stats.pages
                end
            end
        end

        if not title or title == "" then
            title = (path:match("([^/]+)$") or path):gsub("%.[^%.]+$", "")
        end

        return {
            path = path,
            title = title,
            authors = authors or "",
            cover_bb = cover_bb,
            percent = pct or 0,
            status = status,
            pages = pages,
        }
    end

    local function sort_files_like_tbr(files)
        local group_view = cfg and cfg.group_view or {}
        local detail_collate = group_view.detail_collate or {}
        local detail_reverse = group_view.detail_reverse or {}
        local collate_tbl = detail_collate.to_be_read or {}
        local reverse_tbl = detail_reverse.to_be_read or {}

        local collate = collate_tbl.to_be_read or "title"
        local reverse = reverse_tbl.to_be_read == true

        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local lfs = require("libs/libkoreader-lfs")

        local items = {}
        for _i, fpath in ipairs(files) do
            local key
            if collate == "access" then
                key = lfs.attributes(fpath, "access") or 0
            elseif collate == "series_index" then
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and tonumber(bi.series_index)) or math.huge
            elseif collate == "title" then
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and bi.title) or (fpath:match("([^/]+)$") or fpath)
            else
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and bi.title) or (fpath:match("([^/]+)$") or fpath)
            end
            table.insert(items, { path = fpath, key = key })
        end

        table.sort(items, function(a, b)
            if collate == "access" or collate == "series_index" then
                local ka = type(a.key) == "number" and a.key or 0
                local kb = type(b.key) == "number" and b.key or 0
                if collate == "access" then
                    if reverse then return ka < kb else return ka > kb end
                end
                if reverse then return ka > kb else return ka < kb end
            end
            local sa = tostring(a.key):lower()
            local sb = tostring(b.key):lower()
            if reverse then return sa > sb else return sa < sb end
        end)

        local sorted = {}
        for _i, item in ipairs(items) do
            table.insert(sorted, item.path)
        end
        return sorted
    end

    local function get_tbr_paths()
        if tbr_cached then return tbr_cached end
        tbr_cached = {}
        local ok_db, db = pcall(require, "common/db_bookinfo")
        if ok_db and db and type(db.getTBRBooks) == "function" then
            tbr_cached = db.getTBRBooks() or {}
            tbr_cached = sort_files_like_tbr(tbr_cached)
        end
        return tbr_cached
    end

    local function get_paths_by_status(status_key, limit)
        local hist = get_history()
        local out = {}
        for _i, path in ipairs(hist) do
            local eff = book_status.getEffectiveStatusFromFile(path)
            if eff == status_key then
                table.insert(out, path)
                if #out >= limit then break end
            end
        end
        return out
    end

    function provider:getFeaturedBook(source_key)
        local path
        if source_key == "reading_first" then
            local paths = get_paths_by_status("reading", 1)
            path = paths[1]
        elseif source_key == "tbr_first" then
            local paths = get_tbr_paths()
            path = paths[1]
        else
            local hist = get_history()
            path = hist[1]
        end
        return get_book(path)
    end

    function provider:getBooksForStrip(source_key, count)
        local paths = {}
        if source_key == "reading_recent" then
            paths = get_paths_by_status("reading", count)
        elseif source_key == "to_be_read" then
            local tbr = get_tbr_paths()
            for _i, path in ipairs(tbr) do
                table.insert(paths, path)
                if #paths >= count then break end
            end
        else
            local hist = get_history()
            for _i, path in ipairs(hist) do
                table.insert(paths, path)
                if #paths >= count then break end
            end
        end

        local books = {}
        for _i, path in ipairs(paths) do
            local book = get_book(path)
            if book then table.insert(books, book) end
        end
        return books
    end

    function provider:getCurrentQuote()
        local idx
        local quote_cfg = dcfg.quotes or {}
        if quote_cfg.day_seed == get_quote_day_index() and type(quote_cfg.manual_index) == "number" then
            idx = quote_cfg.manual_index
        else
            idx = get_daily_quote_index()
        end
        if idx < 1 then idx = 1 end
        if idx > #QUOTES then idx = ((idx - 1) % #QUOTES) + 1 end
        return QUOTES[idx]
    end

    function provider:nextQuote()
        local quote_cfg = dcfg.quotes or {}
        if type(quote_cfg.manual_index) ~= "number" then
            quote_cfg.manual_index = get_daily_quote_index()
        end
        quote_cfg.manual_index = quote_cfg.manual_index + 1
        if quote_cfg.manual_index > #QUOTES then quote_cfg.manual_index = 1 end
        quote_cfg.day_seed = get_quote_day_index()
        dcfg.quotes = quote_cfg
        save_zen_config(cfg)
        if _dashboard_menu and _dashboard_menu._dashboard_rebuild then
            _dashboard_menu:_dashboard_rebuild()
        end
    end

    provider.stats = get_stats()

    return provider
end

local function compute_row_heights(rows, body_h)
    local specs = {}
    local total_pref = 0

    for _i, comp in ipairs(rows) do
        local size = comp.size or {}
        local pref = tonumber(size.preferred) or 120
        local min_h = tonumber(size.min) or math.max(60, math.floor(pref * 0.7))
        local max_h = tonumber(size.max) or math.max(pref, min_h)
        table.insert(specs, { pref = pref, min = min_h, max = max_h, h = pref })
        total_pref = total_pref + pref
    end

    if #specs == 0 then return specs end

    if total_pref > body_h then
        local scale = body_h / total_pref
        local total = 0
        for _i, sp in ipairs(specs) do
            sp.h = math.floor(sp.pref * scale)
            if sp.h < sp.min then sp.h = sp.min end
            if sp.h > sp.max then sp.h = sp.max end
            total = total + sp.h
        end
        local i = 1
        while total > body_h and #specs > 0 do
            local sp = specs[i]
            if sp.h > sp.min then
                sp.h = sp.h - 1
                total = total - 1
            end
            i = i + 1
            if i > #specs then i = 1 end
        end
    else
        local total = 0
        for _i, sp in ipairs(specs) do total = total + sp.h end
        local remaining = body_h - total
        local i = 1
        while remaining > 0 and #specs > 0 do
            local sp = specs[i]
            if sp.h < sp.max then
                sp.h = sp.h + 1
                remaining = remaining - 1
            end
            i = i + 1
            if i > #specs then i = 1 end
            if i == 1 then
                local all_at_max = true
                for _j, s in ipairs(specs) do
                    if s.h < s.max then all_at_max = false; break end
                end
                if all_at_max then break end
            end
        end
    end

    return specs
end

local function build_dashboard_content(menu, cfg, dcfg, rows, data_provider)
    local Device = require("device")
    local Screen = Device.screen
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Font = require("ui/font")

    local tb = menu.title_bar
    local tb_h = tb and tb:getSize().h or 0
    local body_h = (menu.inner_dimen and menu.inner_dimen.h or menu.dimen.h) - tb_h
    if body_h < 1 then body_h = Screen:getHeight() - tb_h end
    local body_w = menu.inner_dimen and menu.inner_dimen.w or Screen:getWidth()

    local row_heights = compute_row_heights(rows, body_h)

    local face_title = Font:getFace("smallinfofont", Screen:scaleBySize(24))
    local face_value = Font:getFace("smallinfofont", Screen:scaleBySize(20))
    local face_label = Font:getFace("smallinfofont", Screen:scaleBySize(16))

    local FileManager = require("apps/filemanager/filemanager")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")

    local function open_book(path)
        if not path then return end
        local fm = FileManager.instance
        if filemanagerutil.openFile then
            filemanagerutil.openFile(fm, path)
        elseif fm and type(fm.openFile) == "function" then
            fm:openFile(path)
        end
    end

    local children = { align = "left" }
    local used_h = 0

    for i, comp in ipairs(rows) do
        local h = row_heights[i] and row_heights[i].h or 120
        local row_ctx = {
            width = body_w,
            height = h,
            config = dcfg,
            data = data_provider,
            openBook = open_book,
            face_title = face_title,
            face_value = face_value,
            face_label = face_label,
        }
        local ok_widget, widget = pcall(comp.build, row_ctx)
        if ok_widget and widget then
            table.insert(children, FrameContainer:new{
                width = body_w,
                height = h,
                padding = 0,
                bordersize = 0,
                background = 0,
                widget,
            })
            used_h = used_h + h
        else
            logger.warn("zen-ui dashboard: failed to build component:", comp.id, widget)
        end
    end

    if used_h < body_h then
        table.insert(children, VerticalSpan:new{ width = body_h - used_h })
    end

    return VerticalGroup:new(children)
end

function M.showDashboardView(injectNavbar)
    local UIManager = require("ui/uimanager")

    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    local dcfg = ensure_dashboard_cfg(cfg)

    local menu = StandalonePage.create_menu{
        name = "dashboard",
        title = " ",
    }
    StandalonePage.prepare_shell(menu)

    local createStatusRow = _zen_shared and _zen_shared.createStatusRow
    local createStatusRowCustomBack = _zen_shared and _zen_shared.createStatusRowCustomBack
    local repaintTitleBar = _zen_shared and _zen_shared.repaintTitleBar
    StandalonePage.apply_status_row(menu, {
        createStatusRow = createStatusRow,
        createStatusRowCustomBack = createStatusRowCustomBack,
        repaintTitleBar = repaintTitleBar,
    })

    local rows = resolve_rows(dcfg)
    local data_provider = build_data_provider(cfg, dcfg)

    local function rebuild()
        local content = build_dashboard_content(menu, cfg, dcfg, rows, data_provider)
        StandalonePage.mount_body(menu, content)
        UIManager:setDirty(menu, "ui")
    end

    function menu:_dashboard_rebuild()
        rows = resolve_rows(dcfg)
        data_provider = build_data_provider(cfg, dcfg)
        rebuild()
    end

    menu.close_callback = function()
        UIManager:close(menu)
        _dashboard_menu = nil
    end

    _dashboard_menu = menu

    if injectNavbar then
        injectNavbar(menu, "dashboard")
    end

    UIManager:show(menu)
    UIManager:nextTick(function()
        rebuild()
        if menu._zen_status_refresh then
            menu:_zen_status_refresh()
        end
    end)
end

function M.getActivePage()
    return _dashboard_menu and (_dashboard_menu.page or 1)
end

function M.closeAll()
    if _dashboard_menu then
        local UIManager = require("ui/uimanager")
        UIManager:close(_dashboard_menu)
        _dashboard_menu = nil
    end
end

return function()
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    if not zen_plugin._zen_shared then zen_plugin._zen_shared = {} end
    _zen_shared = zen_plugin._zen_shared
    _zen_plugin = zen_plugin
    zen_plugin._zen_shared.dashboard = M
end
