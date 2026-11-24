-- Chord names, transposing and shapes (tabreader/chords.lua).
local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/../guitartabreader.koplugin/?.lua;" .. package.path
local C = require("tabreader/chords")
local fail = 0
local function check(n, c) print(c and "PASS" or "FAIL", n); if not c then fail = fail + 1 end end
local function frets(name) local s = C.shape(name); return s and table.concat(s.frets, ",") end

local r, q, b = C.split("F#m7/C#")
check("split F#m7/C#", r == "F#" and q == "m7" and b == "C#")
check("split rejects words", C.split("Intro") == nil and C.split("x") == nil)
check("transpose C +2 = D", C.transpose("C", 2) == "D")
check("transpose Am -3 = F#m (sharps)", C.transpose("Am", -3) == "F#m")
check("transpose Am -3 = Gbm (flats)", C.transpose("Am", -3, true) == "Gbm")
check("transpose G/B +1 = Ab/C (flats)", C.transpose("G/B", 1, true) == "Ab/C")
check("transpose B7 +1 wraps to C7", C.transpose("B7", 1) == "C7")
check("prefers flats for Bb, Eb songs", C.prefersFlats({ "Bb", "Eb", "F" }) and not C.prefersFlats({ "D", "F#m" }))
check("open C", frets("C") == "-1,3,2,0,1,0")
check("open Em7", frets("Em7") == "0,2,0,0,0,0")
check("German H7 = B7", frets("H7") == frets("B7"))
check("F as E-form barre at 1", frets("F") == "1,3,3,2,1,1" and C.shape("F").barres[1].fret == 1)
check("Bm as A-form barre at 2", frets("Bm") == "-1,2,4,4,3,2" and C.shape("Bm").barres[1].from == 2)
check("C#m: A form at 4, shown from fret 4", frets("C#m") == "-1,4,6,6,5,4" and C.shape("C#m").base == 4)
check("Dbm = C#m", frets("Dbm") == frets("C#m"))
check("G#7 via E form at 4", frets("G#7") == "4,6,4,5,4,4")
check("slash chord uses its base chord", frets("D/F#") == frets("D"))
check("unknown quality gives nil, no crash", C.shape("C13b9") == nil)
check("transpose line keeps positions", C.transposeLine("C       G      Am   F", 2) == "D       A      Bm   G")
check("longer names take spaces", C.transposeLine("A    E    D", 1) == "A#   F    D#")
check("shorter names pad", C.transposeLine("F#   C#m  B", 1) == "G    Dm   C")
local model = { meta = {}, blocks = { { lines = { { chord = true, text = "G  Em  C" }, { text = "words" }, { chord = true, text = "G  D/F#" } } } } }
check("chords used, in order, once", table.concat(C.used(model), " ") == "G Em C D/F#")
print(fail == 0 and "ALL PASS" or (fail .. " FAILED"))
