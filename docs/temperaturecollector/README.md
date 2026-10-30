# TemperatureCollector für FHEM

TemperatureCollector ist ein Meta-Modul für FHEM. Es erkennt automatisch
numerische Temperatur-Readings anderer Geräte und stellt sie in einem
aufklappbaren Dashboard dar. Wenn ein `DbLog`-Gerät vorhanden ist, werden
zusätzlich historische Temperaturwerte als Verlauf angezeigt. Optionale
Feuchte-Readings werden als zweite Datenreihe und in der Messwerttabelle
berücksichtigt.

## Installation

In FHEM einmalig folgende Controls-Datei registrieren:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_temperaturecollector.txt
```

Danach ein FHEM-Update ausführen.

## Einrichtung

```fhem
define TemperatureOverview TemperatureCollector
attr TemperatureOverview room Klima
```

Das Dashboard kann anschließend über die Detailansicht oder mit folgendem
Befehl geöffnet werden:

```fhem
get TemperatureOverview _showDashboard
```

Die Sensorreihenfolge kann dort mit dem Stift bearbeitet werden. Sie wird
serverseitig gespeichert und steht dadurch auf anderen Browsern und Geräten
zur Verfügung. Neu erkannte Sensoren werden automatisch am Ende angefügt.

## Dokumentation

Die vollständige Beschreibung steht in der
[TemperatureCollector-Dokumentation](DOKUMENTATION.md).

Die Moduldatei ist
[`FHEM/50_TemperatureCollector.pm`](../../FHEM/50_TemperatureCollector.pm).
