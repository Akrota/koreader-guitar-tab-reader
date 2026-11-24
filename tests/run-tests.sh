#!/bin/zsh
# Runs all Guitar Tab Reader tests on the Mac.
#   KOREADER   path to KOReader.app (the Mac build)
#   KO_HOME    a KOReader home folder for tests; plugins/guitartabreader.koplugin
#              must link to guitartabreader.koplugin
#   OUT        folder for results and screenshots
# The device screenshots use the size of a Kobo Libra Colour (1264 x 1680).
# On macOS the window is doubled (Retina), so half the size is given.
# Without a DPI override KOReader scales by screen size only, so this matches the device.
setopt nullglob
HERE="${0:A:h}"
ROOT="${HERE:h}"
: "${KOREADER:?set KOREADER to KOReader.app}"
: "${KO_HOME:?set KO_HOME to a test home folder}"
: "${OUT:?set OUT to an output folder}"
BIN="$KOREADER/Contents/MacOS/koreader"
TABS="$OUT/tabs"
PDF="$ROOT/test tabs/hallelujah chords.pdf"
mkdir -p "$OUT" "$KO_HOME/patches"

fresh_tabs() {
  rm -rf "${TABS:?}"; mkdir -p "$TABS/pdf"
  cp "$HERE"/testtabs/* "$TABS/"
  [[ "$1" == "pdf" ]] && cp "$PDF" "$TABS/pdf/"
}

# run_ko <patch> [width height]: start KOReader with one test patch, wait until it quits
run_ko() {
  rm -f "${KO_HOME:?}"/patches/*
  cp "$HERE/$1" "$KO_HOME/patches/"
  ( cd "$OUT" && EMULATE_READER_W="${2:-600}" EMULATE_READER_H="${3:-800}" GTR_TABS="$TABS" GTR_SAMPLES="$HERE/ugsamples" KO_HOME="$KO_HOME" GTR_TEST_OUT="$OUT" \
      "$BIN" "$TABS" > "$OUT/ko-${1%.lua}.log" 2>&1 & PID=$!
    for i in $(seq 1 90); do kill -0 $PID 2>/dev/null || break; sleep 1; done
    kill $PID 2>/dev/null )
  rm -f "${KO_HOME:?}"/patches/*
}

echo "== unit tests"
for t in unit_chord.lua unit_chords.lua unit_layout.lua unit_paste.lua; do
  printf "%-18s " "$t"; luajit "$HERE/$t" | tail -1
done

echo "== library, viewer, PDF"
fresh_tabs pdf; run_ko 2-gtr-test.lua
echo "$(grep -c PASS "$OUT/gtr-results.txt") pass"; grep -E "FAIL|ERROR" "$OUT/gtr-results.txt"

echo "== viewer menu"
fresh_tabs pdf; run_ko 2-gtr-menu.lua
cat "$OUT/gtr-menu.txt" | grep -cE "^PASS" | xargs echo "pass:"; grep -E "FAIL" "$OUT/gtr-menu.txt"

echo "== receiver (curl plays the phone)"
fresh_tabs; rm -f "$OUT/receiver-address.txt" "$OUT/curl-done"
rm -f "${KO_HOME:?}"/patches/*; cp "$HERE/2-gtr-receiver.lua" "$KO_HOME/patches/"
( cd "$OUT" && GTR_TABS="$TABS" KO_HOME="$KO_HOME" GTR_TEST_OUT="$OUT" "$BIN" "$TABS" > "$OUT/ko-receiver.log" 2>&1 & )
for i in $(seq 1 40); do [[ -f "$OUT/receiver-address.txt" ]] && break; sleep 0.5; done
BASE=$(sed -n 1p "$OUT/receiver-address.txt"); TOK=$(sed -n 2p "$OUT/receiver-address.txt"); sleep 1
curl -s -m 10 "$BASE/?t=$TOK" > "$OUT/phone-page.html"
curl -s -m 20 -F "files=@$PDF;filename=Song Upload.pdf" "$BASE/add?t=$TOK" > /dev/null
curl -s -m 10 -F "title=Gesendeter Song" -F "artist=Handy Band" -F $'text=[Verse]\nC    G\nEin Test vom Handy' "$BASE/add?t=$TOK" > /dev/null
curl -s -m 10 -F "link=https://example.com/tab/123" "$BASE/add?t=$TOK" > /dev/null
SHARE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 --data-binary "https://example.com/tab/456" "$BASE/share?t=$TOK")
touch "$OUT/curl-done"
for i in $(seq 1 60); do pgrep -f "koreader $TABS" > /dev/null || break; sleep 1; done
rm -f "${KO_HOME:?}"/patches/*
echo "$(grep -c PASS "$OUT/gtr-receiver-results.txt") pass"; grep -E "FAIL|ERROR" "$OUT/gtr-receiver-results.txt"

echo "== private UG module (sample pages; GTR_LIVE=1 adds 2 real requests)"
fresh_tabs; run_ko 2-gtr-ug.lua
echo "$(grep -c PASS "$OUT/gtr-ug.txt") pass"; grep -E "FAIL|ERROR" "$OUT/gtr-ug.txt"

echo "== stage 6: diagrams, chord taps, transpose, fit, auto turning, setlists (device size)"
fresh_tabs pdf; run_ko 2-gtr-stage6.lua 632 840
echo "$(grep -c PASS "$OUT/gtr-stage6.txt") pass"; grep -E "FAIL|ERROR" "$OUT/gtr-stage6.txt"

echo "== screenshots at Kobo Libra Colour size"
fresh_tabs pdf; run_ko 2-gtr-device-shots.lua 632 840
cat "$OUT/shots.txt"
fresh_tabs; run_ko 2-gtr-ui-shots.lua 632 840
cat "$OUT/ui-shots.txt"
