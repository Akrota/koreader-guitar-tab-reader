--[[--
Turns a parsed tab into pages for the screen. Pure computation: sizes come
from the caller (measure functions), so this can be tested without KOReader.

Rules:
  * Tab systems are never wrapped. All tab systems of a song share one font
    size: the user's size, made smaller until the widest system fits, but not
    below a minimum. Still too wide: the system is split at bar lines ("|"),
    with all its lines (chords, strings, lyrics) cut at the same columns.
  * Chord lines and their lyric line wrap together, so chords stay above
    their syllable.
  * A group (tab system, chord+lyric pair, paragraph) is not split across
    pages; a section heading stays with what follows it.
--]]

local Layout = {}

local function chars(s)
    local t = {}
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = c end
    return t
end

local function len(s) return #chars(s) end

-- Substring by character columns (1-based, inclusive), padded with spaces.
local function cols(s, from, to)
    local t = chars(s)
    local out = {}
    for i = from, to do out[#out + 1] = t[i] or " " end
    return (table.concat(out):gsub("%s+$", ""))
end

-- Like cols(), for lyric and chord lines above or below a tab: a word that
-- runs over the cut is never torn apart ("m" / "it"). It goes to the piece
-- where it ends, moved right to the start of that piece if needed.
local function wordCols(s, from, to)
    local t = chars(s)
    local out = {}
    for i = from, to do out[#out + 1] = " " end
    local i = 1
    while i <= #t do
        if t[i]:match("^%s$") then
            i = i + 1
        else
            local j = i
            while t[j + 1] and not t[j + 1]:match("^%s$") do j = j + 1 end
            if j >= from and j <= to then
                local start = math.max(i, from) - from + 1
                for k = i, j do out[start + k - i] = t[k] end
            end
            i = j + 1
        end
    end
    return (table.concat(out):gsub("%s+$", ""))
end
Layout.wordCols = wordCols

--- Where to cut a tab system of `width` columns into pieces of at most `max` columns.
-- Prefers bar lines in the first string line.
-- @return list of { from, to }
-- @param prefix columns added in front of later pieces (repeated string names)
function Layout.tabCuts(tab_line, width, max, prefix)
    prefix = prefix or 0
    local bars = {}
    local t = chars(tab_line)
    for i, c in ipairs(t) do
        if c == "|" then bars[#bars + 1] = i end
    end
    local cuts, from = {}, 1
    while from <= width do
        local room = from == 1 and max or (max - prefix)
        local to = math.min(width, from + room - 1)
        if to < width then
            -- last bar line within reach (keep it at the end of this piece)
            local best
            for _, b in ipairs(bars) do
                if b > from + 3 and b <= to then best = b end
            end
            if best then to = best end
        end
        cuts[#cuts + 1] = { from, to }
        -- the next piece repeats the string names when there were any
        from = to + 1
    end
    return cuts
end

--- Wrap a chord line and its lyric line together at a common column.
-- @return list of { chord, lyric } pieces (either may be nil)
function Layout.wrapPair(chord, lyric, max)
    local width = math.max(chord and len(chord) or 0, lyric and len(lyric) or 0)
    local pieces, from = {}, 1
    local lt = lyric and chars(lyric) or {}
    local ct = chord and chars(chord) or {}
    while from <= width do
        local to = math.min(width, from + max - 1)
        if to < width then
            -- break after a space in the lyric that is not under a chord name
            local best
            for i = to, from + math.floor(max / 3), -1 do
                local lyric_space = (lt[i] == nil or lt[i] == " ")
                local chord_free = (ct[i] == nil or ct[i] == " ") and (ct[i + 1] == nil or ct[i + 1] == " " or i == to)
                if lyric_space and chord_free then best = i break end
            end
            if best then to = best end
        end
        local c = chord and cols(chord, from, to) or nil
        local l = lyric and cols(lyric, from, to) or nil
        -- continuation lines start without leading blanks in the lyric
        if from > 1 and l then
            local trim = #l:match("^%s*")
            if c then c = cols(c, trim + 1, max) end
            l = l:sub(trim + 1)
        end
        pieces[#pieces + 1] = { chord = c ~= "" and c or nil, lyric = l ~= "" and l or nil }
        from = to + 1
    end
    return pieces
end

--- Word wrap for plain text lines.
function Layout.wrapText(text, max)
    if len(text) <= max then return { text } end
    local out, line = {}, ""
    local indent = text:match("^%s*")
    for word in text:gmatch("%S+") do
        local candidate = line == "" and (indent .. word) or (line .. " " .. word)
        if len(candidate) > max and line ~= "" then
            out[#out + 1] = line
            line = indent .. word
        else
            line = candidate
        end
        while len(line) > max do
            out[#out + 1] = cols(line, 1, max)
            line = cols(line, max + 1, len(line))
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

--- Lay out the song.
-- @param model parsed tab (Parser.parse)
-- @param opts {
--     width, height                 content area in pixels (height of a full page)
--     first_page_offset             pixels taken by the header on page 1
--     size                          user font size; min_size / max_size: smallest / largest size for tab systems
--     charWidth(size), lineHeight(size)   measuring functions (pixels)
--   }
-- @return pages = { { items = { { kind, text, size } … } } … }, tab_size
function Layout.paginate(model, opts)
    local size, min_size = opts.size, opts.min_size or math.max(8, opts.size - 6)
    local function maxCols(s) return math.max(10, math.floor(opts.width / opts.charWidth(s))) end

    -- One size for all tab systems: as large as the user wants, smaller only
    -- as far as it lets systems fit whole. Systems too wide even at the
    -- minimum size are split anyway, so they don't make everything smaller.
    local widest = 0
    local limit = maxCols(min_size)
    for _, block in ipairs(model.blocks) do
        if block.kind == "group" and block.has_tab then
            local w = 0
            for _, line in ipairs(block.lines) do w = math.max(w, len(line.text)) end
            if w <= limit then widest = math.max(widest, w) end
        end
    end
    local tab_size = size
    while tab_size > min_size and widest > maxCols(tab_size) do tab_size = tab_size - 1 end
    -- "fit to width": tabs that fit with room to spare may also get larger (up to max_size)
    if (opts.max_size or size) > size and widest > 0 and tab_size == size then
        while tab_size < opts.max_size and widest <= maxCols(tab_size + 1) do tab_size = tab_size + 1 end
    end

    -- Build "units": lists of items that must stay together.
    local units = {}
    local pending_heading
    local function addUnit(items)
        if pending_heading then
            table.insert(items, 1, pending_heading)
            pending_heading = nil
        end
        units[#units + 1] = items
    end

    for _, block in ipairs(model.blocks) do
        if block.kind == "section" then
            if pending_heading then units[#units + 1] = { pending_heading } end
            pending_heading = { kind = "section", text = "[" .. block.text .. "]", size = size }
        elseif block.kind == "blank" then
            if pending_heading then
                -- heading followed by a blank: keep it with what comes next anyway
            elseif #units > 0 then
                units[#units + 1] = { { kind = "space", size = size } }
            end
        elseif block.has_tab then
            local max = maxCols(tab_size)
            local width, first_tab = 0, nil
            for _, line in ipairs(block.lines) do
                width = math.max(width, len(line.text))
                if line.tab and not first_tab then first_tab = line.text end
            end
            -- Later pieces repeat the string names ("e|"), so they lose two columns.
            local named = first_tab and first_tab:match("^%s*[eBGDAEbgda][#b]?%s*[|:]") ~= nil
            local prefix = named and 2 or 0
            for _, cut in ipairs(Layout.tabCuts(first_tab or "", width, max, prefix)) do
                local items = {}
                for _, line in ipairs(block.lines) do
                    local piece = line.tab and cols(line.text, cut[1], cut[2]) or wordCols(line.text, cut[1], cut[2])
                    if cut[1] > 1 and named then
                        local name = line.tab and line.text:match("^%s*([eBGDAEbgda][#b]?)%s*[|:]")
                        if name then
                            piece = name .. "|" .. piece:gsub("^|", "")
                        else
                            -- keep chords and lyrics aligned with the strings
                            piece = "  " .. piece
                        end
                    end
                    items[#items + 1] = { kind = line.tab and "tab" or (line.chord and "chord" or "text"), text = piece, size = tab_size }
                end
                -- drop lines that are empty in this piece (e.g. lyrics only under the first bars)
                local kept = {}
                for _, item in ipairs(items) do
                    if item.kind == "tab" or item.text:match("%S") then kept[#kept + 1] = item end
                end
                addUnit(kept)
            end
        else
            local max = maxCols(size)
            local lines = block.lines
            local i = 1
            local items = {}
            while i <= #lines do
                local line = lines[i]
                if line.chord then
                    local lyric = lines[i + 1] and not lines[i + 1].chord and not lines[i + 1].tab and lines[i + 1].text or nil
                    for _, piece in ipairs(Layout.wrapPair(line.text, lyric, max)) do
                        if piece.chord then items[#items + 1] = { kind = "chord", text = piece.chord, size = size } end
                        if piece.lyric then items[#items + 1] = { kind = "text", text = piece.lyric, size = size } end
                    end
                    i = i + (lyric and 2 or 1)
                else
                    for _, piece in ipairs(Layout.wrapText(line.text, max)) do
                        items[#items + 1] = { kind = "text", text = piece, size = size }
                    end
                    i = i + 1
                end
            end
            addUnit(items)
        end
    end
    if pending_heading then units[#units + 1] = { pending_heading } end

    -- Fill pages.
    local function height(item)
        if item.kind == "space" then return math.floor(opts.lineHeight(item.size) * 0.6) end
        return opts.lineHeight(item.size)
    end
    local pages = { { items = {} } }
    local used = opts.first_page_offset or 0
    for _, unit in ipairs(units) do
        local h = 0
        for _, item in ipairs(unit) do h = h + height(item) end
        local page = pages[#pages]
        local is_space = #unit == 1 and unit[1].kind == "space"
        if used + h > opts.height and #page.items > 0 then
            if is_space then goto continue end -- no blank space at the top of a page
            pages[#pages + 1] = { items = {} }
            page = pages[#pages]
            used = 0
        end
        if h > opts.height then
            -- taller than a page (very long paragraph): split by lines
            for idx, item in ipairs(unit) do
                local ih = height(item)
                -- a chord line goes to the next page together with its lyrics
                local next_item = unit[idx + 1]
                local need = ih
                if item.kind == "chord" and next_item and next_item.kind == "text" then need = ih + height(next_item) end
                if used + need > opts.height and #page.items > 0 then
                    pages[#pages + 1] = { items = {} }
                    page = pages[#pages]
                    used = 0
                end
                page.items[#page.items + 1] = item
                used = used + ih
            end
        else
            for _, item in ipairs(unit) do page.items[#page.items + 1] = item end
            used = used + h
        end
        ::continue::
    end
    -- no trailing spaces
    for _, page in ipairs(pages) do
        while page.items[#page.items] and page.items[#page.items].kind == "space" do table.remove(page.items) end
    end
    return pages, tab_size
end

Layout.len = len

return Layout
