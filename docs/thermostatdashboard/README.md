# ThermostatDashboard für FHEM

ThermostatDashboard stellt kompatible Homematic- und eQ-3 MAX-Heizkörperthermostate
übersichtlich in einem Dashboard dar. Ist- und Solltemperatur sowie Betriebsart,
Ventilstellung und Batteriestatus werden angezeigt. Solltemperatur und unterstützte
Betriebsarten können direkt bedient werden. MAX-Geräte vom Typ `HeatingThermostatPlus`
werden ebenfalls erkannt. Im Bearbeitungsmodus können einzelne Thermostate dauerhaft
ein- oder ausgeblendet werden. Die Modell-/Typzeile lässt sich mit
`attr <Name> showDeviceType 0` ausblenden; mit `1` wird sie wieder angezeigt. Der Raum
über dem Thermostatnamen kann analog mit `attr <Name> showRoom 0` ausgeblendet werden.
Die Solltemperatur wird über einen Schieberegler (Geräteminimum bis maximal 25 °C) eingestellt
und nach 1,5 Sekunden ohne weitere Eingabe automatisch gesendet. Die Betriebsart kann direkt
über das Auswahlfeld geändert werden; Ventilstellung und Batteriestatus werden grafisch
dargestellt.

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
