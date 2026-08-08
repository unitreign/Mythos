-- Sources tab: Repos → Installed → Available.
local UIManager   = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox  = require("ui/widget/confirmbox")
local NetworkMgr  = require("ui/network/manager")
local ExtMgr      = require("core.extmgr")
local Settings    = require("settings")
local P           = require("ui.panel")

local Sources = {}

local _page = 1

local function close_all()
    if _G.mythos_close_all then _G.mythos_close_all() end
end

local function rebuild()
    require("ui.main_widget").show("sources")
end

-- ── Extension settings sub-panel ─────────────────────────────────────────────

function Sources.ext_settings(meta)
    local MythosUI = require("ui.main_widget")
    local ext      = ExtMgr.get(meta.id)
    local sp       = {}  -- {[1] = panel ref} — filled after P.showSubPanel

    local function close_settings()
        if sp[1] then UIManager:close(sp[1]); sp[1] = nil end
        MythosUI.clearDetail()
    end

    local rows = {
        P.makeRow("Source: " .. meta.name,              { dim = true, callback = function() end }),
        P.makeRow("Version: " .. (meta.version or "?"), { dim = true, callback = function() end }),
        P.makeRow("Site: " .. (meta.site or "?"),       { dim = true, callback = function() end }),
    }
    if ext and ext.supports_page_mode then
        local pm = Settings:getExt(meta.id, "page_mode", false)
        table.insert(rows, P.makeRow("Page Mode: " .. (pm and "ON" or "OFF"), {
            callback = function()
                Settings:toggleExt(meta.id, "page_mode", false)
                close_settings()
                rebuild()
            end,
        }))
    end
    table.insert(rows, P.makeRow("Uninstall", {
        bold = true,
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = "Uninstall " .. meta.name .. "?",
                ok_callback = function()
                    ExtMgr.uninstall(meta.id)
                    close_settings()
                    rebuild()
                end,
            })
        end,
    }))
    table.insert(rows, P.makeRow("← Back", { callback = close_settings }))

    local p = P.showSubPanel(meta.name .. " — Settings", rows, close_settings, close_all)
    sp[1] = p
    MythosUI.setDetail(p)
end

-- ── Widget builder ────────────────────────────────────────────────────────────

function Sources.build_widget()
    local rows = {}

    -- Refresh
    table.insert(rows, P.makeRow("Refresh Index", {
        bold = true,
        callback = function()
            NetworkMgr:runWhenConnected(function()
                UIManager:show(InfoMessage:new{ text = "Fetching extension index...", timeout = 2 })
                ExtMgr.fetchIndex()
                rebuild()
            end)
        end,
    }))
    table.insert(rows, P.hairline())

    -- Repos
    table.insert(rows, P.makeRow("-- Repositories --", { dim = true, callback = function() end }))
    local repos = ExtMgr.getRepos()
    if #repos == 0 then
        table.insert(rows, P.makeRow("(no repos added)", { dim = true, callback = function() end }))
    else
        for _, url in ipairs(repos) do
            local u = url
            table.insert(rows, P.makeRow(u, {
                mandatory     = "hold to remove",
                dim           = true,
                callback      = function() end,
                hold_callback = function()
                    UIManager:show(ConfirmBox:new{
                        text        = "Remove this repo?\n" .. u,
                        ok_callback = function()
                            ExtMgr.removeRepo(u)
                            rebuild()
                        end,
                    })
                end,
            }))
        end
    end
    table.insert(rows, P.makeRow("+ Add Repo", {
        bold = true,
        callback = function()
            local dlg
            dlg = InputDialog:new{
                title      = "Add Extension Repo",
                input_hint = "github.com/username/repo",
                buttons    = {{
                    {
                        text             = "Add",
                        is_enter_default = true,
                        callback         = function()
                            local raw = (dlg:getInputText() or ""):match("^%s*(.-)%s*$")
                            -- Strip https:// from GitHub URLs so we always store the short form
                            local to_store = raw:gsub("^https?://(github%.com/)", "%1")
                            UIManager:close(dlg)
                            if to_store ~= "" then
                                local added = ExtMgr.addRepo(to_store)
                                UIManager:show(InfoMessage:new{
                                    text    = added
                                        and "Repo added. Tap Refresh Index to fetch."
                                        or  "Repo already in list.",
                                    timeout = 3,
                                })
                                if added then rebuild() end
                            end
                        end,
                    },
                    { text = "Cancel", callback = function() UIManager:close(dlg) end },
                }},
            }
            UIManager:show(dlg)
        end,
    }))
    table.insert(rows, P.hairline())

    -- Installed
    table.insert(rows, P.makeRow("-- Installed --", { dim = true, callback = function() end }))
    local installed = ExtMgr.installed()
    if #installed == 0 then
        table.insert(rows, P.makeRow("(no sources installed)", { dim = true, callback = function() end }))
    else
        for _, meta in ipairs(installed) do
            local m       = meta
            local has_upd = ExtMgr.hasUpdate(m.id)
            table.insert(rows, P.makeRow(
                m.name .. "  v" .. (m.version or "?") .. "  ·  " .. (m.lang or "en"), {
                    mandatory      = has_upd and "update!" or "installed",
                    mandatory_bold = has_upd,
                    bold           = has_upd,
                    callback      = function() Sources.ext_settings(m) end,
                    hold_callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = "Uninstall " .. m.name .. "?",
                            ok_callback = function()
                                ExtMgr.uninstall(m.id)
                                rebuild()
                            end,
                        })
                    end,
                }
            ))
        end
    end
    table.insert(rows, P.hairline())

    -- Available
    table.insert(rows, P.makeRow("-- Available --", { dim = true, callback = function() end }))
    local avail = ExtMgr.available()
    if #avail == 0 then
        table.insert(rows, P.makeRow("(tap Refresh Index to load)", { dim = true, callback = function() end }))
    else
        for _, meta in ipairs(avail) do
            local m       = meta
            local inst    = ExtMgr.isInstalled(m.id)
            local has_upd = inst and ExtMgr.hasUpdate(m.id)
            table.insert(rows, P.makeRow(m.name .. "  ·  " .. (m.lang or "en"), {
                mandatory      = inst and (has_upd and "update!" or "installed") or "tap to install",
                mandatory_bold = has_upd or false,
                dim            = inst and not has_upd,
                callback  = function()
                    if not inst or has_upd then
                        NetworkMgr:runWhenConnected(function()
                            UIManager:show(InfoMessage:new{
                                text    = (has_upd and "Updating " or "Installing ") .. m.name .. "...",
                                timeout = 2,
                            })
                            local ok, err = ExtMgr.install(m)
                            UIManager:show(InfoMessage:new{
                                text    = ok and (m.name .. " installed.") or ("Error: " .. tostring(err)),
                                timeout = 3,
                            })
                            if ok then rebuild() end
                        end)
                    end
                end,
            }))
        end
    end
    table.insert(rows, P.hairline())

    -- Paginate with nav bar
    local total         = #rows
    local per_page_full = math.max(1, P.MAX_ROWS)
    local use_nav       = math.ceil(total / per_page_full) > 1
    local per_page      = use_nav and math.max(1, P.MAX_ROWS_NAV) or per_page_full
    local max_pages     = math.max(1, math.ceil(total / per_page))
    if _page > max_pages then _page = max_pages end

    local visible = {}
    local start   = (_page - 1) * per_page + 1
    for i = start, math.min(start + per_page - 1, total) do
        table.insert(visible, rows[i])
    end

    local nav = use_nav and {
        page      = _page,
        max_pages = max_pages,
        on_prev   = _page > 1 and function() _page = _page - 1; rebuild() end or nil,
        on_next   = _page < max_pages and function() _page = _page + 1; rebuild() end or nil,
    } or nil

    return P.showTabPanel("sources", visible, "Sources", close_all, nav)
end

function Sources.close() end

return Sources
