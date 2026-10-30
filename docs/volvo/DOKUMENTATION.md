# VolvoConnect für FHEM: Installations- und Betriebsdokumentation

Stand: 28.10.2026

## Überblick

VolvoConnect bindet ein Volvo-Fahrzeug über OAuth2 mit PKCE an FHEM an. Das Modul fragt Energie-, Fahrzeug-, Diagnose-, Befehls- und optionale Standortdaten über die Volvo Cars APIs ab. Es stellt zusätzlich Fahrzeugbefehle und ein eigenständiges Dashboard bereit.

Das Modul ist ein Community-Projekt und nicht von Volvo Cars herausgegeben oder unterstützt. API-Felder und Funktionen können je nach Fahrzeugmodell, Baujahr/Modelljahr, Region, Volvo-Anwendung und genehmigten Berechtigungen variieren.

## Inhaltsübersicht und empfohlene Reihenfolge

Für eine neue Installation empfiehlt sich diese Reihenfolge:

1. Voraussetzungen und Zugriff auf das Volvo-Fahrzeug prüfen.
2. Anwendung im Volvo Cars Developer Portal anlegen.
3. API-Zugangsdaten und Redirect-URI sicher erfassen.
4. Modul in FHEM installieren und das Gerät mit den Basisattributen anlegen.
5. Benötigte Datenbereiche und Befehle auswählen.
6. OAuth-Anmeldung durchführen und den Autorisierungscode übertragen.
7. Abruf, Readings, Befehle und Dashboard prüfen.
8. Intervalle, Scopes und Zugriffsrechte auf den tatsächlichen Bedarf reduzieren.

Die Abschnitte sind so aufgebaut, dass sie genau dieser Reihenfolge folgen. Bei einer bestehenden Installation können die Abschnitte zu [Scopes](#api-bereiche-und-scopes), [Betrieb](#betrieb-und-regelmäßige-kontrolle) und [Fehlerbehebung](#fehlerbehebung) direkt verwendet werden.

## Wie das Modul aufgebaut ist

`50_VolvoConnect.pm` ist ein einzelnes FHEM-Perl-Modul. Es besteht funktional aus mehreren Schichten:

1. **FHEM-Gerät und Konfiguration:** `define`, Attribute sowie `set`- und `get`-Befehle bilden die Bedienoberfläche.
2. **OAuth2/PKCE:** Das Modul erzeugt eine Volvo-Anmelde-URL, nimmt den kurzlebigen Autorisierungscode entgegen und tauscht ihn gegen Access- und Refresh-Token.
3. **Tokenverwaltung:** Tokens werden im FHEM-Key-Value-Store gespeichert. Access-Tokens werden bei Bedarf mit dem Refresh-Token erneuert; Tokenwerte werden nicht in Readings ausgegeben.
4. **API-Abruf:** Aktivierte Scopes bestimmen, welche Volvo-Endpunkte abgefragt werden. Die Antworten werden asynchron verarbeitet und in FHEM-Readings abgelegt.
5. **Abrufplanung:** Schnelle, langsame und Standort-Endpunkte haben getrennte Intervalle. Erfolgreiche Abrufe werden pro Endpoint zwischengespeichert, damit Neustarts nicht zu unnötigen Wiederholungen führen.
6. **Befehle:** Fahrzeugaktionen werden nur angeboten beziehungsweise gesendet, wenn der passende Scope aktiviert und die Aktion für Fahrzeug und API verfügbar ist.
7. **Dashboard:** Eine eigenständige FHEM-Webseite gruppiert Readings in Kacheln. Layout, Sichtbarkeit und Labels werden je Gerät gespeichert.

Das Modul ist kein eigener Volvo-Server und ersetzt weder die Volvo-App noch die Volvo-Cloud. FHEM ruft die offiziellen APIs auf; die Verfügbarkeit und Aktualität der Daten wird von Volvo, dem Fahrzeug und der jeweiligen API bestimmt.

## 1. Voraussetzungen

- Eine aktuelle FHEM-Installation
- Perl-Module `JSON`, `MIME::Base64` und `Digest::SHA`; `HttpUtils` gehört zu FHEM
- Volvo ID und ein mit dem Konto verknüpftes Fahrzeug
- Anwendung im [Volvo Cars Developer Portal](https://developer.volvocars.com/)
- VCC API Key, OAuth Client-ID und Client-Secret der Anwendung
- Eine Redirect-URI, die exakt in FHEM und im Developer Portal eingetragen ist

Volvo kann für Anwendungen Test-, Veröffentlichungs- und Regionsbeschränkungen festlegen. Eine lokale URI wie `http://localhost` wird für Tests häufig verwendet, muss aber für die Anwendung im Portal zulässig sein. Das Modul verwendet die manuelle Übergabe des OAuth-Autorisierungscodes; eine öffentlich erreichbare Callback-Seite wird vom Modul nicht bereitgestellt.

### Vor der Installation prüfen

- Die 17-stellige VIN des Fahrzeugs liegt vor. Sie ist nicht die Volvo-ID.
- Das Fahrzeug ist mit der Volvo ID verknüpft, die später im Browser verwendet wird.
- Das FHEM-System kann HTTPS-Verbindungen zu den Volvo-Endpunkten aufbauen.
- Uhrzeit und Zeitzone des FHEM-Systems sind korrekt. Eine stark abweichende Systemzeit kann OAuth- und Tokenprüfungen stören.
- Der FHEM-Benutzer, der das Gerät konfigurieren soll, darf Attribute setzen und `set`/`get`-Befehle ausführen.
- Zugangsdaten werden nicht in öffentliche Git-Repositories, Screenshots oder ungeschützte Backup-Dateien übernommen.

## 2. Anwendung im Volvo Cars Developer Portal einrichten

Die Bezeichnungen und Freigabeprozesse im Portal können sich ändern. Die folgenden Schritte beschreiben den fachlichen Ablauf:

1. Im [Volvo Cars Developer Portal](https://developer.volvocars.com/) anmelden.
2. Im Bereich für Anwendungen eine neue Anwendung anlegen.
3. Einen eindeutigen Namen und die erforderlichen Grunddaten der Anwendung eintragen.
4. Den **VCC API Key** kopieren. Das Modul sendet ihn als `vcc-api-key`-Header an die Fahrzeug-API.
5. **OAuth Client-ID** und **Client-Secret** aus den Zugangsdaten der Anwendung kopieren.
6. Eine Redirect-URI hinterlegen.
7. Die benötigten APIs und Berechtigungen für die Anwendung aktivieren beziehungsweise beantragen.
8. Falls das Portal zwischen Test-, Entwicklungs- und Produktionszugang unterscheidet, zunächst den vorgesehenen Testmodus verwenden.
9. Prüfen, ob die Anwendung für die Volvo ID und das gewünschte Fahrzeug freigeschaltet ist.

### Redirect-URI richtig festlegen

Die Redirect-URI muss im Portal und im FHEM-Attribut **zeichengetreu identisch** sein. Das umfasst:

- `http` oder `https`
- Hostname
- Port
- Pfad
- abschließenden Schrägstrich
- Groß-/Kleinschreibung, sofern der Dienst sie unterscheidet

Für lokale Tests wird häufig `http://localhost` verwendet, sofern Volvo diese URI für die Anwendung akzeptiert. Für einen öffentlich erreichbaren FHEM-Server sollte eine von Volvo akzeptierte HTTPS-URI verwendet werden. Das Modul stellt selbst keinen öffentlichen Callback-Webserver bereit: Nach dem Login wird der Code aus der Weiterleitungs-URL manuell kopiert und in FHEM eingegeben.

### Berechtigungen sparsam planen

Aktiviere im Portal und in FHEM nur die Datenbereiche, die tatsächlich benötigt werden. Weniger Scopes bedeuten eine kleinere Berechtigungsfläche und eine übersichtlichere OAuth-Freigabe. Werden Scopes später geändert, ist eine neue Autorisierung erforderlich.

## 3. Installation

### 3.1 Installation direkt aus GitHub über FHEM

Das Modul kann ohne manuellen Download direkt aus dem GitHub-Repository installiert werden.
Dazu im oberen Eingabefeld des FHEM-Browserfensters folgenden Befehl eingeben:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_volvo.txt
```

Anschließend innerhalb von FHEM ein Update ausführen. FHEM liest dabei die Controls-Datei
ein und lädt die darin aufgeführten Moduldateien in das lokale FHEM-Modulverzeichnis.
Ein manueller Download und das manuelle Kopieren von `50_VolvoConnect.pm` sind bei diesem
Installationsweg nicht erforderlich.

Der Ablauf ist damit:

1. `update add ...` einmalig in der FHEM-Eingabezeile ausführen.
2. Das FHEM-Update innerhalb von FHEM starten.
3. Warten, bis FHEM den Download und die Installation abgeschlossen hat.
4. FHEM neu starten oder das Modul nach der lokalen FHEM-Vorgehensweise neu laden.
5. Mit `list TYPE=VolvoConnect` oder der Gerätekonfiguration prüfen, ob das Modul verfügbar ist.

Bei späteren Modulversionen kann derselbe FHEM-Updateweg erneut verwendet werden. Vor einem
Update sollte die FHEM-Konfiguration gesichert werden. Die GitHub-Adresse muss erreichbar sein;
bei Netzwerk-, TLS- oder Berechtigungsfehlern den FHEM-Log prüfen.

Für die anderen Module stehen eigene Controls-Dateien zur Verfügung:

- `https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_temperaturecollector.txt`
- `https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt`
- `https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt`

Je Modul gibt es ein Änderungsprotokoll (`CHANGED_volvo`, `CHANGED_temperaturecollector`,
`CHANGED_gavazzi`, `CHANGED_solax`, ohne Dateiendung) und ein gemeinsames `CHANGED`. Der
GitHub-Actions-Workflow erzeugt sie bei jedem Push mit `scripts/generate_changed.py` aus den
Git-Commits (Betreff plus Zeilen der Commit-Beschreibung) und trägt das Protokoll des Moduls in
dessen Controls-Datei ein, `CHANGED` in `controls_all.txt`. Dadurch können Änderungen nach
einem FHEM-Update nachvollzogen werden.

### 3.2 Manuelle Installation

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

### Installation aktualisieren

Bei einer neuen Modulversion die Datei ersetzen und anschließend FHEM neu laden oder neu starten. Vorher sollten die aktuelle Konfiguration und die laufende FHEM-Installation gesichert werden. Die Tokens liegen getrennt von den Device-Attributen im Key-Value-Store; eine Modulaktualisierung soll sie normalerweise nicht löschen.

Nach der Installation zuerst `list Volvo1` ausführen und prüfen, ob das Gerät erkannt wird. Bei Perl- oder Syntaxfehlern erscheint ein Eintrag im FHEM-Log; in diesem Fall zunächst die Moduldatei und die installierten Perl-Abhängigkeiten prüfen.

## 4. FHEM-Gerät konfigurieren

### Erforderliche Basisattribute

| Attribut | Inhalt | Hinweis |
|---|---|---|
| `vin` | 17-stellige Fahrzeug-VIN | Nicht mit der Volvo ID verwechseln. |
| `client_id` | OAuth Client-ID | Wert aus der Volvo-Anwendung. |
| `client_secret` | OAuth Client-Secret | Wie ein Passwort behandeln. |
| `vcc_api_key` | VCC API Key | Wird für API-Anfragen benötigt. |
| `redirect_uri` | Exakt registrierte Redirect-URI | Muss mit dem Portal übereinstimmen. |

### Sinnvolle optionale Attribute

```fhem
attr Volvo1 interval 300
attr Volvo1 interval_slow 1800
attr Volvo1 interval_location 900
attr Volvo1 location_reverse_geocode 1
```

Die Standardwerte sind für einen normalen Betrieb vorgesehen. Sehr kurze Intervalle erhöhen die API-Last und können von Volvo begrenzt oder abgelehnt werden.

### Datenbereiche und Befehle auswählen

Die Auswahl kann im FHEM-Webinterface über `get Volvo1 _showEntityConfig` vorgenommen werden. Für automatisierte Konfigurationen können die `scope_*`-Attribute direkt gesetzt werden:

```fhem
attr Volvo1 scope_battery_charge 1-aktiviert
attr Volvo1 scope_odometer 1-aktiviert
attr Volvo1 scope_engine_status 1-aktiviert
attr Volvo1 scope_location 1-aktiviert
attr Volvo1 scope_commands 1-aktiviert
```

Die genaue Schreibweise der vom Modul erwarteten Aktivierungswerte sollte über das Konfigurationsfenster beziehungsweise `get Volvo1 scopes` geprüft werden. Eine Änderung der Scope-Auswahl löscht die bisherige Autorisierung, weil der OAuth-Berechtigungsumfang nicht mehr zum gespeicherten Token passt.

## 5. Anmeldung und Tokens

1. Mit `set Volvo1 reauth` die Anmeldung starten.
2. Den Login-Link am FHEM-Gerätestatus öffnen und bei Volvo anmelden.
3. Nach der Weiterleitung nur den Wert des URL-Parameters `code` kopieren.
4. Den Code zeitnah mit `set Volvo1 authCode <code>` an FHEM übergeben.

Access- und Refresh-Tokens werden im FHEM-Key-Value-Store abgelegt und automatisch erneuert. `get Volvo1 tokenInfo` zeigt Tokenstatus und Gültigkeit, nicht die Tokenwerte. `set Volvo1 reauth` löscht gespeicherte Tokens und startet die Anmeldung erneut.

### Schritt-für-Schritt-Ablauf

```fhem
define Volvo1 VolvoConnect
attr Volvo1 vin <17-stellige-VIN>
attr Volvo1 client_id <Client-ID>
attr Volvo1 client_secret <Client-Secret>
attr Volvo1 vcc_api_key <VCC-API-Key>
attr Volvo1 redirect_uri http://localhost
set Volvo1 reauth
```

1. `reauth` löscht vorhandene Tokens und erzeugt den neuen OAuth-Zustand.
2. Den Login-Link neben dem Gerätestatus öffnen.
3. Mit der Volvo ID anmelden und den Zugriff für die angezeigten Bereiche bestätigen.
4. Nach der Weiterleitung die URL ansehen. Sie enthält beispielsweise:

   `http://localhost/?code=AUTH_CODE_BEISPIEL&state=fhemstate`

5. Nur den Wert zwischen `code=` und dem nächsten `&` kopieren.
6. Den Code sofort in FHEM übertragen:

   ```fhem
   set Volvo1 authCode AUTH_CODE_BEISPIEL
   ```

7. Mit `get Volvo1 summary` und `get Volvo1 tokenInfo` prüfen, ob die Anmeldung erfolgreich war.
8. Mit `set Volvo1 update` den ersten Datenabruf erzwingen.

Der Autorisierungscode ist kurzlebig und nur einmal verwendbar. Bei einem Fehler nicht denselben Code wiederholt verwenden, sondern erneut `reauth` ausführen.

**Sicherheit:** Zugangsdaten, Autorisierungscodes, VIN und Tokenwerte nicht in öffentliche Logs, Screenshots, Tickets oder Repositories übernehmen. Eine Scope-Änderung löscht die vorhandenen Tokens; danach ist eine neue Autorisierung erforderlich.

## 6. API-Bereiche und Scopes

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

## 7. Abrufintervalle und Cache

Die Abfrage wird pro Endpoint geplant. Zeitpunkte erfolgreicher Abrufe werden im FHEM-Key-Value-Store pro Gerät gespeichert und bleiben damit auch nach einem FHEM-Neustart erhalten.

| Klasse | Standardintervall | Endpunkte / Werte |
|---|---:|---|
| Dynamisch (`interval`) | 300 Sekunden | Energie-/Ladestatus, Kilometerstand, Verbrauchsstatistik, Kraftstoff, Warnungen, Bremsen, Türen/Fenster, Motorstatus und Befehlsverfügbarkeit |
| Langsam (`interval_slow`) | 1800 Sekunden | Reifen sowie Motor- und Werkstattdiagnose |
| Standort (`interval_location`) | 900 Sekunden | Standortkoordinaten und Positionszeitpunkt |
| Statisch | einmal je VIN | Fähigkeiten, Befehlsliste und Fahrzeugdetails |

Die Intervalle sind in Sekunden angegeben. Schnellwerte haben mindestens 10 Sekunden, die langsameren Intervalle mindestens 60 Sekunden. Nicht gesetzte Attribute verwenden die Tabellen-Standardwerte. `set <name> update` übergeht den Cache und fordert alle aktivierten Endpunkte sofort an; bereits laufende Requests werden nicht doppelt gestartet. Bei diesem Force-Abruf erhalten auch unveränderte Readings einen neuen FHEM-Zeitstempel. Im normalen Pollzyklus werden identische Werte dagegen nicht erneut geschrieben. Fehlgeschlagene Requests werden nicht als erfolgreich gecacht und beim nächsten fälligen Lauf erneut versucht.

Bei einer Änderung der VIN wird der Endpoint-Cache gelöscht. Änderungen an Scopes benötigen weiterhin eine erneute Volvo-Autorisierung. Ein manuelles `update` lädt auch statische Fahrzeugdetails und erneuert damit die von Volvo nur befristet gültigen Bild-URLs.

## 8. Fahrzeugbefehle

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

Vor sicherheitsrelevanten Befehlen wie `lock`, `unlock`, `horn` oder Klimatisierung die aktuelle Fahrzeug- und API-Verfügbarkeit prüfen. Befehle können wegen Fahrzeugstatus, fehlender Netzverbindung, fehlender Freigabe oder Volvo-seitiger Einschränkungen abgelehnt werden. Nach einem Befehl `command_state` und `last_command` prüfen; eine verzögerte Ausführung ist möglich.

## 9. Dashboard

- `get <name> _dashboardURL` liefert die vollständige Dashboard-URL; alternativ ist es unter `<FHEM-URL>/VolvoConnect/<name>` erreichbar.
- `get <name> _showDashboard` gibt die Dashboard-Seite direkt in FHEM aus.
- Das Dashboard gruppiert verfügbare Readings in Kacheln und bietet Fahrzeugaktionen, Statusanzeigen sowie bei aktivem Standort-Scope eine Karte.
- Das Bearbeiten-Symbol wird nur beim Aufruf mit `get <name> _showDashboard`
  angezeigt. Dort lassen sich Kacheln und Readings ein-/ausblenden sowie
  Labels und Reihenfolgen speichern.
- Die isolierte Ansicht über `_dashboardURL` beziehungsweise
  `<FHEM-URL>/VolvoConnect/<name>` ist nicht editierbar und zeigt keinen
  Bearbeitungsstift.
- Die Vier-Wege-Pfeile schalten den kompakten Verschiebemodus. Dabei bleiben Kachelüberschriften sichtbar; Kacheln lassen sich an ihrer Fläche verschieben. Ein erneuter Klick öffnet alle Kacheln wieder.
- Das Dashboard nutzt ein responsives Mehrspaltenlayout. Die gespeicherte DOM-Reihenfolge wird spaltenweise dargestellt; sie ist keine starre zeilenweise Links-nach-rechts-Anordnung.
- Die Standortkachel zeigt standardmäßig Straße mit Hausnummer, Postleitzahl mit Ort, Bundesland, Land, Breitengrad, Längengrad und Positionszeitpunkt in fester Reihenfolge. Die Karte steht darunter.
- `location_reverse_geocode` ist standardmäßig aktiv. Für neue Koordinaten wird die Adresse über OpenStreetMap Nominatim ermittelt. Mit `attr <name> location_reverse_geocode 0` wird die externe Adressabfrage deaktiviert.
- Das Fahrzeug-Detail-API liefert laut Volvo-Dokumentation eine generische Außen- und Innenbild-URL. Die URLs sind befristet und sollen nicht dauerhaft zwischengespeichert werden.
- Der Fahrzeug-Detail-Endpoint wird aus Gründen der API-Ersparnis nur einmal je VIN geladen. Wenn die Bild-URLs abgelaufen sind, `set <name> update` ausführen, um sie neu abzurufen.

Die Dashboard-Konfiguration wird je Gerät im FHEM-Key-Value-Store abgelegt. Für
`Volvo1` lautet der Schlüssel `VolvoConnect_dashboard_Volvo1`. Um die komplette
Layout-Konfiguration dieses Geräts auf Standard zurückzusetzen:

```fhem
{ setKeyValue("VolvoConnect_dashboard_Volvo1", undef) }
```

Das setzt Reihenfolge, Sichtbarkeit und individuelle Labels zurück, aber keine Tokens oder Device-Attribute.

## Einbettung in FTUI

Für die Einbettung in eine andere Seite liefert die Dashboard-URL mit dem
Parameter `embed=1` nur ein Fragment ohne `<html>`, `<head>` und `<body>`.
Die relative URL ermittelt `get MeinVolvo _dashboardEmbedURL`, sie
lautet zum Beispiel `/fhem/VolvoConnect/MeinVolvo?embed=1`.
Im Embed-Modus ist das Dashboard nicht editierbar. Stil und Skript sind auf das Fragment begrenzt, die Aktualisierung läuft über diese Adresse und nicht über die der einbettenden Seite.

Das Fragment enthält ein Skript. Ein einfaches HTML-Widget, das den Inhalt nur
per `innerHTML` setzt, führt dieses Skript nicht aus. Die folgende Variante
in reinem JavaScript funktioniert in FTUI 1 und FTUI 2, weil sie kein jQuery
benötigt. Sie setzt voraus, dass FTUI und FHEMWEB über denselben Host und Port
erreichbar sind (sonst ist CORS nötig):

```html
<div id="fhem-dashboard"></div>
<script>
  fetch('/fhem/VolvoConnect/MeinVolvo?embed=1', {credentials: 'same-origin'})
    .then(function (r) { return r.text(); })
    .then(function (html) {
      var target = document.getElementById('fhem-dashboard');
      target.innerHTML = '';
      target.appendChild(document.createRange().createContextualFragment(html));
    });
</script>
```

`createContextualFragment` führt die enthaltenen Skripte aus. In FTUI 1 kann
alternativ `$('#fhem-dashboard').load('<URL>')` verwendet werden. Ein `iframe`
mit der normalen `_dashboardURL` funktioniert ebenfalls, benötigt aber eine
feste Höhe und Breite im FTUI-Layout.

Ob die Einbettung in der eigenen FTUI-Installation sauber läuft, hängt vom
verwendeten Widget und Layout ab und sollte dort geprüft werden.

## 10. Readings und Status

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

### Statuswerte

- `authStatus` beziehungsweise `state` zeigt, ob das Gerät authentifiziert, eine Autorisierung erforderlich, beim Token-Refresh, fehlerhaft oder deaktiviert ist.
- `lastUpdate` zeigt den letzten erfolgreichen Datenabruf.
- `lastError` und `lastErrorCode` enthalten den letzten bekannten API-Fehler.
- `command_state` und `last_command` beziehen sich auf den zuletzt gesendeten Fahrzeugbefehl.

Readings werden abhängig von den aktivierten Scopes dynamisch erzeugt. Verschachtelte JSON-Felder erscheinen mit Unterstrichen; vom API gelieferte Einheiten können als zusätzliches `_unit`-Reading erscheinen. Ein fehlendes Reading bedeutet nicht automatisch einen Modulfehler: Der zugehörige Scope, die Fahrzeugunterstützung oder die Volvo-Freigabe kann fehlen.

## 11. Betrieb und regelmäßige Kontrolle

Nach der Ersteinrichtung:

1. `get <name> summary` auf Authstatus und letzten Fehler prüfen.
2. `get <name> scopes` mit der gewünschten Konfiguration vergleichen.
3. `set <name> update` ausführen und die erwarteten Readings kontrollieren.
4. Ein ungefährlicher Lesevorgang, etwa Kilometerstand oder Batteriestand, prüfen.
5. Das Dashboard öffnen und nur benötigte Kacheln aktivieren.
6. Die FHEM-Logs auf wiederkehrende HTTP- oder OAuth-Fehler prüfen.

Bei einem regelmäßigen Betrieb sollten API-Fehler, abgelaufene Zugangsdaten und fehlende Readings nicht ignoriert werden. Die Standortabfrage sollte nur aktiv bleiben, wenn sie benötigt wird. `location_reverse_geocode` kann zusätzlich deaktiviert werden, um keine Koordinaten an den externen Geocoding-Dienst zu übermitteln.

## 12. Backup, Umzug und Zurücksetzen

- Device-Definition, Attribute und die FHEM-Konfiguration regelmäßig sichern.
- Den FHEM-Key-Value-Store in die Backup-Strategie einbeziehen, wenn Tokens und Dashboard-Konfiguration erhalten bleiben sollen.
- Bei einem Umzug des FHEM-Systems müssen die Redirect-URI, Erreichbarkeit und gegebenenfalls die Portal-Konfiguration geprüft werden.
- Nach einem Wechsel der Client-ID, des Client-Secrets, des VCC API Keys oder der Scopes `reauth` ausführen.
- Für eine komplette neue Anmeldung `set <name> reauth` verwenden. Dadurch werden Tokens entfernt, nicht aber die Device-Attribute.
- Für ein Dashboard auf Standard `VolvoConnect_dashboard_<name>` aus dem Key-Value-Store löschen. Das setzt nur Layout, Sichtbarkeit und Labels zurück.

## 13. Abfrageverhalten und Grenzen

- Standardintervall: 300 Sekunden. Das Intervall nicht unnötig stark reduzieren; Volvo begrenzt die API-Aufrufe und einzelne Befehlsendpunkte strenger.
- Die Standort-API liefert den zuletzt bekannten Standort, keine Live-Ortung.
- Welche Readings und Befehle verfügbar sind, hängt von Fahrzeug, API-Berechtigungen und Volvo-seitiger Freigabe ab. Nicht unterstützte Felder können fehlen oder einen Nichtverfügbarkeitswert liefern.
- Volvo nennt für die öffentliche Connected Vehicle API Verfügbarkeits- und Regionsbeschränkungen. Maßgeblich sind die aktuellen Angaben im Developer Portal.

## 14. Fehlerbehebung

### Gerät bleibt bei `auth_required`

1. `client_id`, `client_secret`, `vcc_api_key`, VIN und `redirect_uri` prüfen.
2. Redirect-URI Zeichen für Zeichen mit dem Developer Portal vergleichen.
3. `set <name> reauth` ausführen und einen neuen Code verwenden.
4. Prüfen, ob die Anwendung und die Volvo ID für das Fahrzeug freigeschaltet sind.
5. Nur den `code`-Wert, nicht die komplette Redirect-URL, übergeben.

### OAuth-Code wird abgelehnt

- Der Code wurde möglicherweise bereits verwendet oder ist abgelaufen.
- Es wurde möglicherweise `state` statt `code` kopiert.
- Die Redirect-URI oder Client-Daten stimmen nicht exakt überein.
- Der OAuth-Berechtigungsumfang wurde seit der letzten Autorisierung geändert.

In allen Fällen erneut `reauth` ausführen und den Login-Vorgang vollständig wiederholen.

### Keine oder zu wenige Readings

- Mit `get <name> scopes` prüfen, ob der passende Bereich aktiviert ist.
- Mit `set <name> update` einen Abruf erzwingen.
- Prüfen, ob das Fahrzeug den API-Bereich unterstützt und die Anwendung dafür freigeschaltet ist.
- `get <name> summary` sowie `lastError` und `lastErrorCode` ansehen.
- Bei Diagnose- und Standortdaten die langsameren Intervalle berücksichtigen.

### Daten sind veraltet

- Das Modul liefert bei mehreren Volvo-Endpunkten den zuletzt bekannten Fahrzeugwert.
- Ein erfolgreiches API-Ergebnis ist nicht zwingend eine Live-Messung am Fahrzeug.
- `set <name> update` erzwingt einen neuen Abruf, ändert aber nicht die Aktualisierungsfrequenz des Volvo-Backends.
- Standortdaten sind keine Live-Ortung.

### Fahrzeugbefehl funktioniert nicht

- Den passenden Command-Scope aktivieren und danach erneut autorisieren.
- Die Befehlsverfügbarkeit und `command_state` prüfen.
- Fahrzeugstatus, Mobilfunkverbindung, Ladezustand und regionale Einschränkungen berücksichtigen.
- Nicht unterstützte oder vom Fahrzeug abgelehnte Befehle können nicht durch FHEM erzwungen werden.

### Dashboard zeigt alte Bilder oder falsches Layout

- `set <name> update` lädt Fahrzeugdetails und damit befristete Bild-URLs neu.
- Das Dashboard-Layout wird je Gerät gespeichert und ist unabhängig von Tokens.
- Für einen vollständigen Layout-Reset den Schlüssel `VolvoConnect_dashboard_<name>` aus dem FHEM-Key-Value-Store entfernen.

### FHEM meldet einen Modul- oder Perl-Fehler

- Prüfen, ob die Datei im richtigen `FHEM/`-Verzeichnis liegt.
- FHEM neu starten oder das Modul nach der lokalen FHEM-Vorgehensweise neu laden.
- Die benötigten Perl-Module `JSON`, `MIME::Base64` und `Digest::SHA` installieren beziehungsweise deren Verfügbarkeit prüfen.
- Den vollständigen Fehler aus dem FHEM-Log verwenden, aber Secrets und Tokens vor dem Weitergeben entfernen.

## 15. Sicherheit und Datenschutz

- `client_secret`, VCC API Key, Access-Token, Refresh-Token, Autorisierungscode und vollständige OAuth-URLs vertraulich behandeln.
- VIN und Standortdaten können personenbezogene oder sicherheitsrelevante Informationen sein.
- Das Dashboard und FHEM-Webinterface nur mit geeigneter FHEM-Authentifizierung und sicherem Netzwerkzugang veröffentlichen.
- `location_reverse_geocode 0` verwenden, wenn keine externe Adressauflösung gewünscht ist.
- Keine Zugangsdaten in Git committen. Vor dem Teilen von Logs, `list`-Ausgaben oder Screenshots sensible Werte entfernen.
- Bei Verdacht auf kompromittierte Zugangsdaten die Anwendung im Developer Portal rotieren beziehungsweise widerrufen und anschließend neue Zugangsdaten in FHEM setzen.

## 16. Offizielle Referenzen

- [Volvo Cars Developer Portal](https://developer.volvocars.com/)
- [Connected Vehicle API v2](https://developer.volvocars.com/apis/connected-vehicle/v2/overview/)
- [Volvo API Getting Started](https://developer.volvocars.com/apis/docs/getting-started/)
- [Location API v1](https://developer.volvocars.com/apis/location/v1/overview/)
