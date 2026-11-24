--[[--
Chord names: split them, transpose them, and find a shape (where to put the
fingers) for chords without shapes from Ultimate Guitar. Shapes list the
frets from the low E string to the high e; -1 = not played, 0 = open.
Pure Lua, no KOReader needed.
--]]

local Chords = {}

local SHARPS = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLATS = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
local INDEX = {}
for i, n in ipairs(SHARPS) do INDEX[n] = i - 1 end
for i, n in ipairs(FLATS) do INDEX[n] = i - 1 end
INDEX["H"] = 11 -- German B
INDEX["Cb"], INDEX["Fb"], INDEX["E#"], INDEX["B#"] = 11, 4, 5, 0

--- Split a chord name: "F#m7/C#" -> "F#", "m7", "C#".
function Chords.split(name)
    local root, rest = name:match("^([A-H][#b]?)(.*)$")
    if not root or not INDEX[root] then return nil end
    local quality, bass = rest:match("^(.-)/([A-H][#b]?)$")
    if quality and INDEX[bass] then return root, quality, bass end
    return root, rest, nil
end

--- Transpose a chord name by a number of semitones.
-- @param flats use flats (Bb) instead of sharps (A#)
function Chords.transpose(name, steps, flats)
    local root, quality, bass = Chords.split(name)
    if not root then return name end
    local names = flats and FLATS or SHARPS
    local function move(n) return names[(INDEX[n] + steps) % 12 + 1] end
    return move(root) .. quality .. (bass and ("/" .. move(bass)) or "")
end

--- Do the chords of a song lean towards flats? (decides how to spell transposed chords)
function Chords.prefersFlats(names, key)
    local flats, sharps = 0, 0
    for _, n in ipairs(names) do
        local root = Chords.split(n)
        if root and root:find("b", 2, true) then flats = flats + 1 end
        if root and root:find("#", 2, true) then sharps = sharps + 1 end
    end
    if flats ~= sharps then return flats > sharps end
    return key and key:match("^[A-G]b") ~= nil or false
end

-- Open shapes for the common chords.
local OPEN = {
    C = { -1, 3, 2, 0, 1, 0 }, A = { -1, 0, 2, 2, 2, 0 }, G = { 3, 2, 0, 0, 0, 3 },
    E = { 0, 2, 2, 1, 0, 0 }, D = { -1, -1, 0, 2, 3, 2 },
    Am = { -1, 0, 2, 2, 1, 0 }, Em = { 0, 2, 2, 0, 0, 0 }, Dm = { -1, -1, 0, 2, 3, 1 },
    C7 = { -1, 3, 2, 3, 1, 0 }, A7 = { -1, 0, 2, 0, 2, 0 }, G7 = { 3, 2, 0, 0, 0, 1 },
    E7 = { 0, 2, 0, 1, 0, 0 }, D7 = { -1, -1, 0, 2, 1, 2 }, B7 = { -1, 2, 1, 2, 0, 2 },
    Am7 = { -1, 0, 2, 0, 1, 0 }, Em7 = { 0, 2, 0, 0, 0, 0 }, Dm7 = { -1, -1, 0, 2, 1, 1 },
    Cmaj7 = { -1, 3, 2, 0, 0, 0 }, Fmaj7 = { -1, -1, 3, 2, 1, 0 }, Amaj7 = { -1, 0, 2, 1, 2, 0 },
    Dmaj7 = { -1, -1, 0, 2, 2, 2 }, Gmaj7 = { 3, 2, 0, 0, 0, 2 },
    Asus2 = { -1, 0, 2, 2, 0, 0 }, Asus4 = { -1, 0, 2, 2, 3, 0 }, Dsus2 = { -1, -1, 0, 2, 3, 0 },
    Dsus4 = { -1, -1, 0, 2, 3, 3 }, Esus4 = { 0, 2, 2, 2, 0, 0 }, Cadd9 = { -1, 3, 2, 0, 3, 0 },
}

-- Movable barre shapes, relative to the root fret: root on the low E (E form) or on the A string (A form).
local E_FORM = {
    [""] = { 0, 2, 2, 1, 0, 0 }, m = { 0, 2, 2, 0, 0, 0 }, ["7"] = { 0, 2, 0, 1, 0, 0 },
    m7 = { 0, 2, 0, 0, 0, 0 }, maj7 = { 0, -1, 1, 1, 0, -1 }, sus4 = { 0, 2, 2, 2, 0, 0 },
}
local A_FORM = {
    [""] = { -1, 0, 2, 2, 2, 0 }, m = { -1, 0, 2, 2, 1, 0 }, ["7"] = { -1, 0, 2, 0, 2, 0 },
    m7 = { -1, 0, 2, 0, 1, 0 }, maj7 = { -1, 0, 2, 1, 2, 0 }, sus2 = { -1, 0, 2, 2, 0, 0 },
    sus4 = { -1, 0, 2, 2, 3, 0 },
}
-- other spellings of the same quality
local ALIAS = { M = "", maj = "", min = "m", ["-"] = "m", M7 = "maj7", ["7M"] = "maj7", min7 = "m7", ["-7"] = "m7", sus = "sus4" }

local function barre(form, root_fret)
    local frets = {}
    for i, f in ipairs(form) do frets[i] = f < 0 and -1 or f + root_fret end
    return frets
end

--- A shape for a chord name (the bass of slash chords is ignored).
-- @return { frets = {6}, base = first fret shown, barres = { { fret, from, to } } } or nil
function Chords.shape(name)
    local root, quality = Chords.split(name)
    if not root then return nil end
    quality = ALIAS[quality] or quality
    local plain = (root == "H" and "B" or root) .. quality
    if OPEN[plain] then return Chords.normalize({ frets = OPEN[plain] }) end
    -- open shape under another spelling (Db = C#)
    local n = INDEX[root]
    for spelled, frets in pairs(OPEN) do
        local r, q = Chords.split(spelled)
        if INDEX[r] == n and q == quality then return Chords.normalize({ frets = frets }) end
    end
    -- barre: the lower of the E form (root on low E, fret (n-4)%12) and the A form (root on A, fret (n-9)%12)
    local e_fret, a_fret = (n - 4) % 12, (n - 9) % 12
    if e_fret == 0 then e_fret = 12 end
    if a_fret == 0 then a_fret = 12 end
    local candidates = {}
    if E_FORM[quality] then candidates[#candidates + 1] = { fret = e_fret, frets = barre(E_FORM[quality], e_fret), form = "E" } end
    if A_FORM[quality] then candidates[#candidates + 1] = { fret = a_fret, frets = barre(A_FORM[quality], a_fret), form = "A" } end
    table.sort(candidates, function(a, b) return a.fret < b.fret end)
    local c = candidates[1]
    if not c then return nil end
    local barres = { { fret = c.fret, from = c.form == "E" and 1 or 2, to = 6 } }
    return Chords.normalize({ frets = c.frets, barres = barres })
end

--- Fill in the first fret to show (4 frets window) for a shape.
function Chords.normalize(shape)
    local low, high = nil, 0
    for _, f in ipairs(shape.frets) do
        if f > 0 then
            low = math.min(low or f, f)
            high = math.max(high, f)
        end
    end
    shape.barres = shape.barres or {}
    if not low or high <= 4 then
        shape.base = 1
    else
        shape.base = low
    end
    return shape
end

--- Chord names of a parsed song in the order they first appear.
function Chords.used(model)
    local seen, list = {}, {}
    local function add(name)
        if name and not seen[name] and Chords.split(name) then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    for _, n in ipairs(model.meta.chord_names or {}) do add(n) end
    for _, block in ipairs(model.blocks or {}) do
        for _, line in ipairs(block.lines or {}) do
            if line.chord then
                for token in line.text:gmatch("%S+") do add(token) end
            end
        end
    end
    return list
end

--- Transpose the chord lines of a chord line text, keeping chords above their syllables.
function Chords.transposeLine(text, steps, flats)
    local out, col, pending = {}, 0, 0
    -- pending: how many columns the line got longer so far (taken from following spaces)
    for space, token in text:gmatch("(%s*)(%S+)") do
        local gap = #space
        if pending > 0 then
            local take = math.min(pending, math.max(0, gap - 1))
            gap = gap - take
            pending = pending - take
        end
        local new = Chords.split(token) and Chords.transpose(token, steps, flats) or token
        out[#out + 1] = string.rep(" ", gap) .. new
        local diff = #new - #token
        if diff > 0 then pending = pending + diff
        elseif diff < 0 then
            -- shorter: pad after it so the next chord stays in place
            out[#out + 1] = string.rep(" ", -diff)
        end
    end
    return (table.concat(out):gsub("%s+$", ""))
end

return Chords
