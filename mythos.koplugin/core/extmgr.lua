-- Extension manager: download, store, load and query Lua extension files.
local DataStorage = require("datastorage")
local logger      = require("logger")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end
local ok_json, JSON = pcall(require, "rapidjson")
if not ok_json then JSON = require("json") end
local Http     = require("core.http")
local Settings = require("settings")

local ExtMgr = {}

local ext_dir   = DataStorage:getSettingsDir() .. "/mythos/extensions"
local meta_path = DataStorage:getSettingsDir() .. "/mythos/ext_meta.json"

local _loaded     = {}   -- id -> live extension table
local _inst_meta  = {}   -- id -> metadata of installed extensions
local _avail      = {}   -- id -> metadata from remote index

-- ── Internal helpers ─────────────────────────────────────────────────────────

local function ensure_dir()
    logger.dbg("Mythos/ExtMgr: ensure_dir ext_dir=", ext_dir)
    if lfs.attributes(ext_dir, "mode") ~= "directory" then
        logger.dbg("Mythos/ExtMgr: creating mythos dirs")
        lfs.mkdir(DataStorage:getSettingsDir() .. "/mythos")
        lfs.mkdir(ext_dir)
    end
end

local function load_inst_meta()
    logger.dbg("Mythos/ExtMgr: load_inst_meta from", meta_path)
    local f = io.open(meta_path, "r")
    if not f then
        logger.warn("Mythos/ExtMgr: ext_meta.json not found at", meta_path)
        return {}
    end
    local raw = f:read("*all")
    f:close()
    logger.dbg("Mythos/ExtMgr: ext_meta.json raw=", raw)
    local ok, data = pcall(JSON.decode, raw)
    if not ok then
        logger.err("Mythos/ExtMgr: JSON decode failed:", tostring(data))
        return {}
    end
    local count = 0
    for _ in pairs(data) do count = count + 1 end
    logger.dbg("Mythos/ExtMgr: loaded", count, "ext meta entries")
    return data
end

local function save_inst_meta()
    local f = io.open(meta_path, "w")
    if not f then
        logger.err("Mythos/ExtMgr: cannot write ext_meta.json")
        return
    end
    f:write(JSON.encode(_inst_meta))
    f:close()
    logger.dbg("Mythos/ExtMgr: saved ext_meta.json")
end

local function load_ext_file(id)
    local path = ext_dir .. "/" .. id .. ".lua"
    logger.dbg("Mythos/ExtMgr: load_ext_file id=", id, "path=", path)
    local attr = lfs.attributes(path, "mode")
    if attr ~= "file" then
        logger.warn("Mythos/ExtMgr: extension file not found:", path, "(mode=", tostring(attr), ")")
        return nil
    end
    local ok, ext = pcall(dofile, path)
    if ok and type(ext) == "table" then
        _loaded[id] = ext
        logger.dbg("Mythos/ExtMgr: loaded extension", id, "ok")
        return ext
    end
    logger.err("Mythos/ExtMgr: dofile failed for", id, ":", tostring(ext))
    return nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ExtMgr.init()
    logger.dbg("Mythos/ExtMgr: init()")
    ensure_dir()
    _inst_meta = load_inst_meta()
    for id in pairs(_inst_meta) do
        logger.dbg("Mythos/ExtMgr: init loading", id)
        load_ext_file(id)
    end
    logger.dbg("Mythos/ExtMgr: init done. loaded:", (function()
        local ids = {}
        for k in pairs(_loaded) do table.insert(ids, k) end
        return table.concat(ids, ", ")
    end)())
end

-- Return a live extension instance by id, or nil
function ExtMgr.get(id)
    return _loaded[id]
end

-- Ordered list of installed extension metadata tables
function ExtMgr.installed()
    local list = {}
    for id, meta in pairs(_inst_meta) do
        table.insert(list, meta)
    end
    table.sort(list, function(a, b) return (a.name or a.id) < (b.name or b.id) end)
    return list
end

-- List of available (from repos) extension metadata tables
function ExtMgr.available()
    local list = {}
    for _, meta in pairs(_avail) do
        table.insert(list, meta)
    end
    table.sort(list, function(a, b) return (a.name or a.id) < (b.name or b.id) end)
    return list
end

function ExtMgr.isInstalled(id) return _inst_meta[id] ~= nil end

-- Return metadata for a single installed extension, or nil
function ExtMgr.getMeta(id) return _inst_meta[id] end

function ExtMgr.hasUpdate(id)
    local inst = _inst_meta[id]
    local avail = _avail[id]
    if not inst or not avail then return false end
    return inst.version ~= avail.version
end

-- Fetch all repo index URLs and populate _avail.  Returns list of metadata.
function ExtMgr.fetchIndex()
    _avail = {}
    local repos = Settings:get("repos") or {}
    -- Always try the canonical repo URL stored in settings, plus user-added repos
    local all_urls = {}
    for _, url in ipairs(repos) do table.insert(all_urls, url) end

    for _, url in ipairs(all_urls) do
        local data = Http.getJson(url)
        if data and type(data) == "table" then
            for _, meta in ipairs(data) do
                if meta.id then _avail[meta.id] = meta end
            end
        end
    end
    return ExtMgr.available()
end

-- Download and install an extension from its metadata.
-- On success returns true; on failure returns false, error_string.
function ExtMgr.install(meta)
    ensure_dir()
    if not meta.url then return false, "no_url" end
    local dest = ext_dir .. "/" .. meta.id .. ".lua"
    local ok, err = Http.download(meta.url, dest)
    if not ok then return false, tostring(err) end
    _inst_meta[meta.id] = meta
    save_inst_meta()
    load_ext_file(meta.id)
    return true
end

function ExtMgr.update(id)
    local meta = _avail[id]
    if not meta then return false, "not_in_index" end
    return ExtMgr.install(meta)
end

function ExtMgr.uninstall(id)
    os.remove(ext_dir .. "/" .. id .. ".lua")
    _inst_meta[id] = nil
    _loaded[id]    = nil
    save_inst_meta()
end

-- Add a custom repo URL to settings
function ExtMgr.addRepo(url)
    local repos = Settings:get("repos") or {}
    for _, u in ipairs(repos) do
        if u == url then return false end  -- duplicate
    end
    table.insert(repos, url)
    Settings:set("repos", repos)
    return true
end

function ExtMgr.getRepos()
    return Settings:get("repos") or {}
end

return ExtMgr
