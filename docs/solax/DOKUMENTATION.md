# SolaxModbus – Dokumentation

Diese Anleitung beschreibt die Installation und den Betrieb des logischen
FHEM-Moduls `SolaxModbus` für SolaX-X-Hybrid-Wechselrichter.

## Voraussetzungen

- FHEM mit dem Modbus-Toolkit
- Ein über Modbus TCP erreichbarer SolaX X-Hybrid
- IP-Adresse und Port des Wechselrichters
- Die Modbus-Unit-ID des Wechselrichters, häufig `3`
- Das SolaX-Advanced-Passwort, standardmäßig `2014`, falls Schreibbefehle
  verwendet werden

Das Modul wurde mit dem SolaX X-Hybrid SK-SU5000 und der Firmware
`Solax_SI_CH_2nd_20160912_DE02` getestet. Andere Modelle und Firmwarestände
können abweichende Registerbelegungen verwenden.

## Installation

Das Modul kann über die Controls-Datei installiert werden:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt
```

Alternativ kann [`70_SolaxModbus.pm`](../../FHEM/70_SolaxModbus.pm) in das
FHEM-Modulverzeichnis kopiert werden.

Früher hieß die Datei `98_ModbusSolax.pm`. FHEM leitet den Typ aus dem Dateinamen ab, daher
muss sie `70_SolaxModbus.pm` heißen, damit `define … SolaxModbus` funktioniert. Eine alte
`98_ModbusSolax.pm` im Verzeichnis `FHEM` bitte löschen.

## Verbindung und Gerät anlegen

Das Modul kann eine direkte TCP-Verbindung verwenden:

```fhem
define SolaxWR SolaxModbus 3 10 192.168.178.21:502 TCP
attr SolaxWR room Energie
attr SolaxWR password 2014
```

Die Parameter sind Unit-ID, Polling-Intervall in Sekunden sowie optional
`host:port TCP`.

Alternativ kann ein vorhandenes physisches Modbus-IO-Device verwendet werden:

```fhem
define SolaxTCP Modbus 192.168.178.21:502
define SolaxWR SolaxModbus 3 10
attr SolaxWR IODev SolaxTCP
```

Prüfe anschließend im FHEM-Log, ob die Verbindung hergestellt wird und der
Status des Geräts nicht `disconnected` oder `timeout` ist.

## Polling und Readings

Das Standardintervall wird beim `define` festgelegt und kann zur Laufzeit
geändert werden:

```fhem
set SolaxWR interval 10
```

Wichtige Readings sind `gridVoltage`, `gridCurrent`, `acPower`, `pv1Power`,
`pv2Power`, `batterySOC`, `batteryPower`, `inverterStatus`, `inverterFault`,
`gridMeterPower`, `energyFeedInTotal`, `energyConsumedTotal`, `energyToday`
und `energyTotal`. Die Werte werden anhand der Registerdefinition skaliert
und mit Einheiten versehen.

## Schreibbefehle

Für Änderungen am Wechselrichter stehen unter anderem folgende Befehle zur
Verfügung:

```fhem
set SolaxWR workMode Self-Use
set SolaxWR minSoc 20
set SolaxWR gridExportLimit 5000
set SolaxWR batteryChargeMaxCurrent 20
set SolaxWR forceCharge on
```

Weitere Zeitfenster-Befehle sind
`forceChargeStartHour`, `forceChargeStartMinute`,
`forceChargeEndHour`, `forceChargeEndMinute`,
`forceDischargeStartHour`, `forceDischargeStartMinute`,
`forceDischargeEndHour` und `forceDischargeEndMinute`.
Vor jedem Schreibzugriff wird das konfigurierte Advanced-Passwort verwendet.

## Dashboard und Hilfe

```fhem
get SolaxWR _showDashboard
get SolaxWR _dashboardURL
help SolaxModbus
```

Das Dashboard zeigt unter anderem PV-Leistung, Batteriefluss, Netzfluss und
den Verbindungsstatus. Bei einer aktiven Modbus-Verbindung pulsiert der grüne
Statuspunkt langsam. Fehler- und unbekannte Zustände werden nicht als
verbundener Status dargestellt. Die eigenständige URL-Ansicht ist über
`get SolaxWR _dashboardURL` verfügbar und dient der Anzeige ohne
Bearbeitungsfunktion.

## Einbettung in FTUI

Für die Einbettung in eine andere Seite liefert die Dashboard-URL mit dem
Parameter `embed=1` nur ein Fragment ohne `<html>`, `<head>` und `<body>`.
Die relative URL ermittelt `get SolaxWR _dashboardEmbedURL`, sie
lautet zum Beispiel `/fhem/SolaxModbus/SolaxWR?embed=1`.
Die Aktualisierung läuft weiterhin über FHEMWEB.

Das Fragment enthält ein Skript. Ein einfaches HTML-Widget, das den Inhalt nur
per `innerHTML` setzt, führt dieses Skript nicht aus. Die folgenden Beispiele setzen voraus, dass FTUI und FHEMWEB über denselben Host und Port
erreichbar sind (sonst ist CORS nötig).

### FTUI 1 (fhem-tablet-ui, mit jQuery)

Ein Container, in den das Fragment per jQuery geladen wird. Eingebundene Skripte werden dabei
ausgeführt:

```html
<div id="fhem-dashboard"></div>
<script>
  $('#fhem-dashboard').load('/fhem/SolaxModbus/SolaxWR?embed=1');
</script>
```

Alternativ ohne jQuery, auch in FTUI 1 lauffähig:

```html
<div id="fhem-dashboard"></div>
<script>
  fetch('/fhem/SolaxModbus/SolaxWR?embed=1', {credentials: 'same-origin'})
    .then(function (r) { return r.text(); })
    .then(function (html) {
      var target = document.getElementById('fhem-dashboard');
      target.innerHTML = '';
      target.appendChild(document.createRange().createContextualFragment(html));
    });
</script>
```

Der Code kann direkt in die FTUI-Seite oder in das FTUI-HTML-Widget kopiert werden, sofern
dieses Skripte ausführt. Ein Widget, das den Inhalt nur per `innerHTML` setzt, führt sie nicht
aus, dann bleibt nur der `iframe`:

```html
<iframe src="/fhem/SolaxModbus/SolaxWR" style="width:100%;height:900px;border:0"></iframe>
```

### FTUI 2 (ohne jQuery)

```html
<div id="fhem-dashboard"></div>
<script type="module">
  const response = await fetch('/fhem/SolaxModbus/SolaxWR?embed=1', {credentials: 'same-origin'});
  const target = document.getElementById('fhem-dashboard');
  target.replaceChildren(document.createRange().createContextualFragment(await response.text()));
</script>
```

Der `iframe` aus dem FTUI-1-Beispiel funktioniert auch in FTUI 2.

Die Beispiele wurden nicht in einer FTUI-Installation getestet. Passen Sie die Adresse bei
abweichendem FHEMWEB-Pfad oder Port an; `get SolaxWR _dashboardEmbedURL` liefert den
richtigen relativen Pfad.

## Feedback

Fragen, Fehlermeldungen und Ideen können als [GitHub-Issue](https://github.com/stapetz/fhem-modules/issues/new/choose) gemeldet werden.
Issues sind öffentlich sichtbar und können von Suchmaschinen gefunden werden. Bitte keine
Passwörter, Tokens, Adressen oder Fahrzeugdaten veröffentlichen; bei Fehlern genügen
Modulversion, FHEM-Version und die betroffene Logzeile.

## Hinweise

- Vor der Einrichtung muss die Modbus-TCP-Schnittstelle des Wechselrichters
  erreichbar und aktiviert sein.
- Unit-ID und Registerbelegung müssen zum Wechselrichter und Firmwarestand
  passen.
- Schreibbefehle sollten zunächst mit konservativen Grenzwerten getestet
  werden.
- Netzwerk- und Gerätefehler sind im FHEM-Log zu prüfen.
- Das Advanced-Passwort und Netzwerkzugangsdaten gehören nicht in öffentliche
  Konfigurationsdateien.
