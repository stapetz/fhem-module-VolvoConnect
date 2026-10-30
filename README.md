# FHEM-Module

Dieses Repository enthält FHEM-Module und die zugehörigen Controls-Dateien.

## Module und Dokumentation

| Modul | FHEM-Datei | Dokumentation | Controls |
| --- | --- | --- | --- |
| VolvoConnect | [`FHEM/50_VolvoConnect.pm`](FHEM/50_VolvoConnect.pm) | [`docs/volvo/README.md`](docs/volvo/README.md) | [`controls_volvo.txt`](controls_volvo.txt) |
| TemperatureCollector | [`FHEM/50_TemperatureCollector.pm`](FHEM/50_TemperatureCollector.pm) | [`docs/temperaturecollector/README.md`](docs/temperaturecollector/README.md) | [`controls_temperaturecollector.txt`](controls_temperaturecollector.txt) |
| GavazziEM24 | [`FHEM/70_GavazziEM24.pm`](FHEM/70_GavazziEM24.pm) | [`docs/gavazzi/README.md`](docs/gavazzi/README.md) | [`controls_gavazzi.txt`](controls_gavazzi.txt) |
| SolaxModbus | [`FHEM/70_SolaxModbus.pm`](FHEM/70_SolaxModbus.pm) | [`docs/solax/README.md`](docs/solax/README.md) | [`controls_solax.txt`](controls_solax.txt) |
| DashboardHub (Meta-Modul für alle Dashboards) | [`FHEM/50_DashboardHub.pm`](FHEM/50_DashboardHub.pm) | [`docs/dashboardhub/README.md`](docs/dashboardhub/README.md) | [`controls_dashboardhub.txt`](controls_dashboardhub.txt) |

DashboardHub erkennt automatisch alle vorhandenen Dashboard-Geräte (TemperatureCollector,
GavazziEM24, SolaxModbus, VolvoConnect und künftige Module) und zeigt sie mit einer
Navigationsleiste links und dem jeweiligen Dashboard rechts an. Menünamen und
Reihenfolge sind im Bearbeitungsmodus änderbar.

Die Controls-Dateien werden durch GitHub Actions erzeugt und enthalten jeweils nur
das zugehörige Modul sowie dessen Änderungsprotokoll: [`CHANGED_volvo`](CHANGED_volvo),
[`CHANGED_temperaturecollector`](CHANGED_temperaturecollector),
[`CHANGED_gavazzi`](CHANGED_gavazzi), [`CHANGED_solax`](CHANGED_solax) und
[`CHANGED_dashboardhub`](CHANGED_dashboardhub).
Zusätzlich enthält [`controls_all.txt`](controls_all.txt) alle Module des Repositories
sowie das gemeinsame [Änderungsprotokoll](CHANGED).

Die Änderungsprotokolle werden bei jedem Push von
[`scripts/generate_changed.py`](scripts/generate_changed.py) aus den Git-Commits erzeugt:
je Commit eine Zeile mit Datum, Kurz-Hash und Betreff, darunter die Zeilen der
Commit-Beschreibung als Zusammenfassung. Die Dateien der Module enthalten nur Commits, die
das jeweilige Modul oder dessen Dokumentation betreffen. Aussagekräftige Commit-Texte
(Betreff plus Stichpunkte im Text) ergeben daher ein gutes Änderungsprotokoll.

Jedes Modul hat eine eigene Versionsnummer. Die installierte Version steht im Internal
`VERSION` des Geräts (`list <gerät>`).

## Gesamtes Repository in FHEM abonnieren

Alle Module auf einmal:

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
```

Danach `shutdown restart` ausführen. Einzelne Module lassen sich weiterhin über die
folgenden Befehle abonnieren.

## FHEM-Update-Befehle

Je Modul bzw. für alle Module:

**Alle Module**

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_all.txt
```

**VolvoConnect**

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_volvo.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_volvo.txt
```

**TemperatureCollector**

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_temperaturecollector.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_temperaturecollector.txt
```

**GavazziEM24**

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt
```

**SolaxModbus**

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt
```

**DashboardHub**

```text
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_dashboardhub.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_dashboardhub.txt
```

Danach `shutdown restart` ausführen.

Die ausführlichen Anleitungen stehen in den jeweiligen Dokumentationsordnern:

- [Volvo-Dokumentation](docs/volvo/DOKUMENTATION.md)
- [TemperatureCollector-Dokumentation](docs/temperaturecollector/DOKUMENTATION.md)
- [Gavazzi-Dokumentation](docs/gavazzi/DOKUMENTATION.md)
- [SolaX-Dokumentation](docs/solax/DOKUMENTATION.md)
- [DashboardHub-Dokumentation](docs/dashboardhub/DOKUMENTATION.md)

## Feedback

Fragen, Fehler und Ideen bitte als [GitHub-Issue](https://github.com/stapetz/fhem-modules/issues/new/choose) melden. Issues sind öffentlich; keine Passwörter, Tokens oder Adressen posten.
