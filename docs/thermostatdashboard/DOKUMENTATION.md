# ThermostatDashboard – Dokumentation

ThermostatDashboard zeigt kompatible Heizkörperthermostate eines FHEM-Systems in einer
gemeinsamen, responsiven Übersicht. Homematic-Geräte über `CUL_HM` und eQ-3 MAX-Geräte
über `MAX` werden automatisch erkannt.

## Voraussetzungen

- FHEM mit FHEMWEB
- Homematic-Thermostate mit `TYPE CUL_HM`, Temperatur-Readings `measured-temp` und
  `desired-temp` sowie dem Set-Befehl `desired-temp`
- eQ-3 MAX-Heizkörperthermostate mit `TYPE MAX`, `type HeatingThermostat`,
  `HeatingThermostatPlus` oder `WallMountedThermostat` und den
  Readings `temperature` und `desiredTemperature`

Die Erkennung nutzt den tatsächlichen Set-Befehl des Gerätetyps. Andere Geräte, die keine
Solltemperatur unterstützen, werden nicht aufgenommen.

## Installation

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_thermostatdashboard.txt
update all https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_thermostatdashboard.txt
shutdown restart
```

Alternativ die Datei `FHEM/50_ThermostatDashboard.pm` in das FHEM-Modulverzeichnis kopieren
und FHEM neu starten.

## Gerät anlegen und anzeigen

```fhem
define Thermostate ThermostatDashboard
attr Thermostate room Dashboards
get Thermostate _showDashboard
```

Das Gerät erscheint auch automatisch in der Navigation des DashboardHub.

Weitere Befehle:

| FHEM-Befehl | Funktion |
| --- | --- |
| `get <name> _showDashboard` | Dashboard direkt in FHEMWEB anzeigen |
| `get <name> _dashboardURL` | eigenständige Dashboard-URL |
| `get <name> _dashboardEmbedURL` | Fragment-URL für DashboardHub oder FTUI |
| `get <name> list` | erkannte Thermostate auflisten; ausgeblendete markieren |
| `get <name> diagnose` | erkannte CUL_HM-/MAX-Geräte samt Erkennungs- und Sichtbarkeitsstatus anzeigen |

## Anzeige und Bedienung

Pro Gerät werden Alias (ersatzweise Gerätename), optional der Raum, Isttemperatur und
Solltemperatur angezeigt. Wenn vorhanden, zeigt das Dashboard außerdem Betriebsart,
Ventilstellung und Batteriestatus. Die Daten werden standardmäßig alle 15 Sekunden aus FHEM
aktualisiert.

Über das Stiftsymbol kann der Bearbeitungsmodus geöffnet werden. Dort lässt sich für jedes
erkannte Thermostat per **Anzeigen**-Kontrollkästchen festlegen, ob es im Dashboard erscheint.
Ausgeblendete Thermostate bleiben während der Bearbeitung sichtbar und sind abgedunkelt.
**Speichern** übernimmt die Auswahl dauerhaft für dieses ThermostatDashboard-Gerät;
**Abbrechen** verwirft alle Änderungen der aktuellen Bearbeitung.

Die Solltemperatur lässt sich direkt in ihrer Kachel über den Schieberegler in 0,5-Grad-Schritten
einstellen. Der Regler reicht vom Geräteminimum bis maximal 25 °C. Nach 1,5 Sekunden ohne
weitere Änderung wird der Wert automatisch an FHEM gesendet; eine kurze Meldung bestätigt
„Wert gesendet“. Das Dashboard zeigt auch bestehende Sollwerte über 25 °C an, der Regler selbst
endet jedoch bei 25 °C.
Die MAX-Sonderwerte 4,5 °C (`Off`) und 30,5 °C (`On`) werden bewusst nicht als normale
Temperaturwerte angeboten. Die FHEM-Geräte bleiben maßgeblich für die Validierung und
Ausführung der Befehle.

Je nach Fähigkeiten des Geräts erscheinen passende Betriebsarten:

- **CUL_HM:** `Auto`, `Manuell`, `Boost` sowie `Tag` und `Nacht`, sofern die jeweilige
  Option in der Set-Übersicht des Geräts vorhanden ist.
- **MAX:** `Auto`, `Eco`, `Komfort` und `Boost`. Eine numerische Solltemperatur setzt den
  MAX-Thermostat auf den manuellen Temperaturwert. Zusätzlich kann der Modus **Manuell**
  explizit gewählt werden.

Die aktuell aktive Betriebsart ist im Auswahlfeld sichtbar. Sie kann dort direkt geändert
werden. Der Modus wird an das einzelne Thermostat gesendet. Bei miteinander verknüpften MAX-
Thermostaten kann es erforderlich sein, den Befehl für jedes Gerät einzeln zu setzen.

Die Ventilstellung erscheint als farbiger Balken von Blau nach Dunkelrot; Marker und Prozentwert
zeigen die aktuelle Position. Der Batteriestatus wird als Batteriesymbol dargestellt: `ok` und
hohe Prozentwerte erscheinen grün, niedrige Werte und `nok` rot.

## Attribute

| Attribut | Beschreibung |
| --- | --- |
| `includeDevices` | Regex; nur passende Gerätenamen berücksichtigen |
| `excludeDevices` | Regex; passende Gerätenamen ausblenden |
| `autoRefresh` | Aktualisierung in Sekunden: `0`, `15`, `30` oder `60`; Standard `15` |
| `showDeviceType` | Modell-/Typzeile unter dem Thermostatnamen anzeigen (`0` oder `1`); Standard `1` |
| `showRoom` | Raum über dem Thermostatnamen anzeigen (`0` oder `1`); Standard `1` |

Geräte mit `disable 1` werden ausgelassen. Die manuell ausgeblendete Auswahl wird getrennt
je ThermostatDashboard-Gerät gespeichert. Die Anzeige wird nach Raum und Alias sortiert.

## Sicherheit und Datenschutz

Bedienbefehle werden über die angemeldete FHEMWEB-Sitzung mit CSRF-Token an dasselbe
FHEM gesendet. Das Dashboard führt keine eigenen Heizungszeitpläne aus und ändert keine
Gerätekonfiguration oder Wochenprofile.

## Fehlerbehebung

- **Ein Thermostat fehlt:** `get <name> diagnose` ausführen und Readings sowie
  `set <thermostat> ?` des Geräts prüfen.
- **Temperatur lässt sich nicht setzen:** Prüfen, ob das Gerät `desired-temp` (CUL_HM)
  oder `desiredTemperature` (MAX) anbietet. Die Antwort wird im Dashboard neben dem
  jeweiligen Thermostat angezeigt.
- **Messwert wirkt veraltet:** Zeitstempel der Readings in FHEM prüfen. MAX-Geräte übertragen
  Messwerte abhängig von Funk- und Gateway-Aktivität.
