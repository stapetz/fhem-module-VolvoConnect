# DashboardHub für FHEM

DashboardHub ist ein Meta-Modul für alle Dashboards dieses Repositories. Es erkennt
automatisch die vorhandenen Dashboard-Geräte (TemperatureCollector, GavazziEM24,
SolaxModbus, VolvoConnect und künftige Module), zeigt sie links als Navigation an und
stellt rechts das gewählte Dashboard dar.

## Funktionen

- Automatische Erkennung aller Geräte mit Dashboard (`_dashboardEmbedURL`)
- Navigation links, Dashboard-Inhalt rechts
- Menüname standardmäßig der `alias` des Geräts, ersatzweise der Gerätename
- Bearbeitungsmodus (Stift) zum Umbenennen und Umsortieren der Menüpunkte sowie zum Umbenennen der Überschrift
- Serverseitige Speicherung, dadurch auf allen Browsern und Geräten gleich
- Neue Dashboards erscheinen automatisch am Ende der Navigation

## Installation

In FHEM einmalig folgende Controls-Datei registrieren:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_dashboardhub.txt
```

Danach ein FHEM-Update ausführen und `shutdown restart` ausführen.

## Einrichtung

```fhem
define Dashboards DashboardHub
get Dashboards _showDashboard
```

## Dokumentation

Die vollständige Beschreibung steht in der [DashboardHub-Dokumentation](DOKUMENTATION.md).

- [Projektübersicht](../../README.md)
- [DashboardHub-Controls](../../controls_dashboardhub.txt)

Die Moduldatei ist [`FHEM/50_DashboardHub.pm`](../../FHEM/50_DashboardHub.pm).
