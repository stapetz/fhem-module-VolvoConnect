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
das zugehörige Modul sowie dessen Änderungsprotokoll: [`CHANGED_volvo`](CHANGED_volvo),
[`CHANGED_temperaturecollector`](CHANGED_temperaturecollector),
[`CHANGED_gavazzi`](CHANGED_gavazzi) und [`CHANGED_solax`](CHANGED_solax).
Zusätzlich enthält [`controls_all.txt`](controls_all.txt) alle Module des Repositories
sowie das gemeinsame [Änderungsprotokoll](CHANGED).

Die Änderungsprotokolle werden bei jedem Push von
[`scripts/generate_changed.py`](scripts/generate_changed.py) aus den Git-Commits erzeugt:
je Commit eine Zeile mit Datum, Kurz-Hash und Betreff, darunter die Zeilen der
Commit-Beschreibung als Zusammenfassung. Die Dateien der Module enthalten nur Commits, die
das jeweilige Modul oder dessen Dokumentation betreffen. Aussagekräftige Commit-Texte
(Betreff plus Stichpunkte im Text) ergeben daher ein gutes Änderungsprotokoll.

## Gesamtes Repository in FHEM abonnieren

Alle Module auf einmal:

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
```

Danach `shutdown restart` ausführen. Einzelne Module lassen sich weiterhin über die
folgenden URLs abonnieren.

## FHEM-Update-URLs

```text
https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
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
