-- EPUB 2.0 builder: cover image → synopsis → HTML ToC → chapters.
-- Pure-Lua ZIP writer (STORE, no external binary needed).
local DataStorage = require("datastorage")
local logger      = require("logger")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then lfs = require("lfs") end
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

-- ── Output path ───────────────────────────────────────────────────────────────

local function mythos_base_dir()
    local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
    if not home or home == "" then
        local full = DataStorage:getFullDataDir() or DataStorage:getDataDir()
        home = full:match("^(.*)/%.adds/") or full:match("^(.*)/koreader$") or full
    end
    return home .. "/Mythos"
end

-- ── Cover image fetch ─────────────────────────────────────────────────────────

local function fetch_cover(url)
    if not url or url == "" then return nil end
    local ok_h, https = pcall(require, "ssl.https")
    local ok_p, http  = pcall(require, "socket.http")
    if not ok_h and not ok_p then return nil end
    local ltn12 = require("ltn12")
    local sink  = {}
    local req   = (ok_h and url:match("^https")) and https or http
    if not req then return nil end
    local ok, code = req.request{
        url     = url,
        sink    = ltn12.sink.table(sink),
        headers = { ["User-Agent"] = "Mozilla/5.0 (Linux; Android 9; KOReader)" },
        timeout = 15,
    }
    if not ok or code ~= 200 then
        logger.warn("Mythos/Epub: cover fetch failed url=", url, "code=", tostring(code))
        return nil
    end
    local data = table.concat(sink)
    local ext  = (url:match("%.(%w+)%??[^%.]*$") or "jpg"):lower()
    if ext ~= "png" and ext ~= "webp" then ext = "jpg" end
    logger.dbg("Mythos/Epub: cover fetched bytes=", #data, "ext=", ext)
    return data, ext
end

-- ── CRC32 ─────────────────────────────────────────────────────────────────────

local crc_table
local function init_crc()
    crc_table = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if band(c, 1) == 1 then c = bit.bxor(0xEDB88320, rshift(c, 1))
            else c = rshift(c, 1) end
        end
        crc_table[i] = c
    end
end

local function crc32(data)
    if not crc_table then init_crc() end
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        crc = bit.bxor(crc_table[band(bit.bxor(crc, data:byte(i)), 0xFF)], rshift(crc, 8))
    end
    return band(bit.bxor(crc, 0xFFFFFFFF), 0xFFFFFFFF)
end

-- ── Binary helpers ────────────────────────────────────────────────────────────

local function le2(n) return string.char(band(n,0xFF), band(rshift(n,8),0xFF)) end
local function le4(n)
    n = band(n, 0xFFFFFFFF)
    return string.char(band(n,0xFF), band(rshift(n,8),0xFF),
                       band(rshift(n,16),0xFF), band(rshift(n,24),0xFF))
end

-- ── ZIP writer ────────────────────────────────────────────────────────────────

local function write_zip(f, entries)
    local cd, offset = {}, 0
    local MOD = le2(0) .. le2(0)
    for _, e in ipairs(entries) do
        local crc, size, nm = crc32(e.data), #e.data, e.name
        local nlen = le2(#nm)
        local lfh  = table.concat({
            "\x50\x4B\x03\x04", le2(20), le2(0), le2(0),
            MOD, le4(crc), le4(size), le4(size), nlen, le2(0), nm,
        })
        f:write(lfh); f:write(e.data)
        table.insert(cd, table.concat({
            "\x50\x4B\x01\x02", le2(20), le2(20), le2(0), le2(0),
            MOD, le4(crc), le4(size), le4(size),
            nlen, le2(0), le2(0), le2(0), le2(0), le4(0), le4(offset), nm,
        }))
        offset = offset + #lfh + size
    end
    local cd_start, cd_size = offset, 0
    for _, r in ipairs(cd) do f:write(r); cd_size = cd_size + #r end
    f:write(table.concat({
        "\x50\x4B\x05\x06", le2(0), le2(0),
        le2(#entries), le2(#entries), le4(cd_size), le4(cd_start), le2(0),
    }))
end

-- ── XML / HTML helpers ────────────────────────────────────────────────────────

local function xml_esc(s)
    return (s or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;")
end

local function chapter_id(i) return string.format("ch%04d", i) end

local XHTML_HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'
    .. '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" '
    .. '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n'
    .. '<html xmlns="http://www.w3.org/1999/xhtml">\n'

-- ── EPUB content builders ─────────────────────────────────────────────────────

local CONTAINER_XML = [[<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]]

local STYLESHEET = [[body{margin:5% 8%;font-family:serif;line-height:1.7}
h1{text-align:center;margin:1em 0 .5em}
h2{margin:1em 0 .3em}
p{margin:0;text-indent:1.5em}
p+p{margin-top:.3em}
ul{list-style:none;padding:0}
li{padding:.2em 0;border-bottom:1px solid #ccc}
li a{text-decoration:none}
.cover-wrap{text-align:center;margin:0;padding:0}
.cover-wrap img{max-width:100%;display:block;margin:auto}]]

local function make_opf(meta, chapters, cover_ext)
    local man, spine = {}, {}

    if cover_ext then
        local mime = cover_ext == "png" and "image/png" or "image/jpeg"
        table.insert(man, ('    <item id="cover-img" href="Images/cover.%s" media-type="%s"/>'):format(cover_ext, mime))
        table.insert(man, '    <item id="cover-page" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>')
        table.insert(spine, '    <itemref idref="cover-page" linear="yes"/>')
    end

    table.insert(man,   '    <item id="synopsis" href="Text/synopsis.xhtml" media-type="application/xhtml+xml"/>')
    table.insert(spine, '    <itemref idref="synopsis"/>')

    if #chapters > 1 then
        table.insert(man,   '    <item id="toc-page" href="Text/toc.xhtml" media-type="application/xhtml+xml"/>')
        table.insert(spine, '    <itemref idref="toc-page"/>')
    end

    for i = 1, #chapters do
        local id = chapter_id(i)
        table.insert(man,   ('    <item id="%s" href="Text/%s.xhtml" media-type="application/xhtml+xml"/>'):format(id, id))
        table.insert(spine, ('    <itemref idref="%s"/>'):format(id))
    end

    local series_meta = ""
    if meta.series then
        series_meta = ('    <meta name="calibre:series" content="%s"/>\n'
            .. '    <meta name="calibre:series_index" content="%s"/>'):format(
            xml_esc(meta.series), tostring(meta.series_index or 1))
    end
    local cover_meta = cover_ext and '\n    <meta name="cover" content="cover-img"/>' or ""

    return ([[<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>%s</dc:title>
    <dc:creator opf:role="aut">%s</dc:creator>
    <dc:identifier id="bid">mythos:%s</dc:identifier>
    <dc:language>%s</dc:language>
%s%s
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="css" href="Styles/style.css" media-type="text/css"/>
%s
  </manifest>
  <spine toc="ncx">
%s
  </spine>
</package>]]):format(
        xml_esc(meta.title), xml_esc(meta.author or ""),
        xml_esc(meta.title) .. tostring(os.time()),
        meta.language or "en",
        series_meta, cover_meta,
        table.concat(man, "\n"), table.concat(spine, "\n"))
end

local function make_ncx(meta, chapters, has_cover)
    local nav  = {}
    local play = 1
    if has_cover then
        table.insert(nav, ('    <navPoint id="cover" playOrder="%d"><navLabel><text>Cover</text></navLabel><content src="Text/cover.xhtml"/></navPoint>'):format(play))
        play = play + 1
    end
    table.insert(nav, ('    <navPoint id="synopsis" playOrder="%d"><navLabel><text>Synopsis</text></navLabel><content src="Text/synopsis.xhtml"/></navPoint>'):format(play))
    play = play + 1
    if #chapters > 1 then
        table.insert(nav, ('    <navPoint id="toc-page" playOrder="%d"><navLabel><text>Table of Contents</text></navLabel><content src="Text/toc.xhtml"/></navPoint>'):format(play))
        play = play + 1
    end
    for i, ch in ipairs(chapters) do
        table.insert(nav, ('    <navPoint id="n%d" playOrder="%d"><navLabel><text>%s</text></navLabel><content src="Text/%s.xhtml"/></navPoint>'):format(
            i, play, xml_esc(ch.title or ("Chapter " .. i)), chapter_id(i)))
        play = play + 1
    end
    return ([[<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="mythos:%s"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>%s</text></docTitle>
  <navMap>
%s
  </navMap>
</ncx>]]):format(xml_esc(meta.title), xml_esc(meta.title), table.concat(nav, "\n"))
end

local function make_cover_xhtml(cover_ext)
    return XHTML_HEAD .. ([[<head><title>Cover</title>
<style type="text/css">body{margin:0;padding:0}img{max-width:100%%;display:block;margin:auto}</style>
</head>
<body><div class="cover-wrap"><img src="../Images/cover.%s" alt="Cover"/></div></body>
</html>]]):format(cover_ext)
end

local function make_synopsis_xhtml(meta)
    local paras = ""
    local summary = (meta.summary or ""):match("^%s*(.-)%s*$")
    if summary ~= "" then
        -- Each double-newline or single newline becomes a paragraph
        for line in (summary .. "\n\n"):gmatch("(.-)\n%s*\n") do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then
                paras = paras .. "<p>" .. xml_esc(line) .. "</p>\n"
            end
        end
    end
    if paras == "" then paras = "<p>—</p>\n" end
    return XHTML_HEAD .. ([[<head><title>Synopsis</title>
<link rel="stylesheet" type="text/css" href="../Styles/style.css"/></head>
<body>
<h1>%s</h1>
<p><em>by %s</em></p>
<hr/>
%s</body>
</html>]]):format(xml_esc(meta.title), xml_esc(meta.author or "Unknown"), paras)
end

local function make_toc_xhtml(meta, chapters)
    local items = {}
    for i, ch in ipairs(chapters) do
        table.insert(items, ('  <li><a href="%s.xhtml">%s</a></li>'):format(
            chapter_id(i), xml_esc(ch.title or ("Chapter " .. i))))
    end
    return XHTML_HEAD .. ([[<head><title>Table of Contents</title>
<link rel="stylesheet" type="text/css" href="../Styles/style.css"/></head>
<body>
<h1>Table of Contents</h1>
<ul>
%s
</ul>
</body>
</html>]]):format(table.concat(items, "\n"))
end

-- Strip images, scripts, selects, all tag attributes from chapter HTML.
-- Uses a sentinel (ASCII \1) to make Lua patterns match across newlines.
-- \0 cannot appear inside Lua bracket classes, so we use \1 instead.
local SENT = "\1"
local function clean_html(body)
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    -- Replace newlines with sentinel so patterns cross line boundaries
    body = body:gsub("\n", SENT)
    for _, tag in ipairs({"script","style","select","noscript","iframe",
                          "button","aside","figure","picture","nav","form",
                          "header","footer"}) do
        body = body:gsub("<" .. tag .. "[^>]*>.-</" .. tag .. ">", "")
        body = body:gsub("<" .. tag .. "[^>]*/?>", "")
    end
    -- Strip leading h1/h2 — make_chapter_xhtml adds its own h1.
    -- Use repeated gsub to skip leading whitespace/sentinels without a bracket class.
    body = body:gsub("^[\1 \t\r]*<h[12][^>]*>.-</h[12]>", "")
    body = body:gsub(SENT, "\n")
    body = body:gsub("<img[^>]*/?>", "")
    body = body:gsub("<input[^>]*/?>", "")
    body = body:gsub("<source[^>]*/?>", "")
    body = body:gsub("<(%a[%w%-]*)%s[^>]*>", "<%1>")
    body = body:gsub("<br>",  "<br/>")
    body = body:gsub("<hr>",  "<hr/>")
    body = body:gsub("<p>%s*</p>", "")
    body = body:gsub("<div>%s*</div>", "")
    body = body:gsub("(\n%s*){3,}", "\n\n")
    return body
end

local function make_chapter_xhtml(title, body)
    body = clean_html(body)
    return XHTML_HEAD .. ([[<head><title>%s</title>
<link rel="stylesheet" type="text/css" href="../Styles/style.css"/></head>
<body>
<h1>%s</h1>
%s
</body>
</html>]]):format(xml_esc(title), xml_esc(title), body)
end

-- ── mkdir -p ──────────────────────────────────────────────────────────────────

local function mkdirp(path)
    local cur = path:match("^/") and "/" or ""
    for p in path:gmatch("[^/\\]+") do
        cur = cur .. p .. "/"
        if lfs.attributes(cur, "mode") ~= "directory" then lfs.mkdir(cur) end
    end
end

-- ── Public: build one EPUB ────────────────────────────────────────────────────
-- meta: {title, author, language, series, series_index, cover_url, summary}
-- chapters: [{title, content}]

local function build(meta, chapters, output_path)
    mkdirp(output_path:match("^(.*)[/\\][^/\\]+$") or ".")

    -- Fetch cover (optional)
    local cover_data, cover_ext
    if meta.cover_url and meta.cover_url ~= "" then
        cover_data, cover_ext = fetch_cover(meta.cover_url)
    end

    local entries = {}
    local function add(name, data) table.insert(entries, {name=name, data=data}) end

    add("mimetype",               "application/epub+zip")
    add("META-INF/container.xml", CONTAINER_XML)
    add("OEBPS/content.opf",      make_opf(meta, chapters, cover_ext))
    add("OEBPS/toc.ncx",          make_ncx(meta, chapters, cover_ext ~= nil))
    add("OEBPS/Styles/style.css", STYLESHEET)

    if cover_data then
        add("OEBPS/Images/cover." .. cover_ext, cover_data)
        add("OEBPS/Text/cover.xhtml",           make_cover_xhtml(cover_ext))
    end

    add("OEBPS/Text/synopsis.xhtml", make_synopsis_xhtml(meta))

    if #chapters > 1 then
        add("OEBPS/Text/toc.xhtml", make_toc_xhtml(meta, chapters))
    end

    for i, ch in ipairs(chapters) do
        add("OEBPS/Text/" .. chapter_id(i) .. ".xhtml",
            make_chapter_xhtml(ch.title or ("Chapter " .. i), ch.content or "<p></p>"))
    end

    local f = io.open(output_path, "wb")
    if not f then return false, "cannot_write: " .. output_path end
    write_zip(f, entries)
    f:close()
    logger.dbg("Mythos/Epub: wrote", output_path)
    return true
end

-- ── Public: export with 4 modes ───────────────────────────────────────────────
-- mode:     "all_in_one" | "per_chapter" | "every_n" | "range"
-- options:  {title, author, language, series, n, cover_url, summary, out_dir}
-- chapters: [{name, path, chapter_number}]
-- fetch_fn: function(path) -> HTML | nil
-- progress: function(done, total)

local function export(mode, options, chapters, fetch_fn, progress)
    local title     = options.title or "Novel"
    local safe      = title:gsub('[<>:"/\\|?*]', "_")
    local out_dir   = options.out_dir or (mythos_base_dir() .. "/" .. safe)
    logger.dbg("Mythos/Epub: export mode=", mode, "out_dir=", out_dir, "chapters=", #chapters)
    mkdirp(out_dir)

    local base_meta = {
        title     = title,
        author    = options.author,
        language  = options.language or "en",
        series    = options.series or title,
        cover_url = options.cover_url,
        summary   = options.summary,
    }

    local exported, errors = {}, {}
    local total = #chapters

    local function fetch_batch(batch)
        local ch_data = {}
        for i, ch in ipairs(batch) do
            if progress then progress(i, #batch) end
            local html = fetch_fn(ch.path)
            if html then
                table.insert(ch_data, {title = ch.name, content = html})
            else
                table.insert(errors, "fetch_failed:" .. tostring(ch.path))
            end
        end
        return ch_data
    end

    local function do_build(filename, vol_meta, ch_data)
        local path = out_dir .. "/" .. filename:gsub('[<>:"/\\|?*]', "_") .. ".epub"
        local ok, err = build(vol_meta, ch_data, path)
        if ok then table.insert(exported, path)
        else table.insert(errors, tostring(err)) end
    end

    if mode == "all_in_one" or mode == "range" then
        local ch_data = fetch_batch(chapters)
        do_build(options.custom_name or title, base_meta, ch_data)

    elseif mode == "per_chapter" then
        -- Cover + synopsis once; no ToC (single chapter per file)
        for idx, ch in ipairs(chapters) do
            if progress then progress(idx, total) end
            local html = fetch_fn(ch.path)
            if html then
                local cnum = ch.chapter_number or idx
                do_build(string.format("%s - %04d", title, cnum), {
                    title        = ch.name,
                    author       = options.author,
                    language     = options.language or "en",
                    series       = base_meta.series,
                    series_index = cnum,
                    cover_url    = options.cover_url,
                    summary      = options.summary,
                }, {{title=ch.name, content=html}})
            else
                table.insert(errors, "fetch_failed:" .. tostring(ch.path))
            end
        end

    elseif mode == "every_n" then
        local n, vol = math.max(1, options.n or 50), 0
        for i = 1, total, n do
            vol = vol + 1
            local batch = {}
            for j = i, math.min(i+n-1, total) do table.insert(batch, chapters[j]) end
            local first_n = batch[1].chapter_number or i
            local last_n  = batch[#batch].chapter_number or (i+n-1)
            do_build(
                string.format("%s Vol.%d (Ch.%d-%d)", title, vol, first_n, last_n),
                {
                    title        = string.format("%s Vol.%d", title, vol),
                    author       = options.author,
                    language     = options.language or "en",
                    series       = base_meta.series,
                    series_index = vol,
                    cover_url    = options.cover_url,
                    summary      = options.summary,
                },
                fetch_batch(batch))
        end
    end

    return { exported = exported, errors = errors }
end

return { build = build, export = export, fetch_cover = fetch_cover }
