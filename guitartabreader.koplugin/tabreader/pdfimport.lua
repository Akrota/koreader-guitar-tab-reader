--[[--
Reads tab PDFs (e.g. "Save PDF" from the Ultimate Guitar app) into the common
model. KOReader's MuPDF gives every word with its position. The song part of
a UG PDF is set in a monospaced font, so a word's x position gives its exact
column: chords land above the right syllable again. The header (title,
artist, details) and the chord diagram labels use other fonts and sizes and
are recognised by that.

Pure functions (reconstruct, parseHeader) work on plain word lists, so they
can be tested without a PDF; read() does the KOReader part.
--]]

local Parser = require("tabreader/parser")

local PdfImport = {}

local function wordLen(word)
    return select(2, word:gsub("[%z\1-\127\194-\244][\128-\191]*", ""))
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

--- Group a page's words into lines (by vertical position), each sorted left to right.
-- @param words list of { word, x0, x1, y0, y1 }
-- @return lines = { { y, words = {…} } }, top to bottom
function PdfImport.toLines(words)
    -- A strict order (a tolerance here would break table.sort); the
    -- tolerance is applied when grouping below.
    table.sort(words, function(a, b)
        if a.y0 ~= b.y0 then return a.y0 < b.y0 end
        return a.x0 < b.x0
    end)
    local lines = {}
    for _, w in ipairs(words) do
        local line = lines[#lines]
        if not line or math.abs(w.y0 - line.y) > 2 then
            line = { y = w.y0, h = w.y1 - w.y0, words = {} }
            lines[#lines + 1] = line
        end
        table.insert(line.words, w)
    end
    for _, line in ipairs(lines) do
        table.sort(line.words, function(a, b) return a.x0 < b.x0 end)
    end
    return lines
end

--- Width of one character of the monospaced song font: from long words, where
-- width / length is reliable.
function PdfImport.charWidth(pages)
    local samples = {}
    for _, lines in ipairs(pages) do
        for _, line in ipairs(lines) do
            for _, w in ipairs(line.words) do
                local n = wordLen(w.word)
                if n >= 8 then samples[#samples + 1] = (w.x1 - w.x0) / n end
            end
        end
    end
    return median(samples)
end

local function isMonoWord(w, cw)
    local n = wordLen(w.word)
    if n == 0 then return false end
    local ratio = (w.x1 - w.x0) / (n * cw)
    return ratio > 0.92 and ratio < 1.08
end

--- Is this line set in the song's monospaced font?
local function isMonoLine(line, cw)
    local mono, total = 0, 0
    for _, w in ipairs(line.words) do
        local n = wordLen(w.word)
        total = total + n
        if isMonoWord(w, cw) then mono = mono + n end
    end
    return total > 0 and mono / total >= 0.6
end

--- Rebuild the song text and collect the header lines.
-- @param pages list of word lists (one per page)
-- @return text, header_lines (strings, page 1 only), chord_width
function PdfImport.reconstruct(pages)
    local page_lines = {}
    for i, words in ipairs(pages) do page_lines[i] = PdfImport.toLines(words) end
    local cw = PdfImport.charWidth(page_lines)
    if not cw then return nil end

    -- Left edge of the song text: the smallest x of monospaced lines.
    local left
    for _, lines in ipairs(page_lines) do
        for _, line in ipairs(lines) do
            if isMonoLine(line, cw) then
                left = math.min(left or math.huge, line.words[1].x0)
            end
        end
    end
    if not left then return nil end

    -- Typical line spacing of the song text: the most common distance between
    -- consecutive monospaced lines (most lines follow each other directly).
    local gaps = {}
    for _, lines in ipairs(page_lines) do
        local prev
        for _, line in ipairs(lines) do
            if isMonoLine(line, cw) then
                if prev and line.y > prev then gaps[#gaps + 1] = line.y - prev end
                prev = line.y
            end
        end
    end
    local step = median(gaps) or 12

    local out, header = {}, {}
    local body_started = false
    for page_no, lines in ipairs(page_lines) do
        local prev_y
        if page_no > 1 and #out > 0 and out[#out] ~= "" then out[#out + 1] = "" end
        for _, line in ipairs(lines) do
            if isMonoLine(line, cw) then
                body_started = true
                -- a larger distance than usual means an empty line in between
                if prev_y and (line.y - prev_y) > step * 1.5 and out[#out] ~= "" then
                    out[#out + 1] = ""
                end
                local chars, col = {}, 0
                for _, w in ipairs(line.words) do
                    local target = math.floor((w.x0 - left) / cw + 0.5)
                    if target > col then
                        chars[#chars + 1] = string.rep(" ", target - col)
                        col = target
                    elseif col > 0 then
                        -- words touching: keep at least one space
                        chars[#chars + 1] = " "
                        col = col + 1
                    end
                    chars[#chars + 1] = w.word
                    col = col + wordLen(w.word)
                end
                out[#out + 1] = table.concat(chars)
                prev_y = line.y
            elseif page_no == 1 and not body_started then
                local words = {}
                for _, w in ipairs(line.words) do words[#words + 1] = w.word end
                header[#header + 1] = table.concat(words, " ")
            end
        end
    end
    while out[#out] == "" do table.remove(out) end
    return table.concat(out, "\n"), header, cw
end

--- Read title, artist, type and details from the header of a UG PDF.
-- "Hallelujah Chords by" / "Jeff Buckley" / "Difficulty: beginner" / "Tuning: E A D G B E" /
-- "Capo: 6th fret" / "Key: Db" / "CHORDS" / "G Em C D B7" / "STRUMMING PATTERN" / "Whole song 70 bpm"
function PdfImport.parseHeader(lines)
    local meta = {}
    local i = 1
    -- title line ends with "<type> by", the artist follows
    while lines[i] do
        local line = lines[i]
        local title, kind = line:match("^(.-)%s+(%a[%a ]-)%s+by$")
        if title then
            meta.title = title
            meta.type = kind
            if lines[i + 1] and not lines[i + 1]:find(":") then meta.artist = lines[i + 1] end
            break
        end
        i = i + 1
    end
    for idx, line in ipairs(lines) do
        local key, value = line:match("^(%a+):%s*(.-)%s*$")
        if key then
            key = key:lower()
            if key == "difficulty" then meta.difficulty = value
            elseif key == "tuning" then meta.tuning = value
            elseif key == "capo" then meta.capo = value:match("^(%d+)") or value
            elseif key == "key" then meta.key = value
            end
        end
        if line:upper() == "CHORDS" and lines[idx + 1] and Parser.isChordLine(lines[idx + 1]) then
            local chords = {}
            for c in lines[idx + 1]:gmatch("%S+") do chords[#chords + 1] = c end
            meta.chord_names = chords
        end
        local bpm = line:match("(%d+)%s*bpm")
        if bpm then meta.bpm = tonumber(bpm) end
    end
    if not meta.title and lines[1] then meta.title = lines[1] end
    return meta
end

local function readPdf(path)
    local DocumentRegistry = require("document/documentregistry")
    local ok, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, path)
    if not ok or not doc then return nil, "open" end
    local pages = {}
    local ok2, err = pcall(function()
        for page = 1, doc:getPageCount() do
            local words = {}
            for _, line in ipairs(doc:getPageTextBoxes(page) or {}) do
                for _, w in ipairs(line) do
                    if w.word and w.word ~= "" then
                        words[#words + 1] = { word = w.word, x0 = w.x0, x1 = w.x1, y0 = w.y0, y1 = w.y1 }
                    end
                end
            end
            pages[#pages + 1] = words
        end
    end)
    doc:close()
    if not ok2 then return nil, err end
    local text, header = PdfImport.reconstruct(pages)
    if not text then
        -- not a monospaced tab PDF: plain text in reading order
        local lines = {}
        for _, words in ipairs(pages) do
            for _, line in ipairs(PdfImport.toLines(words)) do
                local parts = {}
                for _, w in ipairs(line.words) do parts[#parts + 1] = w.word end
                lines[#lines + 1] = table.concat(parts, " ")
            end
            lines[#lines + 1] = ""
        end
        text, header = table.concat(lines, "\n"), {}
    end
    local meta = PdfImport.parseHeader(header)
    local model = Parser.fromText(text, meta)
    model.meta.source = "pdf"
    return model, nil, text
end

--- Read a PDF file into the model (KOReader needed). Never throws: an odd PDF
-- must not take KOReader down.
-- @return model or nil, error, plus the text
function PdfImport.read(path)
    local ok, model, err, text = pcall(readPdf, path)
    if not ok then return nil, tostring(model) end
    return model, err, text
end

return PdfImport
