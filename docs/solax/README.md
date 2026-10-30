# SolaxModbus für FHEM

SolaxModbus bindet einen SolaX-X-Hybrid-Wechselrichter über Modbus TCP in FHEM
ein. Das Modul ist ein logisches Modbus-Gerät für das FHEM-Modbus-Toolkit und
liest Wechselrichter-, Batterie-, Netz- und PV-Werte.

## Funktionen

- PV-Spannung, PV-Strom und PV-Leistung für zwei Strings
- Netzspannung, Netzstrom, Netzleistung und Netzfrequenz
- Batterie-Spannung, -Strom, -Leistung und Ladezustand
- Wechselrichterstatus, Temperatur und Fehlerbitmaske
- Energiezähler für Bezug, Einspeisung, Tages- und Gesamtertrag
- Schreibbefehle für Betriebsart, Ladegrenzen, Einspeisebegrenzung und
  Zeitfenster
- Integriertes Live-Dashboard
- Langsam pulsierender grüner Statuspunkt bei bestehender Modbus-Verbindung

## Installation

In FHEM einmalig folgende Controls-Datei registrieren:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt
```

Danach ein FHEM-Update ausführen. Die ausführliche Einrichtung steht in der
[Dokumentation](DOKUMENTATION.md).

## Weiterführende Dokumentation

- [Ausführliche Installations- und Betriebsdokumentation](DOKUMENTATION.md)
- [Projektübersicht](../../README.md)
- [SolaX-Controls](../../controls_solax.txt)

## Modul

Die Moduldatei ist [`FHEM/70_SolaxModbus.pm`](../../FHEM/70_SolaxModbus.pm).
