--[[--
Reads tabs from text into one common model, whatever the source:
plain text tabs (as copied from websites), ChordPro, and Ultimate Guitar's
markup ([ch]…[/ch], [tab]…[/tab]).

Model:
  {
    meta = { title, artist, capo, tuning, key, difficulty },
    blocks = {
      { kind = "section", text = "Verse 1" },
      { kind = "group", lines = { { text, chord = true|nil, tab = true|nil } … }, has_tab = bool },
      { kind = "blank" },
    },
  }
A "group" is a run of lines that belong together and must stay together on
a page: a tab system (chord line, six strings, lyric line under it) or a
chord line with its lyric line. Plain text paragraphs are groups too.
--]]

local Parser = {}

-- Building blocks after the root note: "m7b5", "maj7", "sus4", "add9", "6/9", "7(#9)".
local QUALITY_PARTS = { "maj", "min", "dim", "aug", "sus", "add", "m", "M", "b", "#", "+", "-", "(", ")", "/", "°", "ø" }

local function isQuality(rest)
    while rest ~= "" do
        local digits = rest:match("^%d+")
        if digits then
            rest = rest:sub(#digits + 1)
        else
            local found = false
            for _, part in ipairs(QUALITY_PARTS) do
                if rest:sub(1, #part) == part then
                    rest = rest:sub(#part + 1)
                    found = true
                    break
                end
            end
            if not found then return false end
        end
    end
    return true
end

--- A single chord name: G, Em, F#m7, Bbmaj7, Dsus4, C/G, Asus2/E, N.C.
function Parser.isChord(token)
    if token == "N.C." or token == "NC" then return true end
    local root, rest = token:match("^([A-G][#b]?)(.*)$")
    if not root then return false end
    -- slash chord: bass note after the last "/" (but not "6/9")
    local main, bass = rest:match("^(.-)/([A-G][#b]?)$")
    if main then rest = main end
    return isQuality(rest)
end

--- A line made only of chord names (and spacing, bar marks, repeat hints like "x2").
function Parser.isChordLine(line)
    local chords, others = 0, 0
    for token in line:gmatch("%S+") do
        local clean = token:gsub("^[|(%[]+", ""):gsub("[|)%],.]+$", "")
        if clean == "" or clean:match("^x%d+$") or clean:match("^%d+x$") or clean == "-" or clean == "/" then
            -- spacing marks
        elseif Parser.isChord(clean) then
            chords = chords + 1
        else
            others = others + 1
        end
    end
    return chords > 0 and others == 0
end

--- A tab string line: "e|---3---|", "E |--0--", "B:--1--", "D-----2--|".
function Parser.isTabLine(line)
    local s = line:gsub("^%s+", "")
    if s:match("^[eBGDAEbgda][#b]?%s*[|:]") and s:find("%-%-") then return true end
    -- lines without a string name but clearly tab ("|---3---0---|")
    if s:match("^|[%-%d|hpbr/\\~x%s]+|?$") and select(2, s:gsub("%-", "")) >= 6 then return true end
    return false
end

local function trimRight(s) return (s:gsub("%s+$", "")) end

local function sectionName(line)
    local name = line:match("^%s*%[([^%]]+)%]%s*$")
    if name and not Parser.isChord(name) and not name:lower():match("^/?ch$") and not name:lower():match("^/?tab$") then
        return name
    end
end

-- Header lines like "Capo: 6", "Tuning: E A D G B E", "Key: Db".
local META_KEYS = {
    capo = "capo", tuning = "tuning", key = "key", difficulty = "difficulty",
    tonart = "key", stimmung = "tuning", kapo = "capo",
    artist = "artist", interpret = "artist", title = "title", titel = "title",
}

local function metaLine(line)
    local k, v = line:match("^%s*([%a]+)%s*:%s*(.-)%s*$")
    if k and v ~= "" then
        local field = META_KEYS[k:lower()]
        if field then return field, v end
    end
end

--- Group consecutive non-empty lines; sections and blanks separate groups.
local function buildBlocks(lines, meta, read_meta)
    local blocks, group = {}, nil
    local function flush()
        if group then
            table.insert(blocks, group)
            group = nil
        end
    end
    local header = read_meta
    for _, raw in ipairs(lines) do
        local line = trimRight(raw:gsub("\t", "    "))
        -- (not "header and metaLine(line)": "and" would keep only the first value)
        local field, value
        if header then field, value = metaLine(line) end
        local section = sectionName(line)
        if line == "" then
            flush()
            if blocks[#blocks] and blocks[#blocks].kind ~= "blank" then
                table.insert(blocks, { kind = "blank" })
            end
        elseif field then
            -- "Capo: 6th fret" -> "6"
            if field == "capo" then value = value:match("^(%d+)") or value end
            meta[field] = meta[field] or value
        elseif section then
            header = false
            flush()
            table.insert(blocks, { kind = "section", text = section })
        elseif line:match("^%s*Page %d+%s*/%s*%d+$") then
            -- page footer of a UG PDF, e.g. in text copied from it
            header = false
        else
            header = false
            local entry = { text = line }
            if Parser.isTabLine(line) then
                entry.tab = true
            elseif Parser.isChordLine(line) then
                entry.chord = true
            end
            -- Without blank lines a whole song would be one group (and get cut
            -- anywhere): start a new group at each tab system, so systems stay whole.
            local last = group and group.lines[#group.lines]
            if entry.tab and last and not last.tab then
                -- a new tab system; the chord line right above belongs to it
                local carry = last.chord and table.remove(group.lines) or nil
                if #group.lines == 0 then group = nil end
                flush()
                group = { kind = "group", lines = { carry } }
            elseif entry.chord and group and group.has_tab then
                -- chords after a tab system (and its lyrics) start something new
                flush()
            end
            group = group or { kind = "group", lines = {} }
            if entry.tab then group.has_tab = true end
            table.insert(group.lines, entry)
        end
    end
    flush()
    while blocks[#blocks] and blocks[#blocks].kind == "blank" do table.remove(blocks) end
    while blocks[1] and blocks[1].kind == "blank" do table.remove(blocks, 1) end
    return blocks
end

--- Ultimate Guitar markup: [ch]X[/ch] marks chords (positions are already
-- right in the monospaced text), [tab]…[/tab] wraps lines that belong together.
function Parser.fromUG(content, meta)
    local text = content:gsub("\r", "")
    text = text:gsub("%[ch%](.-)%[/ch%]", "%1")
    text = text:gsub("%[/?tab%]", "")
    return Parser.fromText(text, meta)
end

--- ChordPro: directives in braces, chords inline as [Am].
function Parser.fromChordPro(content, meta)
    meta = meta or {}
    local lines = {}
    local in_tab = false
    for raw in (content:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        local directive, value = raw:match("^%s*{%s*([%w_]+)%s*:?%s*(.-)%s*}%s*$")
        if directive then
            directive = directive:lower()
            if directive == "title" or directive == "t" then meta.title = value
            elseif directive == "artist" or directive == "subtitle" or directive == "st" then meta.artist = meta.artist or value
            elseif directive == "capo" then meta.capo = value
            elseif directive == "key" then meta.key = value
            elseif directive == "tuning" then meta.tuning = value
            elseif directive == "comment" or directive == "c" or directive == "ci" or directive == "comment_italic" then
                table.insert(lines, "[" .. value .. "]")
            elseif directive == "start_of_chorus" or directive == "soc" then
                table.insert(lines, "[" .. (value ~= "" and value or "Chorus") .. "]")
            elseif directive == "start_of_verse" or directive == "sov" then
                table.insert(lines, "[" .. (value ~= "" and value or "Verse") .. "]")
            elseif directive == "start_of_bridge" or directive == "sob" then
                table.insert(lines, "[" .. (value ~= "" and value or "Bridge") .. "]")
            elseif directive == "start_of_tab" or directive == "sot" then in_tab = true
            elseif directive == "end_of_tab" or directive == "eot" then in_tab = false
            elseif directive:match("^end_of_") or directive:match("^eo[cvb]$") then
                table.insert(lines, "")
            end
        elseif raw:match("^%s*#") then
            -- comment line
        elseif in_tab or not raw:find("%[") then
            table.insert(lines, raw)
        else
            -- "[G]Amazing [C]grace" -> chord line + lyric line, chords above their syllable
            local chord_line, lyric = {}, {}
            local col = 0
            local pos = 1
            while pos <= #raw do
                local s, e, chord = raw:find("%[([^%]]+)%]", pos)
                local before = raw:sub(pos, (s or #raw + 1) - 1)
                table.insert(lyric, before)
                col = col + #before:gsub("[\128-\191]", "")
                if not s then break end
                local chord_col = #table.concat(chord_line):gsub("[\128-\191]", "")
                if chord_col > col then
                    -- chords too close together: push the lyric apart
                    local pad = chord_col - col
                    table.insert(lyric, string.rep(" ", pad))
                    col = col + pad
                end
                table.insert(chord_line, string.rep(" ", col - chord_col) .. chord .. " ")
                pos = e + 1
            end
            local lyric_text = table.concat(lyric)
            if lyric_text:match("^%s*$") then
                table.insert(lines, trimRight(table.concat(chord_line)))
            else
                table.insert(lines, trimRight(table.concat(chord_line)))
                table.insert(lines, lyric_text)
            end
        end
    end
    return { meta = meta, blocks = buildBlocks(lines, meta, false) }
end

--- Plain text (and the result of the other converters).
function Parser.fromText(content, meta)
    meta = meta or {}
    local lines = {}
    for raw in (content:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, raw)
    end
    return { meta = meta, blocks = buildBlocks(lines, meta, true) }
end

--- Guess the format of a text and parse it.
-- @param name file name (for the format and as fallback for title/artist)
function Parser.parse(content, name)
    local meta = {}
    -- "Artist - Title.txt"
    local base = (name or ""):gsub("^.*/", ""):gsub("%.[^.]+$", "")
    local artist, title = base:match("^(.-)%s+%-%s+(.+)$")
    local ext = (name or ""):match("%.([%w]+)$")
    ext = ext and ext:lower()
    local model
    if ext == "cho" or ext == "chopro" or ext == "chordpro" or ext == "pro" or ext == "crd"
            or content:match("{%s*title%s*:") or content:match("{%s*t%s*:") then
        model = Parser.fromChordPro(content, meta)
    elseif content:find("[ch]", 1, true) or content:find("[tab]", 1, true) then
        model = Parser.fromUG(content, meta)
    else
        model = Parser.fromText(content, meta)
    end
    model.meta.title = model.meta.title or title or (base ~= "" and base or nil)
    model.meta.artist = model.meta.artist or artist
    return model
end

return Parser
