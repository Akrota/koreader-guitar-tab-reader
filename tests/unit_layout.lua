local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/../"
package.path = root .. "guitartabreader.koplugin/?.lua;" .. package.path
local P = require("tabreader/parser")
local L = require("tabreader/layout")
local function read(n) local f = io.open(root .. "tests/testtabs/" .. n); local s = f:read("*a"); f:close(); return s end
local fail = 0
local function check(n, c) print(c and "PASS" or "FAIL", n); if not c then fail = fail + 1 end end
-- fake measures: char width = size*0.6 px, line height = size*1.4
local function opts(width, height, size) return { width = width, height = height, size = size, min_size = 10,
  charWidth = function(s) return s * 0.6 end, lineHeight = function(s) return math.floor(s * 1.4) end, first_page_offset = 0 } end

local m = P.parse(read("Beispiel - Übungsriff.txt"), "Beispiel - Übungsriff.txt")
check("meta from header", m.meta.capo == "2" and m.meta.key == "A" and m.meta.title == "Übungsriff" and m.meta.artist == "Beispiel")
local kinds = {}
for _, b in ipairs(m.blocks) do kinds[#kinds + 1] = b.kind .. (b.has_tab and "+tab" or "") end
print("blocks:", table.concat(kinds, " "))
check("sections and tab groups", kinds[1] == "section" and kinds[2] == "group+tab")
-- narrow screen: 60 columns at size 16 (16*0.6*60 = 576 px)
local pages, tab_size = L.paginate(m, opts(576, 2000, 16))
print("tab size", tab_size)
local maxlen, cols_at = 0, math.floor(576 / (tab_size * 0.6))
for _, p in ipairs(pages) do for _, it in ipairs(p.items) do
  if it.text and (it.kind == "tab" or it.size == tab_size) then maxlen = math.max(maxlen, L.len(it.text)) end end end
check("nothing wider than the screen", maxlen <= cols_at)
-- the long riff got split: count e| lines
local e_lines = 0
for _, p in ipairs(pages) do for _, it in ipairs(p.items) do if it.text and it.text:match("^e|") then e_lines = e_lines + 1 end end end
print("e| lines", e_lines)
check("long riff split into pieces", e_lines >= 3)
-- chords stay aligned over strings in a later piece
local found
for _, p in ipairs(pages) do for i, it in ipairs(p.items) do
  if it.kind == "chord" and p.items[i + 1] and p.items[i + 1].text and p.items[i + 1].text:match("^e|") and it.text:match("A") then found = { it.text, p.items[i + 1].text } end end end
if found then print(found[1]); print(found[2]) end
-- ChordPro
local c = P.parse(read("Traditional - Amazing Grace.cho"), "Traditional - Amazing Grace.cho")
check("chordpro meta", c.meta.title == "Amazing Grace" and c.meta.artist == "Traditional" and c.meta.key == "G")
local g = c.blocks[2]
check("chordpro chord over syllable", g and g.lines[1].chord and g.lines[1].text:sub(1, 2) == " G" and g.lines[2].text:sub(1, 7) == "Amazing")
print(g.lines[1].text); print(g.lines[2].text)
-- UG markup
local u = P.parse(read("Testband - Erfundenes Lied (UG-Format).txt"), "Testband - Erfundenes Lied (UG-Format).txt")
local found_chorus
for _, b in ipairs(u.blocks) do if b.kind == "section" and b.text == "Chorus" then found_chorus = true end end
check("ug markup sections", found_chorus and u.meta.artist == "Testband")
local pu = L.paginate(u, opts(400, 2000, 16)) -- ~41 columns
local wrapped = 0
for _, p in ipairs(pu) do for _, it in ipairs(p.items) do if it.text and L.len(it.text) > math.floor(400 / 9.6) then wrapped = -100 end end end
check("ug long line wrapped within width", wrapped == 0)
for _, it in ipairs(pu[1].items) do print(string.format("%-7s|%s", it.kind, it.text or "")) end
-- pagination: small page height forces several pages, no group split
local pp = L.paginate(m, opts(1200, 200, 16))
check("several pages", #pp > 1)
for i, p in ipairs(pp) do
  local first = p.items[1]
  check("page " .. i .. " does not start with blank", first and first.kind ~= "space")
end
-- lyrics under a split tab: a word over the cut is not torn apart
check("word over the cut stays whole (first piece)", L.wordCols("ab dazu mit", 1, 9) == "ab dazu")
check("word over the cut stays whole (next piece)", L.wordCols("ab dazu mit", 10, 20) == "mit")
check("words inside a piece keep their column", L.wordCols("   E       A", 1, 20) == "   E       A")
print(fail == 0 and "ALL PASS" or ("FAILURES: " .. fail))
