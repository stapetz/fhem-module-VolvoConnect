# TemperatureCollector – Dokumentation

## Zweck

`TemperatureCollector` ist ein Meta-Modul. Es legt keine eigenen Sensoren an,
sondern durchsucht den globalen FHEM-Gerätebestand automatisch nach numerischen
Readings, deren Name `temperature` oder `temp` enthält. Dadurch können
Thermometer verschiedener FHEM-Module gemeinsam dargestellt werden.

Zusätzlich werden passende Feuchte-Readings mit Namen wie `humidity` oder
`feuchte` erkannt. Die Werte werden nur gelesen; die Quellgeräte werden nicht
verändert.

## Voraussetzungen

- Eine aktuelle FHEM-Installation mit FHEMWEB
- Mindestens ein definiertes Gerät mit einem numerischen Temperatur-Reading
- Optional ein konfiguriertes `DbLog`-Gerät für historische Verläufe

## Installation

### Installation über FHEM

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_temperaturecollector.txt
```

Danach ein FHEM-Update ausführen und prüfen, ob
`50_TemperatureCollector.pm` im FHEM-Modulverzeichnis liegt.

### Manuelle Installation

Die Datei
[`50_TemperatureCollector.pm`](../../FHEM/50_TemperatureCollector.pm) nach
`FHEM/` kopieren und FHEM neu starten oder das Modul nach der lokalen
FHEM-Vorgehensweise neu laden.

## Gerät anlegen

```fhem
define TemperatureOverview TemperatureCollector
attr TemperatureOverview room Klima
```

Das Modul benötigt keine Sensorliste und keine manuelle Zuordnung. Nach dem
Anlegen werden Geräte bei jedem Dashboard-Aufruf neu erkannt.
Für die Anzeige wird das FHEM-Attribut `alias` verwendet. Ist kein Alias
gesetzt, zeigt das Dashboard den technischen Gerätenamen an. Der FHEM-Gerätetyp
wird nicht dargestellt.

In der Mitte der Kopfzeile zeigt eine analoge Uhr mit Sekundenzeiger die
aktuelle Browserzeit. Daneben wird das aktuelle Datum angezeigt. Die Uhr wird
unabhängig von der Dashboard-Datenaktualisierung jede Sekunde aktualisiert.

Mit dem Stift-Symbol im Dashboard kann die Reihenfolge der Sensorkarten
bearbeitet werden. Nach dem Aktivieren des Editiermodus lassen sich die Karten
per Drag-and-drop verschieben. Die Reihenfolge wird je TemperatureCollector
serverseitig im FHEM-Key-Value-Speicher gespeichert und ist dadurch auf
anderen Browsern und Geräten identisch. Neu erkannte Geräte werden automatisch
am Ende angefügt. Der aktivierte Editiermodus bleibt auch bei einer automatischen
Dashboard-Aktualisierung aktiv. Beim Verschieben an den oberen oder unteren
Bildschirmrand scrollt die Seite automatisch mit.

Der Stift wird nur bei `get TemperatureOverview _showDashboard` angezeigt.
In der isolierten Ansicht über `_dashboardURL` ist die Sensor-Sortierung
deaktiviert. Der Wechsel zwischen Listen- und Kachelansicht bleibt dort
verfügbar.

Während des Editiermodus wird die automatische Dashboard-Aktualisierung
pausiert, damit das Verschieben nicht durch einen Hintergrund-Refresh
unterbrochen wird. Nach dem Beenden des Editiermodus läuft `autoRefresh`
automatisch weiter. Die Uhr in der Kopfzeile läuft unabhängig davon weiter.

Über den Ansichts-Schalter kann zwischen der Kachelansicht im Grid und einer
einspaltigen Listenansicht gewechselt werden. Die Auswahl wird je
TemperatureCollector im Browser gespeichert.

Der Reading-Name wird standardmäßig unter dem Alias angezeigt. Mit diesem
Attribut kann er ausgeblendet werden:

```fhem
attr TemperatureOverview showReadingName 0
```

Zur erneuten Anzeige:

```fhem
attr TemperatureOverview showReadingName 1
```

## Dashboard öffnen

```fhem
get TemperatureOverview _showDashboard
```

Alternativ kann mit `get TemperatureOverview _dashboardURL` die URL für eine
eigenständige FHEMWEB-Ansicht ermittelt werden. Jede erkannte Temperatur wird
als Karte angezeigt. Durch Aufklappen einer Karte erscheinen, sofern DbLog
verfügbar ist, ein Verlauf und eine Tabelle der letzten Messwerte.

## Einbettung in FTUI

Für die Einbettung in eine andere Seite liefert die Dashboard-URL mit dem
Parameter `embed=1` (alternativ `tcEmbed=1`) nur ein Fragment ohne `<html>`, `<head>` und `<body>`.
Die relative URL ermittelt `get TemperatureOverview _dashboardEmbedURL`, sie
lautet zum Beispiel `/fhem/TemperatureCollector/TemperatureOverview?embed=1`.
Aktualisierung und Nachladen der Diagramme laufen im Embed-Modus immer über
diese Adresse und nicht über die Adresse der einbettenden Seite.

Das Fragment enthält ein Skript. Ein einfaches HTML-Widget, das den Inhalt nur
per `innerHTML` setzt, führt dieses Skript nicht aus. Die folgende Variante
in reinem JavaScript funktioniert in FTUI 1 und FTUI 2, weil sie kein jQuery
benötigt. Sie setzt voraus, dass FTUI und FHEMWEB über denselben Host und Port
erreichbar sind (sonst ist CORS nötig):

```html
<div id="tc-dashboard"></div>
<script>
  fetch('/fhem/TemperatureCollector/TemperatureOverview?embed=1', {credentials: 'same-origin'})
    .then(function (r) { return r.text(); })
    .then(function (html) {
      var target = document.getElementById('tc-dashboard');
      target.innerHTML = '';
      target.appendChild(document.createRange().createContextualFragment(html));
    });
</script>
```

`createContextualFragment` führt die enthaltenen Skripte aus. In FTUI 1 kann
alternativ `$('#tc-dashboard').load('<URL>')` verwendet werden. Ein `iframe`
mit der normalen `_dashboardURL` funktioniert ebenfalls, benötigt aber eine
feste Höhe und Breite im FTUI-Layout.

Ob die Einbettung in der eigenen FTUI-Installation sauber läuft, hängt vom
verwendeten Widget und Layout ab und sollte dort geprüft werden.

## Automatische Erkennung

Erkannt werden ausschließlich numerische Readings mit dem exakt passenden
Namen `temperature`. Zusammengesetzte oder technische Readings wie
`pvbTemperatureFaultValue`, `temperatureOutdoor` und `measured-temp` werden
nicht als Außentemperatur übernommen.

Ein Gerät wird nur aufgenommen, wenn es ein passendes `temperature`-Reading
besitzt. Feuchte-Readings werden optional anhand
von `humidity` oder `feuchte` im Namen ergänzt. Werte mit oder ohne
angehängtes Prozentzeichen werden unterstützt.
Für die Anzeige werden ausschließlich die numerischen `VAL`- beziehungsweise
DbLog-Werte verwendet; `°C` und `%` ergänzt das Dashboard selbst.

Nichtnumerische Werte, zum Beispiel `unknown`, werden nicht dargestellt.
Interne Readings wie `inttemp`, Batterie-, Board-, Inverter-, CPU- oder
Motor-Temperaturen werden standardmäßig nicht als Raumthermometer gewertet.
Auch Sollwerte wie `desired-temp` sowie Charger-/Boost-/Setpoint-/Alarm-
Temperaturen werden ausgeschlossen. Das typische Thermostat-Reading
`measured-temp` wird ebenfalls nicht als eigenständiges Thermometer
aufgenommen.

Mit `includeDevices` kann die Erkennung auf eine feste Geräteliste begrenzt
werden:

```fhem
attr TemperatureOverview includeDevices Wohnzimmer,Schlafzimmer
```

Alternativ können einzelne Geräte ausgeschlossen werden:

```fhem
attr TemperatureOverview excludeDevices Shelly_Gartenhaus,SolaxWR
```

Die Listen enthalten durch Komma getrennte FHEM-Gerätenamen. Eine gesetzte
`includeDevices`-Liste beschränkt die Auswahl; `excludeDevices` wird zusätzlich
angewendet und kann auch ein enthaltenes Gerät ausblenden.

## DbLog-Historie

Ohne Konfiguration verwendet das Modul das erste definierte Gerät vom Typ
`DbLog`. Falls mehrere DbLog-Geräte vorhanden sind, kann eines ausdrücklich
festgelegt werden:

```fhem
attr TemperatureOverview dbLog myDbLog
```

Der Abfragezeitraum wird in Stunden konfiguriert:

```fhem
attr TemperatureOverview historyHours 48
```

Das Modul verwendet die FHEM-interne DbLog-Schnittstelle und fragt nur die
Historie des jeweils erkannten Temperatur-Readings ab. Es führt keine eigenen
SQL-Abfragen aus und ändert keine Datenbankeinträge.

Wenn kein DbLog-Gerät existiert oder ein Reading nicht protokolliert wird,
bleibt die aktuelle Temperatur sichtbar; für dieses Gerät wird lediglich kein
historischer Verlauf angezeigt.

## Messwerttabelle

Die Verlaufskurve wird beim Aufklappen einer Karte angezeigt. Die Tabelle mit
den einzelnen Messreihen ist standardmäßig deaktiviert. Mit dem Attribut wird
nur der Plus-Schalter für die Tabelle aktiviert; die Tabelle selbst erscheint
erst nach einem Klick auf das Plus-Zeichen:

```fhem
attr TemperatureOverview showHistoryTable 1
```

Danach in einer aufgeklappten Karte auf `+` klicken. Zum vollständigen
Entfernen des Schalters:

```fhem
attr TemperatureOverview showHistoryTable 0
```

Wenn eine Feuchte-Historie vorhanden ist, enthält die Tabelle zusätzlich die
Spalte `Luftfeuchtigkeit` neben der Temperaturspalte.

Das Diagramm enthält eine Y-Achse `Temperatur (°C)`, eine X-Achse `Zeit` und
standardmäßig die letzten 24 Stunden. Die X-Achse enthält mehrere Zeitmarken;
an der ersten und letzten Marke werden Datum, Jahr und Uhrzeit angezeigt, die
Zwischenmarken zeigen nur die Uhrzeit. Der Zeitraum kann über `historyHours`
festgelegt werden:

```fhem
attr TemperatureOverview historyHours 6
```

Wenn ein historisches Feuchte-Reading vorhanden ist, wird zusätzlich eine
rechte Y-Achse `Luftfeuchtigkeit (%)` mit eigener Wertebereichsanzeige und
einer dezent blauen Kurve eingeblendet. Unter dem Diagramm zeigt eine
anklickbare Legende die beiden Reihen. Über die Einträge `Temperatur` und
`Luftfeuchtigkeit` können die jeweiligen Kurven einzeln ein- und ausgeblendet
werden; standardmäßig sind beide sichtbar.

Über den Diagrammtasten kann durch die Zeit navigiert werden:

- `←` lädt das vorherige Zeitfenster
- `→` lädt das nächste Zeitfenster
- `+` stellt eine feinere Auflösung ein
- `−` stellt eine gröbere Auflösung ein

Standardmäßig werden die DbLog-Werte in 30-Minuten-Intervallen zusammengefasst.
Die Auflösung kann zwischen 5 Minuten und 240 Minuten verändert werden. Die
Graphen und die zugrunde liegenden Messreihen werden bei jeder Änderung neu
geladen. Bereits geöffnete Sensoren und Messwerttabellen bleiben dabei
geöffnet. Die Navigation funktioniert sowohl im mit `_showDashboard` geöffneten
Dashboard als auch in der eigenständigen Ansicht über `_dashboardURL`.

Mit `autoRefresh` wird das Dashboard standardmäßig alle 60 Sekunden
aktualisiert. Dabei wird kein vollständiger Browser-Reload durchgeführt. Die
aktuellen Dashboard-Daten werden per HTTP nachgeladen und geöffnete Karten
bleiben geöffnet. Das Modul verwendet dafür bewusst kein WebSocket, da die
DbLog-Abfrage ohnehin bei jeder Aktualisierung neu ausgeführt wird und die
HTTP-Aktualisierung mit FHEMWEB ohne zusätzliche Verbindungsverwaltung
robuster ist.

Für längere Zeiträume kann das Diagramm horizontal gescrollt werden.

## Aktualisierung

Das Dashboard kann automatisch neu geladen werden:

```fhem
attr TemperatureOverview autoRefresh 60
```

Mögliche Werte sind `0`, `15`, `30`, `60` und `300` Sekunden. Mit `0` wird die
automatische Aktualisierung deaktiviert.

## Fehlerbehebung

### Keine Thermometer gefunden

- Prüfen, ob ein Quellgerät definiert ist.
- Mit `list <gerät>` kontrollieren, ob ein numerisches Reading `temperature`
  oder `temp` existiert.
- Bei einem anderen Reading-Namen kann die automatische Erkennung das Gerät
  absichtlich nicht aufnehmen.

### Aktuelle Werte vorhanden, aber kein Verlauf

- Prüfen, ob ein Gerät vom Typ `DbLog` definiert ist.
- Bei mehreren DbLog-Geräten das Attribut `dbLog` setzen.
- Prüfen, ob genau das erkannte Reading im DbLog protokolliert wird.
- Den Zeitraum mit `historyHours` vergrößern.

### Dashboard lädt langsam

- `historyHours` reduzieren.
- `autoRefresh` auf `60` oder `300` setzen.
- Die Anzahl der automatisch erkannten Geräte und DbLog-Einträge prüfen.

## Sicherheit und Datenschutz

Das Modul liest Gerätezustände und historische Messwerte aus FHEM. Es schreibt
nicht in die Quellgeräte und verändert keine DbLog-Daten. Das Dashboard kann
jedoch Temperaturverläufe und damit Informationen über Anwesenheit oder
Raumnutzung offenlegen. FHEMWEB sollte daher mit geeigneter Authentifizierung
und nicht ungeschützt aus dem Internet erreichbar sein.
