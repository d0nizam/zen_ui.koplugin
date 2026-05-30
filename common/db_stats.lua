-- common/db_stats.lua
-- Queries KOReader's statistics.sqlite3 database.
-- Returns aggregated reading stats without touching library status,
-- which is handled by db_library.lua.

local logger = require("logger")
local DBConn = require("common/db_connection")

local StatsDB = {}

local function get_db_page_set(conn, id_book, start_time)
    local out = {}
    if not conn or not id_book then return out end
    local sql = string.format(
        "SELECT DISTINCT page FROM page_stat WHERE id_book = %d AND start_time >= %d;",
        id_book, start_time
    )
    local ok_exec, res = pcall(conn.exec, conn, sql)
    if not ok_exec or type(res) ~= "table" then return out end
    local pages = res.page or res[1]
    if type(pages) ~= "table" then return out end
    for i = 1, #pages do
        out[tostring(pages[i])] = true
    end
    return out
end

local function get_live_page_turn_counts(conn, starts)
    local counts = {
        today_pages = 0,
        week_pages = 0,
        month_pages = 0,
        year_pages = 0,
    }
    if type(starts) ~= "table" then return counts end

    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    if not ok_loader or not PluginLoader or type(PluginLoader.getPluginInstance) ~= "function" then
        return counts
    end

    local stats_plugin = PluginLoader:getPluginInstance("statistics")
    if type(stats_plugin) ~= "table" then return counts end
    if type(stats_plugin.isEnabled) == "function" and not stats_plugin:isEnabled() then
        return counts
    end

    local id_book = tonumber(stats_plugin.id_curr_book)
    local page_stat = stats_plugin.page_stat
    if not id_book or type(page_stat) ~= "table" then return counts end

    local existing_today = get_db_page_set(conn, id_book, starts.start_today)
    local existing_week = get_db_page_set(conn, id_book, starts.period_begin)
    local existing_month = get_db_page_set(conn, id_book, starts.start_month)
    local existing_year = get_db_page_set(conn, id_book, starts.start_year)

    local seen_today = {}
    local seen_week = {}
    local seen_month = {}
    local seen_year = {}

    for page, tuples in pairs(page_stat) do
        if type(tuples) == "table" then
            local page_key = tostring(page)
            local in_today = false
            local in_week = false
            local in_month = false
            local in_year = false

            for i = 1, #tuples do
                local tuple = tuples[i]
                local ts = type(tuple) == "table" and tonumber(tuple[1]) or nil
                if ts then
                    if ts >= starts.start_year then in_year = true end
                    if ts >= starts.start_month then in_month = true end
                    if ts >= starts.period_begin then in_week = true end
                    if ts >= starts.start_today then in_today = true end
                end
            end

            if in_today and not existing_today[page_key] and not seen_today[page_key] then
                seen_today[page_key] = true
                counts.today_pages = counts.today_pages + 1
            end
            if in_week and not existing_week[page_key] and not seen_week[page_key] then
                seen_week[page_key] = true
                counts.week_pages = counts.week_pages + 1
            end
            if in_month and not existing_month[page_key] and not seen_month[page_key] then
                seen_month[page_key] = true
                counts.month_pages = counts.month_pages + 1
            end
            if in_year and not existing_year[page_key] and not seen_year[page_key] then
                seen_year[page_key] = true
                counts.year_pages = counts.year_pages + 1
            end
        end
    end

    return counts
end

-- Returns a stats table:
-- {
--   today_pages        number
--   today_duration     number  (seconds)
--   week_pages         number
--   week_duration      number  (seconds)
--   week_daily         list of { date, pages, duration }
--   streak             number  (consecutive reading days)
--   total_books        number  (distinct books with any page_stat row)
-- }
function StatsDB.queryStats()
    local stats = {
        today_pages         = 0,
        today_duration      = 0,
        week_pages          = 0,
        week_duration       = 0,
        streak              = 0,
        total_books         = 0,
        week_daily          = {},
        -- lifetime aggregates (from book table)
        lifetime_read_time  = 0,
        lifetime_pages      = 0,
        books_read          = 0,
        avg_time_per_book   = 0,
        -- personal records (peak durations + representative timestamps for date labels)
        peak_day_duration   = 0,
        peak_day_ts         = nil,
        peak_week_duration  = 0,
        peak_week_ts        = nil,
        peak_month_duration = 0,
        peak_month_ts       = nil,
        -- this-month and this-year aggregates
        month_pages         = 0,
        month_duration      = 0,
        year_pages          = 0,
        year_duration       = 0,
        -- distinct books with any session in each period
        books_this_week     = 0,
        books_this_month    = 0,
        books_this_year     = 0,
    }

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("zen-ui db_stats: cannot open DB:", err)
        return stats
    end

    local one_day = 86400

    local ok, query_err = pcall(function()
        -- Time boundaries
        local now_t = os.date("*t")
        local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
        local now_ts = os.time()
        local start_today = now_ts - from_begin_day
        local period_begin = now_ts - 6 * one_day - from_begin_day
        local start_month = os.time({
            year = now_t.year, month = now_t.month, day = 1,
            hour = 0, min = 0, sec = 0,
        })
        local start_year = os.time({
            year = now_t.year, month = 1, day = 1,
            hour = 0, min = 0, sec = 0,
        })

        -- Today
        local sql_today = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local p, d = conn:rowexec(string.format(sql_today, start_today))
        stats.today_pages    = tonumber(p) or 0
        stats.today_duration = tonumber(d) or 0
        logger.info("zen-ui db_stats: today pages=", stats.today_pages,
                    "duration=", stats.today_duration)

        -- Last 7 days (totals)
        local sql_week = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local wp, wd = conn:rowexec(string.format(sql_week, period_begin))
        stats.week_pages    = tonumber(wp) or 0
        stats.week_duration = tonumber(wd) or 0
        logger.info("zen-ui db_stats: week pages=", stats.week_pages,
                    "duration=", stats.week_duration)

        -- Last 7 days (daily breakdown)
        -- NOTE: %% in the format string becomes % after string.format(); SQLite
        -- then receives strftime('%Y-%m-%d', …) which is what it expects.
        local sql_daily = [[
            SELECT dates, count(*) AS pages, sum(sum_duration) AS durations
            FROM (
                SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                       sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page, dates
            )
            GROUP BY dates
            ORDER BY dates DESC;
        ]]
        local result = conn:exec(string.format(sql_daily, period_begin))
        if result then
            for i = 1, #result.dates do
                table.insert(stats.week_daily, {
                    date     = result.dates[i],
                    pages    = tonumber(result[2][i]) or 0,
                    duration = tonumber(result[3][i]) or 0,
                })
            end
        end

        -- Total books with reading sessions
        local sql_total = "SELECT count(DISTINCT id_book) FROM page_stat;"
        local ok_tot, total = pcall(conn.rowexec, conn, sql_total)
        if not ok_tot then
            logger.warn("zen-ui db_stats: total_books query error:", total)
        end
        stats.total_books = tonumber(total) or 0
        logger.info("zen-ui db_stats: total_books=", stats.total_books)

        -- ── Reading streak ───────────────────────────────────────────────────
        -- Static SQL — no string.format(), so % is passed to SQLite directly.
        local sql_streak = [[
            SELECT DISTINCT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS day
            FROM page_stat
            WHERE duration > 0
            ORDER BY day DESC;
        ]]
        local ok_streak, streak_result = pcall(conn.exec, conn, sql_streak)
        if not ok_streak then
            logger.warn("zen-ui db_stats: streak query error:", streak_result)
            streak_result = nil
        end
        if streak_result and streak_result.day then
            local today_str     = os.date("%Y-%m-%d")
            local yesterday_str = os.date("%Y-%m-%d", os.time() - one_day)
            local most_recent   = streak_result.day[1]
            if most_recent == today_str or most_recent == yesterday_str then
                local streak   = 0
                local expected = most_recent
                for i = 1, #streak_result.day do
                    if streak_result.day[i] == expected then
                        streak = streak + 1
                        local y, mo, dd = expected:match("(%d+)-(%d+)-(%d+)")
                        local noon = os.time({
                            year  = tonumber(y),
                            month = tonumber(mo),
                            day   = tonumber(dd),
                            hour  = 12, min = 0, sec = 0,
                        })
                        expected = os.date("%Y-%m-%d", noon - one_day)
                    else
                        break
                    end
                end
                stats.streak = streak
            end
        end
        logger.info("zen-ui db_stats: streak=", stats.streak)

        -- ── Lifetime aggregates (book table) ─────────────────────────────────
        -- Four columns in one query: total_read_time sum, total_read_pages sum,
        -- book count, average read time (only for books with recorded time).
        -- Wrapped in its own pcall so a missing book table doesn't break the rest.
        local sql_lifetime = [[
            SELECT
                COALESCE(SUM(total_read_time), 0),
                COALESCE(SUM(total_read_pages), 0),
                COUNT(*),
                COALESCE(AVG(CASE WHEN total_read_time > 0
                                 THEN total_read_time END), 0)
            FROM book;
        ]]
        local ok_lt, lt1, lt2, lt3, lt4 = pcall(conn.rowexec, conn, sql_lifetime)
        if ok_lt then
            stats.lifetime_read_time = tonumber(lt1) or 0
            stats.lifetime_pages     = tonumber(lt2) or 0
            stats.books_read         = tonumber(lt3) or 0
            stats.avg_time_per_book  = math.floor(tonumber(lt4) or 0)
        else
            logger.warn("zen-ui db_stats: lifetime query error:", lt1)
        end
        logger.info("zen-ui db_stats: lifetime_read_time=", stats.lifetime_read_time,
                    "books_read=", stats.books_read)

        -- ── Personal records (peak daily / weekly / monthly duration) ─────────
        -- Queries run directly against page_stat_data (indexed on start_time)
        -- rather than the page_stat view, since only durations matter here.
        -- Each query returns (total_duration, rep_ts) for the peak period.
        -- ORDER BY + LIMIT 1 replaces COALESCE(MAX(...)) so we also get a
        -- representative timestamp that can be formatted into a date label.
        -- When the table is empty, rowexec returns nil for both columns.
        local sql_peak_day = [[
            SELECT day_total, rep_ts
            FROM (
                SELECT SUM(duration) AS day_total, MIN(start_time) AS rep_ts
                FROM page_stat_data
                GROUP BY strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')
            )
            ORDER BY day_total DESC
            LIMIT 1;
        ]]
        local ok_pd, pd_dur, pd_ts = pcall(conn.rowexec, conn, sql_peak_day)
        stats.peak_day_duration = ok_pd and (tonumber(pd_dur) or 0) or 0
        stats.peak_day_ts       = ok_pd and tonumber(pd_ts) or nil

        local sql_peak_week = [[
            SELECT week_total, rep_ts
            FROM (
                SELECT SUM(duration) AS week_total, MIN(start_time) AS rep_ts
                FROM page_stat_data
                GROUP BY strftime('%Y-%W', start_time, 'unixepoch', 'localtime')
            )
            ORDER BY week_total DESC
            LIMIT 1;
        ]]
        local ok_pw, pw_dur, pw_ts = pcall(conn.rowexec, conn, sql_peak_week)
        stats.peak_week_duration = ok_pw and (tonumber(pw_dur) or 0) or 0
        stats.peak_week_ts       = ok_pw and tonumber(pw_ts) or nil

        local sql_peak_month = [[
            SELECT month_total, rep_ts
            FROM (
                SELECT SUM(duration) AS month_total, MIN(start_time) AS rep_ts
                FROM page_stat_data
                GROUP BY strftime('%Y-%m', start_time, 'unixepoch', 'localtime')
            )
            ORDER BY month_total DESC
            LIMIT 1;
        ]]
        local ok_pm, pm_dur, pm_ts = pcall(conn.rowexec, conn, sql_peak_month)
        stats.peak_month_duration = ok_pm and (tonumber(pm_dur) or 0) or 0
        stats.peak_month_ts       = ok_pm and tonumber(pm_ts) or nil
        logger.info("zen-ui db_stats: peak_day=", stats.peak_day_duration,
                    "peak_week=", stats.peak_week_duration,
                    "peak_month=", stats.peak_month_duration)

        -- ── Month and Year aggregates ─────────────────────────────────────────

        local sql_month_agg = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local ok_mo, mo_p, mo_d = pcall(conn.rowexec, conn,
            string.format(sql_month_agg, start_month))
        stats.month_pages    = ok_mo and (tonumber(mo_p) or 0) or 0
        stats.month_duration = ok_mo and (tonumber(mo_d) or 0) or 0

        local sql_year_agg = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local ok_yr, yr_p, yr_d = pcall(conn.rowexec, conn,
            string.format(sql_year_agg, start_year))
        stats.year_pages    = ok_yr and (tonumber(yr_p) or 0) or 0
        stats.year_duration = ok_yr and (tonumber(yr_d) or 0) or 0

        -- Distinct books with reading sessions in each period
        local ok_bw, bw_v = pcall(conn.rowexec, conn, string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;",
            period_begin))
        stats.books_this_week = ok_bw and (tonumber(bw_v) or 0) or 0

        local ok_bm, bm_v = pcall(conn.rowexec, conn, string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;",
            start_month))
        stats.books_this_month = ok_bm and (tonumber(bm_v) or 0) or 0

        local ok_by, by_v = pcall(conn.rowexec, conn, string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;",
            start_year))
        stats.books_this_year = ok_by and (tonumber(by_v) or 0) or 0

        local live_counts = get_live_page_turn_counts(conn, {
            start_today = start_today,
            period_begin = period_begin,
            start_month = start_month,
            start_year = start_year,
        })
        if type(live_counts) == "table" then
            stats.today_pages = (stats.today_pages or 0) + (tonumber(live_counts.today_pages) or 0)
            stats.week_pages = (stats.week_pages or 0) + (tonumber(live_counts.week_pages) or 0)
            stats.month_pages = (stats.month_pages or 0) + (tonumber(live_counts.month_pages) or 0)
            stats.year_pages = (stats.year_pages or 0) + (tonumber(live_counts.year_pages) or 0)
            if (live_counts.today_pages or 0) > 0
                or (live_counts.week_pages or 0) > 0
                or (live_counts.month_pages or 0) > 0
                or (live_counts.year_pages or 0) > 0
            then
                logger.info("zen-ui db_stats: live page turns supplement:",
                    "today=", live_counts.today_pages or 0,
                    "week=", live_counts.week_pages or 0,
                    "month=", live_counts.month_pages or 0,
                    "year=", live_counts.year_pages or 0)
            end
        end

        logger.info("zen-ui db_stats: adjusted pages totals:",
            "today=", stats.today_pages,
            "week=", stats.week_pages)
        logger.info("zen-ui db_stats: month_pages=", stats.month_pages,
                    "year_pages=", stats.year_pages,
                    "books_this_week=", stats.books_this_week,
                    "books_this_month=", stats.books_this_month,
                    "books_this_year=", stats.books_this_year)
    end)

    if not ok then
        logger.warn("zen-ui db_stats: query failed:", query_err)
    end

    conn:close()
    return stats
end

return StatsDB
