-- core/updater.lua — Mythos manual OTA updater
-- Checks GitHub releases API, downloads mythos.koplugin.zip, unzips in-place,
-- deletes the zip, then offers a KOReader restart.

local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox  = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local logger      = require("logger")

local Updater = {}

local GITHUB_OWNER = "unitreign"
local GITHUB_REPO  = "mythos"
local ASSET_NAME   = "mythos.koplugin.zip"
local API_URL      = "https://api.github.com/repos/unitreign/mythos/releases/latest"

-- core/ directory (where this file lives)
local _core_dir   = (debug.getinfo(1, "S").source or ""):match("^@?(.+)/[^/]+%.lua$") or ""
-- mythos.koplugin/ — one level up from core/
local _plugin_dir = _core_dir:match("^(.+)/[^/]+$") or _core_dir
-- plugins/ directory — one level up from mythos.koplugin/; zip extracts here
local _parent_dir = _plugin_dir:match("^(.+)/[^/]+$") or _plugin_dir

-- ── Version helpers ───────────────────────────────────────────────────────────

local function current_version()
    return _G.MYTHOS_VERSION or "0.0.0"
end

-- Returns true if semver string a is strictly greater than b.
-- Strips "v" prefix and pre-release suffixes before comparing.
local function version_gt(a, b)
    local function parts(v)
        v = (v or ""):match("^v?(.-)[-+]") or (v or ""):match("^v?(.+)$") or ""
        local t = {}
        for n in (v .. "."):gmatch("(%d+)%.") do t[#t + 1] = tonumber(n) or 0 end
        while #t < 3 do t[#t + 1] = 0 end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, 3 do
        if pa[i] > pb[i] then return true end
        if pa[i] < pb[i] then return false end
    end
    return false
end

-- ── HTTP ──────────────────────────────────────────────────────────────────────

local function _request(url, sink, extra_headers)
    local https = require("ssl.https")
    local http  = require("socket.http")
    local ltn12 = require("ltn12")
    local req   = url:match("^https") and https or http
    local headers = { ["User-Agent"] = "KOReader-Mythos-Updater" }
    if extra_headers then
        for k, v in pairs(extra_headers) do headers[k] = v end
    end
    local ok, code, resp_headers = req.request{
        url     = url,
        sink    = sink,
        headers = headers,
    }
    return ok, code, resp_headers
end

local function http_get(url)
    local ltn12 = require("ltn12")
    local sink  = {}
    local ok, code = _request(url, ltn12.sink.table(sink), {
        ["Accept"] = "application/vnd.github.v3+json",
    })
    logger.dbg("Mythos/Updater: GET", url, "→", tostring(code))
    if not ok or code ~= 200 then return nil, tostring(code) end
    return table.concat(sink)
end

-- GitHub release asset URLs redirect (302) to the CDN. We follow one redirect.
local function http_download(url, dest)
    local ltn12 = require("ltn12")

    -- First request: may return 302 with a Location header.
    local headers_only = {}
    local ok, code, resp_headers = _request(url, ltn12.sink.table(headers_only), nil)
    logger.dbg("Mythos/Updater: download probe", url, "→", tostring(code))

    local final_url = url
    if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
        local location = resp_headers and (resp_headers["location"] or resp_headers["Location"])
        if not location then
            return nil, "redirect with no Location header"
        end
        logger.dbg("Mythos/Updater: following redirect →", location)
        final_url = location
    elseif not ok or code ~= 200 then
        return nil, tostring(code)
    end

    -- Second (or only) request: stream directly to disk.
    local fh, err = io.open(dest, "wb")
    if not fh then return nil, "cannot open dest: " .. tostring(err) end
    local ok2, code2 = _request(final_url, ltn12.sink.file(fh), nil)
    -- ltn12.sink.file closes fh automatically
    logger.dbg("Mythos/Updater: download stream", final_url, "→", tostring(code2))
    if not ok2 or code2 ~= 200 then
        pcall(os.remove, dest)
        return nil, tostring(code2)
    end
    return true
end

-- ── Release parsing ───────────────────────────────────────────────────────────

local function parse_release(body)
    local ok_j, JSON = pcall(require, "rapidjson")
    if not ok_j then ok_j, JSON = pcall(require, "json") end

    if ok_j then
        local ok_d, data = pcall(JSON.decode, body)
        if not ok_d or type(data) ~= "table" then return nil, "JSON parse error" end
        local tag = data.tag_name
        if not tag then return nil, "missing tag_name" end

        local dl_url
        for _, asset in ipairs(data.assets or {}) do
            if asset.name == ASSET_NAME then
                dl_url = asset.browser_download_url
                break
            end
        end

        local notes
        local raw = data.body or ""
        local block = raw:match("<!%-%-himythos%-%->(.-)<!%-%-/himythos%-%->")
        if block and block:match("%S") then
            notes = block:gsub("\r\n", "\n"):gsub("\r", "\n"):match("^%s*(.-)%s*$")
        end

        return {
            version      = tag:match("v?(.*)"),
            download_url = dl_url,
            notes        = (notes and notes ~= "") and notes or nil,
        }
    end

    -- json module unavailable — regex fallback
    logger.warn("Mythos/Updater: json unavailable, using regex fallback")
    local tag = body:match('"tag_name"%s*:%s*"([^"]*)"')
    if not tag then return nil, "could not parse tag_name" end
    local asset_pat = '"browser_download_url"%s*:%s*"([^"]*'
        .. ASSET_NAME:gsub("%.", "%%.") .. '[^"]*)"'
    local raw_body = body:match('"body"%s*:%s*"(.-[^\\])"') or ""
    raw_body = raw_body:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"')
    local fb_notes
    local fb_block = raw_body:match("<!%-%-himythos%-%->(.-)<!%-%-/himythos%-%->")
    if fb_block and fb_block:match("%S") then
        fb_notes = fb_block:match("^%s*(.-)%s*$")
    end
    return {
        version      = tag:match("v?(.*)"),
        download_url = body:match(asset_pat),
        notes        = fb_notes,
    }
end

-- ── Temp zip path ─────────────────────────────────────────────────────────────

local function tmp_zip_path()
    local candidates = {
        DataStorage:getSettingsDir() .. "/mythos_update.zip",
        "/tmp/mythos_update.zip",
        _plugin_dir .. "/mythos_update.zip",
    }
    for _, path in ipairs(candidates) do
        local fh = io.open(path, "wb")
        if fh then fh:close(); os.remove(path); return path end
    end
    return _plugin_dir .. "/mythos_update.zip"
end

-- ── Install ───────────────────────────────────────────────────────────────────

local function apply_update(download_url, new_version)
    local zip = tmp_zip_path()

    local progress = InfoMessage:new{
        text    = "Downloading Mythos v" .. new_version .. "…",
        timeout = 120,
    }
    UIManager:show(progress)

    UIManager:scheduleIn(0.3, function()
        local dl_ok, dl_err = http_download(download_url, zip)
        UIManager:close(progress)

        if not dl_ok then
            logger.err("Mythos/Updater: download failed:", dl_err)
            UIManager:show(InfoMessage:new{
                text    = "Download failed: " .. tostring(dl_err),
                timeout = 5,
            })
            return
        end

        logger.dbg("Mythos/Updater: unzipping", zip, "→", _parent_dir)
        local ret = os.execute(
            string.format("unzip -o -q %q -d %q", zip, _parent_dir)
        )
        os.remove(zip)

        if ret ~= 0 and ret ~= true then
            logger.err("Mythos/Updater: unzip failed, exit=", tostring(ret))
            UIManager:show(InfoMessage:new{
                text    = "Extraction failed. Please update manually.",
                timeout = 5,
            })
            return
        end

        logger.info("Mythos/Updater: update to", new_version, "installed")
        UIManager:show(ConfirmBox:new{
            text        = "Mythos v" .. new_version
                       .. " installed.\n\nRestart KOReader to apply the update?",
            ok_text     = "Restart now",
            cancel_text = "Later",
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Updater.checkForUpdates()
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local checking = InfoMessage:new{ text = "Checking for updates…", timeout = 15 }
        UIManager:show(checking)

        UIManager:scheduleIn(0.3, function()
            local body, fetch_err = http_get(API_URL)
            UIManager:close(checking)

            if not body then
                logger.err("Mythos/Updater: fetch failed:", fetch_err)
                UIManager:show(InfoMessage:new{
                    text    = "Could not reach GitHub: " .. tostring(fetch_err),
                    timeout = 4,
                })
                return
            end

            local release, parse_err = parse_release(body)
            if not release then
                logger.err("Mythos/Updater: parse failed:", parse_err)
                UIManager:show(InfoMessage:new{
                    text    = "Could not read release info.",
                    timeout = 4,
                })
                return
            end

            local current = current_version()
            logger.info("Mythos/Updater: current=", current, "latest=", release.version)

            if not version_gt(release.version, current) then
                UIManager:show(InfoMessage:new{
                    text    = "Mythos is up to date (v" .. current .. ").",
                    timeout = 3,
                })
                return
            end

            if not release.download_url then
                UIManager:show(InfoMessage:new{
                    text    = "Mythos v" .. release.version
                           .. " is available but has no download file yet.",
                    timeout = 5,
                })
                return
            end

            local header = "Mythos v" .. release.version .. " is available!\n"
                        .. "You have v" .. current .. "."
            local notes  = release.notes
                        and ("\n\nWhat's new:\n" .. release.notes)
                        or  ""

            UIManager:show(ConfirmBox:new{
                text        = header .. notes .. "\n\nDownload and install now?",
                ok_text     = "Install",
                cancel_text = "Cancel",
                ok_callback = function()
                    apply_update(release.download_url, release.version)
                end,
            })
        end)
    end)
end

return Updater
