# Entwicklungsdokumentation (intern)

Diese Datei richtet sich an Entwickler und KI-Agenten, die an diesem Repository arbeiten.
Sie wird **nicht** über FHEM `update` ausgeliefert: `update` lädt nur Dateien, die in einer
`controls_*.txt` stehen, und der Ordner `dev-docs/` steht dort nie. Wer das Repository per
`git clone` holt, bekommt sie allerdings mit.

## Inhalt des Repositories

| Pfad | Zweck |
|---|---|
| `FHEM/` | Moduldateien, werden an Nutzer ausgeliefert |
| `docs/<modul>/` | Nutzerdoku je Modul (`README.md`, `DOKUMENTATION.md`) |
| `controls_<modul>.txt`, `controls_all.txt` | Update-Listen für FHEM, **vom Workflow erzeugt** |
| `CHANGED`, `CHANGED_<modul>` | Änderungsprotokolle, **vom Workflow erzeugt** aus der Git-Historie |
| `scripts/generate_changed.py` | Erzeugt die CHANGED-Dateien (Modulliste `MODULES`) |
| `.github/workflows/update.yml` | Erzeugt controls- und CHANGED-Dateien (Modulliste `modules`) |
| `dev-docs/` | Interne Doku, nicht für Nutzer |

Generierte Dateien (`controls_*.txt`, `CHANGED*`) nie von Hand ändern.

## Branches und Release-Ablauf

- `dev`: Arbeitsstand. Alle Änderungen gehen zuerst hierher. Der Workflow läuft auch auf `dev`
  und erzeugt dort die controls-Dateien.
- `main`: nur freigegebene Stände. Nutzer beziehen von hier.
- Der Entwickler testet mit
  `update all https://raw.githubusercontent.com/stapetz/fhem-modules/dev/controls_all.txt`
  und gibt danach `main` ausdrücklich frei. Ohne Freigabe nie nach `main` pushen.
- Nutzer verwenden `.../main/controls_all.txt` bzw. `controls_<modul>.txt`.

### Update-Befehle in FHEM

Entwicklungsstand (nur für den Entwickler, alle Module):

```
update all https://raw.githubusercontent.com/stapetz/fhem-modules/dev/controls_all.txt
shutdown restart
```

Freigegebener Stand (Nutzer, alle Module):

```
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
shutdown restart
```

Ein einzelnes Modul wird mit `controls_<modul>.txt` statt `controls_all.txt` geholt, z. B.
`.../dev/controls_dashboardhub.txt`. Wer zwischen `dev` und `main` wechselt, bekommt eine Datei
nur, wenn der Zeitstempel in der controls-Datei neuer ist als der lokale Dateistand; sonst die
Datei vorher löschen oder mit `touch -t 202001010000 FHEM/<datei>` zurücksetzen.

### Versionen und Freigabe einzelner Module

Jedes Modul hat eine eigene Version nach Semantic Versioning (`X.Y.Z`: Fehlerbehebung = Z,
neue Funktion = Y, inkompatible Änderung = X). Die Version steht im Quelltext in einer Zeile
`our $VERSION = '1.0.0-dev';` (in den Paketen `GavazziEM24`/`SolaxModbus`) bzw.
`our $<Modul>_VERSION = ...;` (DashboardHub, TemperatureCollector, VolvoConnect). Im Gerät
erscheint sie als Internal `VERSION` (sichtbar in `list <gerät>`, gesetzt beim `define` bzw.
beim FHEM-Start).

- Auf `dev` trägt jede Version das Suffix `-dev`, z. B. `1.1.0-dev`. Daran erkennt man in FHEM,
  dass ein Entwicklungsstand läuft.
- Auf `main` steht nur die freigegebene Version ohne Suffix.
- Der initiale Hauptstand wird einmalig als gemeinsamer Snapshot aller fünf Module auf `1.0.0`
  angelegt; danach starten alle Module auf `dev` bei `1.0.1-dev`. Der bisherige Hauptstand bleibt
  zur Wiederherstellung im Backup-Branch `archive/main-before-versioned-initial-20261030`.
- Module werden **einzeln** freigegeben. `main` bekommt dabei nur die Moduldatei und
  `docs/<modul>/` aus `dev`; andere Module auf `main` bleiben unverändert.
- Der Git-Tag heißt `<modul>-v<version>`, z. B. `dashboardhub-v1.0.0`.

Freigabe (vom Branch `dev` aus, Arbeitsverzeichnis sauber, alles committet und gepusht):

```
python3 scripts/release.py <modul> <version> -m "Zeile 1" -m "Zeile 2" --push
```

`<modul>` ist der Schlüssel aus `MODULES` in `scripts/generate_changed.py` (`volvo`,
`temperaturecollector`, `gavazzi`, `solax`, `dashboardhub`). Die `-m`-Zeilen erscheinen in
`CHANGED`/`CHANGED_<modul>`. Das Skript

1. wechselt auf `main`, übernimmt Moduldatei und Doku aus `dev`, setzt die Version ohne `-dev`,
   committet `Release <Modul> <Version>` und setzt den Tag,
2. wechselt zurück auf `dev` und setzt dort die nächste Entwicklungsversion
   (`<Patch+1>-dev`), z. B. nach `1.0.0` dann `1.0.1-dev`,
3. pusht mit `--push` `main`, den Tag und `dev`. Ohne `--push` bleibt alles lokal.

Der Workflow erzeugt danach auf `main` die controls-Dateien. Gemeinsame Dateien wie die
Hauptzeile in `README.md` müssen bei Bedarf separat nach `main` (z. B. beim ersten Release eines
neuen Moduls), das Skript übernimmt nur Moduldatei und `docs/<modul>/`.

Ablauf bei Freigabe auf Zuruf des Entwicklers („gib <Modul> frei"): Version festlegen (Z, Y
oder X erhöhen), 2–4 Änderungszeilen formulieren, Skript mit `--push` ausführen und dem
Entwickler den passenden `update`-Befehl für `main` nennen.

### Freigabe nach `main` (ganzer Stand, nur in Ausnahmen)

Achtung: Dabei kommen die `-dev`-Versionen nach `main`. Danach pro Modul die Version von Hand
ohne Suffix setzen und Tags anlegen. Normalerweise stattdessen `scripts/release.py` nutzen.

1. `git fetch`, dann `git checkout main && git pull`.
2. `git merge --no-ff dev`. Bei Konflikten in generierten Dateien (`controls_*.txt`,
   `CHANGED*`) die Version von `main` übernehmen (`git checkout --ours <datei>`); der Workflow
   erzeugt sie nach dem Push neu.
3. `git push origin main`, danach zurück auf `dev` und `git merge main`, damit beide Branches
   gleich stehen.
4. Der Workflow läuft auf `main` und erzeugt die controls-Dateien. Erst danach sehen Nutzer das
   Update.

### Wichtige Regeln

- Vor jedem Push `git pull --rebase --autostash`, weil der Workflow eigene Commits
  ("Automated update of controls files [skip ci]") auf dem Branch ablegt.
- Commit-Trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
- Ein neues Modul muss an vier Stellen eingetragen werden: `FHEM/`, `docs/<modul>/`,
  `scripts/generate_changed.py` (`MODULES`) und `.github/workflows/update.yml` (`modules`).
  Zusätzlich Hauptzeile in `README.md` (Tabelle, `update add`-Block, Links).
- Nach einem Push muss der Workflow durchgelaufen sein, bevor FHEM `update` die neue
  Größe/den neuen Zeitstempel in `controls_*.txt` sieht.

## Modulnamen und Dateinamen

FHEM leitet den Typ aus dem Dateinamen ab: `70_SolaxModbus.pm` registriert den Typ
`SolaxModbus`. Der Dateiname muss zum Paket-/Typnamen passen. Die Datei hieß früher
`98_ModbusSolax.pm` und wurde deshalb nie benutzt (Typ `ModbusSolax`). Beim Umbenennen eines
Moduls bleibt die alte Datei bei Nutzern liegen, da `update` nichts löscht.

## Aktualisieren und Testen in FHEM

- Nach `update` ist `shutdown restart` nötig, ein `reload` genügt bei den Modbus-Modulen nicht
  zuverlässig. Danach im Browser hart neu laden (Cmd+Shift+R).
- Häufigste Fehlerquelle bei "keine Änderung": alte Version noch geladen, oder eine zweite
  Datei mit demselben Typ im Verzeichnis `FHEM/`.
- Lokal läuft kein FHEM. Geprüft wird mit `perl -c` (Module, die `HttpUtils` oder `%modules`
  brauchen, brauchen Stubs), mit Perl-Stubs für `Log3`, `AttrVal`, `CallFn`, `getKeyValue` usw.
  und mit Chrome headless gegen einen kleinen Python-Server
  (`--headless=new --virtual-time-budget=4000 --dump-dom`).

## Gemeinsames Dashboard-Design

Alle Dashboards sehen gleich aus. Verbindliche Werte:

- Schrift `14px 'Avenir Next','Helvetica Neue',sans-serif`, Zeilenhöhe 1.4.
- Titel (`h1`): `500 22px Georgia,serif`, Rand `3px 0`, Zeilenhöhe 1.1.
- Kicker (kleine Überschrift): `700 10px 'Helvetica Neue'`, Buchstabenabstand 1.2px.
- Kopfzeile: Höhe 76px (`min-height:76px`, vertikales Padding 0, seitlich 24px), Hintergrund
  `#202e29`.
- Wurzelelement: `max-width:1120px`, mittig, Hintergrund `#1d2825`, Rahmen `#46544c`.
- Seitenrand im Einzelaufruf 12px.
- Die Zeilenhöhe und Schriftgrößen müssen im Wurzelelement selbst gesetzt werden, sonst erbt
  das Dashboard sie von der Host-Seite (FHEMWEB, FTUI) und sieht dort anders aus.
- Bearbeiten: Stift-Symbol im Kopf; ein zweiter Klick speichert (nur bei Änderung). Reihenfolge
  per Drag über das Symbol ☰, keine Pfeile.

Gemessene Abweichungen lassen sich im Hub mit einem Konsolen-Skript auslesen (Position, Breite,
Kopfhöhe, Padding und Schriften je Dashboard); Zoomstufen in Screenshots verfälschen den
Vergleich.

## Einbettbare Dashboards (Fragment-Schnittstelle)

Jedes Modul bietet per `get`:

- `_showDashboard`: HTML direkt in FHEMWEB.
- `_dashboardURL`: vollständige URL der Einzelseite.
- `_dashboardEmbedURL`: relative URL eines Fragments ohne `html/head/body`, z. B.
  `/fhem/GavazziEM24/<dev>?embed=1` (TemperatureCollector: `?tcEmbed=1` oder `embed=1`).

Die Seite wird über `$data{FWEXT}{'/<Typ>'}{FUNC}` ausgeliefert. Wer diese Schnittstelle
bietet und `_dashboardEmbedURL` in der Get-Liste führt, wird vom DashboardHub automatisch
erkannt.

Besonderheiten:

- Volvo scoped sein CSS unter `.vcc-embed` und ersetzt `document.body` im Fragment.
- Gavazzi und Solax starten `setInterval(refresh, 5000)` ohne Aufräumen.
- Die Volvo-Standortkarte besteht aus 3×3 OSM-Kacheln (kein iframe).

## DashboardHub

`FHEM/50_DashboardHub.pm`, Meta-Modul mit Navigation links und Dashboard rechts.

- **Erkennung** (`DashboardHub_Discover`): bei jedem Aufruf alle Geräte in `%defs`. Ein Gerät
  zählt, wenn es nicht `disable` ist, nicht durch `includeDevices`/`excludeDevices` ausgefiltert
  ist, `GetFn` hat, `GetFn(...,'?')` den Eintrag `_dashboardEmbedURL` enthält und der Abruf einen
  Pfad ab `/` liefert. Es gibt keinen Cache. `get <hub> diagnose` zeigt je Gerät den Grund.
- **Anzeige**: ohne iframe. Das Fragment wird per `fetch` geladen und mit
  `createRange().createContextualFragment` eingefügt, damit Skripte laufen. Beim Wechsel werden
  die Timer des vorherigen Dashboards beendet (`window.setInterval` wird umhüllt, Intervalle
  werden mitgeschrieben und gelöscht). Ein Token verwirft veraltete Ladevorgänge. Im Container
  `.dh-content` erzwingt CSS 12px Abstand und volle Breite für `.tc-dashboard`, `.wrap`,
  `.gavazzi-dashboard`, `.solax-dashboard`, `.vcc-embed`.
- **Speichern**: `set <hub> saveConfig <base64-JSON>` per `fetch` mit `fwcsrf`, wie die anderen
  Dashboards (`?cmd=set ...&XHR=1&fwcsrf=...`). Ablage mit `setKeyValue('DashboardHub_config_<name>')`
  als JSON `{order,names,title}`. Namen und Reihenfolge werden beim Speichern bereinigt
  (Duplikate, Trim, maximal 80 Zeichen).
- **Anzeigename**: Alias des Geräts, sonst Gerätename; Überschreiben im Bearbeitungsmodus.
- **Kodierung**: Das Modul gibt UTF-8-Bytes aus. Ergebnisse von `decode_json` sind
  Zeichenketten und müssen vor der HTML-Ausgabe mit `utf8::encode` umgewandelt werden, sonst
  erscheinen Umlaute kaputt.
- **Status**: "Gespeichert" blendet nach 4 Sekunden aus.

## Bekannte Fallstricke

- Wiederholte "keine Änderung"-Meldungen: erst die geladene Version prüfen (siehe oben).
- Media-Queries müssen nach den Basisregeln stehen, sonst werden sie überschrieben (so im
  TemperatureCollector geschehen).
- Zwei Dateien mit demselben Typ in `FHEM/` überschreiben sich.
- Bei Gavazzi/Solax war die Abschnitts-Überschrift (`small` in `*-section-head`) wegen eines
  falschen Selektors (`>small`) nicht gestylt.
- Chrome-Tests: Zum Beenden von Hilfsservern nur selbst endende Prozesse nutzen; `kill`
  und `pkill` sind in der Agent-Umgebung gesperrt.
