# Guitar Tab Reader

Gitarren-Tabs und Chords auf dem E-Reader, aufbereitet für E-Ink. Ein KOReader-Plugin.

**Stand: Version 0.7.0**

## Was es schon kann

- **Bibliothek:** alle Tabs aus dem Tab-Ordner und seinen Unterordnern, zuletzt gespielte zuerst. Neue Dateien erscheinen automatisch.
- **Formate:**
  - Text-Tabs (`.txt`, `.tab`), zum Beispiel aus dem Browser kopiert
  - ChordPro (`.cho`, `.chopro`, `.chordpro`, `.pro`, `.crd`)
  - das Format von Ultimate Guitar (`[ch]…[/ch]`, `[tab]…[/tab]`)
  - **PDFs aus der Ultimate-Guitar-App** („Save PDF“): Das Plugin liest den Text aus dem PDF und stellt ihn neu dar, mit Chords über der richtigen Silbe, vollständigen Tab-Blöcken, Titel, Interpret, Capo, Tonart und Stimmung. Das erste Öffnen dauert einen Moment, danach kommt der Tab aus dem Zwischenspeicher. Andere PDFs werden als einfacher Text gezeigt.
- **Darstellung** angelehnt an die UG-PDFs:
  - Kopf mit Titel, Interpret (fett), Stimmung, Capo und Tonart
  - Festbreitenschrift, Chords fett, Abschnitte wie [Verse] hervorgehoben
  - Tabs werden nie umgebrochen. Zu breite Tabs werden an Taktstrichen geteilt, mit Saitennamen und Chords an der richtigen Stelle.
  - Chord- und Textzeilen werden gemeinsam umgebrochen, die Chords bleiben über ihrer Silbe.
  - Ein Tab-Block wird nie über zwei Seiten verteilt, auch wenn der Text keine Leerzeilen hat.
- **Blättern:** rechts tippen oder nach links wischen für vor, links tippen oder nach rechts wischen für zurück, Blättertasten.
- **Schriftgröße** über das Menü (☰ oben links). Jeder Tab merkt sich Schriftgröße und letzte Seite.
- **Tabs vom Handy schicken** (ohne Computer):
  - In der Bibliothek ☰ → „Tab hinzufügen (Handy)“. Der E-Reader zeigt einen QR-Code und die Adresse.
  - Auf der Seite kannst du Dateien (PDF, Text, ChordPro, auch mehrere), eingefügten Text oder einen Link schicken. PDFs landen im Unterordner `pdf`. PDFs vom Kurzbefehl werden automatisch in „Interpret - Titel.pdf“ umbenannt.
  - **iPhone-Kurzbefehl „An E-Reader“:** Auf der Seite gibt es einen fertigen Kurzbefehl zum Laden (danach die Adresse darin prüfen) und eine Anleitung zum Selbstbauen. Danach geht es aus der Ultimate-Guitar-App mit „Save PDF → Teilen → An E-Reader“.
  - Tipp: Text, der aus einem PDF kopiert wurde, verliert die Leerzeichen, die Chords rutschen dann zusammen. Schick lieber gleich das PDF. Text aus dem Browser (UG-Webseite) behält die Abstände.
  - Links werden gemerkt und mit dem Ultimate-Guitar-Modul geladen (siehe unten).
  - Der Empfang läuft nur, solange die Bibliothek offen ist, und stoppt im Ruhemodus. Nur Geräte mit dem geheimen Kürzel in der Adresse können etwas schicken.
- **Schriftgröße als Standard:** Im Menü ☰ → „Als Standard setzen“. Tabs, deren Größe du nie extra verstellt hast, folgen dem Standard.
- **Tab-Größe** (Knopf im Menü, schaltet weiter):
  - *nur verkleinern:* Tabs werden etwas kleiner, damit eine Zeile ganz auf den Bildschirm passt.
  - *an Breite anpassen:* Tabs werden größer oder kleiner, bis sie die Breite füllen (höchstens das 1,5-fache der Schrift).
  - *wie Text:* Tabs bleiben in deiner Schriftgröße, lange Zeilen werden an Taktstrichen geteilt.
- **Chord-Diagramme:** Oben auf der ersten Seite stehen die Griffbilder aller Chords des Songs, im Stil der UG-PDFs. Bei Tabs von Ultimate Guitar sind es die Griffe von UG, sonst die üblichen Griffe aus einer eingebauten Tabelle (offene Akkorde und Barré-Griffe). Im Menü an- und abschaltbar.
- **Chord antippen:** Tippst du im Song auf einen Chord, erscheint sein Griffbild groß. Nochmal tippen schließt es.
- **Transponieren:** Im Menü ♭ −1 / ♯ +1, die Mitte setzt auf die Originaltonart zurück. Chords, Tonart und Griffbilder ändern sich mit, Tab-Zahlen nicht. Jeder Tab merkt sich seine Transponierung.
- **Automatisch blättern:** Im Menü Sekunden pro Seite einstellen. Unten steht dann „▶ 30 s“. Blätterst du selbst, beginnt die Zeit von vorn. Am Ende des Songs hört es auf.
- **Tabs löschen:** In der Bibliothek einen Tab gedrückt halten → „Löschen“. Für mehrere auf einmal: „Mehrere auswählen …“ (oder ☰ → „Tabs auswählen und löschen“), Tabs abhaken, dann ☰ → „Ausgewählte löschen“. Vorher kommt immer eine Rückfrage. Gelöscht wird die Datei samt allem, was sich das Plugin dazu gemerkt hat, und der Tab verschwindet aus den Setlisten.
- **Setlisten:** In der Bibliothek einen Tab lange gedrückt halten → „Zu einer Setlist hinzufügen“. Es gibt beliebig viele Setlisten. Unter ☰ → „Setlisten“ kannst du sie abspielen, sortieren, umbenennen und löschen. Auf der letzten Seite eines Songs steht unten der nächste. Weiterblättern öffnet ihn.
- **Gesten / ZenOS:** Aktionen „Guitar Tab Reader: Bibliothek öffnen“, „… Setlisten“, „… Ultimate Guitar durchsuchen“.
- **Ultimate-Guitar-Modul (experimentell):**
  - Einschalten unter Werkzeuge → Guitar Tab Reader → Ultimate Guitar (experimentell) → „Modul eingeschaltet“. Standardmäßig ist es aus.
  - Beim Einschalten kommt ein Hinweis: Das Modul bewegt sich in einer Grauzone und entspricht nicht ganz den Nutzungsbedingungen von Ultimate Guitar. Die Nutzung erfolgt auf eigene Gefahr, und Ultimate Guitar kann den Zugang jederzeit sperren.
  - **Links laden:** Geschickte UG-Links (Handy-Seite oder Kurzbefehl) werden gleich geladen, wenn das Modul an ist. Ältere gemerkte Links lädst du in der Bibliothek über ☰ → „Gemerkte Links laden“.
  - **Suche am E-Reader:** In der Bibliothek ☰ → „Ultimate Guitar durchsuchen“. Es erscheinen nur Gitarren-Chords und -Tabs, keine Pro- oder offiziellen Tabs. Antippen lädt den Tab und öffnet ihn. Die letzte Suche bleibt im Feld stehen, „Leeren“ macht es frei für eine neue.
  - Geladene Tabs landen als Textdatei in `GuitarTabs/ug/` („Interpret - Titel (Chords).txt“) und sind danach offline da. Die Griffbilder der Chords werden mitgespeichert.
  - Es wird immer nur eine Seite nach der anderen geladen, mit Pause dazwischen. Blockiert UG die Anfrage, stoppt das Modul und meldet es.
- **Wie funktioniert das?** Kurze Anleitung als letzter Eintrag unter Werkzeuge → Guitar Tab Reader.
- Deutsch und Englisch.

## Installation

1. Den Ordner `guitartabreader.koplugin` in den `plugins`-Ordner von KOReader kopieren (Kobo: `.adds/koreader/plugins`).
2. KOReader neu starten.
3. Tabs in den Ordner `GuitarTabs` im Hauptverzeichnis legen (Kobo: am Rechner `KOBOeReader/GuitarTabs`). Der Ordner wird angelegt, falls er fehlt, und lässt sich in den Einstellungen ändern.
4. Öffnen über **Werkzeuge → Guitar Tab Reader → Bibliothek öffnen**, oder per Geste: Aktion „Guitar Tab Reader: Bibliothek öffnen“.

## Noch nicht drin

- Strumming Pattern (UG liefert es in einem Format, das noch nicht entschlüsselt ist)
- Bass und Ukulele (Schalter für die Suche)
- Guitar-Pro-Dateien
