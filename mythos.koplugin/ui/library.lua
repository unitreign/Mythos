-- Library tab: tracked novels list.
local UIManager  = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox  = require("ui/widget/confirmbox")
local DB          = require("core.db")
local Settings    = require("settings")
local P           = require("ui.panel")

local Library = {}
Library.on_novel_tap = nil

local _page = 1

local function close_all()
    if _G.mythos_close_all then _G.mythos_close_all() end
end

local function rebuild()
    require("ui.main_widget").show("library")
end

local function do_refresh()
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenConnected(function()
        UIManager:show(InfoMessage:new{ text = "Checking for updates...", timeout = 2 })
        local ok, err = pcall(DB.refresh_new_chapters)
        if not ok then
            UIManager:show(InfoMessage:new{
                text    = "Refresh failed: " .. tostring(err),
                timeout = 3,
            })
        end
        _page = 1
        rebuild()
    end)
end

function Library.build_widget()
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

    -- Footer rows
    local flat = Settings:get("export_location_flat")
    local loc  = flat and "Home/Series/Book.epub" or "Home/Mythos/Series/Book.epub"
    local footer_rows = {
        P.hairline(),
        P.makeRow("Export Location", { mandatory = loc, dim = true, callback = function() end }),
    }

    -- Paginate novel rows; use nav bar for prev/next when multiple pages exist
    local fixed_h       = 2 * P.ROW_H + 2 * P.HAIRLINE  -- header_rows + footer_rows heights
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
    for _, r in ipairs(footer_rows)     do table.insert(all_rows, r) end

    local nav = use_nav and {
        page      = _page,
        max_pages = max_pages,
        on_prev   = _page > 1 and function() _page = _page - 1; rebuild() end or nil,
        on_next   = _page < max_pages and function() _page = _page + 1; rebuild() end or nil,
    } or nil

    return P.showTabPanel("library", all_rows, "MYTHOS", close_all, nav)
end

function Library.close() end

return Library
