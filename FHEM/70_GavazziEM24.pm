##############################################################################
# FHEM logical Modbus device for Carlo Gavazzi EM24-DIN meters
#
# The register map follows EM24-DIN PFA, PFB and X models Communication
# Protocol, Version 4 Revision 0 (2012-12-03).
##############################################################################

package GavazziEM24;

use strict;
use warnings;

our $VERSION = '1.0.2';
use GPUtils qw(:all);

BEGIN {
    GP_Import(qw(LoadModule));
    GP_Export(qw(Initialize));
}

our %GavazziEM24_parseInfo = (
    # Instantaneous values, physical addresses from table 2.3.
    # keys use plain (non zero-padded) addresses: combined multi-object reads increment
    # the address numerically, so a zero-padded key here would never match again
    'i0' => { reading => 'voltageL1N', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i2' => { reading => 'voltageL2N', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i4' => { reading => 'voltageL3N', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i6' => { reading => 'voltageL1L2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i8' => { reading => 'voltageL2L3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i10' => { reading => 'voltageL3L1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i12' => { reading => 'currentL1', type => 'signed long', revRegs => 1, expr => '$val / 1000', format => '%.3f A', poll => 1 },
    'i14' => { reading => 'currentL2', type => 'signed long', revRegs => 1, expr => '$val / 1000', format => '%.3f A', poll => 1 },
    'i16' => { reading => 'currentL3', type => 'signed long', revRegs => 1, expr => '$val / 1000', format => '%.3f A', poll => 1 },
    # excluded from the normal cyclic poll (poll => 0); read via a dedicated fast timer instead (see PowerPollTimer)
    # this avoids the auto-combine logic pulling in whichever slow neighbor happens to be due that tick
    'i18' => { reading => 'activePowerL1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f W', poll => 0 },
    'i20' => { reading => 'activePowerL2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f W', poll => 0 },
    'i22' => { reading => 'activePowerL3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f W', poll => 0 },
    'i24' => { reading => 'apparentPowerL1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f VA', poll => 1 },
    'i26' => { reading => 'apparentPowerL2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f VA', poll => 1 },
    'i28' => { reading => 'apparentPowerL3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f VA', poll => 1 },
    'i30' => { reading => 'reactivePowerL1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f var', poll => 1 },
    'i32' => { reading => 'reactivePowerL2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f var', poll => 1 },
    'i34' => { reading => 'reactivePowerL3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f var', poll => 1 },
    'i36' => { reading => 'voltageLNMean', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    'i38' => { reading => 'voltageLLMean', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f V', poll => 1 },
    # activePowerTotal is not read via Modbus, it is computed from activePowerL1..L3 in ModbusReadingsFn
    'i42' => { reading => 'apparentPowerTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f VA', poll => 1 },
    'i44' => { reading => 'reactivePowerTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f var', poll => 1 },
    'i46' => { reading => 'demandActivePowerTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f W', poll => 1, polldelay => 0 },
    'i48' => { reading => 'demandApparentPowerTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f VA', poll => 1 },
    'i50' => { reading => 'powerFactorL1', type => 'signed short', expr => '$val / 1000', format => '%.3f', poll => 1 },
    'i51' => { reading => 'powerFactorL2', type => 'signed short', expr => '$val / 1000', format => '%.3f', poll => 1 },
    'i52' => { reading => 'powerFactorL3', type => 'signed short', expr => '$val / 1000', format => '%.3f', poll => 1 },
    'i53' => { reading => 'powerFactorTotal', type => 'signed short', expr => '$val / 1000', format => '%.3f', poll => 1 },
    'i54' => { reading => 'phaseSequence', type => 'signed short', map => '-1:L1-L3-L2, 0:L1-L2-L3', poll => 1 },
    'i55' => { reading => 'frequency', type => 'signed short', expr => '$val / 10', format => '%.1f Hz', poll => 1 },
    'i56' => { reading => 'demandActivePowerMax', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f W', poll => 1 },
    'i58' => { reading => 'demandApparentPowerMax', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f VA', poll => 1 },
    'i60' => { reading => 'demandCurrentMax', type => 'signed long', revRegs => 1, expr => '$val / 1000', format => '%.3f A', poll => 1 },
    'i62' => { reading => 'energyActiveImportTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i64' => { reading => 'energyReactiveImportTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i66' => { reading => 'energyActiveImportPartial', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i68' => { reading => 'energyReactiveImportPartial', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i70' => { reading => 'energyActiveImportL1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i72' => { reading => 'energyActiveImportL2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i74' => { reading => 'energyActiveImportL3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i76' => { reading => 'energyActiveImportTariff1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i78' => { reading => 'energyActiveImportTariff2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i80' => { reading => 'energyActiveImportTariff3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i82' => { reading => 'energyActiveImportTariff4', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i84' => { reading => 'energyReactiveImportTariff1', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i86' => { reading => 'energyReactiveImportTariff2', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i88' => { reading => 'energyReactiveImportTariff3', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i90' => { reading => 'energyReactiveImportTariff4', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i92' => { reading => 'energyActiveExportTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kWh', poll => 1 },
    'i94' => { reading => 'energyReactiveExportTotal', type => 'signed long', revRegs => 1, expr => '$val / 10', format => '%.1f kvarh', poll => 1 },
    'i96' => { reading => 'operatingHours', type => 'signed long', revRegs => 1, expr => '$val / 100', format => '%.2f h', poll => 1 },
    'i98' => { reading => 'digitalCounter1', type => 'signed long', revRegs => 1, poll => 1 },
    'i100' => { reading => 'digitalCounter2', type => 'signed long', revRegs => 1, poll => 1 },
    'i102' => { reading => 'digitalCounter3', type => 'signed long', revRegs => 1, poll => 1 },

    # Digital inputs, tariffs, identification and meter firmware.
    'i768' => { reading => 'digitalInputStatus', type => 'unsigned short', poll => 1 },
    'i769' => { reading => 'currentTariff', type => 'unsigned short', map => '0:Tariff1, 1:Tariff2, 2:Tariff3, 3:Tariff4', poll => 1 },
    'i770' => { reading => 'meterModelCode', type => 'unsigned short', poll => 1 },
    'i771' => { reading => 'meterFirmwareRevision', type => 'unsigned short', poll => 1 },
    'i772' => { reading => 'frontSelectorStatus', type => 'unsigned short', map => '0:unlocked, 1:unlocked, 2:unlocked, 3:locked', poll => 1 },
    'i11' => { reading => 'gavazziProductCode', type => 'unsigned short', poll => 1 },

    # Readable configuration registers (the module does not write them).
    'i4352' => { reading => 'parameterPassword', type => 'unsigned short', poll => 1 },
    'i4353' => { reading => 'applicationType', type => 'unsigned short', map => '0:A, 1:B, 2:C, 3:D, 4:E, 5:F, 6:G, 7:H', poll => 1 },
    'i4354' => { reading => 'measuringSystem', type => 'unsigned short', map => '0:3Pn, 1:3P1, 2:2P, 3:1P, 4:3P', poll => 1 },
    'i4355' => { reading => 'demandIntegrationTime', type => 'unsigned short', format => '%.0f min', poll => 1 },
    'i4356' => { reading => 'selectorPosition3', type => 'unsigned short', format => '%.0f', poll => 1 },
    'i4357' => { reading => 'selectorPosition2', type => 'unsigned short', format => '%.0f', poll => 1 },
    'i4358' => { reading => 'selectorPosition1', type => 'unsigned short', format => '%.0f', poll => 1 },
    'i4359' => { reading => 'selectorPosition0', type => 'unsigned short', format => '%.0f', poll => 1 },
    'i4360' => { reading => 'filterSpan', type => 'unsigned short', poll => 1 },
    'i4361' => { reading => 'filterCoefficient', type => 'unsigned short', poll => 1 },
    'i4362' => { reading => 'modbusAddress', type => 'unsigned short', poll => 1 },
    'i4363' => { reading => 'baudRateCode', type => 'unsigned short', map => '0:4800, 1:9600', poll => 1 },
    'i4364' => { reading => 'userId1', type => 'unsigned short', poll => 1 },
    'i4365' => { reading => 'userId2', type => 'unsigned short', poll => 1 },
    'i4366' => { reading => 'userId3', type => 'unsigned short', poll => 1 },
    'i4385' => { reading => 'digitalInput1Type', type => 'unsigned short', poll => 1 },
    'i4386' => { reading => 'digitalInput2Type', type => 'unsigned short', poll => 1 },
    'i4387' => { reading => 'digitalInput3Type', type => 'unsigned short', poll => 1 },
    'i4388' => { reading => 'digitalInput1Prescaler', type => 'unsigned short', poll => 1 },
    'i4389' => { reading => 'digitalInput2Prescaler', type => 'unsigned short', poll => 1 },
    'i4390' => { reading => 'digitalInput3Prescaler', type => 'unsigned short', poll => 1 },
    'i4391' => { reading => 'serialTariffControl', type => 'unsigned short', poll => 1 },
    'i4403' => { reading => 'digitalInput1Format', type => 'unsigned short', poll => 1 },
    'i4404' => { reading => 'digitalInput2Format', type => 'unsigned short', poll => 1 },
    'i4405' => { reading => 'digitalInput3Format', type => 'unsigned short', poll => 1 },
    'i4428' => { reading => 'currentTransformerRatio', type => 'unsigned long', revRegs => 1, poll => 1 },
    'i4430' => { reading => 'voltageTransformerRatio', type => 'unsigned long', revRegs => 1, poll => 1 },
    'i4864' => { reading => 'serialNumberWord1', type => 'unsigned short', poll => 1 },
    'i4865' => { reading => 'serialNumberWord2', type => 'unsigned short', poll => 1 },
    'i4866' => { reading => 'serialNumberWord3', type => 'unsigned short', poll => 1 },
    'i4867' => { reading => 'serialNumberWord4', type => 'unsigned short', poll => 1 },
    'i4868' => { reading => 'serialNumberWord5', type => 'unsigned short', poll => 1 },
    'i4869' => { reading => 'serialNumberWord6', type => 'unsigned short', poll => 1 },
    'i4870' => { reading => 'serialNumberWord7', type => 'unsigned short', poll => 1 },
    'i4871' => { reading => 'secondaryAddress', type => 'unsigned long', revRegs => 1, poll => 1 },
);

for my $inputAddress (grep { /^i\d+$/ } keys %GavazziEM24_parseInfo) {
    (my $holdingAddress = $inputAddress) =~ s/^i/h/;
    $GavazziEM24_parseInfo{$holdingAddress} = {
        %{ $GavazziEM24_parseInfo{$inputAddress} },
        poll => 0,
    };
}

our %GavazziEM24_deviceInfo = (
    'i' => { read => 4, combine => 11, defLen => 1, defFormat => '%.0f',
             defUnpack => 'n', defPoll => 1, defShowGet => 1, defPolldelay => 0 },
    'h' => { read => 3, combine => 11, defLen => 1, defFormat => '%.0f',
             defUnpack => 'n', defPoll => 0, defShowGet => 1, defPolldelay => 0 },
    'timing' => { timeout => 1, commDelay => 0.1 },
);

# German descriptions shown on the entity configuration page, keyed by reading name
our %GavazziEM24_descriptions = (
    voltageL1N => 'Spannung Phase L1 gegen Neutralleiter',
    voltageL2N => 'Spannung Phase L2 gegen Neutralleiter',
    voltageL3N => 'Spannung Phase L3 gegen Neutralleiter',
    voltageL1L2 => 'Spannung zwischen Phase L1 und L2',
    voltageL2L3 => 'Spannung zwischen Phase L2 und L3',
    voltageL3L1 => 'Spannung zwischen Phase L3 und L1',
    currentL1 => 'Strom Phase L1',
    currentL2 => 'Strom Phase L2',
    currentL3 => 'Strom Phase L3',
    activePowerL1 => 'Aktuelle Wirkleistung Phase L1',
    activePowerL2 => 'Aktuelle Wirkleistung Phase L2',
    activePowerL3 => 'Aktuelle Wirkleistung Phase L3',
    apparentPowerL1 => 'Scheinleistung Phase L1',
    apparentPowerL2 => 'Scheinleistung Phase L2',
    apparentPowerL3 => 'Scheinleistung Phase L3',
    reactivePowerL1 => 'Blindleistung Phase L1',
    reactivePowerL2 => 'Blindleistung Phase L2',
    reactivePowerL3 => 'Blindleistung Phase L3',
    voltageLNMean => 'Mittlere Spannung gegen Neutralleiter (alle Phasen)',
    voltageLLMean => 'Mittlere Außenleiterspannung (alle Phasen)',
    apparentPowerTotal => 'Gesamte Scheinleistung',
    reactivePowerTotal => 'Gesamte Blindleistung',
    demandActivePowerTotal => 'Momentane mittlere Wirkleistung (Demand)',
    demandApparentPowerTotal => 'Momentane mittlere Scheinleistung (Demand)',
    powerFactorL1 => 'Leistungsfaktor Phase L1',
    powerFactorL2 => 'Leistungsfaktor Phase L2',
    powerFactorL3 => 'Leistungsfaktor Phase L3',
    powerFactorTotal => 'Gesamter Leistungsfaktor',
    phaseSequence => 'Phasenfolge (Drehfeld)',
    frequency => 'Netzfrequenz',
    demandActivePowerMax => 'Maximale Wirkleistung (Spitzenwert Demand)',
    demandApparentPowerMax => 'Maximale Scheinleistung (Spitzenwert Demand)',
    demandCurrentMax => 'Maximaler Strom (Spitzenwert Demand)',
    energyActiveImportTotal => 'Wirkenergie Bezug gesamt',
    energyReactiveImportTotal => 'Blindenergie Bezug gesamt',
    energyActiveImportPartial => 'Wirkenergie Bezug Teilzähler',
    energyReactiveImportPartial => 'Blindenergie Bezug Teilzähler',
    energyActiveImportL1 => 'Wirkenergie Bezug Phase L1',
    energyActiveImportL2 => 'Wirkenergie Bezug Phase L2',
    energyActiveImportL3 => 'Wirkenergie Bezug Phase L3',
    energyActiveImportTariff1 => 'Wirkenergie Bezug Tarif 1',
    energyActiveImportTariff2 => 'Wirkenergie Bezug Tarif 2',
    energyActiveImportTariff3 => 'Wirkenergie Bezug Tarif 3',
    energyActiveImportTariff4 => 'Wirkenergie Bezug Tarif 4',
    energyReactiveImportTariff1 => 'Blindenergie Bezug Tarif 1',
    energyReactiveImportTariff2 => 'Blindenergie Bezug Tarif 2',
    energyReactiveImportTariff3 => 'Blindenergie Bezug Tarif 3',
    energyReactiveImportTariff4 => 'Blindenergie Bezug Tarif 4',
    energyActiveExportTotal => 'Wirkenergie Einspeisung gesamt',
    energyReactiveExportTotal => 'Blindenergie Einspeisung gesamt',
    operatingHours => 'Betriebsstunden des Zählers',
    digitalCounter1 => 'Digitalzähler Eingang 1',
    digitalCounter2 => 'Digitalzähler Eingang 2',
    digitalCounter3 => 'Digitalzähler Eingang 3',
    digitalInputStatus => 'Status der Digitaleingänge',
    currentTariff => 'Aktuell aktiver Tarif',
    meterModelCode => 'Modellcode des Zählers',
    meterFirmwareRevision => 'Firmware-Version des Zählers',
    frontSelectorStatus => 'Status des Fronttasters (gesperrt/entsperrt)',
    gavazziProductCode => 'Gavazzi Produktcode',
    parameterPassword => 'Parameter-Passwort (Konfigurationsregister)',
    applicationType => 'Anwendungstyp (Konfiguration)',
    measuringSystem => 'Messsystem, 1/2/3-phasig (Konfiguration)',
    demandIntegrationTime => 'Integrationszeit für die Demand-Berechnung',
    selectorPosition3 => 'Position des Frontwahlschalters, Ziffer 3',
    selectorPosition2 => 'Position des Frontwahlschalters, Ziffer 2',
    selectorPosition1 => 'Position des Frontwahlschalters, Ziffer 1',
    selectorPosition0 => 'Position des Frontwahlschalters, Ziffer 0',
    filterSpan => 'Filter-Spanne (Konfiguration)',
    filterCoefficient => 'Filterkoeffizient (Konfiguration)',
    modbusAddress => 'Eingestellte Modbus-Adresse des Zählers',
    baudRateCode => 'Eingestellte Baudrate (codiert)',
    userId1 => 'Benutzerdefinierte ID 1',
    userId2 => 'Benutzerdefinierte ID 2',
    userId3 => 'Benutzerdefinierte ID 3',
    digitalInput1Type => 'Typ des Digitaleingangs 1',
    digitalInput2Type => 'Typ des Digitaleingangs 2',
    digitalInput3Type => 'Typ des Digitaleingangs 3',
    digitalInput1Prescaler => 'Vorteiler des Digitaleingangs 1',
    digitalInput2Prescaler => 'Vorteiler des Digitaleingangs 2',
    digitalInput3Prescaler => 'Vorteiler des Digitaleingangs 3',
    serialTariffControl => 'Serielle Tarifsteuerung (Konfiguration)',
    digitalInput1Format => 'Format des Digitaleingangs 1',
    digitalInput2Format => 'Format des Digitaleingangs 2',
    digitalInput3Format => 'Format des Digitaleingangs 3',
    currentTransformerRatio => 'Übersetzungsverhältnis Stromwandler',
    voltageTransformerRatio => 'Übersetzungsverhältnis Spannungswandler',
    serialNumberWord1 => 'Seriennummer, Wort 1',
    serialNumberWord2 => 'Seriennummer, Wort 2',
    serialNumberWord3 => 'Seriennummer, Wort 3',
    serialNumberWord4 => 'Seriennummer, Wort 4',
    serialNumberWord5 => 'Seriennummer, Wort 5',
    serialNumberWord6 => 'Seriennummer, Wort 6',
    serialNumberWord7 => 'Seriennummer, Wort 7',
    secondaryAddress => 'Sekundäradresse des Zählers',
);

# default poll delay (seconds) for the slow objects, kept in sync with attr pollInterval
our $GavazziEM24_defaultPollInterval = 300;

# activePowerL1 register address and combined length covering L1..L3 (2 registers each)
our $GavazziEM24_PowerPollAdr = 18;
our $GavazziEM24_PowerPollLen = 6;

sub Initialize {
    my ($modHash) = @_;
    undef $GavazziEM24::DashboardTemplate;
    undef $GavazziEM24::EntityConfigTemplate;
    $modHash->{parseInfo} = \%GavazziEM24_parseInfo;
    $modHash->{deviceInfo} = \%GavazziEM24_deviceInfo;

    LoadModule('Modbus');
    Modbus::InitializeLD($modHash);
    $modHash->{AttrList} .= ' ' . $modHash->{ObjAttrList} . ' ' . $modHash->{DevAttrList};
    $modHash->{DefFn} = \&GavazziEM24::DefineFn;
    $modHash->{AttrFn} = \&GavazziEM24::AttrFn;
    $modHash->{GetFn} = \&GavazziEM24::GetFn;
    $modHash->{SetFn} = \&GavazziEM24::SetFn;
    $modHash->{NotifyFn} = \&GavazziEM24::NotifyFn;
    $modHash->{ModbusReadingsFn} = \&GavazziEM24::ModbusReadingsFn;
    $modHash->{AttrList} .= ' pollMode:active,passive pollInterval pollIntervalPower pollRegisters';
    delete $main::data{FWEXT}{'/GavazziEM24config'};
    $main::data{FWEXT}{'/GavazziEM24'}{FUNC} = 'GavazziEM24_DashboardCGI';
    $main::data{FWEXT}{'/GavazziEM24'}{FORKABLE} = 0;

    # a "reload" re-runs Initialize but fires no attr/notify events for existing
    # devices, so the dedicated power-poll timer has to be (re)started here
    if ($main::init_done) {
        foreach my $devName (keys %main::defs) {
            my $devHash = $main::defs{$devName};
            next if (!$devHash || $devHash->{TYPE} ne 'GavazziEM24');
            EnsureStateFormat($devName);
            next if (!$devHash->{MODE} || $devHash->{MODE} ne 'master');
            StartPowerPollTimer($devHash);
        }
    }
    else {
        main::InternalTimer(time() + 5, \&GavazziEM24::EnsureExistingStateFormats,
            'GavazziEM24_stateFormat', 0);
    }
    return;
}

sub DefineFn {
    my ($hash, $def) = @_;
    $def .= ' 1 passive RTU' if ($def =~ /^\S+\s+\S+\s*$/);
    $hash->{parseInfo} = { map { $_ => { %{$GavazziEM24_parseInfo{$_}} } } keys %GavazziEM24_parseInfo };
    ApplyPollRegisters($hash);
    my $ret = Modbus::DefineLDFn($hash, $def);
    $hash->{VERSION} = $VERSION;
    RemoveLegacyPollAttributes($hash->{NAME});
    EnsureStateFormat($hash->{NAME}) if (!defined($ret) || $ret eq '');
    return $ret;
}

sub EnsureStateFormat {
    my ($name) = @_;
    my $stateFormat = $main::attr{$name}{stateFormat};
    return if (defined($stateFormat) && $stateFormat ne 'state');
    $main::attr{$name}{stateFormat} = "{GavazziEM24::StateIcon('$name')}";
}

sub EnsureExistingStateFormats {
    for my $name (keys %main::defs) {
        next if (!$main::defs{$name} || $main::defs{$name}{TYPE} ne 'GavazziEM24');
        EnsureStateFormat($name);
    }
}

# Modbus's own NotifyFn starts the normal cyclic timer on the global INITIALIZED
# event; our dedicated power-poll timer needs the same hook, since AttrFn's
# init_done-gated startup code never runs while config lines are being replayed
sub NotifyFn {
    my ($hash, $source) = @_;
    my $ret = Modbus::NotifyFn($hash, $source);
    return $ret if (!$source || $source->{NAME} ne 'global');
    my $events = main::deviceEvents($source, 1);
    return $ret if (!$events || !grep { m/^(?:INITIALIZED|REREADCFG)$/ } @{$events});
    RemoveLegacyPollAttributes($hash->{NAME});
    StartPowerPollTimer($hash) if ($hash->{MODE} && $hash->{MODE} eq 'master');
    return $ret;
}

# dedicated fast timer for activePowerL1..L3, run independent of the normal cyclic poll
# so all three phases are always fetched together in one Modbus request, unaffected
# by whichever slow object happens to be due for the generic auto-combine that tick
sub PowerPollTimer {
    my ($param) = @_;
    my (undef, $name) = split(/:/, $param, 2);
    my $hash = $main::defs{$name};
    return if (!$hash || $hash->{MODE} ne 'master');
    my $interval = main::AttrVal($name, 'pollIntervalPower', $GavazziEM24_defaultPollInterval);
    main::RemoveInternalTimer("powerpoll:$name");
    main::InternalTimer(time() + $interval, \&GavazziEM24::PowerPollTimer, "powerpoll:$name", 0);

    # skip if a power-poll request for this block is already queued or in flight,
    # so a slow round-trip can not pile up duplicate requests and flood the queue
    my $ioHash = Modbus::GetIOHash($hash);
    if ($ioHash) {
        my $pending = grep { ($_->{TYPE} // '') eq 'i' && ($_->{ADR} // -1) == $GavazziEM24_PowerPollAdr } @{$ioHash->{QUEUE} || []};
        return if ($pending);
        return if ($ioHash->{REQUEST} && ($ioHash->{REQUEST}{TYPE} // '') eq 'i'
            && ($ioHash->{REQUEST}{ADR} // -1) == $GavazziEM24_PowerPollAdr);
    }
    Modbus::DoRequest($hash, {TYPE => 'i', ADR => $GavazziEM24_PowerPollAdr, LEN => $GavazziEM24_PowerPollLen,
        OPERATION => 'read', DBGINFO => 'fast phase power poll (L1-L3)'});
    return;
}

sub StartPowerPollTimer {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    main::RemoveInternalTimer("powerpoll:$name");
    main::InternalTimer(time(), \&GavazziEM24::PowerPollTimer, "powerpoll:$name", 0);
    return;
}

sub StopPowerPollTimer {
    my ($hash) = @_;
    main::RemoveInternalTimer("powerpoll:$hash->{NAME}");
    return;
}

# called by Modbus.pm for every parsed object instead of the generic readingsBulkUpdate
# used here to derive activePowerTotal from the phases in the same readings transaction
sub ModbusReadingsFn {
    my ($hash, $reading, $val) = @_;
    return if ($reading !~ /^activePowerL[123]$/);
    my $name = $hash->{NAME};
    main::readingsBulkUpdate($hash, $reading, $val);
    # $val already has the "%.1f W" format applied, so strip the unit before summing
    my $l1 = ($reading eq 'activePowerL1') ? NumericPart($val) : main::ReadingsNum($name, 'activePowerL1', 0);
    my $l2 = ($reading eq 'activePowerL2') ? NumericPart($val) : main::ReadingsNum($name, 'activePowerL2', 0);
    my $l3 = ($reading eq 'activePowerL3') ? NumericPart($val) : main::ReadingsNum($name, 'activePowerL3', 0);
    main::readingsBulkUpdate($hash, 'activePowerTotal', sprintf('%.1f', $l1 + $l2 + $l3));
    return 1;
}

sub NumericPart {
    my ($val) = @_;
    return 0 if (!defined($val));
    return ($val =~ /(-?\d+(?:\.\d+)?)/) ? $1 : 0;
}

sub AttrFn {
    my ($cmd, $name, $attrName, $attrValue) = @_;
    my $hash = $main::defs{$name};

    if ($cmd eq 'set' && $attrName eq 'pollMode'
        && $attrValue !~ /^(?:active|passive)$/) {
        return "pollMode must be active or passive";
    }
    if ($cmd eq 'set' && ($attrName eq 'pollInterval' || $attrName eq 'pollIntervalPower')
        && ($attrValue !~ /^\d+(?:\.\d+)?$/ || $attrValue <= 0)) {
        return "$attrName must be a positive number of seconds";
    }
    if ($cmd eq 'set' && $attrName eq 'pollRegisters') {
            return 'pollRegisters must contain entries like i0=1,i2=0'
            if (defined($attrValue) && $attrValue ne ''
                && $attrValue !~ /^\s*i\d+\s*=\s*[01](?:\s*[;,]\s*i\d+\s*=\s*[01])*\s*$/);
    }

    my $ret = Modbus::AttrLDFn($cmd, $name, $attrName, $attrValue);
    return $ret if (defined($ret) && $ret ne '');

    # config lines are replayed in arbitrary order at startup, so pollInterval/pollIntervalPower
    # must never re-derive or touch MODE - only react to the actual pollMode attribute
    return HandlePollModeChange($hash, $name, $cmd, $attrValue) if ($attrName eq 'pollMode');
    return HandlePollIntervalChange($hash, $name) if ($attrName eq 'pollInterval' || $attrName eq 'pollIntervalPower');
    if ($attrName eq 'pollRegisters') {
        my $states = PollRegisterMap($hash, $cmd eq 'set' ? ($attrValue // '') : '');
        my $reactivated = ApplyPollRegisters($hash, $states);
        my $canonical = PollRegisterList($hash, $states);
        if ($cmd eq 'set' && defined($attrValue) && $attrValue ne $canonical) {
            main::InternalTimer(time(), sub {
                main::CommandAttr(undef, "$name pollRegisters $canonical");
            }, $hash, 0);
        }
        RemoveLegacyPollAttributes($name);
        Modbus::GetUpdate("reread:$name")
            if ($cmd eq 'set' && $reactivated && ($hash->{MODE} // '') eq 'master');
        return;
    }
    return;
}

sub HandlePollModeChange {
    my ($hash, $name, $cmd, $attrValue) = @_;
    my $pollMode = ($cmd eq 'set') ? $attrValue : 'passive';
    my $tickInterval = CalcTickInterval($name);
    my $newMode = $pollMode eq 'active' ? 'master' : 'passive';
    my $oldMode = $hash->{MODE};
    my $oldInterval = $hash->{Interval};
    my $oldIoName = $hash->{IODev} ? $hash->{IODev}{NAME} : undef;

    return "passive mode requires a serial Modbus IODev"
        if ($newMode eq 'passive' && $hash->{TCPConn});

    if ($oldMode ne $newMode && $oldMode eq 'master' && $main::init_done) {
        Modbus::SetLDFn($hash, $name, 'stop');
        StopPowerPollTimer($hash);
    }
    if ($oldMode ne $newMode && !$hash->{TCPConn}) {
        Modbus::UnregAtIODev($hash);
        $hash->{MODE} = $newMode;
    }

    if ($newMode eq 'master') {
        $hash->{Interval} = $tickInterval;
    }
    else {
        delete $hash->{Interval};
        StopPowerPollTimer($hash);
    }

    if ($main::init_done && !$hash->{TCPConn}) {
        my $ioHash = Modbus::SetIODev($hash);
        if (!$ioHash) {
            $hash->{MODE} = $oldMode;
            $hash->{Interval} = $oldInterval if defined($oldInterval);
            Modbus::SetIODev($hash, $oldIoName) if $oldIoName;
            Modbus::SetLDFn($hash, $name, 'interval', $oldInterval)
                if ($oldMode eq 'master' && defined($oldInterval));
            return "no compatible Modbus IODev for $pollMode mode";
        }
    }

    if ($newMode eq 'master' && $main::init_done) {
        my $intervalResult = Modbus::SetLDFn($hash, $name, 'interval', $tickInterval);
        return $intervalResult
            if (defined($intervalResult) && $intervalResult ne '' && $intervalResult ne '0');
        StartPowerPollTimer($hash);
    }
    return;
}

# reacts to pollInterval / pollIntervalPower changes without ever touching MODE,
# so attribute order during config replay at startup can not break pollMode
sub HandlePollIntervalChange {
    my ($hash, $name) = @_;
    return if (!$hash || ($hash->{MODE} // '') ne 'master');
    my $tickInterval = CalcTickInterval($name);
    $hash->{Interval} = $tickInterval;
    return if (!$main::init_done);
    my $intervalResult = Modbus::SetLDFn($hash, $name, 'interval', $tickInterval);
    return $intervalResult
        if (defined($intervalResult) && $intervalResult ne '' && $intervalResult ne '0');
    StartPowerPollTimer($hash);
    return;
}

# the normal cyclic timer only serves the slow objects; activePowerL1..L3 have their
# own dedicated timer (see PowerPollTimer) so they never share a tick with slow objects
sub CalcTickInterval {
    my ($name) = @_;
    return main::AttrVal($name, 'pollInterval', $GavazziEM24_defaultPollInterval);
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
            or die "cannot read Gavazzi module template: $!";
        local $/;
        my $source = <$moduleFile>;
        close $moduleFile;
        ($DashboardTemplate) = $source =~ /^__DATA__\r?\n(.*?)\n__CONFIGDATA__/ms;
        die 'Gavazzi dashboard template is missing' if (!defined($DashboardTemplate));
    }

    my $name = HtmlEscape($hash->{NAME});
    my $basePath = HtmlEscape(DashboardBasePath());
    my $html = $DashboardTemplate;
    $html =~ s/__DEVICE__/$name/g;
    $html =~ s/__FHEM_BASE__/$basePath/g;
    main::Log3($hash, 3, 'GavazziEM24 DEBUG BuildDashboard name=' . $hash->{NAME}
        . ' templateLength=' . length($DashboardTemplate) . ' htmlLength=' . length($html));
    # Embed mode: fragment without html/head/body for FTUI and similar hosts
    return $html if ($embed);
    return '<!doctype html><html lang="de"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>' . $name . ' - EM24 Netzmonitor</title></head>'
        . '<body style="margin:0;background:#151f1b;padding:12px">'
        . $html . '</body></html>';
}

sub main::GavazziEM24_DashboardCGI {
    my ($request) = @_;
    $request = '' if (!defined($request));
    my ($path) = split(/\?/, $request, 2);
    my @parts = split('/', $path);
    my $name = $parts[-1];
    my $hash = $main::defs{$name};
    return ('text/plain; charset=utf-8', "Unknown GavazziEM24 device: $name")
        if (!$hash || $hash->{TYPE} ne 'GavazziEM24');

    my $embed = $request =~ /[?&]embed=1(?:&|$)/ ? 1 : 0;
    my $html = eval { GavazziEM24::BuildDashboard($hash, $embed) };
    if ($@ || !defined($html)) {
        main::Log3($name, 2, "$name: Gavazzi dashboard rendering failed: $@");
        return ('text/plain; charset=utf-8', "Dashboard rendering failed: $@");
    }
    return ('text/html; charset=utf-8', $html);
}

sub PollRegisterMap {
    my ($hash, $rawOverride) = @_;
    my %states = map { $_ => ($GavazziEM24_parseInfo{$_}{poll} ? 1 : 0) }
        grep { /^i\d+$/ } keys %GavazziEM24_parseInfo;
    my $raw = defined($rawOverride) ? $rawOverride
        : main::AttrVal($hash->{NAME}, 'pollRegisters', '');
    for my $entry (split(/[;,]/, $raw)) {
        next if ($entry !~ /^\s*(i\d+)\s*=\s*([01])\s*$/);
        $states{$1} = 0 + $2 if (exists($states{$1}));
    }
    return \%states;
}

sub PollRegisterList {
    my ($hash, $states) = @_;
    $states //= PollRegisterMap($hash);
    my @pairs = map { $_ . '=' . $states->{$_} } sort {
        $a =~ /i(\d+)/; my $aa = $1;
        $b =~ /i(\d+)/; my $bb = $1;
        $aa <=> $bb;
    } keys %{$states};
    my @chunks;
    while (@pairs) {
        push @chunks, join(',', splice(@pairs, 0, 10));
    }
    return join(', ', @chunks);
}

sub ApplyPollRegisters {
    my ($hash, $states) = @_;
    return if (!$hash || !$hash->{parseInfo});
    $states //= PollRegisterMap($hash);
    my $reactivated = 0;
    for my $key (keys %{$hash->{parseInfo}}) {
        next if ($key !~ /^i\d+$/ || !exists($states->{$key}));
        my $wasEnabled = $hash->{parseInfo}{$key}{poll} ? 1 : 0;
        if ($states->{$key} && !$wasEnabled) {
            $reactivated++;
            delete $hash->{lastRead}{$key} if ($hash->{lastRead});
        }
        $hash->{parseInfo}{$key}{poll} = $states->{$key};
    }
    delete $hash->{UPDATECACHE};
    delete $hash->{OICACHE};
    return $reactivated;
}

sub RemoveLegacyPollAttributes {
    my ($name) = @_;
    return if (!$main::attr{$name});
    for my $attrName (keys %{$main::attr{$name}}) {
        next if ($attrName !~ /^(?:obj-i\d+-poll|dev-i-defPolldelay)$/);
        main::CommandDeleteAttr(undef, "$name $attrName");
    }
    return;
}

# lists all pollable 'i' type objects (not the auto-generated 'h' copies) sorted by address
sub GetPollableObjects {
    my ($hash) = @_;
    my $parseInfo = $hash->{parseInfo} // \%GavazziEM24_parseInfo;
    my @objects;
    foreach my $key (keys %{$parseInfo}) {
        next if ($key !~ /^i(\d+)$/);
        my $adr = $1;
        my $oi = $parseInfo->{$key};
        push @objects, { key => $key, adr => $adr, reading => $oi->{reading},
            defaultPoll => ($oi->{poll} || $oi->{reading} =~ /^activePowerL[123]$/ ? 1 : 0) };
    }
    return sort { $a->{adr} <=> $b->{adr} } @objects;
}

our $EntityConfigTemplate;

sub BuildEntityConfig {
    my ($hash) = @_;
    if (!defined($EntityConfigTemplate)) {
        open my $moduleFile, '<', __FILE__
            or die "cannot read Gavazzi module template: $!";
        local $/;
        my $source = <$moduleFile>;
        close $moduleFile;
        ($EntityConfigTemplate) = $source =~ /^__CONFIGDATA__\r?\n(.*)\z/ms;
        die 'Gavazzi entity config template is missing' if (!defined($EntityConfigTemplate));
    }

    my $saveBase = HtmlEscape(DashboardBasePath());
    my $csrf = HtmlEscape($main::FW_CSRF // '');
    my $states = PollRegisterMap($hash);
    my @rows;
    foreach my $obj (GetPollableObjects($hash)) {
        my $reading = $obj->{reading};
        next if (!$reading);
        # activePowerL1..L3 are always fetched via the dedicated fast timer, not toggleable here
        my $isFastPower = ($reading =~ /^activePower(?:L1|L2|L3)$/);
        my $enabled = $isFastPower ? 1
            : (exists($states->{$obj->{key}}) ? $states->{$obj->{key}} : $obj->{defaultPoll});
        my $desc = HtmlEscape($GavazziEM24_descriptions{$reading} // '');
        my $checked = $enabled ? ' checked' : '';
        my $disabled = ' disabled';
        my $fixed = $isFastPower ? ' data-fixed="1"' : '';
        my $note = $isFastPower ? ' <small>(immer aktiv, schnelles Powerintervall)</small>' : '';
        my $inputAttrs = ' type="checkbox" data-key="' . HtmlEscape($obj->{key}) . '"' . $fixed . $checked . $disabled;
        my $switch = '<label class="gec-switch"><input' . $inputAttrs . '><span></span></label>';
        push @rows, '<tr><td>' . $switch . '</td>'
            . '<td class="gec-reading">' . HtmlEscape($reading) . $note . '</td>'
            . '<td class="gec-desc">' . $desc . '</td></tr>';
    }

    my $name = HtmlEscape($hash->{NAME});
    my $basePath = $saveBase;
    my $html = $EntityConfigTemplate;
    $html =~ s/__DEVICE__/$name/g;
    $html =~ s/__FHEM_BASE__/$basePath/g;
    $html =~ s/__FW_CSRF__/$csrf/g;
    $html =~ s/__ROWS__/join("\n", @rows)/e;
    main::Log3($hash, 3, 'GavazziEM24 DEBUG BuildEntityConfig name=' . $hash->{NAME}
        . ' rows=' . scalar(@rows) . ' csrf=' . ($csrf ne '' ? 'present' : 'missing')
        . ' rawPollRegisters=' . main::AttrVal($hash->{NAME}, 'pollRegisters', '<missing>')
        . ' state_i0=' . ($states->{i0} // '<missing>')
        . ' state_i12=' . ($states->{i12} // '<missing>')
        . ' state_i4870=' . ($states->{i4870} // '<missing>')
        . ' htmlLength=' . length($html));
    return $html;
}

sub ClearInactiveEntityReadings {
    my ($hash) = @_;
    return if (!$hash);

    my $states = PollRegisterMap($hash);
    my $parseInfo = $hash->{parseInfo} // \%GavazziEM24_parseInfo;
    my (%activeReadings, %inactiveReadings);
    for my $key (grep { /^i\d+$/ } keys %{$parseInfo}) {
        my $reading = $parseInfo->{$key}{reading};
        next if (!$reading);
        if (($states->{$key} // 0) || $reading =~ /^activePower(?:L1|L2|L3)$/) {
            $activeReadings{$reading} = 1;
        }
        else {
            $inactiveReadings{$reading} = 1;
        }
    }

    for my $reading (keys %inactiveReadings) {
        next if ($activeReadings{$reading});
        main::readingsDelete($hash, $reading) if (exists($hash->{READINGS}{$reading}));
    }
    return 'Readings bereinigt';
}

sub SetFn {
    my ($hash, $name, $cmd, @args) = @_;
    return BuildEntityConfig($hash) if ($cmd eq 'showEntityConfig');

    my $ret = Modbus::SetLDFn($hash, $name, $cmd, @args);
    if (defined($ret) && $ret =~ /^Unknown argument .*?, choose one of (.*)$/) {
        $ret = "Unknown argument $cmd, choose one of showEntityConfig:noArg $1";
    }
    return $ret;
}

sub GetFn {
    my ($hash, $name, $cmd, @args) = @_;
    main::Log3($hash, 3, 'GavazziEM24 DEBUG GetFn name=' . $name . ' cmd=' . ($cmd // 'undef'));
    return ClearInactiveEntityReadings($hash) if ($cmd eq '_finishEntityConfig');
    if ($cmd eq '_dashboardEmbedURL') {
        return DashboardBasePath() . '/GavazziEM24/' . main::urlEncode($name) . '?embed=1';
    }
    if ($cmd eq '_dashboardURL') {
        my $webName = $main::FW_wname;
        my $webHash = defined($webName) ? $main::defs{$webName} : undef;
        my $scheme = $webName && main::AttrVal($webName, 'HTTPS', 0) ? 'https' : 'http';
        my $host = $main::FW_httpheader{Host};
        if (!defined($host) || $host eq '') {
            my $port = $webHash && defined($webHash->{PORT}) ? $webHash->{PORT} : undef;
            $host = 'localhost' . (defined($port) && $port ne '' ? ":$port" : '');
        }
        return $scheme . '://' . $host . DashboardBasePath()
            . '/GavazziEM24/' . main::urlEncode($name);
    }
    return BuildDashboard($hash) if ($cmd eq '_showDashboard');
    return BuildEntityConfig($hash) if ($cmd eq '_showEntityConfig');

    my $ret = Modbus::GetLDFn($hash, $name, $cmd, @args);
    if (defined($ret) && $ret =~ /^Unknown argument .*?, choose one of (.*)$/) {
        $ret = "Unknown argument $cmd, choose one of _dashboardURL:noArg _dashboardEmbedURL:noArg _showDashboard:noArg _showEntityConfig:noArg $1";
    }
    return $ret;
}

1;

=pod
=item device
=item summary Modbus-Anbindung fuer Carlo-Gavazzi-EM24-DIN-Zaehler
=item summary_DE Modbus-Anbindung fuer Carlo-Gavazzi-EM24-DIN-Zaehler
=begin html

<a id="GavazziEM24"></a>
<h3>GavazziEM24</h3>

This logical Modbus device reads Carlo Gavazzi EM24-DIN PFA, PFB and X meters.
Its register map follows the manufacturer's EM24-DIN Communication Protocol,
Version 4 Revision 0. Signed and unsigned 32-bit readings use the meter's
low-word-first register order; values are scaled to the documented engineering
units. Input registers are read via function 04 and corresponding holding
registers are available via function 03. Writable holding registers can be
changed with the generic Modbus set commands where the meter permits it.
<br><br>

<b>Define</b>
<ul>
    <code>define &lt;name&gt; GavazziEM24</code> listens passively on Modbus RTU
    (default Modbus ID 1). Assign the serial Modbus device as IODev, e.g.
    <code>define GavazziRS485 Modbus /dev/ttyUSB0@9600</code> and
    <code>attr &lt;name&gt; IODev GavazziRS485</code>.<br>
    To select another meter ID explicitly, use
    <code>define &lt;name&gt; GavazziEM24 &lt;id&gt; passive RTU</code>.
    A physical Modbus IO device can also use Modbus TCP, for example
    <code>define GavazziTCP Modbus 192.168.1.50:502</code>, when a native TCP
    meter or an RTU-to-TCP gateway such as <code>mbusd</code> is available.
    Assign it with <code>attr &lt;name&gt; IODev GavazziTCP</code>; the meter's
    Modbus slave ID remains unchanged. TCP connections use active polling;
    passive mode is intended for a serial RTU bus.
</ul>

<b>Attributes</b>
<ul>
    <code>pollMode active|passive</code> selects active polling or passive bus
    monitoring. Passive is the default. <code>pollInterval &lt;seconds&gt;</code>
    sets the active polling interval (default: 300 seconds). Enabled readings
    are polled every cycle; active phase power uses
    <code>pollIntervalPower &lt;seconds&gt;</code>.
</ul>

<b>Readings</b>
<ul>
    In passive mode, readings are updated only for registers requested by the
    external Modbus master. Both function 03 (holding registers) and function
    04 (input registers) are mapped. Registers the external master never reads
    cannot produce readings in passive mode.
</ul>

<b>Writing registers</b>
<ul>
    Corresponding holding-register entries can be written through the inherited
    Modbus set handling, for example
    <code>set &lt;name&gt; demandIntegrationTime 15</code> or
    <code>set &lt;name&gt; modbusAddress 2</code>, if the meter model and register
    support the operation. The manufacturer's register permissions and any
    required parameter password or save sequence must be followed. Input
    registers and read-only meter values cannot be written.
</ul>

<b>Dashboard</b>
<ul>
    <code>get &lt;name&gt; _showDashboard</code> renders the dashboard inline.
</ul>

<b>Register configuration</b>
<ul>
    <code>get &lt;name&gt; _showEntityConfig</code> renders it inline. The selected
    registers are stored in the single <code>pollRegisters</code> attribute as
    entries such as <code>i0=1,i2=0</code>.
</ul>

<a name="GavazziEM24Feedback"></a>
<b>Feedback</b>
<ul>
    Questions, bug reports and ideas: <a href="https://github.com/stapetz/fhem-modules/issues/new/choose">GitHub issues</a>.
    Issues are public, so please do not post passwords, tokens or addresses.
</ul>

=end html
=cut

__DATA__
<section class="gavazzi-dashboard" data-device="__DEVICE__" data-fhem-base="__FHEM_BASE__" aria-label="Gavazzi EM24 Energie-Dashboard">
    <header class="ge24-header"><div class="ge24-brand"><span class="ge24-brand-mark" aria-hidden="true"><svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="3" width="16" height="18" rx="2"/><rect x="7" y="6" width="10" height="5" rx="1"/><path d="M8 15h1m3 0h1m3 0h1M9 18h6"/></svg></span><div><small>CARLO GAVAZZI / EM24</small><h1>Netzmonitor</h1></div></div><div class="ge24-live"><i class="ge24-led"></i><span class="ge24-state">warte auf Daten</span></div></header>
    <main class="ge24-main">
        <section class="ge24-instrument"><div class="ge24-instrument-top"><span>WIRKLEISTUNG / NETZ</span><span>EM24-DIN &#183; 3~</span></div><div class="ge24-display-row"><div class="ge24-dial"><div class="ge24-dial-track"></div><div class="ge24-dial-arc" data-power-arc></div><div class="ge24-dial-needle" data-power-needle></div><div class="ge24-dial-hub"></div><span>&#8722;</span><span>+</span></div><div class="ge24-lcd"><small>SUMME L1 + L2 + L3</small><strong data-reading="activePowerTotal">--</strong><div class="ge24-flow"><i></i><span data-flow>Leistung wird ermittelt</span></div></div></div><div class="ge24-instrument-bottom"><span>LEISTUNGSFAKTOR <b data-reading="powerFactorTotal">--</b></span><span>NETZFREQUENZ <b data-reading="frequency">--</b></span><span>PHASENFOLGE <b data-reading="phaseSequence">--</b></span></div></section>
        <section class="ge24-section"><div class="ge24-section-head"><div><small>LIVE / 3-PHASEN</small><h2>Phasenleistung</h2></div><small>W &#183; V &#183; A &#183; PF</small></div><div class="ge24-phases">
            <article class="ge24-phase" data-phase="L1"><div class="ge24-phase-head">L1</div><strong data-reading="activePowerL1">--</strong><div class="ge24-bar"><i data-bar="activePowerL1"></i></div><dl><div><dt>Spannung</dt><dd data-reading="voltageL1N">--</dd></div><div><dt>Strom</dt><dd data-reading="currentL1">--</dd></div><div><dt>Leistungsfaktor</dt><dd data-reading="powerFactorL1">--</dd></div></dl></article>
            <article class="ge24-phase" data-phase="L2"><div class="ge24-phase-head">L2</div><strong data-reading="activePowerL2">--</strong><div class="ge24-bar"><i data-bar="activePowerL2"></i></div><dl><div><dt>Spannung</dt><dd data-reading="voltageL2N">--</dd></div><div><dt>Strom</dt><dd data-reading="currentL2">--</dd></div><div><dt>Leistungsfaktor</dt><dd data-reading="powerFactorL2">--</dd></div></dl></article>
            <article class="ge24-phase" data-phase="L3"><div class="ge24-phase-head">L3</div><strong data-reading="activePowerL3">--</strong><div class="ge24-bar"><i data-bar="activePowerL3"></i></div><dl><div><dt>Spannung</dt><dd data-reading="voltageL3N">--</dd></div><div><dt>Strom</dt><dd data-reading="currentL3">--</dd></div><div><dt>Leistungsfaktor</dt><dd data-reading="powerFactorL3">--</dd></div></dl></article>
        </div></section>
        <section class="ge24-section"><div class="ge24-section-head"><div><small>ZAEHLERSTAENDE</small><h2>Energie</h2></div><small>kWh</small></div><div class="ge24-energy-grid"><div><i>&darr;</i><span>Bezug gesamt</span><strong data-reading="energyActiveImportTotal">--</strong></div><div><i>&uarr;</i><span>Einspeisung gesamt</span><strong data-reading="energyActiveExportTotal">--</strong></div><div><i>&sum;</i><span>Bezug Teilzaehler</span><strong data-reading="energyActiveImportPartial">--</strong></div><div><i>&#8599;</i><span>Leistungsspitze</span><strong data-reading="demandActivePowerMax">--</strong></div></div></section>
        <footer class="ge24-footer"><span>SPANNUNG L-L <b data-reading="voltageLLMean">--</b></span><span>SPANNUNG L-N <b data-reading="voltageLNMean">--</b></span><span>AKTUELLER TARIF <b data-reading="currentTariff">--</b></span><span>GAVAZZI EM24-DIN</span></footer>
    </main>
</section>
<style>
.gavazzi-dashboard{--ink:#1d2825;--mint:#52bd8b;--amber:#e3b953;--red:#d45b45;background:var(--ink);color:#f4f4e9;font:14px 'Avenir Next','Helvetica Neue',sans-serif;line-height:1.4;width:100%;max-width:1120px;margin:0 auto;overflow:hidden;border:1px solid #46544c;box-shadow:0 16px 44px #0c16124a}.gavazzi-dashboard *{box-sizing:border-box}.ge24-header{min-height:76px;padding:0 24px;display:flex;justify-content:space-between;align-items:center;gap:20px;background:#202e29;border-bottom:1px solid #405149}.ge24-brand{display:flex;align-items:center;gap:12px}.ge24-brand-mark{width:39px;height:39px;border:2px solid var(--mint);color:var(--mint);display:grid;place-items:center;font:700 22px Georgia,serif;border-radius:50%}.ge24-header small,.ge24-instrument-top,.ge24-instrument-bottom,.ge24-section-head small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac}.ge24-header h1,.ge24-section h2{font:500 22px Georgia,serif;margin:3px 0;letter-spacing:0;line-height:1.1}.ge24-live{display:grid;grid-template-columns:auto auto;gap:2px 8px;align-items:center;font-size:12px}.ge24-led{grid-row:1/3;width:8px;height:8px;border-radius:50%;background:#879088}.ge24-led[data-value="opened"],.ge24-led[data-value="ok"]{background:var(--mint);box-shadow:0 0 0 3px #52bd8b29}.ge24-live small{grid-column:2;font-size:10px}.ge24-main{padding:22px 24px 16px;background:linear-gradient(155deg,#26352e,#1b2823 62%,#202c27)}.ge24-instrument{padding:16px 19px 12px;background:#303d35;border:1px solid #536054;box-shadow:inset 0 0 0 4px #0d161231,0 8px 20px #0002}.ge24-instrument-top,.ge24-instrument-bottom{display:flex;justify-content:space-between;align-items:center;gap:12px;color:#bac5b8;font:700 9px 'Helvetica Neue',sans-serif;letter-spacing:1.2px}.ge24-display-row{min-height:178px;display:flex;align-items:center;justify-content:center;gap:30px;padding:9px 0 14px}.ge24-dial{width:168px;height:168px;position:relative;flex:0 0 168px;border-radius:50%}.ge24-dial-track,.ge24-dial-arc{position:absolute;inset:4px;border-radius:50%;mask:radial-gradient(farthest-side,transparent calc(100% - 10px),#000 calc(100% - 9px))}.ge24-dial-track{background:conic-gradient(from 225deg,#66756a 0deg 270deg,transparent 270deg)}.ge24-dial-arc{background:conic-gradient(from 225deg,var(--mint) 0deg 0deg,var(--amber) 0deg 0deg,var(--red) 0deg 0deg,transparent 0deg 360deg)}.ge24-dial-needle{position:absolute;left:50%;top:50%;width:2px;height:57px;background:#f4e9c5;transform-origin:50% calc(100% - 1px);transform:translate(-50%,-100%) rotate(-135deg);transition:transform .35s}.ge24-dial-hub{position:absolute;left:50%;top:50%;width:13px;height:13px;border-radius:50%;background:var(--amber);transform:translate(-50%,-50%);border:2px solid #25312c}.ge24-dial>span{position:absolute;bottom:12px;color:#bdc7bb;font:700 13px Georgia,serif}.ge24-dial>span:nth-last-child(2){left:16px}.ge24-dial>span:last-child{right:16px}.ge24-lcd{width:min(100%,490px);min-height:128px;padding:16px 21px;background:linear-gradient(150deg,#d8e3bc,#b7c99c);color:#20372d;border:5px solid #18231f;box-shadow:inset 0 0 0 1px #ffffff7a,0 0 0 1px #657568;display:flex;flex-direction:column;justify-content:center}.ge24-lcd small{font:700 9px 'Helvetica Neue',sans-serif;letter-spacing:1.5px;color:#4b6350}.ge24-lcd>strong{font:500 49px 'Avenir Next','Helvetica Neue',sans-serif;line-height:1.06;color:#172d23;font-variant-numeric:tabular-nums}.ge24-flow{display:flex;align-items:center;gap:7px;font:600 11px 'Helvetica Neue',sans-serif;color:#526650}.ge24-flow i{width:7px;height:7px;border-radius:50%;background:var(--mint)}.ge24-flow.is-export i{background:var(--red)}.ge24-instrument-bottom{border-top:1px solid #536054;padding-top:10px;flex-wrap:wrap}.ge24-instrument-bottom b,.ge24-footer b{color:#f1f1e4;letter-spacing:0;margin-left:4px;font-size:11px}.ge24-section{padding-top:22px}.ge24-section-head{display:flex;align-items:end;justify-content:space-between;gap:12px;margin-bottom:12px}.ge24-section-head h2{font-size:20px}.ge24-phases{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.ge24-phase{--phase:var(--mint);padding:14px 15px;background:#26342d;border-top:2px solid var(--phase);min-width:0}.ge24-phase[data-phase="L2"]{--phase:var(--amber)}.ge24-phase[data-phase="L3"]{--phase:#8ab6d1}.ge24-phase-head{font:500 17px Georgia,serif;color:var(--phase)}.ge24-phase>strong{display:block;margin:7px 0 9px;font:500 27px 'Avenir Next','Helvetica Neue',sans-serif;font-variant-numeric:tabular-nums;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.ge24-bar{height:3px;background:#45534a;margin-bottom:10px}.ge24-bar i{display:block;width:0;height:100%;background:var(--phase)}.ge24-phase dl{margin:0}.ge24-phase dl div{display:flex;justify-content:space-between;gap:10px;padding:4px 0;border-top:1px solid #cfddcf14;font-size:11px}.ge24-phase dt{color:#9fac9f}.ge24-phase dd{margin:0;color:#edf0e6;font-variant-numeric:tabular-nums;text-align:right}.ge24-energy-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));border-top:1px solid #526056;border-bottom:1px solid #526056}.ge24-energy-grid>div{display:grid;grid-template-columns:30px minmax(0,1fr);align-items:center;gap:2px 10px;padding:14px 12px;border-right:1px solid #46534a;min-width:0}.ge24-energy-grid>div:last-child{border:0}.ge24-energy-grid i{grid-row:1/3;display:grid;place-items:center;width:30px;height:30px;border:1px solid var(--mint);color:var(--mint);font:500 19px Georgia,serif;border-radius:50%;font-style:normal}.ge24-energy-grid>div:nth-child(2) i{border-color:#d67a5e;color:#d67a5e}.ge24-energy-grid span{color:#9fac9f;font-size:10px}.ge24-energy-grid strong{font-size:15px;font-variant-numeric:tabular-nums;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.ge24-footer{display:flex;gap:18px;flex-wrap:wrap;padding:13px 0 1px;color:#93a196;font:700 9px 'Helvetica Neue',sans-serif;letter-spacing:.9px}.ge24-footer b{font-size:10px}.ge24-error{color:#e9a38c!important}@media(max-width:760px){.ge24-main{padding:16px 15px}.ge24-display-row{gap:12px}.ge24-dial{width:128px;height:128px;flex-basis:128px}.ge24-dial-needle{height:43px}.ge24-lcd{min-height:110px;padding:12px}.ge24-lcd>strong{font-size:37px}.ge24-energy-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.ge24-energy-grid>div:nth-child(2){border-right:0}.ge24-energy-grid>div:nth-child(-n+2){border-bottom:1px solid #46534a}}@media(max-width:500px){.ge24-header{align-items:flex-start;flex-direction:column;gap:9px;padding:13px 15px}.ge24-display-row{flex-direction:column;gap:3px;padding:13px 0}.ge24-dial{width:120px;height:120px;flex-basis:120px}.ge24-dial-needle{height:40px}.ge24-lcd{width:100%;min-height:104px}.ge24-lcd>strong{font-size:34px}.ge24-phases{grid-template-columns:1fr;gap:7px}.ge24-phase{display:grid;grid-template-columns:58px minmax(115px,1fr) minmax(70px,.55fr);align-items:center;column-gap:10px;padding:11px 12px}.ge24-phase-head{grid-column:1}.ge24-phase>strong{grid-column:2;margin:0;font-size:21px}.ge24-bar{grid-column:3;margin:0}.ge24-phase dl{grid-column:1/-1;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-top:9px}.ge24-phase dl div{display:block;padding-top:5px}.ge24-phase dd{text-align:left;margin-top:2px}.ge24-energy-grid>div{padding:12px 8px}.ge24-energy-grid i{width:25px;height:25px}.ge24-energy-grid strong{font-size:13px}}
 .ge24-led[data-value="error"]{background:var(--red);box-shadow:0 0 0 3px #d45b4529}
</style>
<style>
.gavazzi-dashboard .ge24-live{display:flex;align-items:center}
.gavazzi-dashboard .ge24-state{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
.gavazzi-dashboard .ge24-led{display:block!important;width:12px;height:12px;border-radius:50%;background:#879088}
.gavazzi-dashboard .ge24-led[data-value="opened" i],.gavazzi-dashboard .ge24-led[data-value="ok" i]{background:#52bd8b;animation:ge24-live-pulse 4s ease-in-out infinite}
.gavazzi-dashboard .ge24-led[data-value="error" i],.gavazzi-dashboard .ge24-led[data-value="closed" i],.gavazzi-dashboard .ge24-led[data-value="disconnected" i],.gavazzi-dashboard .ge24-led[data-value="offline" i]{background:#d45b45;box-shadow:0 0 0 3px #d45b4540}
@keyframes ge24-live-pulse{0%,100%{opacity:.35;box-shadow:0 0 3px #52bd8b}50%{opacity:1;box-shadow:0 0 10px #52bd8b}}
</style>
<script>
(function(){var root=document.querySelector('.gavazzi-dashboard');if(!root)return;var device=root.getAttribute('data-device');var base=root.getAttribute('data-fhem-base');var nodes=root.querySelectorAll('[data-reading]');function num(v){var m=String(v==null?'':v).replace(',','.').match(/[-+]?[0-9]+(?:\.[0-9]+)?/);return m?Number(m[0]):null}function render(readings){nodes.forEach(function(node){var reading=readings[node.getAttribute('data-reading')];node.textContent=reading&&reading.Value!==''?reading.Value:'--';node.classList.toggle('ge24-error',!reading||reading.Value==='')});var total=num(readings.activePowerTotal&&readings.activePowerTotal.Value);if(total!==null){var fill=Math.min(Math.abs(total)/12000,1),angle=fill*270,arc=root.querySelector('[data-power-arc]'),needle=root.querySelector('[data-power-needle]'),flow=root.querySelector('[data-flow]'),flowBox=root.querySelector('.ge24-flow');if(arc)arc.style.background='conic-gradient(from 225deg,#52bd8b 0deg '+angle*.58+'deg,#e3b953 '+angle*.58+'deg '+angle*.82+'deg,#d45b45 '+angle*.82+'deg '+angle+'deg,transparent '+angle+'deg 360deg)';if(needle)needle.style.transform='translate(-50%,-100%) rotate('+(-135+fill*270)+'deg)';if(flow)flow.textContent=total<0?'Einspeisung ins Netz':'Energiebezug aus dem Netz';if(flowBox)flowBox.classList.toggle('is-export',total<0)}var powers=['activePowerL1','activePowerL2','activePowerL3'].map(function(k){return num(readings[k]&&readings[k].Value)}),max=Math.max.apply(null,powers.map(function(v){return v===null?0:Math.abs(v)}))||1;powers.forEach(function(v,i){var bar=root.querySelector('[data-bar="'+['activePowerL1','activePowerL2','activePowerL3'][i]+'"]');if(bar)bar.style.width=v===null?'0%':Math.max(3,Math.abs(v)/max*100)+'%'});var state=readings.state&&readings.state.Value||'warte auf Daten',led=root.querySelector('.ge24-led'),status=root.querySelector('.ge24-state');if(status)status.textContent=state;if(led)led.setAttribute('data-value',state)}function refresh(){fetch(base.replace(/\/$/,'')+'?cmd='+encodeURIComponent('jsonlist2 '+device)+'&XHR=1',{cache:'no-store'}).then(function(r){if(!r.ok)throw Error('HTTP '+r.status);return r.json()}).then(function(d){if(!d.Results||!d.Results.length)throw Error('Device nicht gefunden');render(d.Results[0].Readings||{})}).catch(function(){var s=root.querySelector('.ge24-state'),l=root.querySelector('.ge24-led');if(s)s.textContent='Verbindung fehlgeschlagen';if(l)l.setAttribute('data-value','error')})}refresh();window.setInterval(refresh,5000)})();
</script>

__CONFIGDATA__
<div class="gec" data-device="__DEVICE__" data-fhem-base="__FHEM_BASE__" data-csrf="__FW_CSRF__">
<div class="gec-head">
<div class="gec-brand"><span class="gec-brand-mark" aria-hidden="true"><svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="3" width="16" height="18" rx="2"/><rect x="7" y="6" width="10" height="5" rx="1"/><path d="M8 15h1m3 0h1m3 0h1M9 18h6"/></svg></span><div><small>CARLO GAVAZZI / EM24</small><h1>Register-Konfiguration __DEVICE__</h1></div></div>
<div class="gec-actions">
<button type="button" class="gec-edit" title="Bearbeiten" aria-label="Bearbeiten">&#9998;</button>
<div class="gec-edit-actions">
<button type="button" class="gec-cancel">Abbrechen</button>
<button type="button" class="gec-save">&#128190; Speichern</button>
</div>
<button type="button" class="gec-toggle-all">Alle auswählen</button>
<div class="gec-status" aria-live="polite"></div>
</div>
</div>
<div class="gec-note">Nicht benötigte Register abw&auml;hlen, um die Modbus-Buslast zu reduzieren. &Auml;nderungen wirken sofort, ohne Neustart.</div>
<div class="gec-list">
<table class="gec-table"><thead><tr><th>Aktiv</th><th>Reading</th><th>Beschreibung</th></tr></thead>
<tbody>
__ROWS__
</tbody></table>
</div>
</div>
<style>
.gec{font:14px 'Avenir Next','Helvetica Neue',sans-serif;color:#f4f4e9;max-width:1120px;height:100vh;margin:0 auto;display:flex;flex-direction:column;overflow:hidden;background:#1d2825;border:1px solid #46544c;box-shadow:0 16px 44px #0c16124a}
.gec-head{min-height:76px;flex:0 0 auto;padding:15px 24px;display:flex;justify-content:space-between;align-items:center;gap:20px;background:#202e29;border-bottom:1px solid #405149}
.gec-brand{display:flex;align-items:center;gap:12px;min-width:0}
.gec-brand-mark{width:39px;height:39px;flex:0 0 39px;border:2px solid #52bd8b;border-radius:50%;color:#52bd8b;display:grid;place-items:center}
.gec-head small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac}
.gec h1{font:500 22px Georgia,serif;margin:3px 0;letter-spacing:0}
.gec-note{flex:0 0 auto;padding:10px 24px;background:#26342d;color:#c7d0c8;border-bottom:1px solid #46534a;font-size:12px;line-height:1.45}
.gec-actions{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.gec-list{flex:1 1 auto;min-height:0;overflow:auto}
.gec-table{width:100%;border-collapse:collapse;background:#202e29;border:1px solid #46544c}
.gec-table th,.gec-table td{padding:8px 10px;border-bottom:1px solid #3a463f;text-align:left;vertical-align:middle}
.gec-table th{position:sticky;top:0;z-index:1;background:#202e29;color:#a9b7ac;font-size:11px;letter-spacing:.8px;text-transform:uppercase}
.gec-reading{font-weight:600;white-space:nowrap}
.gec-desc{color:#c7d0c8}
.gec-switch{display:inline-flex;align-items:center;justify-content:center;width:38px;height:22px;cursor:pointer}
.gec-switch input{display:block;width:18px;height:18px;margin:0;opacity:1;cursor:pointer;accent-color:#52bd8b}
.gec-switch input:disabled{opacity:.45;cursor:not-allowed}
.gec-switch span{display:none}
.gec-status{font-size:12px;color:#a9b7ac;min-height:16px}
.gec-edit,.gec-cancel,.gec-save,.gec-toggle-all{padding:8px 12px;border:1px solid #52bd8b;background:#26342d;color:#f4f4e9;cursor:pointer;font:600 12px 'Helvetica Neue',sans-serif}
.gec-edit{padding:0;border:0;background:none;font-size:28px;line-height:1;width:40px;height:40px}
.gec-edit:hover{color:#9ce2bb}
.gec-edit-actions{display:none;align-items:center;gap:8px}
.gec.edit-mode .gec-edit-actions{display:flex}
.gec-toggle-all{display:none}
.gec.edit-mode .gec-toggle-all{display:inline-block}
.gec-cancel,.gec-toggle-all{border-color:#69796f}
.gec button:disabled{opacity:.5;cursor:wait}
@media(max-width:760px){.gec-head{padding:13px 15px}.gec-note{padding:10px 15px}}
@media(max-width:500px){.gec-head{align-items:flex-start;flex-wrap:wrap;gap:10px}.gec-actions{width:100%;justify-content:flex-start}.gec-note{padding:9px 12px}.gec-table th,.gec-table td{padding:7px 6px}.gec-desc{min-width:180px}}
</style>
<script>
(function(){
    var root=document.querySelector('.gec');
    if(!root)return;
    var device=root.getAttribute('data-device');
    var base=root.getAttribute('data-fhem-base').replace(/\/$/,'');
    var csrf=root.getAttribute('data-csrf')||(typeof FW_CSRF==='string'?FW_CSRF:'');
    if(!csrf){var cookie=document.cookie.match(/(?:^|;\s*)fwcsrf=([^;]+)/);csrf=cookie?decodeURIComponent(cookie[1]):''}
    var status=root.querySelector('.gec-status');
    var editButton=root.querySelector('.gec-edit');
    var cancelButton=root.querySelector('.gec-cancel');
    var saveButton=root.querySelector('.gec-save');
    var toggleAll=root.querySelector('.gec-toggle-all');
    var fields=root.querySelectorAll('input[type=checkbox][data-key]');
    var selectable=root.querySelectorAll('input[type=checkbox][data-key]:not([data-fixed="1"])');
    var finishing=false;
    var originalStates=[];
    function requestCommand(command,keepalive){
        var url=base+'?cmd='+encodeURIComponent(command)+'&XHR=1';
        if(csrf)url+='&fwcsrf='+encodeURIComponent(csrf);
        return fetch(url,{cache:'no-store',credentials:'same-origin',keepalive:!!keepalive}).then(function(response){
            return response.text().then(function(text){
                if(!response.ok||/error|unknown|forbidden/i.test(text))throw new Error('HTTP '+response.status+' '+text.slice(0,120));
            });
        });
    }
    function reloadCaller(){
        var caller=window.opener&&!window.opener.closed?window.opener:(window.parent!==window?window.parent:null);
        if(caller)caller.location.reload();
    }
    function setEditMode(editing){
        root.classList.toggle('edit-mode',editing);
        Array.prototype.forEach.call(fields,function(field){
            field.disabled=!editing||field.getAttribute('data-fixed')==='1';
        });
        toggleAll.disabled=!editing;
        status.textContent='';
    }
    function beginEditing(){
        originalStates=Array.prototype.map.call(fields,function(field){return field.checked});
        setEditMode(true);
    }
    function cancelEditing(){
        Array.prototype.forEach.call(fields,function(field,index){field.checked=originalStates[index]});
        setEditMode(false);
        refreshToggleButton();
    }
    function saveConfig(){
        if(finishing)return;
        finishing=true;
        saveButton.disabled=true;
        cancelButton.disabled=true;
        toggleAll.disabled=true;
        var pairs=Array.prototype.map.call(fields,function(field){
            return field.getAttribute('data-key')+'='+(field.checked?'1':'0');
        });
        var chunks=[];
        for(var i=0;i<pairs.length;i+=10)chunks.push(pairs.slice(i,i+10).join(','));
        status.textContent='speichere...';
        requestCommand('attr '+device+' pollRegisters '+chunks.join(', '),false).then(function(){
            return requestCommand('save config',false);
        }).then(function(){
            return requestCommand('get '+device+' _finishEntityConfig',false);
        }).then(function(){
            originalStates=Array.prototype.map.call(fields,function(field){return field.checked});
            finishing=false;
            saveButton.disabled=false;
            cancelButton.disabled=false;
            setEditMode(false);
            refreshToggleButton();
            status.textContent='Konfiguration gespeichert.';
        }).catch(function(error){
            status.textContent='Fehler: '+error.message;
            finishing=false;
            saveButton.disabled=false;
            cancelButton.disabled=false;
            toggleAll.disabled=false;
        });
    }
    function ask(onDiscard,onSave){var o=document.createElement('div');o.style.cssText='position:fixed;top:0;right:0;bottom:0;left:0;background:rgba(0,0,0,.6);z-index:99999;display:flex;align-items:center;justify-content:center';var b=document.createElement('div');b.style.cssText='background:#1d2825;color:#f4f4e9;border:1px solid #46544c;padding:20px 24px;font:14px sans-serif;max-width:360px';var p=document.createElement('p');p.style.cssText='margin:0 0 16px';p.textContent='\u00c4nderungen verwerfen?';b.appendChild(p);function mk(t,fn){var x=document.createElement('button');x.type='button';x.textContent=t;x.style.cssText='margin:0 8px 0 0;padding:8px 12px;border:1px solid #52bd8b;background:#26342d;color:#f4f4e9;cursor:pointer;font:600 12px sans-serif';x.onclick=function(){o.remove();if(fn)fn();};b.appendChild(x);}mk('OK',onDiscard);mk('Abbrechen',null);mk('\u00c4nderungen speichern',onSave);o.appendChild(b);document.body.appendChild(o);}
    function toggleEditing(){
        if(!root.classList.contains('edit-mode')){beginEditing();return;}
        var changed=Array.prototype.some.call(fields,function(field,index){return field.checked!==originalStates[index]});
        if(!changed){cancelEditing();return;}
        ask(cancelEditing,saveConfig);
    }
    editButton.addEventListener('click',toggleEditing);
    cancelButton.addEventListener('click',cancelEditing);
    saveButton.addEventListener('click',saveConfig);
    if(window.jQuery){
        window.jQuery(document).on('dialogclose.gavazziEntityConfig','#FW_okDialog',function(){
            if(finishing)return;
            finishing=true;
            requestCommand('get '+device+' _finishEntityConfig',true).then(function(){
                window.location.reload();
            },function(){
                window.location.reload();
            });
        });
    }
    window.addEventListener('pagehide',function(){
        if(finishing)return;
        requestCommand('get '+device+' _finishEntityConfig',true).then(reloadCaller,reloadCaller);
    });
    function refreshToggleButton(){
        var allSelected=selectable.length>0&&Array.prototype.every.call(selectable,function(field){return field.checked});
        toggleAll.textContent=allSelected?'Alle abwählen':'Alle auswählen';
    }
    Array.prototype.forEach.call(selectable,function(field){
        field.addEventListener('change',refreshToggleButton);
    });
    toggleAll.addEventListener('click',function(){
        var allSelected=selectable.length>0&&Array.prototype.every.call(selectable,function(field){return field.checked});
        Array.prototype.forEach.call(selectable,function(field){field.checked=!allSelected});
        refreshToggleButton();
    });
    setEditMode(false);
    refreshToggleButton();
})();
</script>
