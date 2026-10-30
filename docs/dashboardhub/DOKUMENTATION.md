# DashboardHub – Dokumentation

Diese Anleitung beschreibt Installation und Betrieb des Meta-Moduls `DashboardHub`.

## Voraussetzungen

- FHEM mit FHEMWEB
- Mindestens ein Gerät mit Dashboard, z. B. `TemperatureCollector`, `GavazziEM24`,
  `SolaxModbus` oder `VolvoConnect`

## Installation

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_dashboardhub.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_dashboardhub.txt
```

Danach `shutdown restart` ausführen. Alternativ kann
[`50_DashboardHub.pm`](../../FHEM/50_DashboardHub.pm) in das FHEM-Modulverzeichnis
kopiert werden.

## Gerät anlegen

```fhem
define Dashboards DashboardHub
attr Dashboards room Dashboards
```

## Wie Dashboards erkannt werden

DashboardHub prüft alle definierten Geräte. Ein Gerät gilt als Dashboard, wenn sein
Get-Befehl `_dashboardEmbedURL` bekannt ist. Diese Schnittstelle bieten alle
Dashboard-Module dieses Repositories. Künftige Module mit derselben Schnittstelle
werden daher ohne Konfiguration erkannt: Sobald ein entsprechendes Gerät angelegt ist,
erscheint es in der Navigation. Deaktivierte Geräte (`disable 1`) werden ausgelassen.

Mit den Attributen `includeDevices` und `excludeDevices` (reguläre Ausdrücke auf den
Gerätenamen) lässt sich die Auswahl einschränken.

## Anzeige

```fhem
get Dashboards _showDashboard
```

Links steht die Navigation, rechts das gewählte Dashboard. Die Auswahl wird im Browser
gemerkt. Das Dashboard wird ohne iframe direkt in die Seite geladen (Dashboard-Fragment per
`_dashboardEmbedURL`). Beim Wechsel beendet DashboardHub die Aktualisierungs-Timer des
zuvor angezeigten Dashboards. Alle Dashboards erhalten einheitlich 12 px Abstand zum Rand
und nutzen die volle Breite, damit sie nebeneinander gleich aussehen.
Auf schmalen Bildschirmen
wandert die Navigation über das Dashboard.

Weitere Zugriffswege:

| Befehl | Beschreibung |
| --- | --- |
| `get <name> _dashboardURL` | vollständige URL der eigenständigen Ansicht |
| `get <name> _dashboardEmbedURL` | relative URL des Fragments ohne html/head/body, z. B. für FTUI |
| `get <name> list` | erkannte Dashboards in der aktuellen Reihenfolge |
| `get <name> diagnose` | pro Gerät: wird es erkannt, und wenn nicht, warum |

Eigenständige Ansicht und Fragment sind nicht editierbar; bearbeiten lässt sich nur in
`_showDashboard`.

## Menüpunkte bearbeiten

In `_showDashboard` schaltet der Stift oberhalb der Navigation den Bearbeitungsmodus
ein:

- **Name:** Der Standardname ist der `alias` des Geräts (ohne Alias der Gerätename). Im
  Eingabefeld lässt sich ein eigener Name setzen. Ein leeres Feld stellt den Alias
  wieder her.
- **Überschrift:** Die Überschrift der Navigation („Dashboards“) lässt sich ebenfalls
  umbenennen; ein leeres Feld stellt den Standard wieder her.
- **Reihenfolge:** Menüpunkte lassen sich per Ziehen am Symbol ☰ verschieben.
- **Speichern:** Ein erneuter Klick auf den Stift speichert die Änderungen serverseitig
  und beendet den Bearbeitungsmodus. Ohne Änderungen wird nichts gespeichert. Das
  Ergebnis steht unter der Überschrift der Navigation („Gespeichert" bzw. „Fehler: …").

Die Konfiguration wird mit `setKeyValue` gespeichert (nicht in `fhem.cfg`) und gilt
für alle Browser. Neu erkannte Dashboards werden alphabetisch am Ende angefügt.
Entfernte Geräte verschwinden aus der Navigation; ihr gespeicherter Name bleibt erhalten,
falls sie wieder angelegt werden.

## Attribute

| Attribut | Beschreibung |
| --- | --- |
| `includeDevices` | Regex; nur passende Gerätenamen werden berücksichtigt |
| `excludeDevices` | Regex; passende Gerätenamen werden ausgeblendet |
| `navWidth` | Breite der Navigation in Pixel, 120–600, Standard 220 |
| `frameHeight` | Mindesthöhe der Anzeige in Pixel, 300–3000, Standard 800 |

## Set

| Befehl | Beschreibung |
| --- | --- |
| `set <name> saveConfig <base64-json>` | wird vom Bearbeitungsmodus verwendet |

## Fehlerbehebung

- **Keine Dashboards gefunden:** Prüfen, ob das Gerät `get <gerät> _dashboardEmbedURL`
  unterstützt und nicht durch `excludeDevices` oder `disable` ausgeschlossen ist.
- **Dashboard bleibt leer:** Die eigenständige URL des Dashboards direkt im Browser
  öffnen, um Fehler im jeweiligen Modul zu erkennen.
- **Speichern schlägt fehl:** Der Browser muss FHEMWEB mit demselben Host und derselben
  Anmeldung erreichen; ggf. csrfToken bzw. Authentifizierung prüfen.
