-- Settings singleton for Mythos.
-- All keys are lazy-loaded; file is only written when a value changes.
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local DEFAULTS = {
    covers_library  = true,
    covers_browse   = false,
    covers_detail   = true,
    repos           = {},
    extension_settings = {},
}

local Settings = {}
local _file = nil

local function get_file()
    if not _file then
        _file = LuaSettings:open(DataStorage:getSettingsDir() .. "/mythos.lua")
    end
    return _file
end

function Settings:get(key)
    local val = get_file():readSetting(key)
    if val == nil then return DEFAULTS[key] end
    return val
end

function Settings:set(key, value)
    get_file():saveSetting(key, value)
    get_file():flush()
end

function Settings:toggle(key)
    self:set(key, not self:get(key))
end

-- Per-extension settings (keyed by extension id)
function Settings:getExt(ext_id, key, default)
    local all = self:get("extension_settings") or {}
    local ext = all[ext_id] or {}
    local val = ext[key]
    if val == nil then return default end
    return val
end

function Settings:setExt(ext_id, key, value)
    local all = self:get("extension_settings") or {}
    if not all[ext_id] then all[ext_id] = {} end
    all[ext_id][key] = value
    self:set("extension_settings", all)
end

function Settings:toggleExt(ext_id, key, default)
    self:setExt(ext_id, key, not self:getExt(ext_id, key, default))
end

return Settings
