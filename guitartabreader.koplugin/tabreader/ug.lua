--[[--
Ultimate Guitar module (experimental, off by default): loads tabs from Ultimate Guitar (links and search).

For personal use. It is off until switched on in the menu. It only reads
public pages one at a time, the way a browser would: no login, no Pro or
official tabs, nothing that gets around a block. If UG blocks the request,
it reports that and stops.

UG pages carry their data as JSON in a "js-store" element: the tab text with
[ch]/[tab] markup, capo, key, tuning, chord shapes and search results.
The pure functions (parseStore, tabFromStore, searchFromStore, toFileText)
take the decoder as an argument, so they can be tested without KOReader.
--]]

local UG = {}

UG.SEARCH_URL = "https://www.ultimate-guitar.com/search.php?search_type=title&value=%s&page=%d"
-- Types we show and load: guitar only for now (bass and ukulele later via a switch).
UG.TYPES = { Chords = true, Tabs = true }

--- Is this a link to a tab page on Ultimate Guitar?
function UG.isTabLink(url)
    if type(url) ~= "string" then return false end
    local host, path = url:match("^https?://([%w%.%-]+)(/[^%s]*)")
    if not host then return false end
    host = host:lower()
    if not (host == "ultimate-guitar.com" or host:match("%.ultimate%-guitar%.com$")) then return false end
    return path:match("^/tab/") ~= nil
end

local ENTITIES = { quot = '"', amp = "&", lt = "<", gt = ">", apos = "'", nbsp = " " }

local function utf8char(n)
    if n < 0x80 then return string.char(n) end
    if n < 0x800 then return string.char(0xC0 + math.floor(n / 0x40), 0x80 + n % 0x40) end
    if n < 0x10000 then
        return string.char(0xE0 + math.floor(n / 0x1000), 0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40)
    end
    return string.char(0xF0 + math.floor(n / 0x40000), 0x80 + math.floor(n / 0x1000) % 0x40,
        0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40)
end

--- Decode the HTML entities of an attribute value.
function UG.unescape(s)
    return (s:gsub("&(#?[xX]?)(%w+);", function(kind, name)
        if kind == "" then return ENTITIES[name] end
        local n = kind:lower() == "#x" and tonumber(name, 16) or tonumber(name)
        return n and utf8char(n) or nil
    end))
end

--- The page data from the js-store element.
-- @param html page source
-- @param decode JSON decoder (function(string) -> table)
-- @return table or nil, "nodata"
function UG.parseStore(html, decode)
    local raw = html:match('class="js%-store"%s+data%-content="([^"]*)"')
    if not raw then return nil, "nodata" end
    local ok, data = pcall(decode, UG.unescape(raw))
    if not ok or type(data) ~= "table" then return nil, "nodata" end
    return data
end

-- JSON null comes back as a placeholder value, not nil: only accept real strings.
local function str(v)
    if type(v) == "string" and v ~= "" then return v end
end

local function pageData(store)
    return store and store.store and store.store.page and store.store.page.data
end

-- Chord shapes: UG lists frets from the high e string down; we keep low E first.
local function chordShapes(applicature)
    if type(applicature) ~= "table" then return nil end
    local shapes = {}
    for name, variants in pairs(applicature) do
        local v = type(variants) == "table" and variants[1]
        if type(v) == "table" and type(v.frets) == "table" and #v.frets == 6 then
            local frets, fingers = {}, {}
            for i = 6, 1, -1 do
                frets[#frets + 1] = tonumber(v.frets[i]) or -1
                fingers[#fingers + 1] = type(v.fingers) == "table" and tonumber(v.fingers[i]) or 0
            end
            local barres = {}
            for _, b in ipairs(type(v.listCapos) == "table" and v.listCapos or {}) do
                -- strings counted from the high e (1) as well
                local fret, first, last = tonumber(b.fret), tonumber(b.startString), tonumber(b.lastString)
                if fret and first and last then
                    barres[#barres + 1] = { fret = fret, from = 6 - last, to = 6 - first, finger = tonumber(b.finger) }
                end
            end
            shapes[name] = { frets = frets, fingers = fingers, base = tonumber(v.fret) or 0, barres = barres }
        end
    end
    return next(shapes) and shapes or nil
end

--- The tab of a tab page.
-- @return tab = { title, artist, type, version, url, content, meta = {…}, chords = {…} }
--         or nil, reason ("nodata", "pro" for Pro/official/blocked tabs, "type" for other instruments)
function UG.tabFromStore(store)
    local data = pageData(store)
    local tab, view = data and data.tab, data and data.tab_view
    if type(tab) ~= "table" or type(view) ~= "table" then return nil, "nodata" end
    local kind = str(tab.type) or str(tab.type_name)
    if kind == "Pro" or kind == "Official" or kind == "Power" or kind == "Video" or view.blocked == true then
        return nil, "pro"
    end
    if not UG.TYPES[kind] then return nil, "type" end
    local content = type(view.wiki_tab) == "table" and str(view.wiki_tab.content)
    if not content then return nil, "nodata" end
    local m = type(view.meta) == "table" and view.meta or {}
    local meta = {
        capo = (tonumber(m.capo) or 0) > 0 and tostring(m.capo) or nil,
        key = str(m.tonality) or str(tab.tonality_name),
        tuning = type(m.tuning) == "table" and str(m.tuning.value) or nil,
        difficulty = str(m.difficulty),
    }
    return {
        title = str(tab.song_name), artist = str(tab.artist_name), type = kind, version = tonumber(tab.version),
        url = str(tab.tab_url), content = (content:gsub("\r\n", "\n")), meta = meta,
        chords = chordShapes(view.applicature),
    }
end

--- Search results, guitar tabs only (no Pro/official, no other instruments).
-- @return list of { title, artist, type, version, rating, votes, url }, pages
function UG.searchFromStore(store)
    local data = pageData(store)
    if type(data) ~= "table" then return nil, "nodata" end
    local list = {}
    for _, r in ipairs(type(data.results) == "table" and data.results or {}) do
        -- official/Pro entries carry a marketing type
        if type(r) == "table" and UG.TYPES[r.type] and UG.isTabLink(r.tab_url) and not str(r.marketing_type) then
            list[#list + 1] = {
                title = str(r.song_name), artist = str(r.artist_name), type = r.type, version = tonumber(r.version),
                rating = tonumber(r.rating), votes = tonumber(r.votes), url = r.tab_url,
            }
        end
    end
    local pages = type(data.pagination) == "table" and tonumber(data.pagination.total) or 1
    return list, pages
end

--- The tab as a text file: header lines the parser reads, then UG's own markup.
function UG.toFileText(tab)
    local out = {}
    local function add(k, v) if v and v ~= "" then out[#out + 1] = k .. ": " .. v end end
    add("Title", tab.title)
    add("Artist", tab.artist)
    add("Capo", tab.meta.capo)
    add("Key", tab.meta.key)
    add("Tuning", tab.meta.tuning)
    add("Difficulty", tab.meta.difficulty)
    out[#out + 1] = ""
    out[#out + 1] = tab.content
    return table.concat(out, "\n")
end

--- File name: "Artist - Title (Chords).txt", version added if it is not the first.
function UG.fileName(tab)
    local base = (tab.artist and (tab.artist .. " - ") or "") .. (tab.title or "Tab")
    local suffix = tab.type or ""
    if tab.version and tonumber(tab.version) and tonumber(tab.version) > 1 then
        suffix = suffix .. " v" .. tab.version
    end
    if suffix ~= "" then base = base .. " (" .. suffix .. ")" end
    return (base:gsub("[/\\:%*%?\"<>|]", "-")) .. ".txt"
end

function UG.searchUrl(query, page)
    local q = query:gsub("[^%w%-_%.~ ]", function(c) return string.format("%%%02X", c:byte()) end):gsub(" ", "%%20")
    return string.format(UG.SEARCH_URL, q, page or 1)
end

-- KOReader part ---------------------------------------------------------------

--- Fetch a page.
-- @return body or nil, reason ("network", "blocked", "http <code>")
function UG.get(url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, headers = socket.skip(1, http.request{
        url = url,
        method = "GET",
        headers = { ["Accept"] = "text/html", ["Accept-Language"] = "en" },
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if not headers then return nil, "network" end
    local body = table.concat(sink)
    if code == 403 or code == 429 or code == 503 then return nil, "blocked" end
    if code ~= 200 then return nil, "http " .. tostring(code) end
    return body
end

local function decoder()
    local json = require("json")
    return function(s) return json.decode(s) end
end

--- Load a tab page.
-- @return tab or nil, reason
function UG.fetchTab(url)
    local body, err = UG.get(url)
    if not body then return nil, err end
    local store, err2 = UG.parseStore(body, decoder())
    if not store then return nil, err2 end
    return UG.tabFromStore(store)
end

--- Search.
-- @return results, pages or nil, reason
function UG.search(query, page)
    local body, err = UG.get(UG.searchUrl(query, page))
    if not body then return nil, err end
    local store, err2 = UG.parseStore(body, decoder())
    if not store then return nil, err2 end
    return UG.searchFromStore(store)
end

--- Save a loaded tab into the tab folder (subfolder "ug"), chord shapes next to it.
-- @return path, rel or nil, error
function UG.save(tab, folder)
    local util = require("util")
    local lfs = require("libs/libkoreader-lfs")
    local dir = folder .. "/ug"
    util.makePath(dir)
    local name = UG.fileName(tab)
    local path = dir .. "/" .. name
    local f = io.open(path, "wb")
    if not f then return nil, "write" end
    f:write(UG.toFileText(tab))
    f:close()
    local rel = "ug/" .. name
    local Extra = require("tabreader/extra")
    Extra.save(folder, rel, { chords = tab.chords, url = tab.url })
    return path, rel, lfs.attributes(path, "size")
end

return UG
