-- Shared Mythos UI: FullScreenPanel base + row/header/tab helpers.
-- All screens are built as ONE FullScreenPanel widget shown via UIManager,
-- so tab bar and content share a single widget tree with no z-order issues.

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")

local Screen = Device.screen

local P = {}

-- ── Dimensions ────────────────────────────────────────────────────────────────

P.W         = Screen:getWidth()
P.H         = Screen:getHeight()
P.TITLE_H   = Screen:scaleBySize(44)
P.TAB_H     = Screen:scaleBySize(52)
P.ROW_H     = Screen:scaleBySize(48)
P.MARGIN    = Screen:scaleBySize(16)
P.HAIRLINE  = math.max(1, Screen:scaleBySize(1))

-- Content height available inside a tab screen (between title bar and tab bar)
P.CONTENT_H = P.H - P.TITLE_H - 2 * P.HAIRLINE - P.TAB_H
-- Content height for sub-screens (no tab bar)
P.SUB_H     = P.H - P.TITLE_H - P.HAIRLINE

-- How many rows fit in each context
P.MAX_ROWS     = math.floor(P.CONTENT_H / P.ROW_H)
P.MAX_SUB_ROWS = math.floor(P.SUB_H     / P.ROW_H)

-- Nav bar (< > prev/next row that sits between content and the tab bar)
P.NAV_ROW_H     = Screen:scaleBySize(40)
-- Content height when nav bar is visible (reserves HAIRLINE + NAV_ROW_H)
P.CONTENT_H_NAV = P.CONTENT_H - P.NAV_ROW_H - P.HAIRLINE
P.MAX_ROWS_NAV  = math.floor(P.CONTENT_H_NAV / P.ROW_H)

local TABS = {
    { id = "library", label = "Library" },
    { id = "browse",  label = "Browse"  },
    { id = "sources", label = "Sources" },
}

-- ── Gesture wrapper ───────────────────────────────────────────────────────────

function P.wrapTappable(widget, callback, hold_callback)
    if not callback and not hold_callback then return widget end
    local wrapper = InputContainer:new{ dimen = widget:getSize(), widget }
    wrapper.ges_events = {}
    if callback then
        wrapper.ges_events.Tap = {
            GestureRange:new{ ges = "tap", range = wrapper.dimen }
        }
        wrapper.onTap = function() callback(); return true end
    end
    if hold_callback then
        wrapper.ges_events.Hold = {
            GestureRange:new{ ges = "hold", range = wrapper.dimen }
        }
        wrapper.onHold = function() hold_callback(); return true end
    end
    return wrapper
end

-- ── Primitives ────────────────────────────────────────────────────────────────

function P.hairline()
    return LineWidget:new{
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        dimen = Geom:new{ w = P.W, h = P.HAIRLINE },
    }
end

function P.spacer(h)
    return VerticalSpan:new{ width = h }
end

-- ── Row widget ────────────────────────────────────────────────────────────────
-- opts: { bold, dim, mandatory, callback, hold_callback }

function P.makeRow(text, opts)
    opts = opts or {}
    local face       = Font:getFace("cfont", 18)
    local small_face = Font:getFace("cfont", 14)
    local fgcolor    = opts.dim and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK

    local label = TextWidget:new{
        text    = text or "",
        face    = face,
        bold    = opts.bold,
        fgcolor = fgcolor,
    }

    local inner
    if opts.mandatory and opts.mandatory ~= "" then
        local hint = TextWidget:new{
            text    = tostring(opts.mandatory),
            face    = small_face,
            fgcolor = Blitbuffer.COLOR_GRAY,
        }
        inner = HorizontalGroup:new{
            label,
            HorizontalSpan:new{ width = P.MARGIN },
            hint,
        }
    else
        inner = label
    end

    -- Vertical centering
    local inner_h   = inner:getSize().h
    local v_top     = math.floor((P.ROW_H - inner_h) / 2)
    local v_bottom  = P.ROW_H - inner_h - v_top

    local frame = FrameContainer:new{
        bordersize     = 0,
        padding_top    = v_top,
        padding_bottom = v_bottom,
        padding_left   = P.MARGIN,
        padding_right  = 0,
        width          = P.W,
        background     = Blitbuffer.COLOR_WHITE,
        inner,
    }
    return P.wrapTappable(frame, opts.callback, opts.hold_callback)
end

-- ── Multi-line text block (for synopsis, descriptions) ────────────────────────

function P.makeTextBlock(text, max_chars)
    max_chars = max_chars or 400
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local face      = Font:getFace("cfont", 16)
    local inner_w   = P.W - 2 * P.MARGIN
    local display   = (text or ""):match("^%s*(.-)%s*$")
    if #display > max_chars then
        display = display:sub(1, max_chars) .. "…"
    end
    local tw = TextBoxWidget:new{
        text      = display,
        face      = face,
        width     = inner_w,
        alignment = "left",
    }
    return FrameContainer:new{
        bordersize     = 0,
        padding_left   = P.MARGIN,
        padding_right  = P.MARGIN,
        padding_top    = Screen:scaleBySize(6),
        padding_bottom = Screen:scaleBySize(6),
        background     = Blitbuffer.COLOR_WHITE,
        tw,
    }
end

-- ── Image block (for book covers) ─────────────────────────────────────────────
-- bb must already be scaled to the desired display size by the caller.

function P.makeImageRow(bb)
    if not bb then return nil end
    local ImageWidget = require("ui/widget/imagewidget")
    local img = ImageWidget:new{
        image  = bb,
        width  = bb:getWidth(),
        height = bb:getHeight(),
    }
    return FrameContainer:new{
        bordersize     = 0,
        padding_left   = P.MARGIN,
        padding_right  = P.MARGIN,
        padding_top    = Screen:scaleBySize(8),
        padding_bottom = Screen:scaleBySize(4),
        background     = Blitbuffer.COLOR_WHITE,
        img,
    }
end

-- ── Title bar ─────────────────────────────────────────────────────────────────
-- on_back: left arrow callback (nil = no arrow); on_close: ✕ callback

function P.makeTitleBar(title, on_back, on_close)
    local H     = P.TITLE_H
    local W     = P.W
    local face  = Font:getFace("cfont", 18)
    local bface = Font:getFace("cfont", 22)

    local BTN_W = Screen:scaleBySize(48)
    local left_w  = on_back  and BTN_W or 0
    local right_w = on_close and BTN_W or 0
    local mid_w   = W - left_w - right_w

    local function btnFrame(text_str, cb)
        local btn = TextWidget:new{ text = text_str, face = bface }
        local f = FrameContainer:new{
            bordersize = 0, padding = 0,
            width = BTN_W, height = H,
            CenterContainer:new{ dimen = Geom:new{ w = BTN_W, h = H }, btn },
        }
        return P.wrapTappable(f, cb)
    end

    local title_widget = TextWidget:new{ text = title or "", face = face, bold = true }
    local title_frame  = FrameContainer:new{
        bordersize = 0, padding = 0,
        width = mid_w, height = H,
        CenterContainer:new{ dimen = Geom:new{ w = mid_w, h = H }, title_widget },
    }

    local children = {}
    if on_back  then table.insert(children, btnFrame("←", on_back))  end
    table.insert(children, title_frame)
    if on_close then table.insert(children, btnFrame("✕", on_close)) end

    return HorizontalGroup:new(children)
end

-- ── Tab bar (main navigation: Library / Browse / Sources) ────────────────────

function P.makeTabBar(active_id)
    local W      = P.W
    local H      = P.TAB_H
    local seg_w  = math.floor(W / #TABS)
    local cells  = {}

    for i, tab in ipairs(TABS) do
        local t        = tab
        local is_active = t.id == active_id
        local cell_w   = (i == #TABS) and (W - seg_w * (#TABS - 1)) or seg_w
        local face     = Font:getFace("cfont", is_active and 16 or 15)

        local ind_h = Screen:scaleBySize(3)
        local indicator = FrameContainer:new{
            bordersize = 0, padding = 0,
            width = cell_w, height = ind_h,
            background = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
            HorizontalSpan:new{ width = cell_w },
        }
        local lbl = TextWidget:new{ text = t.label, face = face, bold = is_active }
        local cell_body = VerticalGroup:new{
            align = "center",
            indicator,
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            lbl,
        }
        local cell_frame = FrameContainer:new{
            bordersize = 0, padding = 0,
            width = cell_w, height = H,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = H }, cell_body },
        }

        if is_active then
            table.insert(cells, cell_frame)
        else
            table.insert(cells, P.wrapTappable(cell_frame, function()
                require("ui.main_widget").show(t.id)
            end))
        end
    end

    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{ w = W, h = P.HAIRLINE },
        },
        HorizontalGroup:new(cells),
    }
end

-- ── Custom tab bar (for in-screen 2-tab layouts like Details / Chapters) ─────

function P.makeCustomTabBar(tabs, active_id, switch_fn)
    local W     = P.W
    local H     = P.TAB_H
    local seg_w = math.floor(W / #tabs)
    local cells = {}

    for i, tab in ipairs(tabs) do
        local t        = tab
        local is_active = t.id == active_id
        local cell_w   = (i == #tabs) and (W - seg_w * (#tabs - 1)) or seg_w
        local face     = Font:getFace("cfont", is_active and 16 or 15)

        local ind_h = Screen:scaleBySize(3)
        local indicator = FrameContainer:new{
            bordersize = 0, padding = 0,
            width = cell_w, height = ind_h,
            background = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
            HorizontalSpan:new{ width = cell_w },
        }
        local lbl = TextWidget:new{ text = t.label, face = face, bold = is_active }
        local cell_body = VerticalGroup:new{
            align = "center",
            indicator,
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            lbl,
        }
        local cell_frame = FrameContainer:new{
            bordersize = 0, padding = 0,
            width = cell_w, height = H,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = H }, cell_body },
        }

        if is_active then
            table.insert(cells, cell_frame)
        else
            table.insert(cells, P.wrapTappable(cell_frame, function()
                switch_fn(t.id)
            end))
        end
    end

    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{ w = W, h = P.HAIRLINE },
        },
        HorizontalGroup:new(cells),
    }
end

-- ── Nav bar (< > row above the tab bar for paginated screens) ────────────────
-- nav = { page, max_pages (nil = unknown), on_prev (nil = disabled), on_next (nil = disabled) }
-- Height of the emitted widget = HAIRLINE + NAV_ROW_H.

function P.makeNavBar(nav)
    local W = P.W
    local H = P.NAV_ROW_H

    -- Shared helper: button frame of explicit width/height, optionally tappable
    local function cell(w, lbl_str, face, cb)
        local color = cb and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY
        local lbl   = TextWidget:new{ text = lbl_str, face = face, fgcolor = color }
        local f     = FrameContainer:new{
            bordersize = 0, padding = 0, width = w, height = H,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = w, h = H }, lbl },
        }
        return cb and P.wrapTappable(f, cb) or f
    end

    local row

    if nav.max_pages then
        -- Extended layout (known page count): «  ‹N  ‹   N/M   ›  N›  »
        local ff_w   = Screen:scaleBySize(36)   -- « and »
        local jmp_w  = Screen:scaleBySize(46)   -- ‹N and N›
        local nav_w  = Screen:scaleBySize(44)   -- ‹ and ›
        local mid_w  = W - 2 * (ff_w + jmp_w + nav_w)

        local ff_face  = Font:getFace("cfont", 17)
        local jmp_face = Font:getFace("cfont", 15)
        local arr_face = Font:getFace("cfont", 22)
        local lbl_face = Font:getFace("cfont", 15)

        -- Jump-to-page dialog (shared by ‹N and N›)
        local function open_jump()
            local InputDialog = require("ui/widget/inputdialog")
            local dlg
            dlg = InputDialog:new{
                title   = "Go to page (1 – " .. tostring(nav.max_pages) .. ")",
                input_type = "number",
                buttons = {{
                    { text = "Go", is_enter_default = true, callback = function()
                        local n = tonumber(dlg:getInputText())
                        UIManager:close(dlg)
                        if n then nav.on_jump(n) end
                    end },
                    { text = "Cancel", callback = function() UIManager:close(dlg) end },
                }},
            }
            UIManager:show(dlg)
        end

        local jmp_cb = nav.on_jump and open_jump or nil

        local page_str = tostring(nav.page) .. " / " .. tostring(nav.max_pages)
        local mid_lbl  = TextWidget:new{ text = page_str, face = lbl_face, fgcolor = Blitbuffer.COLOR_GRAY }
        local mid = FrameContainer:new{
            bordersize = 0, padding = 0, width = mid_w, height = H,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = mid_w, h = H }, mid_lbl },
        }

        row = HorizontalGroup:new{
            cell(ff_w,  "«",  ff_face,  nav.on_first),
            cell(jmp_w, "‹N", jmp_face, jmp_cb),
            cell(nav_w, "‹",  arr_face, nav.on_prev),
            mid,
            cell(nav_w, "›",  arr_face, nav.on_next),
            cell(jmp_w, "N›", jmp_face, jmp_cb),
            cell(ff_w,  "»",  ff_face,  nav.on_last),
        }
    else
        -- Simple layout (unknown total, e.g., source browse): ‹  p.N  ›
        local btn_w = Screen:scaleBySize(72)
        local mid_w = W - 2 * btn_w
        local arr_face = Font:getFace("cfont", 24)
        local lbl_face = Font:getFace("cfont", 15)

        local page_str = "p." .. tostring(nav.page)
        local mid_lbl  = TextWidget:new{ text = page_str, face = lbl_face, fgcolor = Blitbuffer.COLOR_GRAY }
        local mid = FrameContainer:new{
            bordersize = 0, padding = 0, width = mid_w, height = H,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = mid_w, h = H }, mid_lbl },
        }

        row = HorizontalGroup:new{
            cell(btn_w, "‹", arr_face, nav.on_prev),
            mid,
            cell(btn_w, "›", arr_face, nav.on_next),
        }
    end

    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{ w = W, h = P.HAIRLINE },
        },
        row,
    }
end

-- ── FullScreenPanel ───────────────────────────────────────────────────────────

local FullScreenPanel = InputContainer:extend{
    body           = nil,
    close_callback = nil,
    partial        = false,
}

function FullScreenPanel:init()
    local W, H = P.W, P.H
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.covers_fullscreen = true
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0, padding = 0,
        width = W, height = H,
        self.body,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
end

function FullScreenPanel:onShow()
    UIManager:setDirty(self, self.partial and "partial" or "full")
end

function FullScreenPanel:onCloseWidget()
    UIManager:setDirty(nil, self.partial and "partial" or "full")
end

function FullScreenPanel:onClose()
    UIManager:close(self)
    if self.close_callback then self.close_callback() end
    return true
end

P.FullScreenPanel = FullScreenPanel

-- ── Content frame ─────────────────────────────────────────────────────────────
-- Returns a VerticalGroup that reports exactly `height` pixels tall by adding
-- a filler spacer. This ensures the tab bar always lands at the correct y.

function P.contentFrame(rows, height)
    local used = 0
    for _, r in ipairs(rows) do
        local s = r:getSize()
        used = used + (s.h or 0)
    end
    local fill = math.max(0, height - used)
    local children = {}
    for _, r in ipairs(rows) do table.insert(children, r) end
    if fill > 0 then
        table.insert(children, VerticalSpan:new{ width = fill })
    end
    return VerticalGroup:new{ align = "left", table.unpack(children) }
end

-- ── Panel builders ────────────────────────────────────────────────────────────

-- Build and show a main tab screen (Library / Browse / Sources).
-- nav (optional) = { page, max_pages, on_prev, on_next } — shows nav bar above tab bar.
function P.showTabPanel(active_id, rows, title, close_fn, nav)
    local content_h = nav and P.CONTENT_H_NAV or P.CONTENT_H
    local body = VerticalGroup:new{
        align = "left",
        P.makeTitleBar(title, nil, close_fn),
        P.hairline(),
        P.contentFrame(rows, content_h),
        nav and P.makeNavBar(nav) or P.spacer(0),
        P.makeTabBar(active_id),
    }
    local panel = FullScreenPanel:new{ body = body, close_callback = close_fn }
    UIManager:show(panel)
    return panel
end

-- Build and show a sub-screen (export options, source settings).
-- No X button — sub-screens use ← back only; X lives on main tab screens.
function P.showSubPanel(title, rows, on_back, close_fn)
    local body = VerticalGroup:new{
        align = "left",
        P.makeTitleBar(title, on_back, nil),
        P.hairline(),
        P.contentFrame(rows, P.SUB_H),
    }
    local panel = FullScreenPanel:new{ body = body, close_callback = close_fn }
    UIManager:show(panel)
    return panel
end

-- Build and show a screen with a custom 2-tab bar (e.g. Details / Chapters).
-- No X button — uses ← back only; X lives on main tab screens.
-- nav (optional) = { page, max_pages, on_prev, on_next, on_first, on_last, on_jump }
-- partial (optional) = true to use partial e-ink refresh instead of full.
function P.showCustomTabPanel(tabs, active_id, switch_fn, rows, title, on_back, close_fn, nav, partial)
    local content_h = nav and P.CONTENT_H_NAV or P.CONTENT_H
    local body = VerticalGroup:new{
        align = "left",
        P.makeTitleBar(title, on_back, nil),
        P.hairline(),
        P.contentFrame(rows, content_h),
        nav and P.makeNavBar(nav) or P.spacer(0),
        P.makeCustomTabBar(tabs, active_id, switch_fn),
    }
    local panel = FullScreenPanel:new{ body = body, close_callback = close_fn, partial = partial or false }
    UIManager:show(panel)
    return panel
end

return P
