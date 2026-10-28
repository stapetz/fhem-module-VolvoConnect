# SolaxModbus – Dokumentation

Diese Anleitung beschreibt die Installation und den Betrieb des logischen
FHEM-Moduls `SolaxModbus` für SolaX-X-Hybrid-Wechselrichter.

## Voraussetzungen

- FHEM mit dem Modbus-Toolkit
- Ein über Modbus TCP erreichbarer SolaX X-Hybrid
- IP-Adresse und Port des Wechselrichters
- Die Modbus-Unit-ID des Wechselrichters, häufig `3`
- Das SolaX-Advanced-Passwort, standardmäßig `2014`, falls Schreibbefehle
  verwendet werden

Das Modul wurde mit dem SolaX X-Hybrid SK-SU5000 und der Firmware
`Solax_SI_CH_2nd_20160912_DE02` getestet. Andere Modelle und Firmwarestände
können abweichende Registerbelegungen verwenden.

## Installation

Das Modul kann über die Controls-Datei installiert werden:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_solax.txt
```

Alternativ kann [`98_ModbusSolax.pm`](../../FHEM/98_ModbusSolax.pm) in das
FHEM-Modulverzeichnis kopiert werden.

## Verbindung und Gerät anlegen

Das Modul kann eine direkte TCP-Verbindung verwenden:

```fhem
define SolaxWR SolaxModbus 3 10 192.168.178.21:502 TCP
attr SolaxWR room Energie
attr SolaxWR password 2014
```

Die Parameter sind Unit-ID, Polling-Intervall in Sekunden sowie optional
`host:port TCP`.

Alternativ kann ein vorhandenes physisches Modbus-IO-Device verwendet werden:

```fhem
define SolaxTCP Modbus 192.168.178.21:502
define SolaxWR SolaxModbus 3 10
attr SolaxWR IODev SolaxTCP
```

Prüfe anschließend im FHEM-Log, ob die Verbindung hergestellt wird und der
Status des Geräts nicht `disconnected` oder `timeout` ist.

## Polling und Readings

Das Standardintervall wird beim `define` festgelegt und kann zur Laufzeit
geändert werden:

```fhem
set SolaxWR interval 10
```

Wichtige Readings sind `gridVoltage`, `gridCurrent`, `acPower`, `pv1Power`,
`pv2Power`, `batterySOC`, `batteryPower`, `inverterStatus`, `inverterFault`,
`gridMeterPower`, `energyFeedInTotal`, `energyConsumedTotal`, `energyToday`
und `energyTotal`. Die Werte werden anhand der Registerdefinition skaliert
und mit Einheiten versehen.

## Schreibbefehle

Für Änderungen am Wechselrichter stehen unter anderem folgende Befehle zur
Verfügung:

```fhem
set SolaxWR workMode Self-Use
set SolaxWR minSoc 20
set SolaxWR gridExportLimit 5000
set SolaxWR batteryChargeMaxCurrent 20
set SolaxWR forceCharge on
```

Weitere Zeitfenster-Befehle sind
`forceChargeStartHour`, `forceChargeStartMinute`,
`forceChargeEndHour`, `forceChargeEndMinute`,
`forceDischargeStartHour`, `forceDischargeStartMinute`,
`forceDischargeEndHour` und `forceDischargeEndMinute`.
Vor jedem Schreibzugriff wird das konfigurierte Advanced-Passwort verwendet.

## Dashboard und Hilfe

```fhem
get SolaxWR _showDashboard
get SolaxWR _dashboardURL
help SolaxModbus
```

Das Dashboard zeigt unter anderem PV-Leistung, Batteriefluss, Netzfluss und
den Verbindungsstatus.

## Hinweise

- Vor der Einrichtung muss die Modbus-TCP-Schnittstelle des Wechselrichters
  erreichbar und aktiviert sein.
- Unit-ID und Registerbelegung müssen zum Wechselrichter und Firmwarestand
  passen.
- Schreibbefehle sollten zunächst mit konservativen Grenzwerten getestet
  werden.
- Netzwerk- und Gerätefehler sind im FHEM-Log zu prüfen.
- Das Advanced-Passwort und Netzwerkzugangsdaten gehören nicht in öffentliche
  Konfigurationsdateien.
