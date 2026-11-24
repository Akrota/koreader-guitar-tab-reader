-- Test: private UG module (stage 4 + 5). Uses invented sample pages (tests/ugsamples);
-- with GTR_LIVE=1 it also loads one real tab page and one real search (2 requests).
local UIManager = require("ui/uimanager")
local OUT = os.getenv("GTR_TEST_OUT") or "."
local SAMPLES = os.getenv("GTR_SAMPLES")
local f = io.open(OUT .. "/gtr-ug.txt", "w")
local function log(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring(select(i, ...)) end f:write(table.concat(p, " ") .. "\n"); f:flush() end
local function check(n, ok) log(ok and "PASS" or "FAIL", n) end
local function top() return UIManager:getTopmostVisibleWidget() end
local function read(name) local h = io.open(SAMPLES .. "/" .. name, "rb"); local s = h:read("*a"); h:close(); return s end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local p = require("apps/filemanager/filemanager").instance.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    local UG = require("tabreader/ug")
    local Parser = require("tabreader/parser")
    local json = require("json")
    local decode = function(s) return json.decode(s) end

    -- links
    check("tab link recognised", UG.isTabLink("https://tabs.ultimate-guitar.com/tab/jeff-buckley/hallelujah-chords-198052"))
    check("other links not", not UG.isTabLink("https://example.com/tab/1") and not UG.isTabLink("https://www.ultimate-guitar.com/pro/?x=1")
      and not UG.isTabLink("https://evil-ultimate-guitar.com/tab/x"))

    -- tab page
    local store = UG.parseStore(read("tab.html"), decode)
    local tab, why = UG.tabFromStore(store)
    check("tab read from the page", tab ~= nil)
    log("tab:", tab and tab.title, tab and tab.artist, tab and tab.type, why)
    check("title, artist (umlaut), type", tab.title == "Testlied" and tab.artist == "Testband Ü" and tab.type == "Chords")
    check("capo, key, tuning", tab.meta.capo == "2" and tab.meta.key == "C" and tab.meta.tuning == "E A D G B E")
    check("quotes and & decoded", tab.content:find('With "quotes" & ampersand <ok>', 1, true) ~= nil)
    check("no CR left", not tab.content:find("\r"))
    local C, F = tab.chords and tab.chords.C, tab.chords and tab.chords.F
    check("chord shape C low E first (x32010)", C and table.concat(C.frets, ",") == "-1,3,2,0,1,0")
    check("barre of F over all strings at fret 1", F and F.barres[1] and F.barres[1].fret == 1 and F.barres[1].from == 1 and F.barres[1].to == 6)
    check("file name", UG.fileName(tab) == "Testband Ü - Testlied (Chords v2).txt")
    local model = Parser.parse(UG.toFileText(tab), UG.fileName(tab))
    local tabs, chords = 0, 0
    for _, b in ipairs(model.blocks) do for _, l in ipairs(b.lines or {}) do
      if l.tab then tabs = tabs + 1 end; if l.chord then chords = chords + 1 end end end
    check("saved text parses: meta + chords + 6 tab lines", model.meta.title == "Testlied" and model.meta.capo == "2" and tabs == 6 and chords >= 3)
    local pro, why2 = UG.tabFromStore(UG.parseStore(read("tab-pro.html"), decode))
    check("Pro tab refused", pro == nil and why2 == "pro")
    check("page without data", UG.parseStore("<html></html>", decode) == nil)

    -- search
    local results, pages = UG.searchFromStore(UG.parseStore(read("search.html"), decode))
    local bad = 0
    for _, r in ipairs(results) do if not (r.type == "Chords" or r.type == "Tabs") or not UG.isTabLink(r.url) then bad = bad + 1 end end
    log("search:", #results, "results,", pages, "pages")
    check("search: 12 guitar results, no Pro/official/ukulele", #results == 12 and bad == 0)
    check("search: page count", pages == 2)
    check("search url encodes the query", UG.searchUrl("AC/DC & Co", 2):find("value=AC%2FDC%20%26%20Co&page=2", 1, true) ~= nil)

    -- the whole way: remembered links -> files -> library -> viewer (UG.get answers from the samples)
    local real_get = UG.get
    local requests = 0
    UG.get = function(url) requests = requests + 1; return read("tab.html") end
    p:setSetting("ug_enabled", true)
    local folder = p:getFolder()
    local LuaSettings = require("luasettings")
    require("util").makePath(folder .. "/.tabreader")
    local q = LuaSettings:open(folder .. "/.tabreader/links.lua")
    q:saveSetting("links", { { url = "https://tabs.ultimate-guitar.com/tab/testband/testlied-chords-1" }, { url = "https://example.com/nope" } })
    q:flush()
    local lib = p:openLibrary()
    local before = #lib.item_table
    p:loadLinks()
    UIManager:scheduleIn(5, function()
      local ok2, e2 = pcall(function()
        UG.get = real_get
        local lfs = require("libs/libkoreader-lfs")
        check("one request for the one UG link", requests == 1)
        check("tab saved in ug/", lfs.attributes(folder .. "/ug/Testband Ü - Testlied (Chords v2).txt", "mode") == "file")
        local links = LuaSettings:open(folder .. "/.tabreader/links.lua"):readSetting("links")
        check("both links done, the other one marked unsupported", links[1].done and links[1].file and links[2].done and links[2].error == "unsupported")
        check("library shows the new tab", #lib.item_table == before + 1)
        while top() ~= lib and top() do UIManager:close(top()) end -- the report
        lib.openRel("ug/Testband Ü - Testlied (Chords v2).txt")
        local v = top()
        check("tab opens", v and v.pages ~= nil)
        check("chord shapes reach the viewer", v.model.chords and v.model.chords.G ~= nil)
        v:onClose()

        if os.getenv("GTR_LIVE") == "1" then
          local t, err = UG.fetchTab("https://tabs.ultimate-guitar.com/tab/jeff-buckley/hallelujah-chords-198052")
          log("live tab:", t and t.title, t and t.artist, err)
          check("LIVE: real tab page loads in KOReader", t and t.title == "Hallelujah" and #t.content > 500)
          local r, n = UG.search("hallelujah buckley")
          log("live search:", r and #r, n)
          check("LIVE: real search gives guitar results", r and #r > 0)
        end
      end)
      if not ok2 then log("ERROR", e2) end
      f:close(); UIManager:quit()
    end)
  end)
  if not ok then log("ERROR", e); f:close(); UIManager:quit() end
end)
