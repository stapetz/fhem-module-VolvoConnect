# FHEM-Module

Dieses Repository enthält FHEM-Module und die zugehörigen Controls-Dateien.

## Module und Dokumentation

| Modul | FHEM-Datei | Dokumentation | Controls |
| --- | --- | --- | --- |
| VolvoConnect | [`FHEM/50_VolvoConnect.pm`](FHEM/50_VolvoConnect.pm) | [`docs/volvo/README.md`](docs/volvo/README.md) | [`controls_volvo.txt`](controls_volvo.txt) |
| TemperatureCollector | [`FHEM/50_TemperatureCollector.pm`](FHEM/50_TemperatureCollector.pm) | [`docs/temperaturecollector/README.md`](docs/temperaturecollector/README.md) | [`controls_temperaturecollector.txt`](controls_temperaturecollector.txt) |
| GavazziEM24 | [`FHEM/70_GavazziEM24.pm`](FHEM/70_GavazziEM24.pm) | [`docs/gavazzi/README.md`](docs/gavazzi/README.md) | [`controls_gavazzi.txt`](controls_gavazzi.txt) |
| SolaxModbus | [`FHEM/98_ModbusSolax.pm`](FHEM/98_ModbusSolax.pm) | [`docs/solax/README.md`](docs/solax/README.md) | [`controls_solax.txt`](controls_solax.txt) |

Die Controls-Dateien werden durch GitHub Actions erzeugt und enthalten jeweils nur
das zugehörige Modul sowie das gemeinsame [Änderungsprotokoll](CHANGED).

## FHEM-Update-URLs

```text
https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_volvo.txt
https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_temperaturecollector.txt
https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt
https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt
```

Die ausführlichen Anleitungen stehen in den jeweiligen Dokumentationsordnern:

- [Volvo-Dokumentation](docs/volvo/DOKUMENTATION.md)
- [TemperatureCollector-Dokumentation](docs/temperaturecollector/DOKUMENTATION.md)
- [Gavazzi-Dokumentation](docs/gavazzi/DOKUMENTATION.md)
- [SolaX-Dokumentation](docs/solax/DOKUMENTATION.md)
