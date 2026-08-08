-- Novel detail: Details tab (cover, meta, synopsis, track) +
-- Chapters tab (select/deselect/export pinned, paginated chapter list with export markers).
local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr  = require("ui/network/manager")
local ExtMgr      = require("core.extmgr")
local DB          = require("core.db")
local P           = require("ui.panel")
local Device      = require("device")
local Screen      = Device.screen

local function get_export_ui() return require("ui.export") end

local Detail = {}
Detail.on_back = nil

local _source_id    = nil
local _novel_info   = nil
local _all_chapters = {}
local _selected     = {}
local _page         = 1
local _detail_tab   = "details"  -- "details" | "chapters"
local _panel        = nil
local _cover_bb     = nil
local _fetch_id     = 0  -- cancels stale in-flight fetches

local DETAIL_TABS = {
    { id = "details",  label = "Details"  },
    { id = "chapters", label = "Chapters" },
}

local function close_all()
    if _G.mythos_close_all then _G.mythos_close_all() end
end

local function ch_path(ch, idx)
    return ch.path or ch.sourceUrl or tostring(idx)
end

local function count_selected()
    local n = 0
    for _ in pairs(_selected) do n = n + 1 end
    return n
end

local function select_all()
    _selected = {}
    for i, ch in ipairs(_all_chapters) do
        _selected[ch_path(ch, i)] = true
    end
end

local function deselect_all()
    _selected = {}
end

local function selected_chapters()
    local out = {}
    for i, ch in ipairs(_all_chapters) do
        if _selected[ch_path(ch, i)] then out[#out + 1] = ch end
    end
    return out
end

-- ── Details tab rows ──────────────────────────────────────────────────────────

local function build_details_rows(info)
    local is_tracked = DB.find(_source_id, info.path or "") ~= nil
    local rows = {}

    -- Cover image (already aspect-ratio scaled at fetch time)
    local cover_widget = P.makeImageRow(_cover_bb)
    if cover_widget then table.insert(rows, cover_widget) end

    -- Metadata
    local meta_str = (info.author or "Unknown")
        .. "  ·  " .. (info.status or "?")
        .. "  ·  " .. #_all_chapters .. " ch"
    table.insert(rows, P.makeRow(meta_str, { dim = true, callback = function() end }))

    -- Synopsis
    if info.summary and info.summary ~= "" then
        table.insert(rows, P.makeTextBlock(info.summary, 500))
    end

    table.insert(rows, P.hairline())

    -- Track / Untrack
    table.insert(rows, P.makeRow(
        is_tracked and "Untrack Novel" or "Track Novel", {
            bold = true,
            callback = function()
                if is_tracked then
                    DB.untrack(_source_id, info.path or "")
                else
                    DB.track({
                        title          = info.name or info.title or "Novel",
                        source_id      = _source_id,
                        path           = info.path or "",
                        cover          = info.cover,
                        author         = info.author,
                        status         = info.status,
                        summary        = info.summary,
                        total_chapters = #_all_chapters,
                    })
                end
                Detail.rebuild(info, true)
            end,
        }
    ))

    table.insert(rows, P.makeRow("Refresh Chapter List", {
        dim      = true,
        callback = function()
            Detail.fetchForceRefresh(_source_id, info.path or "")
        end,
    }))

    return rows
end

-- ── Chapters tab rows ─────────────────────────────────────────────────────────
-- Returns rows, nav where nav is the pagination nav bar descriptor (or nil).

local function build_chapters_rows(info)
    local sel_count    = count_selected()
    local exported_set = DB.getExportedChapterSet(_source_id, info.path or "")
    local rows         = {}

    -- ── Pinned action header (always at top, not paginated) ──

    table.insert(rows, P.makeRow("Select All (" .. #_all_chapters .. ")", {
        bold = true,
        callback = function() select_all(); Detail.rebuild(info, true) end,
    }))
    table.insert(rows, P.makeRow("Deselect All", {
        callback = function() deselect_all(); Detail.rebuild(info, true) end,
    }))

    local ext = ExtMgr.get(_source_id)
    local export_label = sel_count > 0
        and ("Export (" .. sel_count .. " chapters)")
        or  "Export — select chapters first"
    table.insert(rows, P.makeRow(export_label, {
        bold = sel_count > 0,
        dim  = sel_count == 0,
        callback = function()
            if sel_count == 0 or not ext then return end
            get_export_ui().show({
                chapters       = selected_chapters(),
                novel          = info,
                source_id      = _source_id,
                total_chapters = #_all_chapters,
                fetch_fn       = function(path)
                    local ok, html = pcall(ext.parseChapter, ext, path)
                    return ok and html or nil
                end,
            })
        end,
    }))
    table.insert(rows, P.hairline())

    -- ── Paginated chapter list ──

    -- Fixed content height consumed by the 3 action rows + hairline
    local fixed_h       = 3 * P.ROW_H + P.HAIRLINE
    local total_ch      = #_all_chapters
    -- Compute per_page using full height first; if all chapters fit, no nav bar needed
    local per_page_full = math.max(1, math.floor((P.CONTENT_H     - fixed_h) / P.ROW_H))
    local per_page_nav  = math.max(1, math.floor((P.CONTENT_H_NAV - fixed_h) / P.ROW_H))
    local use_nav       = math.ceil(total_ch / per_page_full) > 1
    local per_page      = use_nav and per_page_nav or per_page_full
    local max_pages     = math.max(1, math.ceil(total_ch / per_page))
    if _page > max_pages then _page = max_pages end

    if total_ch == 0 then
        table.insert(rows, P.makeRow("No chapters found", { dim = true, callback = function() end }))
    else
        local ch_start = (_page - 1) * per_page + 1
        local ch_end   = math.min(ch_start + per_page - 1, total_ch)
        for i = ch_start, ch_end do
            local ch        = _all_chapters[i]
            local p         = ch_path(ch, i)
            local label     = ch.name or ch.title or ("Chapter " .. i)
            local inf       = info
            local is_exp    = exported_set[p] and true or false
            local is_sel    = _selected[p] and true or false
            local is_locked = ch.locked == true
            local prefix    = is_exp and "✓" or " "
            local display   = is_locked
                and (prefix .. " (locked) " .. label)
                or  (prefix .. (is_sel and " [x] " or " [ ] ") .. label)
            table.insert(rows, P.makeRow(display, {
                mandatory = ch.chapter_number and ("Ch." .. ch.chapter_number) or nil,
                bold      = is_sel and not is_locked,
                dim       = is_locked,
                callback  = is_locked and function() end or function()
                    if _selected[p] then _selected[p] = nil
                    else _selected[p] = true end
                    Detail.rebuild(inf, true)
                end,
            }))
        end
    end

    -- Nav bar descriptor (nil when all chapters fit on one page)
    local nav = use_nav and {
        page      = _page,
        max_pages = max_pages,
        on_prev   = _page > 1 and function()
            _page = _page - 1; Detail.rebuild(info, true)
        end or nil,
        on_next   = _page < max_pages and function()
            _page = _page + 1; Detail.rebuild(info, true)
        end or nil,
        on_first  = _page > 1 and function()
            _page = 1; Detail.rebuild(info, true)
        end or nil,
        on_last   = _page < max_pages and function()
            _page = max_pages; Detail.rebuild(info, true)
        end or nil,
        on_jump   = function(n)
            _page = math.max(1, math.min(max_pages, math.floor(n)))
            Detail.rebuild(info, true)
        end,
    } or nil

    return rows, nav
end

-- ── Rebuild ───────────────────────────────────────────────────────────────────
-- partial = true uses partial e-ink refresh (chapter ticks, pagination changes).

function Detail.rebuild(info, partial)
    local MythosUI = require("ui.main_widget")
    local title    = info.name or info.title or "Novel"

    local rows, nav
    if _detail_tab == "chapters" then
        rows, nav = build_chapters_rows(info)
    else
        rows = build_details_rows(info)
    end

    -- Closure captures module-level _novel_info so tab switches always use fresh data
    local function switch_tab(id)
        _detail_tab = id
        _page = 1
        Detail.rebuild(_novel_info)  -- full refresh on tab switch
    end

    local function on_back()
        Detail.close()
        MythosUI.clearDetail()
        if Detail.on_back then Detail.on_back() end
    end

    -- Let MythosUI.setDetail close the previous panel
    _panel = P.showCustomTabPanel(
        DETAIL_TABS, _detail_tab, switch_tab,
        rows, title, on_back, close_all, nav, partial
    )
    MythosUI.setDetail(_panel)
end

-- ── Public ────────────────────────────────────────────────────────────────────

-- Clear chapter cache then re-fetch from scratch.
function Detail.fetchForceRefresh(source_id, path)
    DB.clearChapterCache(source_id, path)
    Detail.fetch(source_id, path)
end

function Detail.fetch(source_id, path)
    _fetch_id     = _fetch_id + 1
    local my_id   = _fetch_id
    _source_id    = source_id
    _selected     = {}
    _all_chapters = {}
    _novel_info   = nil
    _page         = 1
    _detail_tab   = "details"
    if _cover_bb then _cover_bb:free(); _cover_bb = nil end

    local ext = ExtMgr.get(source_id)
    if not ext then
        UIManager:show(InfoMessage:new{
            text    = "Extension not loaded: " .. tostring(source_id),
            timeout = 3,
        })
        return
    end

    NetworkMgr:runWhenConnected(function()
        local loading = InfoMessage:new{ text = "Loading novel details…" }
        UIManager:show(loading)

        UIManager:scheduleIn(0.1, function()
            if my_id ~= _fetch_id then return end

            local info

            if type(ext.parseNovelMeta) == "function" then
                -- ── Fast path: metadata-only fetch + smart chapter loading ────
                -- Only 1 HTTP request when the chapter count hasn't changed.
                local ok, meta = pcall(ext.parseNovelMeta, ext, path)
                if not ok or not meta then
                    UIManager:close(loading)
                    UIManager:show(InfoMessage:new{
                        text    = "Failed to load novel: " .. tostring(meta),
                        timeout = 4,
                    })
                    return
                end
                info = meta

                local new_total = info.total_chapters or 0
                local cache     = DB.loadChapterCache(source_id, path)

                if cache and cache.total == new_total and new_total > 0 then
                    -- Cache hit: chapter count unchanged, use cached list
                    _all_chapters = cache.chapters
                elseif cache and cache.total > 0 and new_total > cache.total
                       and type(ext.parsePage) == "function" and ext.chapters_per_page then
                    -- Delta: fetch only the new pages
                    local per_page     = ext.chapters_per_page
                    local first_new_pg = math.floor(cache.total / per_page) + 1
                    local last_pg      = math.ceil(new_total / per_page)
                    local new_chs      = {}
                    for pg = first_new_pg, last_pg do
                        local ok_p, pdata = pcall(ext.parsePage, ext, path, tostring(pg))
                        if ok_p and pdata and pdata.chapters then
                            for _, ch in ipairs(pdata.chapters) do
                                table.insert(new_chs, ch)
                            end
                        end
                    end
                    local seen = {}
                    _all_chapters = {}
                    for _, ch in ipairs(cache.chapters) do
                        seen[ch.path or ""] = true
                        table.insert(_all_chapters, ch)
                    end
                    for _, ch in ipairs(new_chs) do
                        if not seen[ch.path or ""] then
                            table.insert(_all_chapters, ch)
                        end
                    end
                    DB.saveChapterCache(source_id, path, _all_chapters, #_all_chapters)
                else
                    -- Full fetch (cache miss, count decreased, or no delta support)
                    local ok_n, full = pcall(ext.parseNovel, ext, path)
                    if ok_n and full then
                        _all_chapters = full.chapters or {}
                        for k, v in pairs(full) do
                            if info[k] == nil then info[k] = v end
                        end
                    end
                    DB.saveChapterCache(source_id, path, _all_chapters, #_all_chapters)
                end
                info.total_chapters = #_all_chapters

            else
                -- ── Legacy path: parseNovel returns everything ────────────────
                local ok, full = pcall(ext.parseNovel, ext, path)
                if not ok or not full then
                    UIManager:close(loading)
                    UIManager:show(InfoMessage:new{
                        text    = "Failed to load novel: " .. tostring(full),
                        timeout = 4,
                    })
                    return
                end
                info          = full
                _all_chapters = full.chapters or {}
                DB.saveChapterCache(source_id, path, _all_chapters, #_all_chapters)
            end

            UIManager:close(loading)
            _novel_info = info

            -- ── Cover: disk cache first, download if missing ──────────────────
            if info.cover and info.cover ~= "" then
                local ok_epub, Epub       = pcall(require, "core.epub")
                local ok_ri,  RenderImage = pcall(require, "ui/renderimage")
                if ok_epub and ok_ri then
                    local cdata = DB.loadCoverCache(source_id, path)
                    if not cdata then
                        cdata = Epub.fetch_cover(info.cover)
                        if cdata then DB.saveCoverCache(source_id, path, cdata) end
                    end
                    if cdata then
                        local ok_bb, native = pcall(
                            RenderImage.renderImageData, RenderImage,
                            cdata, #cdata, false)
                        if ok_bb and native then
                            local nw, nh = native:getWidth(), native:getHeight()
                            if nw > 0 and nh > 0 then
                                local max_w = P.W - 2 * P.MARGIN
                                local max_h = Screen:scaleBySize(180)
                                local scale = math.min(max_w / nw, max_h / nh)
                                local dw = math.max(1, math.floor(nw * scale))
                                local dh = math.max(1, math.floor(nh * scale))
                                _cover_bb = native:scale(dw, dh)
                            end
                            native:free()
                        end
                    end
                end
            end

            -- ── Persist summary for tracked novels ────────────────────────────
            if info.summary and info.summary ~= "" then
                local tracked = DB.find(source_id, info.path or path)
                if tracked and not tracked.summary then
                    DB.update(source_id, info.path or path, { summary = info.summary })
                end
            end

            Detail.rebuild(info)
        end)
    end)
end

function Detail.close()
    if _panel then
        UIManager:close(_panel)
        _panel = nil
    end
    if _cover_bb then
        _cover_bb:free()
        _cover_bb = nil
    end
end

return Detail
