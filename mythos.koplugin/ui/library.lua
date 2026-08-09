-- Library tab: tracked novels list.
local UIManager  = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox  = require("ui/widget/confirmbox")
local DB          = require("core.db")
local P           = require("ui.panel")

local Library = {}
Library.on_novel_tap = nil

local _page     = 1
local _fetch_id = 0

local function rebuild()
    require("ui.main_widget").show("library")
end

local function do_refresh_confirmed()
    _fetch_id = _fetch_id + 1
    local my_id = _fetch_id

    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenConnected(function()
        if my_id ~= _fetch_id then return end

        local ExtMgr  = require("core.extmgr")
        local loading = InfoMessage:new{ text = "Checking for updates…" }
        UIManager:show(loading)
        UIManager:scheduleIn(0.1, function()
            if my_id ~= _fetch_id then
                UIManager:close(loading)
                return
            end

            local novels  = DB.getAll()
            local updated = 0
            for _, novel in ipairs(novels) do
                local ext = ExtMgr.get(novel.source_id)
                if ext then
                    local ok, info = pcall(ext.parseNovel, ext, novel.path)
                    if ok and info then
                        local new_total = info.chapters and #info.chapters or 0
                        if new_total ~= (novel.total_chapters or 0) then
                            DB.update(novel.source_id, novel.path, { total_chapters = new_total })
                            updated = updated + 1
                        end
                    end
                end
            end
            UIManager:close(loading)
            UIManager:show(InfoMessage:new{
                text    = updated > 0
                    and (updated .. " novel(s) have new chapters!")
                    or  "No new chapters found.",
                timeout = 3,
            })
            _page = 1
            rebuild()
        end)
    end)
end

local function do_refresh()
    UIManager:show(ConfirmBox:new{
        text        = "This checks every tracked novel for new chapters.\n\nThe more novels you have tracked, the longer this takes. To update a specific novel only, open it individually instead.\n\nContinue?",
        ok_text     = "Refresh All",
        cancel_text = "Cancel",
        ok_callback = do_refresh_confirmed,
    })
end

function Library.build_rows()
    local MythosUI = require("ui.main_widget")

    local novels = DB.getByFilter("all")

    -- Fixed header rows (always shown)
    local header_rows = {
        P.makeRow("Refresh  (check for new chapters)", {
            bold = true, callback = do_refresh,
        }),
        P.hairline(),
    }

    -- Novel rows
    local novel_rows = {}
    if #novels == 0 then
        table.insert(novel_rows, P.makeRow("No novels tracked yet — go to Browse", {
            dim = true,
            callback = function() MythosUI.show("browse") end,
        }))
    else
        for _, n in ipairs(novels) do
            local novel  = n
            local new    = novel.new_chapters or 0
            local badge  = new > 0 and ("  [+" .. new .. " new]") or ""
            local src    = novel.source_id or "?"
            local ch     = novel.total_chapters or 0
            table.insert(novel_rows, P.makeRow(
                (novel.title or "Unknown") .. badge, {
                    mandatory = src .. "  ·  " .. ch .. " ch",
                    bold      = new > 0,
                    callback  = function()
                        if Library.on_novel_tap then Library.on_novel_tap(novel) end
                    end,
                    hold_callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = 'Untrack "' .. (novel.title or "?") .. '"?',
                            ok_callback = function()
                                DB.untrack(novel.source_id, novel.path)
                                _page = 1
                                rebuild()
                            end,
                        })
                    end,
                }
            ))
        end
    end

    -- Paginate novel rows; nav bar handles prev/next when there are multiple pages
    local fixed_h       = P.ROW_H + P.HAIRLINE  -- header_rows: Refresh row + hairline
    local total         = #novel_rows
    local per_page_full = math.max(1, math.floor((P.CONTENT_H     - fixed_h) / P.ROW_H))
    local use_nav       = math.ceil(total / per_page_full) > 1
    local per_page      = use_nav
        and math.max(1, math.floor((P.CONTENT_H_NAV - fixed_h) / P.ROW_H))
        or  per_page_full
    local max_pages = math.max(1, math.ceil(total / per_page))
    if _page > max_pages then _page = max_pages end

    local page_novel_rows = {}
    local start = (_page - 1) * per_page + 1
    for i = start, math.min(start + per_page - 1, total) do
        table.insert(page_novel_rows, novel_rows[i])
    end

    local all_rows = {}
    for _, r in ipairs(header_rows)     do table.insert(all_rows, r) end
    for _, r in ipairs(page_novel_rows) do table.insert(all_rows, r) end

    local nav = use_nav and {
        page      = _page,
        max_pages = max_pages,
        on_prev   = _page > 1 and function() _page = _page - 1; rebuild() end or nil,
        on_next   = _page < max_pages and function() _page = _page + 1; rebuild() end or nil,
    } or nil

    return all_rows, "MYTHOS", nav
end

function Library.close() end

return Library
