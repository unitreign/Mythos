-- JSON-based persistence for tracked novels.
-- Stored at: <koreader_settings>/mythos/tracked.json
local DataStorage = require("datastorage")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end
local ok_json, JSON = pcall(require, "rapidjson")
if not ok_json then JSON = require("json") end

local DB = {}

local db_dir      = DataStorage:getSettingsDir() .. "/mythos"
local db_path     = db_dir .. "/tracked.json"
local exports_path = db_dir .. "/exports.json"
local _data    = nil  -- lazy loaded
local _exports = nil  -- lazy loaded

local function ensure_dir()
    if lfs.attributes(db_dir, "mode") ~= "directory" then
        lfs.mkdir(db_dir)
    end
end

local function load()
    if _data then return _data end
    ensure_dir()
    local f = io.open(db_path, "r")
    if not f then
        _data = { novels = {} }
        return _data
    end
    local raw = f:read("*all")
    f:close()
    local ok, parsed = pcall(JSON.decode, raw)
    _data = (ok and parsed and parsed.novels) and parsed or { novels = {} }
    return _data
end

local function save()
    ensure_dir()
    local f = io.open(db_path, "w")
    if not f then return false end
    f:write(JSON.encode(_data))
    f:close()
    return true
end

function DB.getAll()
    return load().novels
end

function DB.getByFilter(status_filter)
    local novels = load().novels
    if not status_filter or status_filter == "all" then return novels end
    local out = {}
    for _, n in ipairs(novels) do
        local s = (n.status or ""):lower()
        if status_filter == "ongoing" and s == "ongoing" then
            table.insert(out, n)
        elseif status_filter == "completed" and s:match("complet") then
            table.insert(out, n)
        end
    end
    return out
end

function DB.find(source_id, path)
    for _, n in ipairs(load().novels) do
        if n.source_id == source_id and n.path == path then return n end
    end
    return nil
end

-- Track or update a novel.  novel must have: title, source_id, path
function DB.track(novel)
    local data = load()
    for i, n in ipairs(data.novels) do
        if n.source_id == novel.source_id and n.path == novel.path then
            local prev_ch = n.total_chapters or 0
            for k, v in pairs(novel) do n[k] = v end
            n.new_chapters = math.max(0, (n.total_chapters or 0) - prev_ch)
            data.novels[i] = n
            save()
            return n
        end
    end
    -- New entry
    novel.id              = novel.source_id .. ":" .. novel.path
    novel.tracked_at      = os.time()
    novel.new_chapters    = 0
    novel.last_seen_count = novel.total_chapters or 0
    table.insert(data.novels, novel)
    save()
    return novel
end

function DB.untrack(source_id, path)
    local data = load()
    for i, n in ipairs(data.novels) do
        if n.source_id == source_id and n.path == path then
            table.remove(data.novels, i)
            save()
            return true
        end
    end
    return false
end

-- Merge fields into an existing entry by source_id+path
function DB.update(source_id, path, fields)
    local data = load()
    for i, n in ipairs(data.novels) do
        if n.source_id == source_id and n.path == path then
            local prev_ch = n.last_seen_count or n.total_chapters or 0
            for k, v in pairs(fields) do n[k] = v end
            n.new_chapters = math.max(0, (n.total_chapters or 0) - prev_ch)
            data.novels[i] = n
            save()
            return n
        end
    end
    return nil
end

-- Mark all new chapters as seen for a novel
function DB.markSeen(source_id, path)
    local data = load()
    for i, n in ipairs(data.novels) do
        if n.source_id == source_id and n.path == path then
            n.last_seen_count = n.total_chapters or 0
            n.new_chapters    = 0
            data.novels[i]    = n
            save()
            return
        end
    end
end

-- ── Export tracking ──────────────────────────────────────────────────────────

local function load_exports()
    if _exports then return _exports end
    ensure_dir()
    local f = io.open(exports_path, "r")
    if not f then _exports = { records = {} }; return _exports end
    local raw = f:read("*all"); f:close()
    local ok, parsed = pcall(JSON.decode, raw)
    _exports = (ok and parsed and parsed.records) and parsed or { records = {} }
    return _exports
end

local function save_exports()
    ensure_dir()
    local f = io.open(exports_path, "w")
    if not f then return false end
    f:write(JSON.encode(_exports))
    f:close()
    return true
end

-- Record which chapter paths were exported to which epub file.
function DB.recordExport(source_id, novel_path, chapter_paths, epub_path)
    local data = load_exports()
    table.insert(data.records, {
        source_id     = source_id,
        novel_path    = novel_path,
        chapter_paths = chapter_paths,
        epub_path     = epub_path,
        exported_at   = os.time(),
    })
    save_exports()
end

-- Returns a set table {chapter_path = true} of all ever-exported chapters for a novel.
function DB.getExportedChapterSet(source_id, novel_path)
    local data = load_exports()
    local set = {}
    for _, rec in ipairs(data.records) do
        if rec.source_id == source_id and rec.novel_path == novel_path then
            for _, cp in ipairs(rec.chapter_paths or {}) do
                set[cp] = true
            end
        end
    end
    return set
end

return DB
