# VolvoConnect für FHEM: Installations- und Betriebsdokumentation

Stand: 08.10.2026

## Überblick

VolvoConnect bindet ein Volvo-Fahrzeug über OAuth2 mit PKCE an FHEM an. Das Modul fragt Energie-, Fahrzeug-, Diagnose-, Befehls- und optionale Standortdaten über die Volvo Cars APIs ab. Es stellt zusätzlich Fahrzeugbefehle und ein eigenständiges Dashboard bereit.

Das Modul ist ein Community-Projekt und nicht von Volvo Cars herausgegeben oder unterstützt. API-Felder und Funktionen können je nach Fahrzeugmodell, Baujahr/Modelljahr, Region, Volvo-Anwendung und genehmigten Berechtigungen variieren.

## Voraussetzungen

- Eine aktuelle FHEM-Installation
- Perl-Module `JSON`, `MIME::Base64` und `Digest::SHA`; `HttpUtils` gehört zu FHEM
- Volvo ID und ein mit dem Konto verknüpftes Fahrzeug
- Anwendung im [Volvo Cars Developer Portal](https://developer.volvocars.com/)
- VCC API Key, OAuth Client-ID und Client-Secret der Anwendung
- Eine Redirect-URI, die exakt in FHEM und im Developer Portal eingetragen ist

Volvo kann für Anwendungen Test-, Veröffentlichungs- und Regionsbeschränkungen festlegen. Eine lokale URI wie `http://localhost` wird für Tests häufig verwendet, muss aber für die Anwendung im Portal zulässig sein. Das Modul verwendet die manuelle Übergabe des OAuth-Autorisierungscodes; eine öffentlich erreichbare Callback-Seite wird vom Modul nicht bereitgestellt.

## Installation

1. `50_VolvoConnect.pm` in das FHEM-Modulverzeichnis kopieren, üblicherweise `FHEM/`.
2. FHEM neu starten oder das Modul entsprechend der lokalen FHEM-Verwaltung neu laden.
3. Das Gerät anlegen und Zugangsdaten konfigurieren:

```fhem
define Volvo1 VolvoConnect
attr Volvo1 vin <17-stellige-VIN>
attr Volvo1 client_id <Client-ID>
attr Volvo1 client_secret <Client-Secret>
attr Volvo1 vcc_api_key <VCC-API-Key>
attr Volvo1 redirect_uri http://localhost
attr Volvo1 interval 300
attr Volvo1 interval_slow 1800
attr Volvo1 interval_location 900
```

`define` trägt zunächst Platzhalter ein. Ersetze alle Zugangsdaten, bevor du die Anmeldung startest. Die Redirect-URI muss exakt der im Developer Portal registrierten URI entsprechen.

## Anmeldung und Tokens

1. Mit `set Volvo1 reauth` die Anmeldung starten.
2. Den Login-Link am FHEM-Gerätestatus öffnen und bei Volvo anmelden.
3. Nach der Weiterleitung nur den Wert des URL-Parameters `code` kopieren.
4. Den Code zeitnah mit `set Volvo1 authCode <code>` an FHEM übergeben.

Access- und Refresh-Tokens werden im FHEM-Key-Value-Store abgelegt und automatisch erneuert. `get Volvo1 tokenInfo` zeigt Tokenstatus und Gültigkeit, nicht die Tokenwerte. `set Volvo1 reauth` löscht gespeicherte Tokens und startet die Anmeldung erneut.

**Sicherheit:** Zugangsdaten, Autorisierungscodes, VIN und Tokenwerte nicht in öffentliche Logs, Screenshots, Tickets oder Repositories übernehmen. Eine Scope-Änderung löscht die vorhandenen Tokens; danach ist eine neue Autorisierung erforderlich.

## API-Bereiche und Scopes

Zusätzliche Datenbereiche werden über Attribute aktiviert. Nicht gesetzte `scope_*` Attribute gelten als deaktiviert. Die konkrete Freigabe muss außerdem für die Anwendung im Volvo Developer Portal verfügbar sein.

| Attribut | Datenbereich |
|---|---|
| `scope_capabilities` | Fahrzeugfähigkeiten und unterstützte Energie-Funktionen |
| `scope_warnings` | Fahrzeugwarnungen und Beleuchtungswerte |
| `scope_brakes` | Bremsstatus |
| `scope_doors` | Türen, Verriegelung und zugehörige Daten |
| `scope_windows` | Fensterstatus |
| `scope_engine_status` | Motorstatus (`engineStatus`) |
| `scope_vehicle_relation` | Fahrzeugdaten, Modell, Modelljahr, Bilder und Ausstattung |
| `scope_fuel` | Kraftstoffdaten |
| `scope_battery_charge` | Batterieladung; aktiviert ebenfalls den Abruf des Fuel-Endpunkts |
| `scope_odometer` | Kilometerstand |
| `scope_statistics` | Fahrt- und Verbrauchsstatistik |
| `scope_tyres` | Reifendaten |
| `scope_engine_diagnostics` | Motordiagnose |
| `scope_workshop_diagnostics` | Werkstattdiagnose und Wartungswerte |
| `scope_location` | Standortdaten und Karte |
| `scope_commands` | Verfügbare Fahrzeugbefehle |
| `scope_command_accessibility` | Aktuelle Befehlsverfügbarkeit |
| `scope_honk_flash` | Hupe und Lichtsignal |
| `scope_lock`, `scope_unlock` | Ver- und Entriegeln |
| `scope_climatization` | Klimatisierung starten/stoppen |
| `scope_engine_commands` | Motorbefehle und Vorkonditionierung |

Die Gruppenauswahl lässt sich über `get Volvo1 _showEntityConfig` öffnen. Alternativ können Attribute direkt gesetzt werden, zum Beispiel:

```fhem
attr Volvo1 scope_location 1-aktiviert
attr Volvo1 scope_engine_status 1-aktiviert
```

## Abrufintervalle und Cache

Die Abfrage wird pro Endpoint geplant. Zeitpunkte erfolgreicher Abrufe werden im FHEM-Key-Value-Store pro Gerät gespeichert und bleiben damit auch nach einem FHEM-Neustart erhalten.

| Klasse | Standardintervall | Endpunkte / Werte |
|---|---:|---|
| Dynamisch (`interval`) | 300 Sekunden | Energie-/Ladestatus, Kilometerstand, Verbrauchsstatistik, Kraftstoff, Warnungen, Bremsen, Türen/Fenster, Motorstatus und Befehlsverfügbarkeit |
| Langsam (`interval_slow`) | 1800 Sekunden | Reifen sowie Motor- und Werkstattdiagnose |
| Standort (`interval_location`) | 900 Sekunden | Standortkoordinaten und Positionszeitpunkt |
| Statisch | einmal je VIN | Fähigkeiten, Befehlsliste und Fahrzeugdetails |

Die Intervalle sind in Sekunden angegeben. Schnellwerte haben mindestens 10 Sekunden, die langsameren Intervalle mindestens 60 Sekunden. Nicht gesetzte Attribute verwenden die Tabellen-Standardwerte. `set <name> update` übergeht den Cache und fordert alle aktivierten Endpunkte sofort an; bereits laufende Requests werden nicht doppelt gestartet. Bei diesem Force-Abruf erhalten auch unveränderte Readings einen neuen FHEM-Zeitstempel. Im normalen Pollzyklus werden identische Werte dagegen nicht erneut geschrieben. Fehlgeschlagene Requests werden nicht als erfolgreich gecacht und beim nächsten fälligen Lauf erneut versucht.

Bei einer Änderung der VIN wird der Endpoint-Cache gelöscht. Änderungen an Scopes benötigen weiterhin eine erneute Volvo-Autorisierung. Ein manuelles `update` lädt auch statische Fahrzeugdetails und erneuert damit die von Volvo nur befristet gültigen Bild-URLs.

## Befehle

| Befehl | Wirkung |
|---|---|
| `set <name> update` | Sofortige Datenabfrage starten |
| `set <name> reauth` | Tokens löschen und neue Autorisierung starten |
| `set <name> authCode <code>` | OAuth-Autorisierungscode übergeben |
| `set <name> login` | Aktuelle Login-URL ausgeben, falls vorhanden |
| `set <name> lock` / `unlock` | Fahrzeug verriegeln/entriegeln |
| `set <name> horn` | Hupe betätigen |
| `set <name> climate` / `climate_stop` | Klimatisierung starten/stoppen |
| `set <name> charge_start` / `charge_stop` | Ladevorgang starten/stoppen |
| `set <name> charge_limit <10-100>` | Zielladestand in Prozent setzen |
| `set <name> precondition` | Vorkonditionierung anfordern |

Die API kann Befehle fahrzeug- oder regionsabhängig ablehnen. Eine erfolgreiche Übergabe an die API garantiert nicht, dass das Fahrzeug den Befehl sofort ausführt.

## Dashboard

- `get <name> _dashboardURL` liefert die vollständige Dashboard-URL; alternativ ist es unter `<FHEM-URL>/VolvoConnect/<name>` erreichbar.
- `get <name> _showDashboard` gibt die Dashboard-Seite direkt in FHEM aus.
- Das Dashboard gruppiert verfügbare Readings in Kacheln und bietet Fahrzeugaktionen, Statusanzeigen sowie bei aktivem Standort-Scope eine Karte.
- Das Bearbeiten-Symbol schaltet den Edit-Modus ein. Dort lassen sich Kacheln und Readings ein-/ausblenden sowie Labels und Reihenfolgen speichern.
- Die Vier-Wege-Pfeile schalten den kompakten Verschiebemodus. Dabei bleiben Kachelüberschriften sichtbar; Kacheln lassen sich an ihrer Fläche verschieben. Ein erneuter Klick öffnet alle Kacheln wieder.
- Das Dashboard nutzt ein responsives Mehrspaltenlayout. Die gespeicherte DOM-Reihenfolge wird spaltenweise dargestellt; sie ist keine starre zeilenweise Links-nach-rechts-Anordnung.
- Die Standortkachel zeigt standardmäßig Straße mit Hausnummer, Postleitzahl mit Ort, Bundesland, Land, Breitengrad, Längengrad und Positionszeitpunkt in fester Reihenfolge. Die Karte steht darunter.
- `location_reverse_geocode` ist standardmäßig aktiv. Für neue Koordinaten wird die Adresse über OpenStreetMap Nominatim ermittelt. Mit `attr <name> location_reverse_geocode 0` wird die externe Adressabfrage deaktiviert.
- Das Fahrzeug-Detail-API liefert laut Volvo-Dokumentation eine generische Außen- und Innenbild-URL. Die URLs sind befristet und sollen nicht dauerhaft zwischengespeichert werden.
- Der Fahrzeug-Detail-Endpoint wird aus Gründen der API-Ersparnis nur einmal je VIN geladen. Wenn die Bild-URLs abgelaufen sind, `set <name> update` ausführen, um sie neu abzurufen.

Die Dashboard-Konfiguration wird je Gerät im FHEM-Key-Value-Store abgelegt. Für `Volvo1` lautet der Schlüssel `VolvoConnect_dashboard_Volvo1`. Um die komplette Layout-Konfiguration dieses Geräts auf Standard zurückzusetzen:

```fhem
{ setKeyValue("VolvoConnect_dashboard_Volvo1", undef) }
```

Das setzt Reihenfolge, Sichtbarkeit und individuelle Labels zurück, aber keine Tokens oder Device-Attribute.

## Readings

Die API-Readings werden abhängig von aktivierten Scopes dynamisch erzeugt. Verschachtelte JSON-Felder werden mit Unterstrichen abgeflacht; bei Messwerten mit Einheiten kann ein zusätzliches `_unit` Reading entstehen.

| Präfix / Beispiel | Bedeutung |
|---|---|
| `state_*` | Energie- und Ladezustand, z. B. `state_batteryChargeLevel`, `state_chargingStatus` |
| `capabilities_*` | Unterstützte Funktionen |
| `warnings_*`, `brakes_*`, `doors_*`, `windows_*` | Warnungen und Karosseriestatus |
| `engine_*`, `engineDiagnostics_*`, `workshopDiagnostics_*` | Motor- und Werkstattdiagnose |
| `commands_*`, `commandAccessibility_*` | Fahrzeugbefehle und Verfügbarkeit |
| `fuel_*`, `batteryCharge_*`, `odometer_*`, `statistics_*`, `tyres_*` | Energie-, Fahrt- und Fahrzeugdaten |
| `vehicle_*` | Fahrzeugdetails wie `vehicle_modelYear` und `vehicle_images_exteriorImageUrl` |
| `location_*` | Koordinaten und Reverse-Geocoding-Daten |

`authStatus` beschreibt den Authentifizierungsstatus. `state` kann zusätzlich den Verarbeitungsstatus der letzten Abfrage enthalten. `lastUpdate`, `lastError` und `lastErrorCode` unterstützen die Fehlersuche.

## Abfrageverhalten und Grenzen

- Standardintervall: 300 Sekunden. Das Intervall nicht unnötig stark reduzieren; Volvo begrenzt die API-Aufrufe und einzelne Befehlsendpunkte strenger.
- Die Standort-API liefert den zuletzt bekannten Standort, keine Live-Ortung.
- Welche Readings und Befehle verfügbar sind, hängt von Fahrzeug, API-Berechtigungen und Volvo-seitiger Freigabe ab. Nicht unterstützte Felder können fehlen oder einen Nichtverfügbarkeitswert liefern.
- Volvo nennt für die öffentliche Connected Vehicle API Verfügbarkeits- und Regionsbeschränkungen. Maßgeblich sind die aktuellen Angaben im Developer Portal.

## Fehlerbehebung

- `get <name> summary`: Authstatus, letztes Update, letzten Fehler und letzten Befehl prüfen.
- `get <name> tokenInfo`: Token vorhanden und noch gültig? Es werden keine Tokenwerte ausgegeben.
- `get <name> scopes`: aktivierte und deaktivierte Scopes anzeigen.
- `set <name> update`: sofortige Datenabfrage anstoßen.
- Bei OAuth-Fehlern Client-ID, Client-Secret, VCC API Key und exakt übereinstimmende Redirect-URI prüfen. Sicherstellen, dass die Anwendung die benötigten APIs/Scopes verwenden darf.
- Bei fehlenden Readings den zugehörigen Scope, die Volvo-Freigabe und die Verfügbarkeit für das Fahrzeug prüfen.

## Offizielle Referenzen

- [Volvo Cars Developer Portal](https://developer.volvocars.com/)
- [Connected Vehicle API v2](https://developer.volvocars.com/apis/connected-vehicle/v2/overview/)
- [Volvo API Getting Started](https://developer.volvocars.com/apis/docs/getting-started/)
- [Location API v1](https://developer.volvocars.com/apis/location/v1/overview/)
