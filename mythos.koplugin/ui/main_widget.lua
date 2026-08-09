-- Tab shell: tracks the active tab and the single persistent main panel.
-- Three navigation levels:
--   _panel  — main tab (Library / Browse / Sources) — kept alive across rebuilds
--   _detail — detail/settings sub-screen shown above the tab panel
--   _export — export sub-screen shown above the detail panel
-- Each level is shown without closing the one below it, so closing a level
-- reveals whatever was underneath automatically via UIManager.
local UIManager = require("ui/uimanager")

local MythosUI = {}

MythosUI.active_tab = "library"

-- Filled by main.lua — each returns (rows, title, nav) for its tab
MythosUI.get_library_rows = nil
MythosUI.get_browse_rows  = nil
MythosUI.get_sources_rows = nil

local _panel  = nil  -- level 1: main tab panel (persistent)
local _detail = nil  -- level 2: detail / source-settings sub-screen
local _export = nil  -- level 3: export sub-screen

local function close_fn()
    if _G.mythos_close_all then _G.mythos_close_all() end
end

-- ── Level 1: main tab ─────────────────────────────────────────────────────────

function MythosUI.show(tab)
    if _export then UIManager:close(_export); _export = nil end
    if _detail then UIManager:close(_detail); _detail = nil end

    local same_tab = _panel ~= nil and MythosUI.active_tab == (tab or "library")
    MythosUI.active_tab = tab or "library"

    local rows, title, nav
    if MythosUI.active_tab == "library" and MythosUI.get_library_rows then
        rows, title, nav = MythosUI.get_library_rows()
    elseif MythosUI.active_tab == "browse" and MythosUI.get_browse_rows then
        rows, title, nav = MythosUI.get_browse_rows()
    elseif MythosUI.active_tab == "sources" and MythosUI.get_sources_rows then
        rows, title, nav = MythosUI.get_sources_rows()
    end

    if not rows then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text    = "Tab not ready: " .. tostring(MythosUI.active_tab),
            timeout = 2,
        })
        return
    end

    local P = require("ui.panel")
    if _panel then
        _panel:swapBody(P.buildTabBody(MythosUI.active_tab, rows, title, close_fn, nav), close_fn, same_tab)
    else
        _panel = P.showTabPanel(MythosUI.active_tab, rows, title, close_fn, nav)
    end
end

-- ── Level 2: detail panel ─────────────────────────────────────────────────────

function MythosUI.setDetail(widget)
    if _export then UIManager:close(_export); _export = nil end
    if _detail then UIManager:close(_detail) end
    _detail = widget
end

function MythosUI.clearDetail()
    if _export then UIManager:close(_export); _export = nil end
    _detail = nil
end

-- ── Level 3: export panel ─────────────────────────────────────────────────────

function MythosUI.setExport(widget)
    if _export then UIManager:close(_export) end
    _export = widget
end

function MythosUI.clearExport()
    _export = nil
end

-- ── Legacy aliases ────────────────────────────────────────────────────────────

function MythosUI.showSub(widget)
    MythosUI.setDetail(widget)
end

function MythosUI.backFromSub()
    if _export then UIManager:close(_export); _export = nil end
    if _detail then UIManager:close(_detail); _detail = nil end
end

-- ── Close everything ──────────────────────────────────────────────────────────

function MythosUI.close()
    if _export then UIManager:close(_export); _export = nil end
    if _detail then UIManager:close(_detail); _detail = nil end
    if _panel  then UIManager:close(_panel);  _panel  = nil end
end

return MythosUI
