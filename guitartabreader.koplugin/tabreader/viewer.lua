--[[--
The tab view: a full-screen, paged view in the style of Ultimate Guitar's
PDFs (title, artist, details, chord diagrams, then the song in a monospaced
font with bold chords). Tap right or swipe left for the next page, tap left
or swipe right for the previous one; page keys work too. Tapping a chord in
the song shows its diagram. The menu (☰) has font size, tab size, transpose,
chord diagrams and automatic page turning.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local Layout = require("tabreader/layout")
local Chords = require("tabreader/chords")
local ChordDiagram = require("tabreader/chorddiagram")
local _ = require("tabreader/i18n")
local T = require("ffi/util").template

local MONO = "droid/DroidSansMono.ttf"
local MIN_SIZE, MAX_SIZE = 8, 40

local Viewer = InputContainer:extend{
    model = nil,       -- parsed tab (Parser.parse)
    font_size = 16,
    page = 1,
    own_size = false,  -- true: this tab has its own font size (else it follows the default)
    default_size = nil, -- the default font size, for "Reset to default"
    tab_fit = "shrink", -- tab size: "fit" (larger or smaller to the width), "shrink" (smaller if needed), "off"
    transpose = 0,     -- semitones
    show_diagrams = true, -- chord diagrams on the first page
    next_title = nil,  -- in a setlist: title of the next song
    on_next = nil,     -- in a setlist: function() opens the next song
    on_close = nil,    -- function(state) with { page, font_size (nil = default), transpose }
    on_set_default = nil, -- function(size): make this size the default
    on_tab_fit_changed = nil, -- function(mode)
    on_diagrams_changed = nil, -- function(on)
}

local FIT_MODES = { "shrink", "fit", "off" } -- order of the menu button
local FIT_NAMES = { fit = _("fit to width"), shrink = _("smaller if needed"), off = _("same as text") }

local function monoFace(size) return Font:getFace(MONO, size) end

-- Pixel width of one character of the monospaced font at a size.
local char_width_cache, line_height_cache = {}, {}
local function charWidth(size)
    if not char_width_cache[size] then
        local sample = string.rep("0", 20)
        char_width_cache[size] = RenderText:sizeUtf8Text(0, Screen:getWidth() * 4, monoFace(size), sample).x / 20
    end
    return char_width_cache[size]
end

local function lineHeight(size)
    if not line_height_cache[size] then
        local w = TextWidget:new{ text = "Mg|", face = monoFace(size) }
        line_height_cache[size] = w:getSize().h
        w:free()
    end
    return line_height_cache[size]
end

function Viewer:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.margin = Size.padding.large
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        title = self.model.meta.title or "",
        fullscreen = true,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self.footer_height = math.floor(lineHeight(14) * 1.4)
    self.content_height = self.dimen.h - self.title_bar:getHeight() - self.footer_height - self.margin
    self.content_width = self.dimen.w - 2 * self.margin

    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = {
            NextPage = { { Device.input.group.PgFwd } },
            PrevPage = { { Device.input.group.PgBack } },
            Close = { { Device.input.group.Back } },
        }
    end
    self:relayout()
end

--- The header on the first page, like the UG PDF: title, artist (bold), details.
function Viewer:buildHeader()
    local meta = self.display.meta
    local group = VerticalGroup:new{ align = "left" }
    local width = self.content_width
    local function add(widget) table.insert(group, widget) end
    add(TextBoxWidget:new{ text = meta.title or "", face = Font:getFace("infofont", 22), width = width })
    if meta.artist then
        add(TextBoxWidget:new{ text = meta.artist, face = Font:getFace("infofont", 22), bold = true, width = width })
    end
    local details = {}
    if meta.difficulty then table.insert(details, T(_("Difficulty: %1"), meta.difficulty)) end
    if meta.tuning then table.insert(details, T(_("Tuning: %1"), meta.tuning)) end
    if meta.capo and meta.capo ~= "0" and meta.capo ~= "" then table.insert(details, T(_("Capo: %1"), meta.capo)) end
    if meta.key then table.insert(details, T(_("Key: %1"), meta.key)) end
    if #details > 0 then
        add(VerticalSpan:new{ width = Size.padding.default })
        for _i, line in ipairs(details) do
            add(TextWidget:new{ text = line, face = Font:getFace("smallinfofont", 15), max_width = width })
        end
    end
    add(VerticalSpan:new{ width = Size.padding.default })
    add(LineWidget:new{ background = Blitbuffer.COLOR_GRAY, dimen = Geom:new{ w = width, h = Size.line.thin } })
    add(VerticalSpan:new{ width = Size.padding.large })
    if self.show_diagrams then
        local rows = self:diagramRows(width)
        if #rows > 0 then
            for _i, row in ipairs(rows) do add(row) end
            add(VerticalSpan:new{ width = Size.padding.default })
            add(LineWidget:new{ background = Blitbuffer.COLOR_GRAY, dimen = Geom:new{ w = width, h = Size.line.thin } })
            add(VerticalSpan:new{ width = Size.padding.large })
        end
    end
    return group
end

--- Shape for a chord of this song: from Ultimate Guitar if there is one (and the
-- song is not transposed), else from the built-in table.
function Viewer:shapeFor(name)
    local ug = self.transpose == 0 and self.model.chords and self.model.chords[name]
    if ug and type(ug.frets) == "table" then
        local frets = {}
        local base = tonumber(ug.base) or 0
        local high = 0
        for i, f in ipairs(ug.frets) do frets[i] = f; high = math.max(high, f) end
        -- shapes given relative to a start fret (only small numbers): make them absolute
        if base > 1 and high <= 4 then
            for i, f in ipairs(frets) do if f > 0 then frets[i] = f + base - 1 end end
        end
        return Chords.normalize({ frets = frets, barres = ug.barres })
    end
    return Chords.shape(name)
end

--- Rows of chord diagrams for the chords used in the song.
function Viewer:diagramRows(width)
    local names = Chords.used(self.display)
    if #names == 0 then return {} end
    local gap = Size.padding.large
    local dw = math.max(Screen:scaleBySize(46), math.min(Screen:scaleBySize(70), math.floor(width / 8)))
    local per_row = math.max(1, math.floor((width + gap) / (dw + gap)))
    local rows, row = {}, nil
    for i, name in ipairs(names) do
        if (i - 1) % per_row == 0 then
            row = HorizontalGroup:new{ align = "top" }
            rows[#rows + 1] = row
        else
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        table.insert(row, ChordDiagram:new{ name = name, shape = self:shapeFor(name), width = dw })
    end
    return rows
end

--- The song as shown: chord lines transposed if wanted.
function Viewer:buildDisplay()
    if self.transpose == 0 then return self.model end
    local m = self.model
    local flats = Chords.prefersFlats(Chords.used(m), m.meta.key)
    local meta = {}
    for k, v in pairs(m.meta) do meta[k] = v end
    if meta.key then meta.key = Chords.transpose(meta.key, self.transpose, flats) end
    if meta.chord_names then
        local names = {}
        for i, n in ipairs(meta.chord_names) do names[i] = Chords.transpose(n, self.transpose, flats) end
        meta.chord_names = names
    end
    local blocks = {}
    for i, b in ipairs(m.blocks) do
        if b.lines then
            local nb = {}
            for k, v in pairs(b) do nb[k] = v end
            nb.lines = {}
            for j, line in ipairs(b.lines) do
                if line.chord then
                    nb.lines[j] = { text = Chords.transposeLine(line.text, self.transpose, flats), chord = true }
                else
                    nb.lines[j] = line
                end
            end
            blocks[i] = nb
        else
            blocks[i] = b
        end
    end
    return { meta = meta, blocks = blocks, chords = m.chords }
end

--- Compute the pages for the current font size.
--- Lay the song out again and show it.
-- @param ratio optional: position in the song (0..1) to stay at
function Viewer:relayout(ratio)
    self.display = self:buildDisplay()
    if self.header then self.header:free() end
    self.header = self:buildHeader()
    local pages, tab_size = Layout.paginate(self.display, {
        width = self.content_width,
        height = self.content_height,
        first_page_offset = self.header:getSize().h,
        size = self.font_size,
        -- Tabs may shrink a little to fit (if wanted); anything wider is split
        -- at bar lines, so tabs and lyrics keep a similar size.
        min_size = self.tab_fit ~= "off" and math.max(MIN_SIZE, math.floor(self.font_size * 0.8)) or self.font_size,
        max_size = self.tab_fit == "fit" and math.min(MAX_SIZE, math.floor(self.font_size * 1.5)) or self.font_size,
        charWidth = charWidth,
        lineHeight = lineHeight,
    })
    self.pages = pages
    self.tab_size = tab_size
    if ratio then self.page = math.floor(ratio * (#pages - 1) + 0.5) + 1 end
    self.page = math.max(1, math.min(self.page, #pages))
    self:render()
end

function Viewer:render()
    local items = self.pages[self.page] and self.pages[self.page].items or {}
    local body = VerticalGroup:new{ align = "left" }
    -- where the chord lines are, for taps on a chord
    self.chord_hits = {}
    local y = self.title_bar:getHeight() + self.margin
    if self.page == 1 then
        table.insert(body, self.header)
        y = y + self.header:getSize().h
    end
    for _i, item in ipairs(items) do
        if item.kind == "space" then
            local h = math.floor(lineHeight(item.size) * 0.6)
            table.insert(body, VerticalSpan:new{ width = h })
            y = y + h
        else
            local h = lineHeight(item.size)
            if item.kind == "chord" then
                self.chord_hits[#self.chord_hits + 1] = { y0 = y, y1 = y + h, size = item.size, text = item.text }
            end
            y = y + h
            table.insert(body, TextWidget:new{
                text = item.text ~= "" and item.text or " ",
                face = monoFace(item.size),
                bold = item.kind == "chord" or item.kind == "section",
                max_width = self.content_width,
                truncate_with_ellipsis = false,
            })
        end
    end
    local footer_text = T("%1 / %2", self.page, #self.pages)
    if self.auto_seconds then footer_text = footer_text .. "   ▶ " .. T(_("%1 s"), self.auto_seconds) end
    if self.page == #self.pages and self.next_title then
        footer_text = footer_text .. "   → " .. self.next_title
    end
    local footer = TextWidget:new{
        text = footer_text,
        face = Font:getFace("smallinfofont", 14),
        max_width = self.dimen.w - 2 * self.margin,
    }
    local content = VerticalGroup:new{
        align = "left",
        self.title_bar,
        FrameContainer:new{
            padding = 0, padding_left = self.margin, padding_right = self.margin, padding_top = self.margin,
            bordersize = 0,
            width = self.dimen.w,
            height = self.content_height + self.margin,
            body,
        },
    }
    -- The page number always sits at the bottom edge.
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0, padding = 0,
        width = self.dimen.w, height = self.dimen.h,
        OverlapGroup:new{
            dimen = self.dimen:copy(),
            content,
            BottomContainer:new{
                dimen = self.dimen:copy(),
                CenterContainer:new{
                    dimen = Geom:new{ w = self.dimen.w, h = self.footer_height },
                    footer,
                },
            },
        },
    }
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function Viewer:goTo(page)
    page = math.max(1, math.min(page, #self.pages))
    if page == self.page then return end
    self.page = page
    self:render()
end

function Viewer:onNextPage()
    if self.page == #self.pages and self.on_next then
        -- setlist: on to the next song
        local on_next = self.on_next
        self:onClose()
        on_next()
        return true
    end
    self:goTo(self.page + 1)
    self:restartAuto()
    return true
end

function Viewer:onPrevPage()
    self:goTo(self.page - 1)
    self:restartAuto()
    return true
end

--- The chord under a tap, if any.
function Viewer:chordAt(pos)
    for _i, hit in ipairs(self.chord_hits or {}) do
        if pos.y >= hit.y0 and pos.y < hit.y1 then
            local col = math.floor((pos.x - self.margin) / charWidth(hit.size))
            local start = 0
            for token in hit.text:gmatch("%S+") do
                local s = hit.text:find(token, start + 1, true)
                local e = s + #token - 1
                start = e
                -- a little slack around short names (col counts from 0, s and e from 1)
                if col + 1 >= s - 1 and col + 1 <= e + 1 then
                    return Chords.split(token) and token or nil
                end
            end
        end
    end
end

function Viewer:showChord(name)
    local shape = self:shapeFor(name)
    local w = math.floor(math.min(self.dimen.w, self.dimen.h) * 0.42)
    local popup = InputContainer:new{
        dimen = self.dimen:copy(),
        ges_events = { Tap = { GestureRange:new{ ges = "tap", range = self.dimen } } },
    }
    popup[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.large,
            shape and ChordDiagram:new{ name = name, shape = shape, width = w }
                or TextWidget:new{ text = T(_("No diagram for %1"), name), face = Font:getFace("infofont", 20) },
        },
    }
    popup.onTap = function()
        UIManager:close(popup)
        self:cleanRefresh()
        return true
    end
    UIManager:show(popup)
end

function Viewer:onTap(_arg, ges)
    local chord = self:chordAt(ges.pos)
    if chord then
        self:showChord(chord)
        return true
    end
    -- left third: back, rest: forward (like KOReader's reader)
    if ges.pos.x < self.dimen.w / 3 then self:onPrevPage() else self:onNextPage() end
    return true
end

-- Automatic page turning --------------------------------------------------------

function Viewer:startAuto(seconds)
    self:stopAuto()
    self.auto_seconds = seconds
    self.auto_tick = function()
        if self.page >= #self.pages then
            self:stopAuto()
            return
        end
        self:goTo(self.page + 1)
        UIManager:scheduleIn(self.auto_seconds, self.auto_tick)
    end
    UIManager:scheduleIn(seconds, self.auto_tick)
    self:render()
end

function Viewer:stopAuto()
    if self.auto_tick then UIManager:unschedule(self.auto_tick) end
    local was = self.auto_seconds
    self.auto_tick, self.auto_seconds = nil, nil
    if was then self:render() end
end

--- After turning a page by hand, the next automatic turn waits the full time again.
function Viewer:restartAuto()
    if self.auto_tick then
        UIManager:unschedule(self.auto_tick)
        UIManager:scheduleIn(self.auto_seconds, self.auto_tick)
    end
end

function Viewer:onCloseWidget()
    if self.auto_tick then UIManager:unschedule(self.auto_tick) end
end

function Viewer:onSwipe(_arg, ges)
    if ges.direction == "west" then self:onNextPage()
    elseif ges.direction == "east" then self:onPrevPage() end
    return true
end

function Viewer:setFontSize(size)
    size = math.max(MIN_SIZE, math.min(MAX_SIZE, size))
    if size == self.font_size then return end
    -- keep roughly the same place in the song
    local ratio = (#self.pages > 1) and (self.page - 1) / (#self.pages - 1) or 0
    self.font_size = size
    self.own_size = true
    self:relayout(ratio)
end

--- Keep about the same place in the song while the layout changes.
function Viewer:relayoutKeepingPlace()
    local ratio = (#self.pages > 1) and (self.page - 1) / (#self.pages - 1) or 0
    self:relayout(ratio)
end

function Viewer:showMenu()
    local dialog
    local function again(fn)
        return function()
            fn()
            UIManager:close(dialog)
            self:showMenu()
        end
    end
    local next_fit = FIT_MODES[1]
    for i, m in ipairs(FIT_MODES) do if m == self.tab_fit then next_fit = FIT_MODES[i % #FIT_MODES + 1] end end
    local transposed = self.transpose == 0 and _("original key") or string.format("%+d", self.transpose)
    dialog = ButtonDialog:new{
        title = T(_("Font size: %1"), self.font_size) .. (self.own_size and "" or " (" .. _("default") .. ")"),
        title_align = "center",
        buttons = {
            {
                { text = "A−", callback = again(function() self:setFontSize(self.font_size - 1) end) },
                { text = "A+", callback = again(function() self:setFontSize(self.font_size + 1) end) },
            },
            {
                { text = _("Set as default"), enabled = self.own_size, callback = again(function()
                    self.own_size = false
                    self.default_size = self.font_size
                    if self.on_set_default then self.on_set_default(self.font_size) end
                end) },
                -- back to the default after trying other sizes
                { text = _("Reset to default"), enabled = self.own_size and self.default_size ~= nil, callback = again(function()
                    if self.font_size ~= self.default_size then self:setFontSize(self.default_size) end
                    self.own_size = false
                end) },
            },
            {
                { text = T(_("Tab size: %1"), FIT_NAMES[self.tab_fit]), callback = again(function()
                    self.tab_fit = next_fit
                    if self.on_tab_fit_changed then self.on_tab_fit_changed(next_fit) end
                    self:relayoutKeepingPlace()
                end) },
            },
            {
                { text = "♭ −1", callback = again(function()
                    self.transpose = self.transpose - 1 < -11 and 0 or self.transpose - 1
                    self:relayoutKeepingPlace()
                end) },
                { text = T(_("Transpose: %1"), transposed), callback = again(function()
                    self.transpose = 0
                    self:relayoutKeepingPlace()
                end) },
                { text = "♯ +1", callback = again(function()
                    self.transpose = self.transpose + 1 > 11 and 0 or self.transpose + 1
                    self:relayoutKeepingPlace()
                end) },
            },
            {
                { text = self.show_diagrams and _("Chord diagrams: on") or _("Chord diagrams: off"), callback = again(function()
                    self.show_diagrams = not self.show_diagrams
                    if self.on_diagrams_changed then self.on_diagrams_changed(self.show_diagrams) end
                    self:relayoutKeepingPlace()
                end) },
            },
            {
                { text = self.auto_seconds and T(_("Stop page turning (%1 s)"), self.auto_seconds) or _("Turn pages automatically …"),
                  callback = function()
                    UIManager:close(dialog)
                    if self.auto_seconds then
                        self:stopAuto()
                        self:cleanRefresh()
                    else
                        self:askAuto()
                    end
                end },
            },
            {
                { text = _("Back to the library"), callback = function()
                    UIManager:close(dialog)
                    self:onClose()
                end },
                { text = _("Close"), callback = function()
                    UIManager:close(dialog)
                    self:cleanRefresh()
                end },
            },
        },
        -- tapping outside closes it too
        tap_close_callback = function() self:cleanRefresh() end,
    }
    UIManager:show(dialog)
end

function Viewer:askAuto()
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Turn pages automatically"),
        info_text = _("Seconds per page. Turning a page by hand starts the time again."),
        value = self.last_auto or 30, value_min = 5, value_max = 300, value_step = 5, value_hold_step = 30,
        default_value = 30,
        ok_text = _("Start"),
        callback = function(spin)
            self.last_auto = spin.value
            self:startAuto(spin.value)
            self:cleanRefresh()
        end,
    })
end

--- Full refresh after a popup: otherwise e-ink keeps a ghost of its border.
function Viewer:cleanRefresh()
    UIManager:setDirty(self, "full")
end

function Viewer:onClose()
    UIManager:close(self)
    if self.on_close then
        self.on_close({ page = self.page, font_size = self.own_size and self.font_size or nil, transpose = self.transpose })
    end
    return true
end

return Viewer
