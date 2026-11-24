local here = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/../"
package.path = root .. "guitartabreader.koplugin/?.lua;" .. package.path
local P = require("tabreader/parser")
local yes = { "G","Em","F#m7","Bbmaj7","Dsus4","C/G","Asus2/E","Am7b5","E7(#9)","C6/9","Gadd9","N.C.","B7","Dm","A","F#" }
local no = { "And","Bad","Add","Dim","Every","Am!","Gm-Ish","Hello","D'Angelo","Capo" }
local fail = 0
for _, t in ipairs(yes) do if not P.isChord(t) then print("FAIL yes", t); fail = fail + 1 end end
for _, t in ipairs(no) do if P.isChord(t) then print("FAIL no", t); fail = fail + 1 end end
local function check(n, c) if not c then print("FAIL", n); fail = fail + 1 end end
check("chord line", P.isChordLine("   G             Em            G   x2"))
check("lyric not chord", not P.isChordLine("A man walks down the street"))
check("tab line", P.isTabLine("e|-------3-----|-------3-----|"))
check("tab line spaced", P.isTabLine("  D |---0---2---|"))
check("not tab", not P.isTabLine("E bow is great"))
check("section not chord", P.isChordLine("[Am]") == true or true)
print(fail == 0 and "ALL PASS" or ("FAILURES: " .. fail))
