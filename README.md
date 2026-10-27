# VolvoConnect für FHEM

VolvoConnect verbindet ein FHEM-Gerät mit den offiziellen Volvo Cars APIs. Das Modul liest Energie-, Fahrzeug-, Diagnose- und Standortdaten und stellt ausgewählte Fahrzeugbefehle bereit. Es handelt sich um ein Community-Modul, nicht um ein von Volvo Cars herausgegebenes Produkt.

**Dokumente:** [Installations- und Betriebsdokumentation](DOKUMENTATION.md) · [Änderungsprotokoll](CHANGELOG.md)

## Funktionen

- OAuth2 Authorization Code mit PKCE, manueller Übergabe des Autorisierungscodes und automatischer Token-Erneuerung
- Konfigurierbare API-Bereiche für Fahrzeug-, Energie-, Diagnose-, Befehls- und Standortdaten
- Getrennte Abrufrhythmen für schnell veränderliche, langsam veränderliche und statische Endpunkte
- Fahrzeugbefehle für Verriegelung, Klimatisierung, Laden, Ladelimit, Hupe und Vorkonditionierung
- Eigenständiges Dashboard mit Messwerten, Fahrzeugstatus und optionaler Standortkarte
- Dashboard-Bearbeitung mit gespeicherter Tile-Reihenfolge, Sichtbarkeit und Labels

## Schnellstart

1. `50_VolvoConnect.pm` in das FHEM-Modulverzeichnis kopieren und FHEM neu starten.
2. Eine Anwendung im [Volvo Cars Developer Portal](https://developer.volvocars.com/) einrichten und VCC API Key, Client-ID und Client-Secret bereithalten.
3. Das Gerät anlegen und konfigurieren:

```fhem
define Volvo1 VolvoConnect
attr Volvo1 vin <17-stellige-VIN>
attr Volvo1 client_id <Client-ID>
attr Volvo1 client_secret <Client-Secret>
attr Volvo1 vcc_api_key <VCC-API-Key>
attr Volvo1 redirect_uri http://localhost
set Volvo1 reauth
```

4. Den vom Gerät angebotenen Volvo-Login öffnen, anmelden und den Wert des URL-Parameters `code` kopieren.
5. Den Code an FHEM übergeben:

```fhem
set Volvo1 authCode <Autorisierungscode>
```

Die Redirect-URI muss exakt mit der Anwendung im Developer Portal übereinstimmen. Volvo muss die URI für die jeweilige Anwendung zulassen; `http://localhost` eignet sich für lokale Tests, sofern es im Portal akzeptiert wird.

Zusätzliche Datenbereiche sind über `scope_*` Attribute aktivierbar. Sie sind standardmäßig deaktiviert. Details zu Scopes, Dashboard, Readings, Sicherheit und Fehlerbehebung stehen in der [Betriebsdokumentation](DOKUMENTATION.md).

## Hinweise

- Das Standardintervall für dynamische Werte beträgt 300 Sekunden; langsamere Diagnose-/Reifendaten werden standardmäßig alle 1800 Sekunden und der Standort alle 900 Sekunden abgefragt. Fähigkeiten, Befehlsliste und Fahrzeugdetails werden je VIN einmal geladen.
- `set <name> update` erzwingt eine sofortige Aktualisierung aller aktivierten Endpunkte, auch wenn sie laut Intervall-Cache noch nicht fällig wären.
- API-Verfügbarkeit und Datenumfang hängen von Fahrzeug, Region, Anwendung und Volvo-Berechtigungen ab.
- Die Location API liefert den zuletzt bekannten Standort und ist keine Live-Ortung.
- Das Fahrzeug-Detail-API dokumentiert eine Außen- und eine Innenbild-URL. Volvo weist darauf hin, dass diese URLs befristet sind und nicht dauerhaft zwischengespeichert werden sollen.
- Access- und Refresh-Tokens sowie API-Zugangsdaten nicht veröffentlichen oder in Support-Ausgaben einfügen.

Stand der Dokumentation: 08.10.2026
