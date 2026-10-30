# GavazziEM24 – Dokumentation

Diese Anleitung beschreibt die Installation und den Betrieb des logischen
FHEM-Moduls `GavazziEM24` für Carlo-Gavazzi-EM24-DIN-Zähler. Das Modul kann
über Modbus RTU oder Modbus TCP kommunizieren und unterstützt neben dem Lesen
auch Schreibzugriffe auf geeignete Holding-Register.

## Voraussetzungen

- FHEM mit dem Modbus-Toolkit
- Ein Gavazzi EM24 mit erreichbarer Modbus-RTU- oder Modbus-TCP-Verbindung
- Ein FHEM-Modbus-IO-Device und die Geräte-ID des Zählers
- Bei RTU: eine passende serielle Schnittstelle und Baudrate
- Bei TCP: IP-Adresse und Port des nativen TCP-Geräts oder des Gateways

Die Registerkarte folgt dem EM24-DIN Communication Protocol, Version 4,
Revision 0. Unterstützt werden die EM24-DIN-Varianten PFA, PFB und X, soweit
deren Registerbelegung kompatibel ist.

## Installation

Das Modul kann über die Controls-Datei installiert werden:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt
```

Alternativ kann [`70_GavazziEM24.pm`](../../FHEM/70_GavazziEM24.pm) in das
FHEM-Modulverzeichnis kopiert werden.

## IO-Device und Gerät anlegen

### Modbus RTU

Ein passives RTU-Gerät wird typischerweise zusammen mit einem Modbus-IO-Device
angelegt:

```fhem
define GavazziRS485 Modbus /dev/ttyUSB0@9600
define GavazziEM24_1 GavazziEM24
attr GavazziEM24_1 IODev GavazziRS485
```

Für eine abweichende Modbus-ID und explizit passiven Modus kann die Definition
erweitert werden:

```fhem
define GavazziEM24_2 GavazziEM24 2 passive RTU
attr GavazziEM24_2 IODev GavazziRS485
```

Die verwendete Schnittstelle, Baudrate, Geräte-ID und der Polling-Modus müssen
zur konkreten Installation passen.

### Modbus TCP

Bei einem Gavazzi-Zähler mit nativer Modbus-TCP-Schnittstelle oder einem
RTU-zu-TCP-Gateway wird ein TCP-Modbus-IO-Device verwendet:

```fhem
define GavazziTCP Modbus 192.168.1.50:502
define GavazziEM24_TCP GavazziEM24 1 active TCP
attr GavazziEM24_TCP IODev GavazziTCP
```

`192.168.1.50` ist durch die IP-Adresse des Geräts oder Gateways zu ersetzen.
Der TCP-Port ist üblicherweise `502`. Die Slave-ID `1` muss der am EM24
eingestellten Modbus-ID entsprechen. Bei einem RTU-zu-TCP-Gateway bleibt die
Slave-ID des Zählers unverändert; das Gateway übersetzt nur den Transportweg.
Bei einer TCP-Verbindung wird aktives Polling verwendet, da der passive Modus
des Moduls einen seriellen RTU-Bus voraussetzt.

#### RTU-zu-TCP mit `mbusd`

Ein Raspberry Pi kann einen USB-RS485-Adapter mit `mbusd` als Modbus-TCP-
Gateway bereitstellen. Die grundlegenden Schritte sind:

```bash
ls /dev/ttyUSB*
sudo apt update
sudo apt install mbusd -y
sudo nano /etc/mbusd/mbusd.conf
```

Eine typische Konfiguration für einen Adapter unter `/dev/ttyUSB0` und einen
9600-8N1-Bus enthält:

```ini
device = /dev/ttyUSB0
speed = 9600
mode = 8n1
address = 0.0.0.0
port = 502
maxconn = 32
timeout = 60
retries = 3
pause = 100
```

Danach den Dienst neu starten, aktivieren und prüfen:

```bash
sudo systemctl restart mbusd
sudo systemctl enable mbusd
sudo systemctl status mbusd
```

In FHEM wird anschließend die IP-Adresse des Raspberry Pi als Modbus-TCP-
IO-Device verwendet. Das Gateway muss aus dem FHEM-Netz erreichbar sein;
Port `502` darf nicht ungeschützt aus dem Internet erreichbar sein.

## Betriebsarten

Passiv ist der Standardmodus. In diesem Modus aktualisiert das Modul Readings,
wenn ein externer Modbus-Master die entsprechenden Register abfragt. Es werden
Holding Register (Funktion 03) und Input Register (Funktion 04) berücksichtigt.
Register, die niemals vom externen Master gelesen werden, können im passiven
Modus keine Werte liefern.

Für aktives Polling:

```fhem
attr GavazziEM24_1 pollMode active
attr GavazziEM24_1 pollInterval 300
attr GavazziEM24_1 pollIntervalPower 5
```

`pollInterval` steuert den allgemeinen Abruf, `pollIntervalPower` den
separaten Abruf der aktuellen Phasenleistung. Die Intervalle sollten zur
Buslast und zur Anzahl der Modbus-Geräte passen.

## Readings, Registerauswahl und Schreibzugriffe

Typische Readings sind Spannungen (`voltageL1N`, `voltageL2N`,
`voltageL3N`), Ströme (`currentL1`, `currentL2`, `currentL3`) und
Leistungswerte (`activePowerL1`, `activePowerL2`, `activePowerL3`).
Die Messwerte werden in den dokumentierten Einheiten skaliert.

Die Registerauswahl kann über das Attribut `pollRegisters` gesteuert werden,
beispielsweise:

```fhem
attr GavazziEM24_1 pollRegisters i0=1,i2=0,i4=1
```

Die verfügbaren Register und die Standardauswahl sind in der Modulhilfe
dokumentiert.

Die Moduldefinition erzeugt für die Registerkarte entsprechende Holding-
Register-Einträge. Soweit der EM24 das jeweilige Register als schreibbar
definiert, kann der Wert über die generische Modbus-Set-Funktion geändert
werden, beispielsweise:

```fhem
set GavazziEM24_1 demandIntegrationTime 15
set GavazziEM24_1 modbusAddress 2
```

Welche Register tatsächlich geschrieben werden dürfen, hängt vom EM24-Modell
und der Herstellerdokumentation ab. Input-Register (`i...`) und reine
Messwertregister sind nicht schreibbar. Bei Konfigurationsregistern können
zusätzliche Freigaben, ein Parameter-Passwort oder ein Speichervorgang
erforderlich sein. Schreibzugriffe sollten zuerst mit einer gesicherten
Konfiguration und einem unkritischen Testwert geprüft werden.

## Dashboard und Hilfe

```fhem
get GavazziEM24_1 _showDashboard
get GavazziEM24_1 _dashboardURL
get GavazziEM24_1 _showEntityConfig
help GavazziEM24
```

Das Entity-Config-Dialogfenster unterstützt bei der Auswahl der zu
überwachenden Register. Das Dashboard zeigt die verfügbaren Messwerte und
den Verbindungsstatus. Der grüne Statuspunkt für einen aktiven beziehungsweise
ordnungsgemäßen Zustand pulsiert langsam; Fehler-, Offline- und unbekannte
Zustände bleiben rot beziehungsweise neutral. `_dashboardURL` liefert eine
eigenständige Ansicht des Dashboards.

## Einbettung in FTUI

Für die Einbettung in eine andere Seite liefert die Dashboard-URL mit dem
Parameter `embed=1` nur ein Fragment ohne `<html>`, `<head>` und `<body>`.
Die relative URL ermittelt `get GavazziEM24_1 _dashboardEmbedURL`, sie
lautet zum Beispiel `/fhem/GavazziEM24/GavazziEM24_1?embed=1`.
Die Aktualisierung läuft weiterhin über FHEMWEB.

Das Fragment enthält ein Skript. Ein einfaches HTML-Widget, das den Inhalt nur
per `innerHTML` setzt, führt dieses Skript nicht aus. Die folgende Variante
in reinem JavaScript funktioniert in FTUI 1 und FTUI 2, weil sie kein jQuery
benötigt. Sie setzt voraus, dass FTUI und FHEMWEB über denselben Host und Port
erreichbar sind (sonst ist CORS nötig):

```html
<div id="fhem-dashboard"></div>
<script>
  fetch('/fhem/GavazziEM24/GavazziEM24_1?embed=1', {credentials: 'same-origin'})
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

## Feedback

Fragen, Fehlermeldungen und Ideen können als [GitHub-Issue](https://github.com/stapetz/fhem-modules/issues/new/choose) gemeldet werden.
Issues sind öffentlich sichtbar und können von Suchmaschinen gefunden werden. Bitte keine
Passwörter, Tokens, Adressen oder Fahrzeugdaten veröffentlichen; bei Fehlern genügen
Modulversion, FHEM-Version und die betroffene Logzeile.

## Fehlerbehebung und Sicherheit

- Bei fehlenden Werten zuerst IO-Device, serielle Schnittstelle, Baudrate und
  Modbus-ID prüfen.
- Im passiven Modus muss der externe Modbus-Master die gewünschten Register
  tatsächlich abfragen.
- Bei aktivem Polling die Buslast und die Polling-Intervalle prüfen.
- Keine Modbus-Geräte mehrfach mit widersprüchlichen aktiven Polling-Zyklen
  konfigurieren.
- Serielle Geräteknoten und FHEM-Zugriff dürfen nicht ungeschützt öffentlich
  erreichbar sein.
