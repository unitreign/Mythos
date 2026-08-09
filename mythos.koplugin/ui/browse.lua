-- Browse tab: source picker → novel list.
local UIManager   = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr  = require("ui/network/manager")
local ExtMgr      = require("core.extmgr")
local P           = require("ui.panel")

local Browse = {}
Browse.on_novel_tap = nil

Browse._state     = "picker"
Browse._source_id = nil
Browse._novels    = {}
Browse._page      = 1
Browse._search    = nil

local _fetch_id = 0

local function rebuild()
    require("ui.main_widget").show("browse")
end

local function open_search()
    local sid  = Browse._source_id
    local meta = ExtMgr.getMeta(sid) or {}
    local dlg
    dlg = InputDialog:new{
        title      = "Search — " .. (meta.name or sid),
        input_hint = "Novel title...",
        buttons    = {{
            {
                text             = "Search",
                is_enter_default = true,
                callback         = function()
                    local term = dlg:getInputText()
                    UIManager:close(dlg)
                    if term and term ~= "" then
                        Browse._search = term
                        Browse.fetchAndShow(sid, 1, term)
                    end
                end,
            },
            { text = "Cancel", callback = function() UIManager:close(dlg) end },
        }},
    }
    UIManager:show(dlg)
end

local function build_source_picker_rows()
    local MythosUI  = require("ui.main_widget")
    local installed = ExtMgr.installed()
    local rows = {}

    if #installed == 0 then
        table.insert(rows, P.makeRow("No sources installed — go to Sources tab", {
            dim = true,
            callback = function() MythosUI.show("sources") end,
        }))
        return rows, "Browse"
    end

    table.insert(rows, P.makeRow("-- Installed Sources --", { dim = true, callback = function() end }))
    for _, meta in ipairs(installed) do
        local m = meta
        table.insert(rows, P.makeRow(m.name, {
            mandatory = m.lang or "en",
            bold      = true,
            callback  = function()
                Browse._source_id = m.id
                Browse._search    = nil
                Browse.fetchAndShow(m.id, 1, nil)
            end,
        }))
    end
    return rows, "Browse"
end

local function build_novel_list_rows()
    local source_id = Browse._source_id
    local novels    = Browse._novels
    local page      = Browse._page
    local is_search = Browse._search ~= nil
    local meta      = ExtMgr.getMeta(source_id) or {}
    local rows      = {}

    -- Search / back row
    table.insert(rows, P.makeRow(
        is_search and ("Search  (\"" .. Browse._search .. "\")") or "Search", {
            bold = true, callback = open_search,
        }
    ))
    table.insert(rows, P.makeRow("← Back to Source Select", {
        bold = true,
        callback = function()
            Browse._state = "picker"
            rebuild()
        end,
    }))
    table.insert(rows, P.hairline())

    -- Trim novel list to fit content area with the nav bar present
    local fixed_h        = 2 * P.ROW_H + P.HAIRLINE  -- Search + Back + hairline
    local max_novel_rows = math.max(1, math.floor((P.CONTENT_H_NAV - fixed_h) / P.ROW_H))

    if #novels == 0 then
        table.insert(rows, P.makeRow("No results", { dim = true, callback = function() end }))
    else
        for i = 1, math.min(#novels, max_novel_rows) do
            local novel = novels[i]
            table.insert(rows, P.makeRow(novel.name or novel.title or "?", {
                mandatory = novel.author or "",
                callback  = function()
                    if Browse.on_novel_tap then Browse.on_novel_tap(source_id, novel) end
                end,
            }))
        end
    end

    -- Nav bar handles prev/next for the source's own API pages
    local nav = {
        page    = page,
        on_prev = page > 1 and function()
            Browse.fetchAndShow(source_id, page - 1, Browse._search)
        end or nil,
        on_next = function()
            Browse.fetchAndShow(source_id, page + 1, Browse._search)
        end,
    }

    local title = (meta.name or source_id)
        .. (is_search and ("  —  \"" .. Browse._search .. "\"") or "  —  Popular")

    return rows, title, nav
end

function Browse.build_rows()
    local rows, title, nav
    if Browse._state == "list" then
        rows, title, nav = build_novel_list_rows()
    else
        Browse._state = "picker"
        rows, title   = build_source_picker_rows()
    end

    -- Trim rows to MAX_ROWS for source picker (no nav bar there)
    local visible = {}
    for i = 1, math.min(#rows, nav and P.MAX_ROWS_NAV or P.MAX_ROWS) do
        table.insert(visible, rows[i])
    end

    return visible, title, nav
end

function Browse.fetchAndShow(source_id, page, search_term)
    local ext = ExtMgr.get(source_id)
    if not ext then
        UIManager:show(InfoMessage:new{
            text    = "Extension not loaded: " .. tostring(source_id),
            timeout = 3,
        })
        return
    end

    _fetch_id = _fetch_id + 1
    local my_id = _fetch_id

    NetworkMgr:runWhenConnected(function()
        if my_id ~= _fetch_id then return end

        local loading = InfoMessage:new{ text = "Loading…" }
        UIManager:show(loading)

        UIManager:scheduleIn(0.1, function()
            if my_id ~= _fetch_id then
                UIManager:close(loading)
                return
            end

            local novels, err
            if search_term and search_term ~= "" then
                local ok, res = pcall(ext.searchNovels, ext, search_term, page)
                if ok and res then novels = res.novels or res else err = tostring(res) end
            else
                local ok, res = pcall(ext.popularNovels, ext, page, {})
                if ok and res then novels = res.novels or res else err = tostring(res) end
            end

            UIManager:close(loading)

            if err then
                UIManager:show(InfoMessage:new{ text = "Error: " .. err, timeout = 4 })
                return
            end

            Browse._state     = "list"
            Browse._source_id = source_id
            Browse._novels    = novels or {}
            Browse._page      = page
            Browse._search    = (search_term and search_term ~= "") and search_term or nil
            rebuild()
        end)
    end)
end

function Browse.close() end

return Browse
