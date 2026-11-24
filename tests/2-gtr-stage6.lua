-- Test: stage 6 (chord diagrams, tapping chords, transpose, tab size "fit",
-- automatic page turning, setlists). Run at device size for the screenshots.
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local OUT = os.getenv("GTR_TEST_OUT") or "."
local SAMPLES = os.getenv("GTR_SAMPLES")
local f = io.open(OUT .. "/gtr-stage6.txt", "w")
local function log(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring(select(i, ...)) end f:write(table.concat(p, " ") .. "\n"); f:flush() end
local function check(n, ok) log(ok and "PASS" or "FAIL", n) end
local function top() return UIManager:getTopmostVisibleWidget() end
local function shot(name) UIManager:forceRePaint(); Screen:shot(OUT .. "/" .. name .. ".png") end
local function read(name) local h = io.open(SAMPLES .. "/" .. name, "rb"); local s = h:read("*a"); h:close(); return s end
local function find(lib, pattern)
  for _, it in ipairs(lib.item_table) do if it.text:find(pattern) then return it end end
end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local p = require("apps/filemanager/filemanager").instance.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    local Chords = require("tabreader/chords")
    -- a tab from "Ultimate Guitar" (sample page) with chord shapes
    local UG = require("tabreader/ug")
    local json = require("json")
    local tab = UG.tabFromStore(UG.parseStore(read("tab.html"), function(s) return json.decode(s) end))
    UG.save(tab, p:getFolder())
    local lib = p:openLibrary()

    -- PDF: chord diagrams from the header ("CHORDS G Em C D B7")
    lib.openFile(find(lib, "Hallelujah").file)
    local v = top()
    local names = Chords.used(v.display)
    log("chords:", table.concat(names, " "))
    check("chords of the song found (G first)", names[1] == "G" and #names >= 5)
    check("every chord has a shape", (function() for _, n in ipairs(names) do if not v:shapeFor(n) then return false end end return true end)())
    check("diagram rows in the header", #v:diagramRows(v.content_width) >= 1)
    shot("30-pdf-diagrams")
    local h_on = v.header:getSize().h
    v.show_diagrams = false; v:relayout()
    check("diagrams can be switched off (header smaller)", v.header:getSize().h < h_on)
    v.show_diagrams = true; v:relayout()

    -- tapping a chord shows its diagram; elsewhere the page turns
    v:goTo(2)
    local hit = v.chord_hits[1]
    check("chord lines known for taps", hit ~= nil)
    -- find the x of the first chord by asking the viewer, pixel by pixel
    local token = hit.text:match("%S+")
    local col_x
    for px = v.margin, v.margin + 400 do
      if v:chordAt({ x = px, y = hit.y0 + 2 }) == token then col_x = px; break end
    end
    check("tap on '" .. tostring(token) .. "' finds the chord", col_x ~= nil)
    v:onTap(nil, { pos = { x = col_x, y = hit.y0 + 2 } })
    local popup = top()
    check("chord popup opens", popup ~= v)
    shot("31-chord-popup")
    popup:onTap()
    check("popup closes on tap", top() == v)
    local page = v.page
    v:onTap(nil, { pos = { x = Screen:getWidth() * 0.8, y = Screen:getHeight() - 60 } })
    check("tap elsewhere still turns the page", v.page == page + 1)

    -- transpose: +2 makes G -> A, Em -> F#m, key Db -> Eb (song uses flats)
    v:goTo(1)
    v.transpose = 2; v:relayoutKeepingPlace()
    local tn = Chords.used(v.display)
    log("transposed:", table.concat(tn, " "), "key", v.display.meta.key)
    check("transpose +2: G -> A, Em -> F#m or Gbm", tn[1] == "A" and (tn[2] == "F#m" or tn[2] == "Gbm"))
    check("key moves too (Db -> Eb)", v.display.meta.key == "Eb")
    check("original model unchanged", Chords.used(v.model)[1] == "G")
    shot("32-transposed")
    local result
    v.on_close = (function(orig) return function(r) result = r; orig(r) end end)(v.on_close)
    v:onClose()
    check("transpose remembered for the tab", result.transpose == 2)
    lib.openFile(find(lib, "Hallelujah").file)
    v = top()
    check("reopened with transpose +2", v.transpose == 2)
    v.transpose = 0; v:onClose()

    -- UG tab: shapes from UG are used
    lib.openFile(find(lib, "Testlied").file)
    v = top()
    check("UG shape used for C", table.concat(v:shapeFor("C").frets, ",") == "-1,3,2,0,1,0")
    v.transpose = 1; v:relayout()
    check("transposed UG song uses the built-in shapes (C#)", v:shapeFor("C#") ~= nil)
    v.transpose = 0; v:onClose()

    -- tab size "fit": narrow tabs get larger, never wider than the screen
    lib.openFile(find(lib, "Übungsriff").file)
    v = top()
    v.tab_fit = "shrink"; v:relayout(); local small = v.tab_size
    v.tab_fit = "fit"; v:relayout(); local big = v.tab_size
    log("riff tab size shrink/fit:", small, big, "font", v.font_size)
    check("fit makes tabs larger when there is room", big > small and big <= math.floor(v.font_size * 1.5))
    shot("33-fit-width")
    v.tab_fit = "shrink"; v:relayout()

    -- automatic page turning
    v:goTo(1)
    local pages = #v.pages
    v:startAuto(10)
    check("auto turning runs, shown in the footer", v.auto_seconds == 10 and v.auto_tick ~= nil)
    if pages > 1 then v.auto_tick() end
    check("a tick turns the page", pages == 1 or v.page == 2)
    v:stopAuto()
    check("auto turning stops", v.auto_tick == nil)
    v:onClose()

    -- setlist: two songs; the last page of the first leads to the second
    local Setlists = require("tabreader/setlists")
    local riff = find(lib, "Übungsriff").file.rel
    local grace = find(lib, "Amazing Grace").file.rel
    Setlists.save(p, { { name = "Probe", items = { riff, grace } } })
    local lists = Setlists.load(p)
    check("setlist saved", #lists == 1 and #lists[1].items == 2)
    check("no duplicates", Setlists.add(lists, 1, riff) == false)
    Setlists.play(p, lists[1], 1)
    v = top()
    check("setlist starts with song 1 on page 1, knows the next", v.page == 1 and v.next_title and v.next_title:find("Amazing Grace"))
    v:goTo(#v.pages)
    shot("34-setlist-last-page")
    v:onNextPage()
    local v2 = top()
    check("next page at the end opens song 2", v2 ~= v and v2.model.meta.title == "Amazing Grace")
    check("last song has no next", v2.next_title == nil)
    v2:onClose()
    Setlists.move(lists[1], 2, -1)
    check("move song up", lists[1].items[1] == grace)

    -- screenshots of the menus
    Setlists.save(p, lists)
    Setlists.show(p)
    shot("35-setlists")
    UIManager:close(top())
    lib.openFile(find(lib, "Hallelujah").file)
    v = top()
    v:showMenu()
    shot("36-viewer-menu")
    UIManager:close(top())
    v:onClose()
  end)
  if not ok then log("ERROR", e) end
  f:close(); UIManager:quit()
end)
