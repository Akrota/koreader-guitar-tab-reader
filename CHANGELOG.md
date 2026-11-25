# Changelog – Guitar Tab Reader

*Deutsche Fassung weiter unten.*

## After 0.7.0 (25 Oct 2026, no new version number yet)

**Removed**
- **iPhone shortcut:** it needed a fixed address of the e-reader in the home network. When the router assigned a new one, it stopped working. The phone page still offers files, text and link and is opened with the QR code, so a new address does not matter there. PDFs from the Ultimate Guitar app: save them to "Files" and upload them.

## 0.7.0 (24 Oct 2026)

**New**
- **Delete tabs:** long-press a tab → "Delete" or "Select several …" (tick them, then ☰ → "Delete selected"). Always with a confirmation. Saved state, PDF cache and chord diagrams are deleted too, and the tab disappears from all setlists.
- **Search:** a "Clear" button. The last search stays as before.
- **Font size:** "Reset to default" next to "Set as default".
- **How does it work?** as the last entry under Tools → Guitar Tab Reader.
- Now at the top of the Tools menu.

**Fixed**
- Setlists: changes to the songs of a list got lost if you changed something in the overview afterwards.
- Saved links: a link sent from the phone while others were loading got lost.
- An unusual PDF could crash KOReader.
- Lyrics under split tabs: words are no longer cut at the break.

**Faster**
- After closing a tab, the folder is not scanned again (also between two songs of a setlist).
- PDFs that cannot be read are not retried every time.
- Font size, transposing and tab size draw the page only once.
- Receiving from the phone polls less often (saves battery).

## 0.6.0

Chord diagrams, tap a chord, transposing, tab size "fit to width", automatic page turning, setlists, gesture actions.

## 0.5.0

Ultimate Guitar module (load links, search), "Set as default", shrinking tabs.

## 0.3.x

PDFs from the Ultimate Guitar app, tab blocks without blank lines, shortcut guide.

## 0.2.0

Send tabs from the phone (QR code, shortcut).

## 0.1.0

Library, text tabs, ChordPro and Ultimate Guitar format, view made for e-ink.

---

# Deutsch

## Nach 0.7.0 (25.10.2026, noch ohne neue Versionsnummer)

**Entfernt**
- **iPhone-Kurzbefehl:** Er brauchte eine feste Adresse des E-Readers im Heimnetz. Vergibt der Router eine neue, ging er nicht mehr. Die Handy-Seite bietet weiter Dateien, Text und Link und wird über den QR-Code geöffnet, deshalb stört eine neue Adresse dort nicht. PDFs aus der Ultimate-Guitar-App: in „Dateien“ sichern und dann hochladen.

## 0.7.0 (24.10.2026)

**Neu**
- **Tabs löschen:** Tab gedrückt halten → „Löschen“ oder „Mehrere auswählen …“ (Haken setzen, dann ☰ → „Ausgewählte löschen“). Immer mit Rückfrage. Gemerkter Zustand, PDF-Zwischenspeicher und Griffbilder werden mitgelöscht, der Tab verschwindet aus allen Setlisten.
- **Suche:** Knopf „Leeren“. Die letzte Suche bleibt wie bisher stehen.
- **Schriftgröße:** „Auf Standard zurücksetzen“ neben „Als Standard setzen“.
- **Wie funktioniert das?** als letzter Eintrag unter Werkzeuge → Guitar Tab Reader.
- Steht oben im Werkzeuge-Menü.

**Behoben**
- Setlisten: Änderungen an den Songs einer Liste gingen verloren, wenn man danach in der Übersicht etwas änderte.
- Gemerkte Links: Ein Link, der vom Handy kam, während andere geladen wurden, ging verloren.
- Ein ungewöhnliches PDF konnte KOReader abstürzen lassen.
- Liedtext unter geteilten Tabs: Wörter werden nicht mehr an der Schnittstelle getrennt.

**Schneller**
- Nach dem Schließen eines Tabs wird der Ordner nicht mehr neu durchsucht (auch zwischen zwei Songs einer Setlist).
- PDFs, die sich nicht lesen lassen, werden nicht bei jedem Öffnen neu versucht.
- Schriftgröße, Transponieren und Tab-Größe zeichnen die Seite nur einmal.
- Der Handy-Empfang fragt seltener nach (schont den Akku).

## 0.6.0

Chord-Diagramme, Chord antippen, Transponieren, Tab-Größe „an Breite anpassen“, automatisch blättern, Setlisten, Gesten-Aktionen.

## 0.5.0

Ultimate-Guitar-Modul (Links laden, Suche), „Als Standard setzen“, Tabs verkleinern.

## 0.3.x

PDFs aus der Ultimate-Guitar-App, Tab-Blöcke ohne Leerzeilen, Kurzbefehl-Anleitung.

## 0.2.0

Tabs vom Handy schicken (QR-Code, Kurzbefehl).

## 0.1.0

Bibliothek, Text-Tabs, ChordPro und Ultimate-Guitar-Format, Ansicht für E-Ink.
