##############################################################################
# $Id: 70_SolaxModbus.pm $
#
# FHEM-Modul für den SolaX X-Hybrid Wechselrichter SK-SU5000
# (getestet mit Firmware Solax_SI_CH_2nd_20160912_DE02, "Generation 2"
#  Modbus-Protokoll der SolaX Pocket-LAN / Modbus-TCP Schnittstelle)
#
# Dieses Modul ist ein *logisches* Modbus-Gerät im Sinne des FHEM
# "Modbus-Toolkits" (98_Modbus.pm von Stefan Strobel). Es liefert selbst
# keine TCP-Verbindung, sondern verwendet ein physisches Modbus-Device
# (IODev) für die eigentliche Kommunikation. Das Toolkit übernimmt dabei
# bereits:
#   - zyklisches Poll(en) der Input-/Holding-Register (Intervall siehe unten)
#   - Set/Get inkl. Wertebereichsprüfung (min/max) für schreibbare Register
#   - Skalierung, Mapping auf Klartext, Zusammenfassen benachbarter Register
#   - sauberes Fehlerhandling: state wird bei Verbindungsproblemen
#     automatisch auf "disconnected"/"timeout" gesetzt, ohne dass FHEM
#     blockiert
#
# Eigener Modul-Code ist dadurch bewusst schlank: im Wesentlichen die
# Register-Tabelle (%SolaxModbus_parseInfo) sowie ein kleiner Set-Wrapper
# für den komfortablen Pseudo-Befehl "forceCharge on|off".
#
# -----------------------------------------------------------------------
# Beispiel-Definitionen für die fhem.cfg
# -----------------------------------------------------------------------
#
# 1) Direktes Modbus-TCP-Device. Ein separates Modbus-IODev ist nicht nötig.
#    Die Unit-ID muss der des funktionierenden 98_ModbusSolax-Devices
#    entsprechen, hier beispielhaft 3.
#
#    define SolaxWR SolaxModbus 3 10 192.168.178.21:502 TCP
#    attr   SolaxWR room Energie
#    attr   SolaxWR stateFormat {SolaxModbus::StateIcon('SolaxWR')}
#    attr   SolaxWR password 2014
#
#    Alternativ kann weiterhin ein externes IODev verwendet werden:
#    define SolaxTCP Modbus 192.168.178.21:502
#    define SolaxWR SolaxModbus 3 10
#    attr   SolaxWR IODev SolaxTCP
#
#    Das Poll-Intervall lässt sich später jederzeit per
#    "set SolaxWR interval <Sekunden>" ändern (siehe Abschnitt "Set" in der
#    Commandref weiter unten). Ein Attribut "interval" existiert im
#    Modbus-Toolkit bewusst nicht - die Intervallsteuerung erfolgt über den
#    define-Parameter bzw. den set-Befehl "interval".
#
# -----------------------------------------------------------------------
# Register-Übersicht (siehe %SolaxModbus_parseInfo weiter unten für die
# technische, für FHEM auswertbare Fassung dieser Tabelle)
# -----------------------------------------------------------------------
#
# Lesbare Register (Input Register, FC 04) ------------------------------
# Adresse | Reading                 | Typ            | Skalierung | Einheit
# --------|-------------------------|----------------|------------|--------
# 0x00    | gridVoltage             | unsigned short | 0.1        | V
# 0x01    | gridCurrent             | signed short   | 0.1        | A
# 0x02    | acPower                 | signed short   | 0.1        | W
# 0x03    | pv1Voltage              | unsigned short | 0.1        | V
# 0x04    | pv2Voltage              | unsigned short | 0.1        | V
# 0x05    | pv1Current              | unsigned short | 0.1        | A
# 0x06    | pv2Current              | unsigned short | 0.1        | A
# 0x07    | gridFrequency           | unsigned short | 0.01       | Hz
# 0x08    | inverterTemperature     | signed short   | 1          | °C
# 0x09    | inverterStatus          | unsigned short | Textmap    | -
# 0x0A    | pv1Power                | unsigned short | 1          | W
# 0x0B    | pv2Power                | unsigned short | 1          | W
# 0x14    | batteryVoltage          | signed short   | 0.01       | V
# 0x15    | batteryCurrent          | signed short   | 0.01       | A
# 0x16    | batteryPower            | signed short   | 1          | W (+laden/-entladen)
# 0x17    | bmsConnectState         | unsigned short | Textmap    | -
# 0x18    | batteryTemperature      | signed short   | 1          | °C
# 0x1C    | batterySOC              | unsigned short | 1          | %
# 0x40/41 | inverterFault           | unsigned long  | 1          | Bitmaske
# 0x46/47 | gridMeterPower          | signed long    | 1          | W
# 0x48/49 | energyFeedInTotal       | unsigned long  | 0.01       | kWh
# 0x4A/4B | energyConsumedTotal     | unsigned long  | 0.01       | kWh
# 0x50    | energyToday             | unsigned short | 0.1        | kWh
# 0x52/53 | energyTotal             | unsigned long  | 0.1        | kWh
#
# Schreibbare Register (Holding Register, FC 03 lesen / FC 06 schreiben) -
# Adresse | Reading                    | Typ            | Bereich       | Einheit
# --------|----------------------------|----------------|---------------|--------
# 0x1F    | workMode                   | unsigned short | 0,1,2 (Map)   | -
# 0x20    | minSoc                     | unsigned short | 10..99        | %
# 0x24    | batteryChargeMaxCurrent    | unsigned short | 0..30 (*0.01) | A
# 0x25    | batteryDischargeMaxCurrent | unsigned short | 0..30 (*0.01) | A
# 0x42    | gridExportLimit            | unsigned short | 0..5000       | W
# 0x92    | forceChargeStartHour       | unsigned short | 0..23         | h
# 0x93    | forceChargeStartMinute     | unsigned short | 0..59         | min
# 0x94    | forceChargeEndHour         | unsigned short | 0..23         | h
# 0x95    | forceChargeEndMinute       | unsigned short | 0..59         | min
# 0x96    | forceDischargeStartHour    | unsigned short | 0..23         | h
# 0x97    | forceDischargeStartMinute  | unsigned short | 0..59         | min
# 0x98    | forceDischargeEndHour      | unsigned short | 0..23         | h
# 0x99    | forceDischargeEndMinute    | unsigned short | 0..59         | min
#
# Hinweis zur Wartbarkeit: alle Angaben (Adresse, Datentyp, Skalierung,
# Rechte, Zielreading) stehen ausschließlich in %SolaxModbus_parseInfo.
# Wer weitere Register ergänzen möchte, muss nur dort einen neuen Eintrag
# hinzufügen - Polling, Set/Get und Commandref-Generierung benötigen keine
# weiteren Codeänderungen.
#
# Hinweis zur Firmware/Registerherkunft: Die Adressen 0x00-0x53 entsprechen
# dem "klassischen" SolaX-Modbus-Protokoll der SK-SU5000(E)-Serie
# (Generation 2, Firmware Solax_SI_CH_2nd_...), die Steuerregister
# 0x1F/0x20/0x24/0x25/0x42/0x92-0x99 sind für Generation-2-Hybridgeräte
# dokumentiert. Da SolaX je nach Firmware-/Hardwarestand einzelne
# Registerbedeutungen leicht abweichend belegt, unbedingt vor dem
# produktiven Schreibzugriff (insbesondere gridExportLimit) mit dem
# eigenen Netzbetreiber-Limit sowie ggf. dem offiziellen SolaX-Modbus-PDF
# der eigenen Firmware abgleichen!
#
##############################################################################

package SolaxModbus;

use strict;
use warnings;

our $VERSION = '1.0.2-dev';
use GPUtils qw(:all);

BEGIN {
    GP_Import(qw(
        LoadModule
        fhem
        Log3
        CommandDeleteAttr
    ));
    GP_Export(qw(
        Initialize
    ));
}

# -----------------------------------------------------------------------
# Register-Mapping-Tabelle
# -----------------------------------------------------------------------
# Schlüssel-Schema des Modbus-Toolkits: <Typ><5-stellige Adresse>
#   Typ 'i' = Input-Register  (FC 04, nur lesbar)
#   Typ 'h' = Holding-Register (FC 03 lesen / FC 06 schreiben)
#
# Unterstützte Felder je Register (siehe FHEM Commandref zu 98_Modbus):
#   reading  - Name des FHEM-Readings
#   type     - eingebauter Datentyp (legt len/unpack automatisch fest)
#   expr     - Perl-Ausdruck zur Skalierung beim Lesen ($val = Rohwert)
#   setexpr  - Perl-Ausdruck zur Rückrechnung beim Schreiben ($val = Eingabe)
#   map      - Klartext-Zuordnung "roh:Text, roh:Text, ..."
#   poll     - 1 = zyklisch abfragen
#   set      - 1 = per "set" beschreibbar
#   min/max  - Wertebereichsprüfung bei "set"
our %SolaxModbus_parseInfo = (

    #### Leistungsdaten AC / PV (Input-Register) ####
    'i00000' => { reading => 'gridVoltage',         type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f V', poll => 1 },
    'i00001' => { reading => 'gridCurrent',         type => 'signed short',
                  expr => '$val * 0.1', format => '%.1f A', poll => 1 },
    'i00002' => { reading => 'acPower',             type => 'signed short',
                  expr => '$val * 0.1', format => '%.1f W', poll => 1 },
    'i00003' => { reading => 'pv1Voltage',          type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f V', poll => 1 },
    'i00004' => { reading => 'pv2Voltage',          type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f V', poll => 1 },
    'i00005' => { reading => 'pv1Current',          type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f A', poll => 1 },
    'i00006' => { reading => 'pv2Current',          type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f A', poll => 1 },
    'i00007' => { reading => 'gridFrequency',       type => 'unsigned short',
                  expr => '$val * 0.01', format => '%.2f Hz', poll => 1 },
    'i00008' => { reading => 'inverterTemperature', type => 'signed short',
                  format => '%.0f °C', poll => 1 },
    'i00009' => { reading => 'inverterStatus',      type => 'unsigned short',
                  map  => '0:Wartet, 1:Prueft-Netz, 2:Normal, 3:Fault, '
                        . '4:Permanenter-Fehler, 5:Update, 6:Netzausfall-Wartet, '
                        . '7:Netzausfall-Betrieb, 8:Selbsttest, 9:Standby-Idle, 10:Standby',
                  poll => 1 },
    'i00010' => { reading => 'pv1Power',            type => 'unsigned short',
                  format => '%.0f W', poll => 1 },
    'i00011' => { reading => 'pv2Power',            type => 'unsigned short',
                  format => '%.0f W', poll => 1 },
    'i00012' => { reading => 'pvTemperatureFaultValue', type => 'signed short', poll => 1 },
    'i00013' => { reading => 'pv1VoltageFaultValue', type => 'unsigned short',
                  expr => '$val * 0.1', poll => 1 },
    'i00014' => { reading => 'pv2VoltageFaultValue', type => 'unsigned short',
                  expr => '$val * 0.1', poll => 1 },
    'i00015' => { reading => 'gfciFaultValue', type => 'unsigned short', poll => 1 },
    'i00016' => { reading => 'gridVoltageFaultValue', type => 'unsigned short',
                  expr => '$val * 0.1', poll => 1 },
    'i00017' => { reading => 'gridFrequencyFaultValue', type => 'unsigned short',
                  expr => '$val * 0.01', poll => 1 },
    'i00018' => { reading => 'dciFaultValue', type => 'unsigned short', poll => 1 },
    'i00019' => { reading => 'timeCountDown', type => 'unsigned short', poll => 1 },

    #### Batteriestatus (Input-Register) ####
    'i00020' => { reading => 'batteryVoltage',      type => 'signed short',
                  expr => '$val * 0.01', format => '%.1f V', poll => 1 },
    'i00021' => { reading => 'batteryCurrent',      type => 'signed short',
                  expr => '$val * 0.01', format => '%.1f A', poll => 1 },
    'i00022' => { reading => 'batteryPower',        type => 'signed short',
                  format => '%.1f W', poll => 1 },     # positiv = laden, negativ = entladen
    'i00023' => { reading => 'Charger_Board_Temp',  type => 'signed short',
                  format => '%.0f °C', poll => 1, polldelay => 0 },
    'i00024' => { reading => 'Battery_Board_Temp',  type => 'signed short',
                  format => '%.0f °C', poll => 1, polldelay => 0 },
    'i00025' => { reading => 'Charger_Boost_Temp', type => 'signed short',
                  format => '%.0f °C', poll => 1, polldelay => 0 },
    'i00028' => { reading => 'batterySOC', type => 'unsigned short',
                  format => '%.0f %%', poll => 1, polldelay => 0 },
    'i00029' => { reading => 'inputEnergyCharge', type => 'unsigned short',
                  len => 2, unpack => 'n', expr => '$val / 10', poll => 1,
                  format => '%.1f kWh', polldelay => 0 },
    'i00032' => { reading => 'outputEnergyCharge', type => 'unsigned short',
                  len => 2, unpack => 'n', expr => '$val / 10', poll => 1,
                  format => '%.1f kWh', polldelay => 0 },
    'i00031' => { reading => 'BMS_Warning', type => 'unsigned short', poll => 1, polldelay => 0 },
    'i00035' => { reading => 'Battery_State_Health', type => 'unsigned short', poll => 1, polldelay => 0 },
    'i00036' => { reading => 'bmsChargeMaxCurrent', type => 'unsigned short',
                  expr => '$val * 0.1', poll => 1 },
    'i00037' => { reading => 'bmsDischargeMaxCurrent', type => 'unsigned short',
                  expr => '$val * 0.1', poll => 1 },

    #### Zaehlerstaende / Systemstatus (Input-Register) ####
    'i00064' => { reading => 'inverterFault',       type => 'unsigned long',
                  poll => 1 },     # Bitmaske, siehe SolaX-Fehlercode-Tabelle
    'i00070' => { reading => 'gridMeterPower',      type => 'signed short',
                  len => 2, unpack => 's>', poll => 1 },
    'i00072' => { reading => 'energyFeedInTotal',   type => 'unsigned short',
                  len => 2, unpack => 'n', expr => '$val / 100', poll => 1,
                  format => '%.0f kWh' },
    'i00074' => { reading => 'energyConsumedTotal', type => 'unsigned short',
                  len => 2, unpack => 'n', expr => '$val / 100', poll => 1,
                  format => '%.0f kWh' },
    'i00080' => { reading => 'energyToday',         type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f kWh', poll => 1 },
    'i00082' => { reading => 'energyTotal',         type => 'unsigned short',
                  len => 2, unpack => 'n', expr => '$val / 1000', poll => 1,
                  format => '%.1f kWh' },
    'i00112' => { reading => 'Solar_Energy_total',  type => 'unsigned short',
                  len => 2, unpack => 'n', expr => '$val / 10', poll => 1,
                  format => '%.3f kWh' },
    'i00066' => { reading => 'Charger_Fault',       type => 'unsigned short', poll => 1 },
    'i00067' => { reading => 'Manager_Fault',       type => 'unsigned short', poll => 1 },
    'i00085' => { reading => 'batteryTemperature', type => 'signed short',
                  expr => '$val * 0.1', format => '%.0f', poll => 1 },
    'i00076' => { reading => 'EPS_Voltage',         type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.0f V', poll => 1 },
    'i00077' => { reading => 'EPS_Current',         type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.0f A', poll => 1 },
    'i00078' => { reading => 'EPS_VA',              type => 'unsigned short',
                  format => '%.0f VA', poll => 1 },
    'i00079' => { reading => 'EPS_Frequency',       type => 'unsigned short',
                  expr => '$val * 0.01', format => '%.0f Hz', poll => 1 },

    #### Betriebsmodus / Einspeisebegrenzung (Holding-Register) ####
    # SolaX verlangt vor jedem Schreibzugriff das Advanced-Passwort in
    # Register 0x0000.
    'h00000' => { reading => 'solaxUnlock',       type => 'unsigned short',
                  ignoreExpr => '1', set => 1, poll => 0, min => 0, max => 9999 },
    'h00139' => { reading => 'workMode',            type => 'unsigned short',
                  map  => '0:Self-Use, 1:Feed-in-Priority, 2:Back-Up, 3:Manual',
                  poll => 1 },
    'h00031' => { reading => 'workModeWrite',       type => 'unsigned short',
                  map  => '0:Self-Use, 1:Feed-in-Priority, 2:Back-Up, 3:Manual',
                  ignoreExpr => '1', set => 1, poll => 0, min => 0, max => 3 },
    'h00032' => { reading => 'manualModeWrite',     type => 'unsigned short',
                  ignoreExpr => '1', set => 1, poll => 0, min => 0, max => 2 },
    'h00182' => { reading => 'gridExportLimit',     type => 'unsigned short',
                  format => '%.0f W', poll => 1 },   # 0x00B6 Export control user limit
    'h00066' => { reading => 'gridExportLimitWrite', type => 'unsigned short',
                  ignoreExpr => '1', set => 1, poll => 0, min => 0, max => 60000 },

    #### Batterie-Ladesteuerung / SOC-Grenzen (Holding-Register) ####
    'h00147' => { reading => 'minSoc',              type => 'unsigned short',
                      expr => '$val >> 8', format => '%.0f %%', poll => 1 },    # 0x0093 high byte
    'h00097' => { reading => 'minSocWrite',         type => 'unsigned short',
                  ignoreExpr => '1', set => 1, poll => 0, min => 10, max => 100 },
    'h00144' => { reading => 'batteryChargeMaxCurrent', type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f A', poll => 1 },     # 0x0090
    'h00036' => { reading => 'batteryChargeMaxCurrentWrite', type => 'unsigned short',
                  ignoreExpr => '1', setexpr => '$val / 0.1', set => 1, poll => 0, min => 0, max => 30 },
    'h00145' => { reading => 'batteryDischargeMaxCurrent', type => 'unsigned short',
                  expr => '$val * 0.1', format => '%.1f A', poll => 1 },     # 0x0091
    'h00037' => { reading => 'batteryDischargeMaxCurrentWrite', type => 'unsigned short',
                  ignoreExpr => '1', setexpr => '$val / 0.1', set => 1, poll => 0, min => 0, max => 30 },

    #### Zeitfenster fuer erzwungenes Laden/Entladen im Force-Time-Use ####
    #### (nur wirksam, wenn workMode = Force-Time-Use)                 ####
    'h00151' => { reading => 'forceChargeStartTime',      type => 'unsigned short',
                  poll => 1 },
    'h00152' => { reading => 'forceChargeEndTime',        type => 'unsigned short',
                  poll => 1 },
    'h00153' => { reading => 'forceDischargeStartTime',   type => 'unsigned short',
                  poll => 1 },
    'h00154' => { reading => 'forceDischargeEndTime',     type => 'unsigned short',
                  poll => 1 },
    'h00104' => { reading => 'forceChargeStartTimeWrite', type => 'unsigned short', ignoreExpr => '1', set => 1, poll => 0 },
    'h00105' => { reading => 'forceChargeEndTimeWrite', type => 'unsigned short', ignoreExpr => '1', set => 1, poll => 0 },
    'h00106' => { reading => 'forceDischargeStartTimeWrite', type => 'unsigned short', ignoreExpr => '1', set => 1, poll => 0 },
    'h00107' => { reading => 'forceDischargeEndTimeWrite', type => 'unsigned short', ignoreExpr => '1', set => 1, poll => 0 },

);

# -----------------------------------------------------------------------
# Geräteeigenschaften: Blockgröße für zusammengefasste Leseanfragen sowie
# ein etwas großzügigeres Timeout, da WLAN/LAN-Dongles teils langsam
# antworten.
# -----------------------------------------------------------------------
our %SolaxModbus_deviceInfo = (
    # Das funktionierende 98_ModbusSolax-Modul liest stabile Blöcke mit
    # maximal zehn Inputregistern; größere Blöcke werden vom Gateway nicht
    # zuverlässig beantwortet.
    'i'      => { read => 4, combine => 1, defLen => 1,
                  defFormat => '%.0f', defUnpack => 'n',
                  defPoll => 1, defShowGet => 1, defPolldelay => 0 },
    'h'      => { read => 3, write => 6, combine => 1, defLen => 1,
                  defUnpack => 'n', defPoll => 0, defShowGet => 1,
                  defPolldelay => 0 },
    'timing' => { timeout => 3, commDelay => 0.1 },
);

#####################################
# Initialize wird von FHEM beim Laden des Moduls aufgerufen.
# Die eigentliche Arbeit (Define, Undef, Set, Get, Attr, Poll-Timer, ...)
# übernimmt das Modbus-Basismodul (98_Modbus.pm) über InitializeLD().
# Wir ergänzen lediglich unsere Register-Tabelle sowie einen kleinen
# Set-Wrapper für den komfortablen Pseudo-Befehl "forceCharge".
sub Initialize {
    my $modHash = shift;

    undef $SolaxModbus::DashboardTemplate;
    $modHash->{parseInfo}  = \%SolaxModbus_parseInfo;
    $modHash->{deviceInfo} = \%SolaxModbus_deviceInfo;

    LoadModule('Modbus');           # 98_Modbus.pm als Basis laden
    Modbus::InitializeLD($modHash); # generische Define/Set/Get/Poll-Logik

    $modHash->{AttrList} = $modHash->{AttrList} . ' '
        . $modHash->{ObjAttrList} . ' '
        . $modHash->{DevAttrList} . ' password';

    # generischen SetFn um unseren Komfortbefehl "forceCharge on|off" ergänzen
    $modHash->{SetFn} = \&SolaxModbus::SetFn;
    $modHash->{GetFn} = \&SolaxModbus::GetFn;
    $modHash->{DefFn} = \&SolaxModbus::DefineFn;
    $modHash->{ModbusReadingsFn} = \&SolaxModbus::ModbusReadingsFn;
    $main::data{FWEXT}{'/SolaxModbus'}{FUNC} = 'SolaxModbus_DashboardCGI';
    $main::data{FWEXT}{'/SolaxModbus'}{FORKABLE} = 0;
    if ($main::init_done) {
        EnsureExistingStateFormats();
    }
    else {
        main::InternalTimer(time() + 5, \&SolaxModbus::EnsureExistingStateFormats,
            'SolaxModbus_stateFormat', 0);
    }

    return;
}

#####################################
# SolaX wird ausschließlich über Modbus TCP betrieben. Das Modbus-Basismodul
# verwendet ohne Protokollangabe standardmäßig RTU.
sub DefineFn {
    my ($hash, $def) = @_;
    $def .= ' TCP' if ($def !~ /\s(?:RTU|ASCII|TCP)\s*$/);
    my $ret = Modbus::DefineLDFn($hash, $def);
    $hash->{VERSION} = $VERSION;
    EnsureStateFormat($hash->{NAME}) if (!defined($ret) || $ret eq '');
    return $ret;
}

sub HtmlEscape {
    my ($value) = @_;
    $value = '' if (!defined($value));
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    return $value;
}

sub EnsureStateFormat {
    my ($name) = @_;
    my $stateFormat = $main::attr{$name}{stateFormat};
    return if (defined($stateFormat) && $stateFormat ne 'state');
    $main::attr{$name}{stateFormat} = "{SolaxModbus::StateIcon('$name')}";
}

sub EnsureExistingStateFormats {
    for my $name (keys %main::defs) {
        next if (!$main::defs{$name} || $main::defs{$name}{TYPE} ne 'SolaxModbus');
        EnsureStateFormat($name);
    }
}

sub StateIcon {
    my ($name) = @_;
    my $state = main::ReadingsVal($name, 'state', '');
    my $normalizedState = lc($state // '');
    my $color = '#879088';
    $color = '#00ff00' if ($normalizedState =~ /^(?:opened|connected|ok|active)$/);
    $color = '#ff0000'
        if ($normalizedState =~ /^(?:closed|disconnected|offline|timeout|error)$/);
    return '<span title="' . HtmlEscape($state)
        . '" style="display:inline-block;width:10px;height:10px;background:'
        . $color . ';border-radius:50%;vertical-align:middle"></span>';
}

sub DashboardBasePath {
    my $path = $main::FW_ME || '/fhem';
    $path =~ s{/$}{};
    return $path;
}

our $DashboardTemplate;

sub BuildDashboard {
    my ($hash, $embed) = @_;
    if (!defined($DashboardTemplate)) {
        open my $moduleFile, '<', __FILE__
            or die "cannot read Solax dashboard template: $!";
        local $/;
        my $source = <$moduleFile>;
        close $moduleFile;
        ($DashboardTemplate) = $source =~ /^__DATA__\r?\n(.*)\z/ms;
        die 'Solax dashboard template is missing' if (!defined($DashboardTemplate));
    }

    my $name = HtmlEscape($hash->{NAME});
    my $basePath = DashboardBasePath();
    my $html = $DashboardTemplate;
    $html =~ s/__DEVICE__/$name/g;
    $html =~ s/__FHEM_BASE__/HtmlEscape($basePath)/ge;
    # Embed mode: fragment without html/head/body for FTUI and similar hosts
    return $html if ($embed);
    return '<!doctype html><html lang="de"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>' . $name . ' - SolaX Energie</title></head>'
        . '<body style="margin:0;background:#111914;padding:12px">'
        . $html . '</body></html>';
}

sub GetFn {
    my ($hash, $name, $cmd, @args) = @_;
    return BuildDashboard($hash) if ($cmd eq '_showDashboard');
    if ($cmd eq '_dashboardEmbedURL') {
        return DashboardBasePath() . '/SolaxModbus/' . main::urlEncode($name) . '?embed=1';
    }
    if ($cmd eq '_dashboardURL') {
        my $webName = $main::FW_wname;
        my $webHash = defined($webName) ? $main::defs{$webName} : undef;
        my $scheme = $webName && main::AttrVal($webName, 'HTTPS', 0) ? 'https' : 'http';
        my $host = $main::FW_httpheader{Host};
        my $forwardedProto = $main::FW_httpheader{'X-Forwarded-Proto'};
        if (defined($forwardedProto) && $forwardedProto =~ /^\s*(https?)(?:\s|,|$)/i) {
            $scheme = lc($1);
        }
        if (!defined($host) || $host eq '') {
            my $port = $webHash && defined($webHash->{PORT}) ? $webHash->{PORT} : undef;
            $host = 'localhost' . (defined($port) && $port ne '' ? ":$port" : '');
        }
        return $scheme . '://' . $host . DashboardBasePath()
            . '/SolaxModbus/' . main::urlEncode($name);
    }

    my $ret = Modbus::GetLDFn($hash, $name, $cmd, @args);
    if (defined($ret) && $ret =~ /^Unknown argument (.*?), choose one of (.*)$/) {
        $ret = "Unknown argument $1, choose one of _showDashboard:noArg _dashboardURL:noArg _dashboardEmbedURL:noArg $2";
    }
    return $ret;
}

sub main::SolaxModbus_DashboardCGI {
    my ($request) = @_;
    $request = '' if (!defined($request));
    my ($path) = split(/\?/, $request, 2);
    my @parts = split('/', $path);
    my $name = $parts[-1];
    my $hash = $main::defs{$name};
    return ('text/plain; charset=utf-8', "Unknown SolaxModbus device: $name")
        if (!$hash || $hash->{TYPE} ne 'SolaxModbus');

    my $embed = $request =~ /[?&]embed=1(?:&|$)/ ? 1 : 0;
    my $html = eval { SolaxModbus::BuildDashboard($hash, $embed) };
    if ($@ || !defined($html)) {
        main::Log3($name, 2, "$name: Solax dashboard rendering failed: $@");
        return ('text/plain; charset=utf-8', "Dashboard rendering failed: $@");
    }
    return ('text/html; charset=utf-8', $html);
}

sub ModbusReadingsFn {
    my ($hash, $reading, $value) = @_;
    main::readingsSingleUpdate($hash, $reading, $value, 1);
    if ($reading eq 'pv1Power' || $reading eq 'pv2Power') {
        my ($pv1Power) = main::ReadingsVal($hash->{NAME}, 'pv1Power', 0)
            =~ /^([-+]?\d+(?:\.\d+)?)/;
        my ($pv2Power) = main::ReadingsVal($hash->{NAME}, 'pv2Power', 0)
            =~ /^([-+]?\d+(?:\.\d+)?)/;
        $pv1Power //= 0;
        $pv2Power //= 0;
        main::readingsSingleUpdate($hash, 'pv_total_power',
            sprintf('%.0f W', $pv1Power + $pv2Power), 1);
    }

    my %timeReadings = (
        forceChargeStartTime    => [qw(forceChargeStartHour forceChargeStartMinute)],
        forceChargeEndTime      => [qw(forceChargeEndHour forceChargeEndMinute)],
        forceDischargeStartTime => [qw(forceDischargeStartHour forceDischargeStartMinute)],
        forceDischargeEndTime   => [qw(forceDischargeEndHour forceDischargeEndMinute)],
    );
    return 1 if (!$timeReadings{$reading});

    my ($hour, $minute) = (($value >> 8) & 0xff, $value & 0xff);
    main::readingsSingleUpdate($hash, $timeReadings{$reading}[0], $hour, 1);
    main::readingsSingleUpdate($hash, $timeReadings{$reading}[1], $minute, 1);
    return 1;
}

#####################################
# Set-Wrapper: leitet alle Standardbefehle (z.B. gridExportLimit, workMode,
# minSoc, ...) unverändert an das Modbus-Basismodul weiter und ergänzt
# zusätzlich den Komfortbefehl "forceCharge on|off", der Betriebsmodus und
# Ladezeitfenster in einem Schritt setzt, um die Batterie sofort und
# dauerhaft zu laden bzw. den Erzwingungsmodus wieder zu verlassen.
sub SetFn {
    my ($hash, $name, $cmd, @args) = @_;
    $cmd = '' if (!defined($cmd));

    if ($cmd eq 'cleanupScanReadings') {
        $hash->{parseInfo} = \%SolaxModbus_parseInfo;
        $hash->{deviceInfo} = \%SolaxModbus_deviceInfo;
        for my $attrName (keys %{ $main::attr{$name} // {} }) {
            next if ($attrName !~ /^obj-h\d+-reading$/);
            my $attrValue = main::AttrVal($name, $attrName, '');
            CommandDeleteAttr(undef, "$name $attrName")
                if ($attrValue =~ /^scan-/);
        }
        for my $attrName (keys %{ $main::attr{$name} // {} }) {
            CommandDeleteAttr(undef, "$name $attrName")
                if ($attrName =~ /^(?:poll|polldelay)-/
                    || $attrName =~ /^obj-[ih]\d+-(?:poll|polldelay)$/);
        }
        fhem("deletereading $name scan-h.*");
        fhem("deletereading $name solaxParameter.*");
        delete $hash->{PICACHE};
        delete $hash->{UPDATECACHE};
        delete $hash->{lastRead};
        $hash->{'.updateSetGet'} = 1;
        return;
    }

    my %simpleWrites = (
        workMode                   => 'workModeWrite',
        minSoc                     => 'minSocWrite',
        batteryChargeMaxCurrent   => 'batteryChargeMaxCurrentWrite',
        batteryDischargeMaxCurrent => 'batteryDischargeMaxCurrentWrite',
        gridExportLimit            => 'gridExportLimitWrite',
    );

    my $isTimeWrite = $cmd =~ /^(?:forceCharge|forceDischarge)(?:Start|End)(?:Hour|Minute)$/;
    my $isWriteCommand = $cmd eq 'forceCharge'
        || $cmd eq 'solaxUnlock'
        || exists $simpleWrites{$cmd}
        || $isTimeWrite;

    # Das Unlock selbst wird direkt weitergereicht, damit kein rekursiver
    # Login entsteht. Alle anderen Schreibbefehle werden vorher freigeschaltet.
    if ($isWriteCommand && $cmd ne 'solaxUnlock') {
        my $password = main::AttrVal($name, 'password', '2014');
        return "invalid password: expected 0..9999"
            if ($password !~ /^\d{1,4}$/);

        my $unlockRet = Modbus::SetLDFn($hash, $name, 'solaxUnlock', $password);
        return $unlockRet if (defined($unlockRet) && $unlockRet ne '');
    }

    if ($simpleWrites{$cmd}) {
        $cmd = $simpleWrites{$cmd};
    }

    if ($cmd =~ /^(forceCharge|forceDischarge)(Start|End)(Hour|Minute)$/) {
        my ($mode, $edge, $part) = ($1, $2, $3);
        my $prefix = lcfirst($mode) . $edge;
        my $other = $part eq 'Hour' ? 'Minute' : 'Hour';
        my $otherValue = main::ReadingsVal($name, $prefix . $other, 0);
        my $value = $args[0] // 0;
        my $hour = $part eq 'Hour' ? $value : $otherValue;
        my $minute = $part eq 'Minute' ? $value : $otherValue;
        my %writeReading = (
            forceChargeStart => 'forceChargeStartTimeWrite',
            forceChargeEnd => 'forceChargeEndTimeWrite',
            forceDischargeStart => 'forceDischargeStartTimeWrite',
            forceDischargeEnd => 'forceDischargeEndTimeWrite',
        );
        return Modbus::SetLDFn($hash, $name, $writeReading{$mode . $edge},
            ($hour << 8) | $minute);
    }

    if ($cmd eq 'forceCharge') {
        my $val = $args[0] // '';
        return "usage: set $name forceCharge on|off" if ($val ne 'on' && $val ne 'off');

        if ($val eq 'on') {
            Log3($name, 3, "$name: forceCharge on - aktiviere Force-Time-Use und "
                . "setze Ladefenster auf 00:00-23:59 (kein erzwungenes Entladen)");
            Modbus::SetLDFn($hash, $name, 'manualModeWrite', 1);
            fhem("set $name forceChargeStartHour 0");
            fhem("set $name forceChargeStartMinute 0");
            fhem("set $name forceChargeEndHour 23");
            fhem("set $name forceChargeEndMinute 59");
            fhem("set $name forceDischargeStartHour 0");
            fhem("set $name forceDischargeStartMinute 0");
            fhem("set $name forceDischargeEndHour 0");
            fhem("set $name forceDischargeEndMinute 0");
        }
        else {
            Log3($name, 3, "$name: forceCharge off - zurueck in den Self-Use-Modus");
            fhem("set $name workMode Self-Use");
        }
        return;
    }

    # alle anderen Set-Befehle (workMode, minSoc, gridExportLimit, ...)
    # von der generischen Modbus-Toolkit-Logik behandeln lassen
    my $ret = Modbus::SetLDFn($hash, $name, $cmd, @args);
    $ret .= ' forceCharge:on,off'
        if (defined($ret) && $ret =~ /^Unknown argument/);
    $ret .= ' cleanupScanReadings:noArg'
        if (defined($ret) && $ret =~ /^Unknown argument/);
    return $ret;
}

1;

=pod
=item device
=item summary Modbus-TCP-Anbindung für den SolaX X-Hybrid SK-SU5000 (logisches Gerät)
=item summary_DE Modbus-TCP-Anbindung für den SolaX X-Hybrid SK-SU5000 (logisches Gerät)
=begin html

<a id="SolaxModbus"></a>
<h3>SolaxModbus</h3>
<ul>
    SolaxModbus is a logical Modbus device for the FHEM Modbus toolkit
    (98_Modbus.pm) that reads and controls a SolaX X-Hybrid SK-SU5000
    inverter (tested with firmware Solax_SI_CH_2nd_20160912_DE02) over
    Modbus TCP. A separate physical <a href="#Modbus">Modbus</a> device
    holds the TCP connection and is referenced as IODev.
    <br><br>

    <a id="SolaxModbus-define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; SolaxModbus &lt;id&gt; &lt;interval&gt; [host:port TCP]</code>
        <br><br>
        Example:<br>
        <code>
            define SolaxWR SolaxModbus 3 10 192.168.178.21:502 TCP
        </code>
    </ul>
    <br>

    <a id="SolaxModbus-set"></a>
    <b>Set</b>
    <ul>
        <li>workMode Self-Use|Force-Time-Use|Back-Up</li>
        <li>minSoc &lt;10..99&gt; (%)</li>
        <li>gridExportLimit &lt;0..5000&gt; (W) - Einspeisebegrenzung</li>
        <li>batteryChargeMaxCurrent / batteryDischargeMaxCurrent &lt;0..30&gt; (A)</li>
        <li>Vor jedem Schreibzugriff wird das SolaX-Advanced-Passwort in Register
            0x0000 geschrieben. Das Passwort ist als Attribut <code>password</code>
            konfigurierbar und hat den Defaultwert <code>2014</code>.</li>
        <li>forceChargeStartHour/Minute, forceChargeEndHour/Minute,
            forceDischargeStartHour/Minute, forceDischargeEndHour/Minute</li>
        <li>forceCharge on|off - convenience command that switches to
            Force-Time-Use and sets an all-day charge window (on) or
            switches back to Self-Use (off)</li>
        <li>interval &lt;seconds&gt; - change the polling interval at runtime</li>
    </ul>
    <br>

    <a id="SolaxModbus-get"></a>
    <b>Get</b>
    <ul>
        get for any reading defined above, e.g. <code>get SolaxWR batterySOC</code>
        <li><code>_showDashboard</code> - Live-Solax-Dashboard direkt in FHEM anzeigen</li>
        <li><code>_dashboardURL</code> - vollst&auml;ndige URL zur isolierten Dashboard-Ansicht ausgeben</li>
        <li><code>_dashboardEmbedURL</code> - relative URL des Dashboard-Fragments (<code>?embed=1</code>, ohne html/head/body) f&uuml;r FTUI ausgeben</li>
    </ul>
    <br>

    <a id="SolaxModbus-attr"></a>
    <b>Attributes</b>
    <ul>
        See <a href="#Modbus">Modbus</a> for the common attributes
        (IODev, poll-&lt;reading&gt;, polldelay-&lt;reading&gt;, obj-... and
        dev-... attributes to fine tune individual registers without code
        changes).
    </ul>
</ul>

<a name="SolaxModbusFeedback"></a>
<b>Feedback</b>
<ul>
    Fragen, Fehlermeldungen und Ideen: <a href="https://github.com/stapetz/fhem-modules/issues/new/choose">GitHub-Issues</a>.
    Issues sind &ouml;ffentlich, bitte keine Passw&ouml;rter, Tokens oder Adressen posten.
</ul>

=end html
=cut

__DATA__
<section class="solax-dashboard" data-device="__DEVICE__" data-fhem-base="__FHEM_BASE__" aria-label="SolaX Solardashboard">
    <header class="sx-header">
        <div class="sx-brand"><span class="sx-brand-mark" aria-hidden="true"><svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="2.5"/><path d="m5 10 12-1.5 2 7.5H7zM8 16v2m4-2v2m4-2v2M4 21h16M4 6l1-2m-3 5h2"/></svg></span><div><small>SOLAX / X-HYBRID</small><h1>Energiefluss</h1></div></div>
        <div class="sx-live"><i class="sx-led" data-connection data-state="unknown" aria-label="Modbus-Verbindungsstatus" title="Modbus-Verbindungsstatus"></i></div>
    </header>
    <main class="sx-main">
        <section class="sx-hero">
            <div class="sx-hero-primary"><small>LIVE / PHOTOVOLTAIK</small><h2>Solarleistung</h2><div class="sx-total"><strong data-total>--</strong><span>W</span></div><span class="sx-inverter-state" data-reading="inverterStatus">--</span></div>
            <div class="sx-string-panel">
                <div class="sx-string"><div class="sx-string-head"><span>PV 1</span><strong data-reading="pv1Power">--</strong></div><div class="sx-bar"><i data-pv-bar="pv1Power"></i></div><div class="sx-string-meta"><span>Spannung <b data-reading="pv1Voltage">--</b></span><span>Strom <b data-reading="pv1Current">--</b></span></div></div>
                <div class="sx-string"><div class="sx-string-head"><span>PV 2</span><strong data-reading="pv2Power">--</strong></div><div class="sx-bar"><i data-pv-bar="pv2Power"></i></div><div class="sx-string-meta"><span>Spannung <b data-reading="pv2Voltage">--</b></span><span>Strom <b data-reading="pv2Current">--</b></span></div></div>
            </div>
        </section>
        <section class="sx-cards">
            <article class="sx-card sx-battery"><div class="sx-card-head"><small>SPEICHER</small><span data-battery-flow>BATTERIE</span></div><div class="sx-soc"><strong data-reading="batterySOC">--</strong><span>Ladezustand</span></div><div class="sx-soc-track"><i data-soc-bar></i></div><dl><div><dt>Batterieleistung</dt><dd data-reading="batteryPower">--</dd></div><div><dt>Spannung</dt><dd data-reading="batteryVoltage">--</dd></div><div><dt>Temperatur</dt><dd data-reading="batteryTemperature">--</dd></div></dl></article>
            <article class="sx-card sx-grid"><div class="sx-card-head"><small>HAUS / NETZ</small><span>AC</span></div><div class="sx-primary-reading"><strong data-reading="acPower">--</strong><span>Wechselrichterleistung</span></div><dl><div><dt>Netzleistung</dt><dd><b data-reading="gridMeterPower">--</b> W</dd></div><div><dt>Netzspannung</dt><dd data-reading="gridVoltage">--</dd></div><div><dt>Netzfrequenz</dt><dd data-reading="gridFrequency">--</dd></div></dl></article>
            <article class="sx-card sx-inverter"><div class="sx-card-head"><small>WECHSELRICHTER</small><span data-reading="workMode">--</span></div><div class="sx-primary-reading"><strong data-reading="inverterTemperature">--</strong><span>Temperatur</span></div><dl><div><dt>Wechselrichterstatus</dt><dd data-reading="inverterStatus">--</dd></div><div><dt>Fehlercode</dt><dd data-reading="inverterFault">--</dd></div><div><dt>BMS-Warnung</dt><dd data-reading="BMS_Warning">--</dd></div></dl></article>
        </section>
        <section class="sx-energy"><div class="sx-section-head"><div><small>ENERGIEBILANZ</small><h2>Ertrag und Bezug</h2></div><small>MESSWERTE</small></div><div class="sx-energy-grid"><div><span>Heute erzeugt</span><strong data-reading="energyToday">--</strong></div><div><span>Gesamtertrag</span><strong data-reading="energyTotal">--</strong></div><div><span>Einspeisung gesamt</span><strong data-reading="energyFeedInTotal">--</strong></div><div><span>Bezug gesamt</span><strong data-reading="energyConsumedTotal">--</strong></div></div></section>
        <footer class="sx-footer"><span>BATTERIEGESUNDHEIT <b data-reading="Battery_State_Health">--</b></span><span>BATTERIE-LADESTROM MAX. <b data-reading="bmsChargeMaxCurrent">--</b></span><span>BATTERIE-ENTLADESTROM MAX. <b data-reading="bmsDischargeMaxCurrent">--</b></span><span>SOLAX X-HYBRID / GENERATION 2</span></footer>
    </main>
</section>
<style>
.solax-dashboard{--ink:#1d2825;--mint:#52bd8b;--amber:#e3b953;--red:#d45b45;background:var(--ink);color:#f4f4e9;font:14px 'Avenir Next','Helvetica Neue',sans-serif;line-height:1.4;width:100%;max-width:1120px;margin:0 auto;overflow:hidden;border:1px solid #46544c;box-shadow:0 16px 44px #0c16124a}
.solax-dashboard *{box-sizing:border-box}
.sx-header{min-height:76px;padding:0 24px;display:flex;justify-content:space-between;align-items:center;gap:20px;background:#202e29;border-bottom:1px solid #405149}
.sx-brand{display:flex;align-items:center;gap:12px;min-width:0}
.sx-brand-mark{width:39px;height:39px;flex:0 0 39px;border:2px solid var(--mint);border-radius:50%;color:var(--mint);display:grid;place-items:center}
.sx-header small,.sx-card-head,.sx-section-head small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac}
.sx-header h1,.sx-section h2,.sx-section-head h2{font:500 22px Georgia,serif;margin:3px 0;letter-spacing:0;line-height:1.1}
.sx-live{display:flex;align-items:center;gap:8px}
.sx-led{display:block;width:12px;height:12px;border-radius:50%;background:#879088}
.sx-led[data-state="online"]{background:#52bd8b;animation:sx-live-pulse 4s ease-in-out infinite}
.sx-led[data-state="error"]{background:var(--red);box-shadow:0 0 0 3px #d45b4540}
@keyframes sx-live-pulse{0%,100%{opacity:.35;box-shadow:0 0 3px #52bd8b}50%{opacity:1;box-shadow:0 0 10px #52bd8b}}
.sx-main{padding:22px 24px 16px;background:linear-gradient(155deg,#26352e,#1b2823 62%,#202c27)}
.sx-hero{display:grid;grid-template-columns:minmax(230px,.85fr) minmax(300px,1.15fr);gap:24px;align-items:center;padding:20px 22px;background:#303d35;border:1px solid #536054;box-shadow:inset 0 0 0 4px #0d161231,0 8px 20px #0002}
.sx-hero-primary>small,.sx-section-head small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac}
.sx-hero-primary h2{font:500 20px Georgia,serif;margin:5px 0}
.sx-total{display:flex;align-items:baseline;gap:8px;margin:0;color:#f4f4e9}
.sx-total strong{font:500 54px 'Avenir Next','Helvetica Neue',sans-serif;line-height:1.1;font-variant-numeric:tabular-nums}
.sx-total span{font:600 16px 'Helvetica Neue',sans-serif;color:#a9b7ac}
.sx-inverter-state{display:inline-block;margin-top:8px;padding:4px 8px;border-left:2px solid var(--mint);background:#1d2825;color:#c7d0c8;font-size:12px}
.sx-string-panel{display:grid;gap:16px}
.sx-string{min-width:0}
.sx-string-head,.sx-string-meta{display:flex;justify-content:space-between;align-items:baseline;gap:10px}
.sx-string-head{font:600 12px 'Helvetica Neue',sans-serif;color:#c7d0c8}
.sx-string-head strong{font-size:16px;color:#f4f4e9;font-variant-numeric:tabular-nums}
.sx-bar,.sx-soc-track{height:5px;background:#45534a;margin:7px 0}
.sx-bar i,.sx-soc-track i{display:block;width:0;height:100%;background:var(--mint);transition:width .3s}
.sx-string:nth-child(2) .sx-bar i{background:#8ab6d1}
.sx-string-meta{font-size:10px;color:#9fac9f}
.sx-string-meta b{color:#edf0e6;font-weight:600}
.sx-cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;padding-top:20px}
.sx-card{--accent:var(--mint);padding:14px 15px;background:#26342d;border-top:2px solid var(--accent);min-width:0}
.sx-grid{--accent:#8ab6d1}.sx-inverter{--accent:var(--amber)}
.sx-card-head{display:flex;justify-content:space-between;align-items:center;gap:8px;color:var(--accent)}
.sx-card-head span{max-width:55%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#c7d0c8;font-size:10px}
.sx-soc{display:flex;align-items:baseline;gap:8px;margin-top:10px}
.sx-soc strong{font:500 34px 'Avenir Next','Helvetica Neue',sans-serif;font-variant-numeric:tabular-nums}
.sx-soc span,.sx-primary-reading span{font-size:11px;color:#9fac9f}
.sx-soc-track i{background:var(--accent)}
.sx-primary-reading{display:flex;flex-direction:column;gap:2px;margin:12px 0}
.sx-primary-reading strong{font:500 25px 'Avenir Next','Helvetica Neue',sans-serif;font-variant-numeric:tabular-nums;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sx-card dl{margin:10px 0 0}
.sx-card dl div{display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-top:1px solid #cfddcf14;font-size:11px}
.sx-card dt{color:#9fac9f}.sx-card dd{margin:0;color:#edf0e6;text-align:right;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.sx-card dd b{font-weight:600}
.sx-energy{padding-top:22px}
.sx-section-head{display:flex;justify-content:space-between;align-items:end;gap:12px;margin-bottom:12px}
.sx-section-head h2{font-size:20px}
.sx-energy-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));border-top:1px solid #526056;border-bottom:1px solid #526056}
.sx-energy-grid>div{display:flex;flex-direction:column;gap:5px;padding:14px 12px;border-right:1px solid #46534a;min-width:0}
.sx-energy-grid>div:last-child{border:0}
.sx-energy-grid span{color:#9fac9f;font-size:10px}.sx-energy-grid strong{font-size:16px;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.sx-footer{display:flex;gap:16px;flex-wrap:wrap;padding:13px 0 1px;color:#93a196;font:700 9px 'Helvetica Neue',sans-serif;letter-spacing:.8px}
.sx-footer b{color:#f1f1e4;letter-spacing:0;margin-left:4px;font-size:10px}
.sx-missing{color:#9fac9f!important}
@media(max-width:760px){.sx-main{padding:16px 15px}.sx-header{padding:13px 15px}.sx-hero{grid-template-columns:1fr;gap:18px}.sx-cards{grid-template-columns:repeat(2,minmax(0,1fr))}.sx-energy-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.sx-energy-grid>div:nth-child(2){border-right:0}.sx-energy-grid>div:nth-child(-n+2){border-bottom:1px solid #46534a}}
@media(max-width:500px){.sx-header{align-items:flex-start;flex-direction:column;gap:9px;padding:13px 12px}.sx-main{padding:14px 12px}.sx-hero{padding:16px 14px}.sx-total strong{font-size:42px}.sx-cards{grid-template-columns:1fr;gap:7px}.sx-energy-grid>div{padding:12px 8px}}
</style>
<script>
(function(){
    var root=document.querySelector('.solax-dashboard');
    if(!root)return;
    var device=root.getAttribute('data-device');
    var base=root.getAttribute('data-fhem-base');
    var readingNodes=root.querySelectorAll('[data-reading]');
    var connection=root.querySelector('[data-connection]');
    function numeric(value){
        var match=String(value==null?'':value).replace(',','.').match(/[-+]?[0-9]+(?:\.[0-9]+)?/);
        return match?Number(match[0]):null;
    }
    function value(readings,key){
        var reading=readings[key];
        return reading&&reading.Value!=null?String(reading.Value):'';
    }
    function render(result){
        var readings=result.Readings||{};
        Array.prototype.forEach.call(readingNodes,function(node){
            var reading=value(readings,node.getAttribute('data-reading'));
            node.textContent=reading!==''?reading:'--';
            node.classList.toggle('sx-missing',reading==='');
        });
        var pv1=numeric(value(readings,'pv1Power'))||0;
        var pv2=numeric(value(readings,'pv2Power'))||0;
        var total=numeric(value(readings,'pv_total_power'));
        if(total===null)total=pv1+pv2;
        root.querySelector('[data-total]').textContent=Number.isFinite(total)?Math.round(total).toLocaleString('de-DE'):'--';
        var pvScale=Math.max(pv1,pv2,1);
        ['pv1Power','pv2Power'].forEach(function(key){
            var bar=root.querySelector('[data-pv-bar="'+key+'"]');
            var power=numeric(value(readings,key));
            if(bar)bar.style.width=power===null?'0%':Math.max(2,Math.min(100,Math.abs(power)/pvScale*100))+'%';
        });
        var soc=numeric(value(readings,'batterySOC'));
        var socBar=root.querySelector('[data-soc-bar]');
        if(socBar)socBar.style.width=soc===null?'0%':Math.max(0,Math.min(100,soc))+'%';
        var batteryPower=numeric(value(readings,'batteryPower'));
        var batteryFlow=root.querySelector('[data-battery-flow]');
        if(batteryFlow)batteryFlow.textContent=batteryPower===null?'BATTERIE':batteryPower>0?'LAEDT':batteryPower<0?'ENTLAEDT':'BEREIT';
        var inverterStatus=root.querySelector('.sx-inverter-state');
        if(inverterStatus)inverterStatus.textContent=value(readings,'inverterStatus')||'Status unbekannt';
        var state=value(readings,'state')||result.Internals&&result.Internals.STATE||'';
        var isOnline=/^(?:opened|connected|ok|active)$/i.test(state);
        var isError=/^(?:closed|disconnected|offline|error|timeout)$/i.test(state);
        if(connection){var connectionState=isOnline?'online':isError?'error':'unknown';connection.setAttribute('data-state',connectionState);connection.title=state||'Status unbekannt';connection.setAttribute('aria-label',isOnline?'Modbus verbunden':isError?'Keine Verbindung':'Status unbekannt');}
    }
    function refresh(){
        fetch(base+'?cmd='+encodeURIComponent('jsonlist2 '+device)+'&XHR=1',{cache:'no-store',credentials:'same-origin'})
            .then(function(response){if(!response.ok)throw Error('HTTP '+response.status);return response.json();})
            .then(function(data){if(!data.Results||!data.Results.length)throw Error('Geraet nicht gefunden');render(data.Results[0]);})
            .catch(function(){if(connection){connection.setAttribute('data-state','error');connection.title='Keine Verbindung';connection.setAttribute('aria-label','Keine Verbindung');}});
    }
    refresh();
    window.setInterval(refresh,5000);
})();
</script>
