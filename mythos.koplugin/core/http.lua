-- Thin HTTP/HTTPS client for Mythos extensions.
-- Returns body string on success, nil+code on failure.
local https   = require("ssl.https")
local http    = require("socket.http")
local ltn12   = require("ltn12")
local ok_json, JSON = pcall(require, "rapidjson")
if not ok_json then JSON = require("json") end

local UA = "Mozilla/5.0 (Linux; Android 9; KOReader) AppleWebKit/537.36"

local HttpClient = {}

local function do_request(url, headers, timeout)
    local sink = {}
    local req_h = {
        ["User-Agent"]      = UA,
        ["Accept"]          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ["Accept-Language"] = "en-US,en;q=0.5",
    }
    if headers then
        for k, v in pairs(headers) do req_h[k] = v end
    end
    local requester = url:match("^https") and https or http
    local ok, code, resp_h = requester.request {
        url     = url,
        sink    = ltn12.sink.table(sink),
        headers = req_h,
        timeout = timeout or 30,
    }
    if not ok then return nil, tostring(code) end
    if code ~= 200 then return nil, code end
    return table.concat(sink), code, resp_h
end

function HttpClient.get(url, headers, timeout)
    return do_request(url, headers, timeout)
end

function HttpClient.getJson(url, headers)
    local body, code = do_request(url, headers)
    if not body then return nil, code end
    local ok2, data = pcall(JSON.decode, body)
    if not ok2 then return nil, "json_parse_error" end
    return data
end

-- Download url to a local file path; returns true/false, code
function HttpClient.download(url, dest_path, timeout)
    local f = io.open(dest_path, "wb")
    if not f then return false, "open_error" end
    local requester = url:match("^https") and https or http
    local ok, code = requester.request {
        url     = url,
        sink    = ltn12.sink.file(f),
        timeout = timeout or 60,
    }
    -- ltn12.sink.file closes f automatically; calling f:close() again crashes
    local success = ok and (code == 200)
    if not success then os.remove(dest_path) end
    return success, code
end

return HttpClient
