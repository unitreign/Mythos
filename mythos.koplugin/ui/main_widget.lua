-- Tab shell: tracks the active tab and all currently shown panels.
-- Three navigation levels:
--   _panel  — main tab (Library / Browse / Sources)
--   _detail — detail/settings sub-screen shown above the tab panel
--   _export — export sub-screen shown above the detail panel
-- Each level is shown without closing the one below it, so closing a level
-- reveals whatever was underneath automatically via UIManager.
local UIManager = require("ui/uimanager")

local MythosUI = {}

MythosUI.active_tab = "library"

-- Filled by main.lua
MythosUI.get_library_widget = nil
MythosUI.get_browse_widget  = nil
MythosUI.get_sources_widget = nil

local _panel  = nil  -- level 1: main tab panel
local _detail = nil  -- level 2: detail / source-settings sub-screen
local _export = nil  -- level 3: export sub-screen

-- ── Level 1: main tab ─────────────────────────────────────────────────────────

function MythosUI.show(tab)
    if _export then UIManager:close(_export); _export = nil end
    if _detail then UIManager:close(_detail); _detail = nil end
    if _panel  then UIManager:close(_panel);  _panel  = nil end
    MythosUI.active_tab = tab or "library"

    local w
    if MythosUI.active_tab == "library" and MythosUI.get_library_widget then
        w = MythosUI.get_library_widget()
    elseif MythosUI.active_tab == "browse" and MythosUI.get_browse_widget then
        w = MythosUI.get_browse_widget()
    elseif MythosUI.active_tab == "sources" and MythosUI.get_sources_widget then
        w = MythosUI.get_sources_widget()
    end

    if not w then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text    = "Tab not ready: " .. tostring(MythosUI.active_tab),
            timeout = 2,
        })
        return
    end
    _panel = w
end

-- ── Level 2: detail panel ─────────────────────────────────────────────────────

-- Register/replace the detail panel. The main tab panel stays alive underneath.
-- The widget must already be shown (P.showCustomTabPanel / P.showSubPanel calls
-- UIManager:show internally).
function MythosUI.setDetail(widget)
    if _export then UIManager:close(_export); _export = nil end
    if _detail then UIManager:close(_detail) end
    _detail = widget
end

-- Called after Detail.close() has already closed the widget.
-- Clears the slot so the main panel underneath can repaint.
function MythosUI.clearDetail()
    if _export then UIManager:close(_export); _export = nil end
    _detail = nil
end

-- ── Level 3: export panel ─────────────────────────────────────────────────────

-- Register/replace the export panel. The detail panel stays alive underneath.
function MythosUI.setExport(widget)
    if _export then UIManager:close(_export) end
    _export = widget
end

-- Called after Export.close() has already closed the widget.
function MythosUI.clearExport()
    _export = nil
end

-- ── Legacy alias (used by sources.lua ext_settings) ──────────────────────────

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
