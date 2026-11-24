# Guitar Tab Reader – Änderungen

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
