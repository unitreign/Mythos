-- Mythos — main plugin entry point.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")

local plugin_dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
package.path = plugin_dir .. "/?.lua;"
    .. plugin_dir .. "/?/init.lua;"
    .. package.path

-- Close-all helper: shuts every Mythos widget
local function close_all()
    local MythosUI = package.loaded["ui.main_widget"]
    if MythosUI then pcall(MythosUI.close) end
end
_G.mythos_close_all = close_all

local _ready = false

local function open_mythos()
    local ok, err = pcall(function()
        local MythosUI = require("ui.main_widget")
        local Library  = require("ui.library")
        local Browse   = require("ui.browse")
        local Detail   = require("ui.detail")
        local Sources  = require("ui.sources")
        local ExtMgr   = require("core.extmgr")

        if not _ready then
            ExtMgr.init()

            -- Wire tab widget getters
            MythosUI.get_library_widget = function()
                return Library.build_widget()
            end
            MythosUI.get_browse_widget = function()
                return Browse.build_widget()
            end
            MythosUI.get_sources_widget = function()
                return Sources.build_widget()
            end

            -- Library: tapping a novel opens Detail above the library panel
            Library.on_novel_tap = function(novel)
                MythosUI.active_tab = "library"
                Detail.on_back = nil  -- tab panel stays alive; closing detail reveals it
                Detail.fetch(novel.source_id, novel.path)
            end

            -- Browse: tapping a novel opens Detail above the browse panel
            Browse.on_novel_tap = function(source_id, novel_meta)
                MythosUI.active_tab = "browse"
                Detail.on_back = nil
                Detail.fetch(source_id, novel_meta.path or novel_meta.sourceUrl or "")
            end

            _ready = true
        end

        MythosUI.show("library")
    end)

    if not ok then
        UIManager:show(require("ui/widget/infomessage"):new{
            text    = "Mythos failed to open:\n" .. tostring(err),
            timeout = 6,
        })
    end
end

local Mythos = WidgetContainer:extend{
    name        = "mythos",
    fullname    = "Mythos",
    description = "Web novel tracker and EPUB exporter",
    is_doc_only = false,
}

function Mythos:init()
    self.ui.menu:registerToMainMenu(self)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and Dispatcher then
        Dispatcher:init()
        Dispatcher:registerAction("mythos_open", {
            category   = "none",
            event      = "MythosOpen",
            title      = "Mythos: Open",
            general    = true,
        })
    end
end

function Mythos:onMythosOpen()
    open_mythos()
    return true
end

function Mythos:addToMainMenu(menu_items)
    menu_items["mythos"] = {
        text         = "Mythos",
        sorting_hint = "tools",
        callback     = open_mythos,
    }
end

return Mythos
