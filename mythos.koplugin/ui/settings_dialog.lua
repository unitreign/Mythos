-- Settings popup: toggle cover display per screen.
-- Reopens itself after each toggle so the button labels stay current.
local UIManager        = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Settings         = require("settings")

local SettingsDialog = {}
local _dlg = nil

local function on_off(key)
    return Settings:get(key) and "ON" or "OFF"
end

function SettingsDialog.show()
    if _dlg then UIManager:close(_dlg) end

    _dlg = ButtonDialogTitle:new{
        title   = "Mythos Settings",
        buttons = {
            {
                {
                    text     = "Covers · Library Page: " .. on_off("covers_library"),
                    callback = function()
                        Settings:toggle("covers_library")
                        SettingsDialog.show()
                    end,
                },
            },
            {
                {
                    text     = "Covers · Browse Page: " .. on_off("covers_browse"),
                    callback = function()
                        Settings:toggle("covers_browse")
                        SettingsDialog.show()
                    end,
                },
            },
            {
                {
                    text     = "Covers · Detail Page: " .. on_off("covers_detail"),
                    callback = function()
                        Settings:toggle("covers_detail")
                        SettingsDialog.show()
                    end,
                },
            },
            {
                {
                    text     = "Close",
                    callback = function()
                        UIManager:close(_dlg)
                        _dlg = nil
                    end,
                },
            },
        },
    }
    UIManager:show(_dlg)
end

return SettingsDialog
