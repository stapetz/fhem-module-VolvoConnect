# GavazziEM24 für FHEM

GavazziEM24 bindet einen Gavazzi-EM24-Energiezähler über Modbus in FHEM ein.
Das read-only-Modul unterstützt passive RTU-Konfigurationen, aktives Polling
und ein Web-Dashboard.

## Funktionen

- Spannungen und Ströme für alle drei Phasen
- Phasenleistung, Gesamtleistung und Energiezähler
- Modbus-Funktionen 03 (Holding Register) und 04 (Input Register)
- Passives Mithören eines externen Modbus-Masters
- Optionales aktives Polling mit getrenntem Intervall für Phasenleistung
- Konfigurierbare Registerauswahl und integriertes Dashboard

## Installation

In FHEM einmalig folgende Controls-Datei registrieren:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt
```

Danach ein FHEM-Update ausführen. Die Moduldatei ist
[`FHEM/70_GavazziEM24.pm`](../../FHEM/70_GavazziEM24.pm).

## Weiterführende Dokumentation

- [Ausführliche Installations- und Betriebsdokumentation](DOKUMENTATION.md)
- [Projektübersicht](../../README.md)
- [Gavazzi-Controls](../../controls_gavazzi.txt)
