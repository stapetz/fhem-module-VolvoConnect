# ThermostatDashboard für FHEM

ThermostatDashboard stellt kompatible Homematic- und eQ-3 MAX-Heizkörperthermostate
übersichtlich in einem Dashboard dar. Ist- und Solltemperatur sowie Betriebsart,
Ventilstellung und Batteriestatus werden angezeigt. Solltemperatur und unterstützte
Betriebsarten können direkt bedient werden.

## Installation

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_thermostatdashboard.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_thermostatdashboard.txt
shutdown restart
```

## Einrichtung

```fhem
define Thermostate ThermostatDashboard
attr Thermostate room Dashboards
get Thermostate _showDashboard
```

ThermostatDashboard wird auch automatisch im DashboardHub angezeigt, sobald das
ThermostatDashboard-Gerät angelegt ist.

Die vollständige Anleitung steht in der
[ThermostatDashboard-Dokumentation](DOKUMENTATION.md).

- [Projektübersicht](../../README.md)
- [ThermostatDashboard-Controls](../../controls_thermostatdashboard.txt)
- Moduldatei: [`FHEM/50_ThermostatDashboard.pm`](../../FHEM/50_ThermostatDashboard.pm)
