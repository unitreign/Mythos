-- Export dialog: choose mode, trigger EPUB build.
local UIManager   = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr  = require("ui/network/manager")
local DataStorage = require("datastorage")
local logger      = require("logger")
local Epub        = require("core.epub")
local DB          = require("core.db")
local P           = require("ui.panel")

local Export = {}

local function close_all()
    if _G.mythos_close_all then _G.mythos_close_all() end
end

local function mythos_base_dir()
    local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
    if not home or home == "" then
        local full = DataStorage:getFullDataDir() or DataStorage:getDataDir()
        home = full:match("^(.*)/%.adds/") or full:match("^(.*)/koreader$") or full
    end
    local Settings = require("settings")
    if Settings:get("export_location_flat") then return home end
    return home .. "/Mythos"
end

local MODES = {
    { id = "all_in_one",  label = "All in One EPUB",         desc = "Selected chapters → single file" },
    { id = "per_chapter", label = "One EPUB per Chapter",    desc = "Each chapter → separate file"    },
    { id = "every_n",     label = "Bundle every N Chapters", desc = "Group into volumes"               },
    { id = "range",       label = "Selected Chapters Only",  desc = "Custom selection → single file"  },
}

local _ctx   = nil
local _mode  = "all_in_one"
local _n     = 50
local _panel = nil

local function rebuild(ctx)
    Export.show(ctx)
end

-- ── Run ───────────────────────────────────────────────────────────────────────

function Export.run(ctx)
    -- Close the export options panel → detail panel becomes visible
    Export.close()

    local novel   = ctx.novel
    local title   = novel.name or novel.title or "Novel"
    local out_dir = mythos_base_dir() .. "/" .. title:gsub('[<>:"/\\|?*]', "_")
    logger.dbg("Mythos/Export: title=", title, "out_dir=", out_dir)

    -- Auto-track the novel when an export is started
    DB.track({
        title          = title,
        source_id      = ctx.source_id,
        path           = novel.path or "",
        cover          = novel.cover,
        author         = novel.author,
        status         = novel.status,
        total_chapters = ctx.total_chapters or novel.total_chapters or #ctx.chapters,
    })

    -- Show indicator; scheduleIn yields so UIManager paints it before the blocking work
    local progress_msg = InfoMessage:new{ text = "Starting export…" }
    UIManager:show(progress_msg)

    UIManager:scheduleIn(0.1, function()
        NetworkMgr:runWhenConnected(function()
            local options = {
                title     = title,
                author    = novel.author,
                language  = "en",
                series    = title,
                n         = _n,
                out_dir   = out_dir,
                cover_url = novel.cover,
                summary   = novel.summary,
            }

            local last_repaint = os.time()
            local results = Epub.export(
                _mode, options, ctx.chapters, ctx.fetch_fn,
                function(done, total)
                    if done % 10 == 0 or done == total then
                        if progress_msg then UIManager:close(progress_msg) end
                        progress_msg = InfoMessage:new{
                            text    = string.format("Exporting %d / %d…", done, total),
                            timeout = 120,
                        }
                        UIManager:show(progress_msg)
                        -- Force screen repaint at most every 10 s (eink refresh is slow)
                        local now = os.time()
                        if now - last_repaint >= 10 then
                            last_repaint = now
                            pcall(function() UIManager:forceRePaint() end)
                        end
                    end
                end)

            if progress_msg then UIManager:close(progress_msg); progress_msg = nil end

            -- Record exported chapters in the DB
            if #results.exported > 0 then
                local ch_paths = {}
                for _, ch in ipairs(ctx.chapters) do
                    ch_paths[#ch_paths + 1] = ch.path or ch.sourceUrl or ""
                end
                for _, epub_path in ipairs(results.exported) do
                    DB.recordExport(ctx.source_id, novel.path or "", ch_paths, epub_path)
                end
            end

            local n_ok  = #results.exported
            local n_err = #results.errors
            UIManager:show(InfoMessage:new{
                text = string.format(
                    "Export done.\n%d file%s saved to\n%s\n%s",
                    n_ok, n_ok == 1 and "" or "s", out_dir,
                    n_err > 0 and (tostring(n_err) .. " chapter(s) failed.") or ""),
                timeout = 6,
            })
        end)
    end)
end

-- ── Show ──────────────────────────────────────────────────────────────────────

function Export.show(ctx)
    local MythosUI = require("ui.main_widget")
    _ctx           = ctx
    local ch_cnt   = #(ctx.chapters or {})
    local Settings = require("settings")
    local flat     = Settings:get("export_location_flat")

    local rows = {}

    table.insert(rows, P.makeRow(
        string.format("%d chapter%s selected", ch_cnt, ch_cnt == 1 and "" or "s"),
        { dim = true, callback = function() end }
    ))
    table.insert(rows, P.hairline())

    -- Mode selection
    for _, m in ipairs(MODES) do
        local mid = m.id
        table.insert(rows, P.makeRow(
            (mid == _mode and "> " or "  ") .. m.label, {
                mandatory = m.desc,
                bold      = mid == _mode,
                callback  = function() _mode = mid; rebuild(ctx) end,
            }
        ))
    end

    -- N picker (only when every_n active)
    if _mode == "every_n" then
        table.insert(rows, P.makeRow(
            string.format("Chapters per volume: %d  (tap to change)", _n), {
                callback = function()
                    local dlg
                    dlg = InputDialog:new{
                        title      = "Chapters per volume",
                        input_type = "number",
                        input_hint = tostring(_n),
                        buttons    = {{
                            {
                                text             = "OK",
                                is_enter_default = true,
                                callback         = function()
                                    local v = tonumber(dlg:getInputText())
                                    if v and v > 0 then _n = math.floor(v) end
                                    UIManager:close(dlg)
                                    rebuild(ctx)
                                end,
                            },
                            { text = "Cancel", callback = function() UIManager:close(dlg) end },
                        }},
                    }
                    UIManager:show(dlg)
                end,
            }
        ))
    end

    table.insert(rows, P.hairline())

    -- Location toggle
    table.insert(rows, P.makeRow(
        (not flat and "> " or "  ") .. "Home/Mythos/Series/Book.epub", {
            mandatory = "organised",
            bold      = not flat,
            callback  = function()
                Settings:set("export_location_flat", false)
                rebuild(ctx)
            end,
        }
    ))
    table.insert(rows, P.makeRow(
        (flat and "> " or "  ") .. "Home/Series/Book.epub", {
            mandatory = "flat",
            bold      = flat == true,
            callback  = function()
                Settings:set("export_location_flat", true)
                rebuild(ctx)
            end,
        }
    ))

    local out_dir = mythos_base_dir() .. "/"
        .. (ctx.novel.name or ctx.novel.title or "Novel"):gsub('[<>:"/\\|?*]', "_")
    table.insert(rows, P.makeRow("Output: " .. out_dir, { dim = true, callback = function() end }))

    table.insert(rows, P.hairline())
    table.insert(rows, P.makeRow("Start Export", {
        bold = true,
        callback = function() Export.run(ctx) end,
    }))
    table.insert(rows, P.makeRow("Cancel", {
        callback = function() Export.close() end,
    }))

    local function on_back()
        Export.close()
    end

    -- Close old panel before showing the new one
    if _panel then UIManager:close(_panel) end
    _panel = P.showSubPanel("Export Options", rows, on_back, close_all)
    MythosUI.setExport(_panel)
end

function Export.close()
    if _panel then
        UIManager:close(_panel)
        _panel = nil
    end
    local ok, MythosUI = pcall(require, "ui.main_widget")
    if ok then MythosUI.clearExport() end
end

return Export
