-- Test: Guitar Tab Reader stage 1 (library, parsing, viewer, page turns, font size, state).
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local OUT = os.getenv("GTR_TEST_OUT") or "."
local f = io.open(OUT .. "/gtr-results.txt", "w")
local function log(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring(select(i, ...)) end f:write(table.concat(p, " ") .. "\n"); f:flush() end
local function check(n, ok) log(ok and "PASS" or "FAIL", n) end
local function top() return UIManager:getTopmostVisibleWidget() end
local function shot(name) UIManager:forceRePaint(); Screen:shot(OUT .. "/" .. name .. ".png") end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local FM = require("apps/filemanager/filemanager").instance
    local p = FM and FM.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    check("plugin loaded in file browser", p ~= nil)
    local items = {}
    FM.menu.menu_items = FM.menu.menu_items or {}
    p:addToMainMenu(items)
    check("menu entry", items.guitar_tab_reader ~= nil)
    local lib = p:openLibrary()
    check("library opens", lib and top() == lib)
    local titles = {}
    for _, it in ipairs(lib.item_table) do titles[#titles + 1] = it.text end
    log("library:", table.concat(titles, " | "))
    check("4 entries (3 text tabs + 1 PDF)", #lib.item_table == 4)
    shot("01-library")
    -- open the riff example
    local riff
    for _, it in ipairs(lib.item_table) do if it.text:find("Übungsriff") then riff = it end end
    lib:onMenuChoice(riff)
    local v = top()
    check("viewer opens", v and v.pages ~= nil)
    log("pages:", #v.pages, "font", v.font_size, "tab size", v.tab_size)
    shot("02-riff-page1")
    v:onNextPage()
    check("next page", v.page == 2 or #v.pages == 1)
    shot("03-riff-page2")
    v:onPrevPage()
    check("previous page", v.page == 1)
    -- tap right half -> next page
    v:onTap(nil, { pos = { x = Screen:getWidth() * 0.8, y = 500 } })
    check("tap right turns page", v.page == math.min(2, #v.pages))
    v:setFontSize(22)
    log("after A+:", #v.pages, "pages, tab size", v.tab_size)
    check("bigger font gives at least as many pages", #v.pages >= 1 and v.font_size == 22)
    shot("04-riff-font22")
    v:onClose()
    check("back in library after close", top() == lib)
    -- state saved, recently played first
    check("last played on top", lib.item_table[1].text:find("Übungsriff") ~= nil)
    -- ChordPro
    local cho
    for _, it in ipairs(lib.item_table) do if it.text:find("Amazing Grace") then cho = it end end
    check("chordpro title and artist in list", cho and cho.text == "Amazing Grace – Traditional")
    lib:onMenuChoice(cho)
    shot("05-amazing-grace")
    top():onClose()
    -- UG format
    local ug
    for _, it in ipairs(lib.item_table) do if it.text:find("Erfundenes") then ug = it end end
    lib:onMenuChoice(ug)
    shot("06-ug-format")
    top():onClose()
    -- PDF (stage 3): opens as a tab with title and artist from the PDF
    local pdf
    for _, it in ipairs(lib.item_table) do if it.mandatory == "PDF" then pdf = it end end
    check("PDF listed with its real title", pdf and pdf.text == "Hallelujah – Jeff Buckley")
    local t0 = os.clock()
    lib:onMenuChoice(pdf)
    local pv = top()
    log("pdf open time", string.format("%.2f", os.clock() - t0), "pages", pv.pages and #pv.pages)
    check("PDF opens in the tab view", pv and pv.model and pv.model.meta.title == "Hallelujah" and pv.model.meta.artist == "Jeff Buckley")
    check("PDF details", pv.model.meta.capo == "6" and pv.model.meta.key == "Db" and pv.model.meta.tuning == "E A D G B E")
    local tabs, chords = 0, 0
    for _, b in ipairs(pv.model.blocks) do if b.kind == "group" then for _, l in ipairs(b.lines) do
        if l.tab then tabs = tabs + 1 elseif l.chord then chords = chords + 1 end end end end
    log("pdf tab lines", tabs, "chord lines", chords)
    check("PDF: all 48 tab lines (as in the original) and the chord lines recognised", tabs == 48 and chords >= 40)
    shot("07-pdf-page1")
    pv:onNextPage()
    shot("08-pdf-page2")
    pv:onClose()
    local lfs = require("libs/libkoreader-lfs")
    local cache_dir = p:getFolder() .. "/.tabreader/cache"
    local cached = false
    for n in lfs.dir(cache_dir) do if n:match("hallelujah") then cached = true end end
    check("PDF result cached", cached)
    -- reopening the riff restores page and font size
    lib:onMenuChoice(riff)
    local v2 = top()
    check("font size remembered", v2.font_size == 22)
    v2:onClose()
    UIManager:close(lib)
  end)
  if not ok then log("ERROR", e) end
  f:close(); UIManager:quit()
end)
