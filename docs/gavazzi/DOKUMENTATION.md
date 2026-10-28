# GavazziEM24 – Dokumentation

Diese Anleitung beschreibt die Installation und den Betrieb des logischen,
read-only FHEM-Moduls `GavazziEM24` für Carlo-Gavazzi-EM24-DIN-Zähler.

## Voraussetzungen

- FHEM mit dem Modbus-Toolkit
- Ein Gavazzi EM24 mit erreichbarer Modbus-RTU-Verbindung
- Ein FHEM-Modbus-IO-Device und die Geräte-ID des Zählers
- Eine passende serielle Schnittstelle und Baudrate

Die Registerkarte folgt dem EM24-DIN Communication Protocol, Version 4,
Revision 0. Unterstützt werden die EM24-DIN-Varianten PFA, PFB und X, soweit
deren Registerbelegung kompatibel ist.

## Installation

Das Modul kann über die Controls-Datei installiert werden:

```fhem
update add https://raw.githubusercontent.com/stapetz/fhem-modules/main/controls_gavazzi.txt
```

Alternativ kann [`70_GavazziEM24.pm`](../../FHEM/70_GavazziEM24.pm) in das
FHEM-Modulverzeichnis kopiert werden.

## IO-Device und Gerät anlegen

Ein passives RTU-Gerät wird typischerweise zusammen mit einem Modbus-IO-Device
angelegt:

```fhem
define GavazziRS485 Modbus /dev/ttyUSB0@9600
define GavazziEM24_1 GavazziEM24
attr GavazziEM24_1 IODev GavazziRS485
```

Für eine abweichende Modbus-ID und explizit passiven Modus kann die Definition
erweitert werden:

```fhem
define GavazziEM24_2 GavazziEM24 2 passive RTU
attr GavazziEM24_2 IODev GavazziRS485
```

Die verwendete Schnittstelle, Baudrate, Geräte-ID und der Polling-Modus müssen
zur konkreten Installation passen.

## Betriebsarten

Passiv ist der Standardmodus. In diesem Modus aktualisiert das Modul Readings,
wenn ein externer Modbus-Master die entsprechenden Register abfragt. Es werden
Holding Register (Funktion 03) und Input Register (Funktion 04) berücksichtigt.
Register, die niemals vom externen Master gelesen werden, können im passiven
Modus keine Werte liefern.

Für aktives Polling:

```fhem
attr GavazziEM24_1 pollMode active
attr GavazziEM24_1 pollInterval 300
attr GavazziEM24_1 pollIntervalPower 5
```

`pollInterval` steuert den allgemeinen Abruf, `pollIntervalPower` den
separaten Abruf der aktuellen Phasenleistung. Die Intervalle sollten zur
Buslast und zur Anzahl der Modbus-Geräte passen.

## Readings und Registerauswahl

Typische Readings sind Spannungen (`voltageL1N`, `voltageL2N`,
`voltageL3N`), Ströme (`currentL1`, `currentL2`, `currentL3`) und
Leistungswerte (`activePowerL1`, `activePowerL2`, `activePowerL3`).
Die Messwerte werden in den dokumentierten Einheiten skaliert.

Die Registerauswahl kann über das Attribut `pollRegisters` gesteuert werden,
beispielsweise:

```fhem
attr GavazziEM24_1 pollRegisters i0=1,i2=0,i4=1
```

Die verfügbaren Register und die Standardauswahl sind in der Modulhilfe
dokumentiert.

## Dashboard und Hilfe

```fhem
get GavazziEM24_1 _showDashboard
get GavazziEM24_1 _showEntityConfig
help GavazziEM24
```

Das Entity-Config-Dialogfenster unterstützt bei der Auswahl der zu
überwachenden Register. Das Dashboard zeigt die verfügbaren Messwerte und
den Verbindungsstatus.

## Fehlerbehebung und Sicherheit

- Bei fehlenden Werten zuerst IO-Device, serielle Schnittstelle, Baudrate und
  Modbus-ID prüfen.
- Im passiven Modus muss der externe Modbus-Master die gewünschten Register
  tatsächlich abfragen.
- Bei aktivem Polling die Buslast und die Polling-Intervalle prüfen.
- Keine Modbus-Geräte mehrfach mit widersprüchlichen aktiven Polling-Zyklen
  konfigurieren.
- Serielle Geräteknoten und FHEM-Zugriff dürfen nicht ungeschützt öffentlich
  erreichbar sein.
