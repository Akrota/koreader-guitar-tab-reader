-- Text pasted on the phone (copied from a UG PDF): no blank lines, spaces collapsed, page footers.
local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/../"
package.path = root .. "guitartabreader.koplugin/?.lua;" .. package.path
local P = require("tabreader/parser")
local L = require("tabreader/layout")
local fail = 0
local function check(n, c) print(c and "PASS" or "FAIL", n); if not c then fail = fail + 1 end end
local function opts(width, height, size) return { width = width, height = height, size = size, min_size = 10,
  charWidth = function(s) return s * 0.6 end, lineHeight = function(s) return math.floor(s * 1.4) end, first_page_offset = 0 } end

local tab = { "e|-------3-----|-------3-----|", "B|-------3-----|-------3-----|", "G|-----0---0---|-----0---0---|",
  "D|---0---------|---2---------|", "A|-------------|-------------|", "E|-3---------2-|-0---------2-|" }
local lines = { "[Verse 1]" }
for i = 1, 8 do
  lines[#lines + 1] = "G Em"
  for _, t in ipairs(tab) do lines[#lines + 1] = t end
  lines[#lines + 1] = "I heard---- secret---"
  if i == 4 then lines[#lines + 1] = "Page 1/4" end
end
lines[#lines + 1] = "G Em"
lines[#lines + 1] = "I heard there was a secret chord,"
lines[#lines + 1] = "G Em"
lines[#lines + 1] = "That David played and it pleased the Lord,"
local m = P.parse(table.concat(lines, "\n"), "Test.txt")

local systems, ok_shape, footer = 0, true, false
for _, b in ipairs(m.blocks) do
  if b.kind == "group" and b.has_tab then
    systems = systems + 1
    local tabs = 0
    for _, l in ipairs(b.lines) do if l.tab then tabs = tabs + 1 end end
    if not (b.lines[1].chord and tabs == 6 and b.lines[8] and b.lines[8].text:find("heard")) then ok_shape = false end
  end
  for _, l in ipairs(b.lines or {}) do if l.text:find("Page 1/4") then footer = true end end
end
check("8 separate tab systems without blank lines", systems == 8)
check("each: chord line, 6 strings, lyrics", ok_shape)
check("page footer dropped", not footer)
local last = m.blocks[#m.blocks]
check("chord sheet after the tabs is its own group", last.kind == "group" and not last.has_tab and #last.lines == 4)

-- a page that holds 2.5 systems: no system may be cut
local pages = L.paginate(m, opts(600, math.floor(16 * 1.4) * 22, 16))
local cut = false
for _, p in ipairs(pages) do
  local run = 0
  for i, it in ipairs(p.items) do
    if it.kind == "tab" then run = run + 1 else
      if run > 0 and run ~= 6 then cut = true end
      run = 0
    end
  end
  if run > 0 and run ~= 6 then cut = true end
  if p.items[#p.items].kind == "chord" then cut = true end
end
check("no tab system or chord line cut at a page end (" .. #pages .. " pages)", not cut)
print(fail == 0 and "ALL PASS" or (fail .. " FAILED"))
