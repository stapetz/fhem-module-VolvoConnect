package main;

use strict;
use warnings;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(decode_base64);

our $ThermostatDashboard_VERSION = '1.1.1-dev';
our ($readingFnAttributes, $FW_wname, $FW_ME, $FW_CSRF);
our (%data, %defs, %modules, %FW_httpheader);

sub ThermostatDashboard_Initialize {
    my ($modHash) = @_;

    $modHash->{DefFn} = 'ThermostatDashboard_Define';
    $modHash->{GetFn} = 'ThermostatDashboard_Get';
    $modHash->{SetFn} = 'ThermostatDashboard_Set';
    $modHash->{UndefFn} = 'ThermostatDashboard_Undef';
    $modHash->{AttrList} = join(' ',
        'includeDevices',
        'excludeDevices',
        'autoRefresh:0,15,30,60',
        'showDeviceType:0,1',
        'showRoom:0,1',
        $main::readingFnAttributes,
    );

    $main::data{FWEXT}{'/ThermostatDashboard'}{FUNC} = 'ThermostatDashboard_CGI';
    $main::data{FWEXT}{'/ThermostatDashboard'}{FORKABLE} = 0;
}

sub ThermostatDashboard_Define {
    my ($hash, $def) = @_;
    my @args = split(/\s+/, $def);
    return 'Usage: define <name> ThermostatDashboard' if (@args != 2);
    $hash->{VERSION} = $ThermostatDashboard_VERSION;
    $hash->{STATE} = 'defined';
    return undef;
}

sub ThermostatDashboard_Set {
    my ($hash, $name, $cmd, @args) = @_;
    if (defined($cmd) && $cmd eq 'saveConfig') {
        my $error = ThermostatDashboard_SaveConfig($name, decode_base64(join('', @args)));
        return $error if (defined($error));
        return 'ThermostatDashboard-Konfiguration gespeichert.';
    }
    return 'Unknown argument ' . ($cmd // '') . ', choose one of saveConfig';
}

sub ThermostatDashboard_Undef {
    my ($hash, $arg) = @_;
    setKeyValue(ThermostatDashboard_ConfigKey($hash->{NAME}), undef);
    return undef;
}

sub ThermostatDashboard_ConfigKey {
    my ($name) = @_;
    return 'ThermostatDashboard_config_' . $name;
}

sub ThermostatDashboard_LoadHidden {
    my ($name) = @_;
    my ($error, $value) = getKeyValue(ThermostatDashboard_ConfigKey($name));
    return {} if ($error || !defined($value) || $value eq '');
    my $config = eval { decode_json($value) };
    return {} if (ref($config) ne 'HASH' || ref($config->{hidden}) ne 'ARRAY');
    return {map { defined($_) && !ref($_) && $_ ne '' ? ($_ => 1) : () } @{$config->{hidden}}};
}

sub ThermostatDashboard_SaveConfig {
    my ($name, $json) = @_;
    my $config = eval { decode_json($json || '') };
    return 'Ungueltige Konfiguration'
        if (ref($config) ne 'HASH' || ref($config->{hidden}) ne 'ARRAY'
            || grep { !defined($_) || ref($_) || $_ eq '' } @{$config->{hidden}});
    my %seen;
    my @hidden = grep { !$seen{$_}++ } @{$config->{hidden}};
    my $error = setKeyValue(ThermostatDashboard_ConfigKey($name), encode_json({hidden => \@hidden}));
    if (defined($error) && $error ne '') {
        Log3($name, 1, "ThermostatDashboard ($name): setKeyValue failed: $error");
        return 'Speichern fehlgeschlagen: ' . $error;
    }
    return undef;
}

sub ThermostatDashboard_BasePath {
    my $path = $main::FW_ME || '/fhem';
    $path =~ s{/$}{};
    return $path;
}

sub ThermostatDashboard_Get {
    my ($hash, $name, $cmd, @args) = @_;
    $cmd = '' if (!defined($cmd));

    return ThermostatDashboard_BuildDashboard($hash, {editable => 1}) if ($cmd eq '_showDashboard');
    if ($cmd eq '_dashboardEmbedURL') {
        return ThermostatDashboard_BasePath() . '/ThermostatDashboard/' . urlEncode($name) . '?embed=1';
    }
    if ($cmd eq '_dashboardURL') {
        my $scheme = AttrVal($main::FW_wname, 'HTTPS', 0) ? 'https' : 'http';
        my $host = $main::FW_httpheader{Host} || 'localhost';
        return $scheme . '://' . $host . ThermostatDashboard_BasePath()
            . '/ThermostatDashboard/' . urlEncode($name);
    }
    return ThermostatDashboard_Diagnose($name) if ($cmd eq 'diagnose');
    if ($cmd eq 'list') {
        my $devices = ThermostatDashboard_Discover($name);
        my $hidden = ThermostatDashboard_LoadHidden($name);
        return 'Keine kompatiblen Thermostate gefunden' if (!@{$devices});
        return join("\n", map {
            sprintf('%s (%s, %s)%s', $_->{alias}, $_->{name}, $_->{type},
                $hidden->{$_->{name}} ? ' [ausgeblendet]' : '')
        } @{$devices});
    }

    return 'Unknown argument ' . $cmd . ', choose one of diagnose:noArg list:noArg '
        . '_showDashboard:noArg _dashboardURL:noArg _dashboardEmbedURL:noArg';
}

sub ThermostatDashboard_Matches {
    my ($regex, $value) = @_;
    return 0 if (!defined($regex) || $regex eq '');
    my $matched = eval { $value =~ /$regex/ };
    return $matched ? 1 : 0;
}

sub ThermostatDashboard_HasCommand {
    my ($usage, $command) = @_;
    return 0 if (!defined($usage) || ref($usage));
    return $usage =~ /(?:^|\s)\Q$command\E(?:\s|\(|:|$)/ ? 1 : 0;
}

sub ThermostatDashboard_Reading {
    my ($device, @names) = @_;
    for my $name (@names) {
        my $entry = $device->{READINGS}{$name};
        next if (ref($entry) ne 'HASH' || !defined($entry->{VAL}));
        return {name => $name, value => $entry->{VAL}, time => $entry->{TIME} // ''};
    }
    return undef;
}

sub ThermostatDashboard_Number {
    my ($value) = @_;
    return undef if (!defined($value) || ref($value));
    return undef if ($value !~ /^\s*[-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)\s*(?:°?\s*[CFK])?\s*$/i);
    $value =~ s/,/./g;
    $value =~ /([-+]?(?:\d+(?:\.\d*)?|\.\d+))/;
    return 0 + $1;
}

sub ThermostatDashboard_SetUsage {
    my ($device, $name, $type) = @_;
    return undef if (!$main::modules{$type} || !$main::modules{$type}{SetFn});
    my $usage = eval { CallFn($name, 'SetFn', $device, $name, '?') };
    if ($@) {
        my $error = $@;
        $error =~ s/\s+$//;
        Log3($name, 2, "ThermostatDashboard ($name): SetFn ? fehlgeschlagen: $error");
        return undef;
    }
    return defined($usage) && !ref($usage) ? $usage : undef;
}

sub ThermostatDashboard_MatchesType {
    my ($device, $type) = @_;
    if ($type eq 'CUL_HM') {
        return $device->{READINGS}{'measured-temp'} && $device->{READINGS}{'desired-temp'} ? 1 : 0;
    }
    if ($type eq 'MAX') {
        return (($device->{type} // '') =~ /^(?:HeatingThermostat(?:Plus)?|WallMountedThermostat)$/
            || ($device->{model} // '') =~ /^(?:HeatingThermostat(?:Plus)?|WallMountedThermostat)$/) ? 1 : 0;
    }
    return 0;
}

sub ThermostatDashboard_Discover {
    my ($dashboardName) = @_;
    my $include = AttrVal($dashboardName, 'includeDevices', '');
    my $exclude = AttrVal($dashboardName, 'excludeDevices', '');
    my @found;

    for my $name (sort keys %main::defs) {
        my $device = $main::defs{$name};
        next if (ref($device) ne 'HASH' || $name eq $dashboardName);
        my $type = $device->{TYPE} // '';
        next if ($type ne 'CUL_HM' && $type ne 'MAX');
        next if (AttrVal($name, 'disable', 0));
        next if ($include ne '' && !ThermostatDashboard_Matches($include, $name));
        next if (ThermostatDashboard_Matches($exclude, $name));
        next if (!ThermostatDashboard_MatchesType($device, $type));

        my $usage = ThermostatDashboard_SetUsage($device, $name, $type);
        my $temperatureCommand = $type eq 'MAX' ? 'desiredTemperature' : 'desired-temp';
        next if (!ThermostatDashboard_HasCommand($usage, $temperatureCommand));

        my $actual = $type eq 'MAX'
            ? ThermostatDashboard_Reading($device, 'temperature', 'measured-temp')
            : ThermostatDashboard_Reading($device, 'measured-temp', 'temperature');
        my $target = $type eq 'MAX'
            ? ThermostatDashboard_Reading($device, 'desiredTemperature', 'desired-temp')
            : ThermostatDashboard_Reading($device, 'desired-temp', 'desiredTemperature');
        next if (!$actual || !$target);

        my @modes;
        my $modeCommand = $type eq 'MAX' ? 'desiredTemperature' : 'controlMode';
        if (ThermostatDashboard_HasCommand($usage, $modeCommand)) {
            if ($type eq 'MAX') {
                my %labels = (
                    auto => 'Auto',
                    eco => 'Eco',
                    comfort => 'Komfort',
                    boost => 'Boost',
                    manual => 'Manuell',
                );
                @modes = map { [$modeCommand, $_, $labels{$_}] }
                    qw(auto eco comfort boost manual);
            } elsif ($usage =~ /\bcontrolMode(?:\s+\(([^)]*)\)|:([A-Za-z0-9_|,-]+))/) {
                my %labels = (
                    auto => 'Auto',
                    manual => 'Manuell',
                    boost => 'Boost',
                    day => 'Tag',
                    night => 'Nacht',
                );
                my $modeOptions = defined($1) ? $1 : $2;
                @modes = map { [$modeCommand, $_, $labels{$_} // $_] }
                    grep { exists($labels{$_}) } split(/[|,]/, $modeOptions);
            }
        }

        my ($minimum, $maximum) = (5, 30);
        if ($type eq 'CUL_HM'
            && $usage =~ /\b\Q$temperatureCommand\E\s+\([^)]*?(\d+(?:\.\d+)?)\.\.(\d+(?:\.\d+)?)/) {
            $minimum = $1 if ($1 > $minimum);
            $maximum = $2 if ($2 < $maximum);
        }
        my $room = AttrVal($name, 'room', '');
        ($room) = split(/,/, $room, 2);
        $room = '' if (!defined($room));

        push @found, {
            name => $name,
            type => $type,
            alias => AttrVal($name, 'alias', $name),
            room => $room,
            model => AttrVal($name, 'model', $device->{type} // $type),
            actual => $actual,
            target => $target,
            mode => ThermostatDashboard_Reading($device, 'controlMode', 'mode'),
            valve => ThermostatDashboard_Reading($device, 'ValvePosition', 'valveposition'),
            battery => ThermostatDashboard_Reading($device, 'batteryState', 'battery'),
            modes => \@modes,
            temperatureCommand => $temperatureCommand,
            minimum => $minimum,
            maximum => $maximum,
        };
    }

    return [sort {
        lc($a->{room}) cmp lc($b->{room}) || lc($a->{alias}) cmp lc($b->{alias})
    } @found];
}

sub ThermostatDashboard_Diagnose {
    my ($dashboardName) = @_;
    my $hidden = ThermostatDashboard_LoadHidden($dashboardName);
    my @lines;
    for my $name (sort keys %main::defs) {
        my $device = $main::defs{$name};
        next if (ref($device) ne 'HASH' || $name eq $dashboardName);
        my $type = $device->{TYPE} // '';
        next if ($type ne 'CUL_HM' && $type ne 'MAX');
        my $reason;
        if (AttrVal($name, 'disable', 0)) {
            $reason = 'disable gesetzt';
        } else {
            my $usage = ThermostatDashboard_SetUsage($device, $name, $type);
            my $temperatureCommand = $type eq 'MAX' ? 'desiredTemperature' : 'desired-temp';
            if (!ThermostatDashboard_MatchesType($device, $type)) {
                $reason = 'kein unterstützter Thermostat-Typ';
            } elsif (!ThermostatDashboard_HasCommand($usage, $temperatureCommand)) {
                $reason = "Set-Befehl $temperatureCommand fehlt";
            } elsif (!$device->{READINGS}{temperature} && !$device->{READINGS}{'measured-temp'}) {
                $reason = 'kein Temperatur-Reading';
            } else {
                $reason = 'OK';
            }
        }
        $reason .= ' (im Dashboard ausgeblendet)' if ($reason eq 'OK' && $hidden->{$name});
        push @lines, "$name ($type): $reason";
    }
    return @lines ? join("\n", @lines) : 'Keine CUL_HM- oder MAX-Geräte gefunden';
}

sub ThermostatDashboard_Escape {
    my ($text) = @_;
    $text = '' if (!defined($text));
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

sub ThermostatDashboard_Css {
    return <<'CSS';
<style>
.td,.td *{box-sizing:border-box;letter-spacing:normal;text-transform:none;text-shadow:none}
.td{font:14px 'Avenir Next','Helvetica Neue',sans-serif!important;line-height:1.4;color:#f4f4e9;max-width:1120px;min-height:100vh;margin:0 auto;background:#1d2825;border:1px solid #46544c}
.td-head{min-height:76px;padding:0 24px;display:flex;align-items:center;justify-content:space-between;gap:16px;background:#202e29;border-bottom:1px solid #405149}
.td-brand{display:flex;align-items:center;gap:12px;min-width:0}
.td-brand-mark{width:39px;height:39px;flex:0 0 39px;border:2px solid #52bd8b;border-radius:50%;display:grid;place-items:center;color:#52bd8b}
.td-brand-mark svg{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.td-head small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac}
.td h1{font:500 22px/1.1 Georgia,serif;margin:3px 0}
.td-head-actions{display:flex;align-items:center;justify-content:flex-end;gap:8px;flex-wrap:wrap}
.td-edit,.td-cancel,.td-save{padding:8px 12px;border:1px solid #52bd8b;background:#26342d;color:#f4f4e9;cursor:pointer;font:600 12px 'Helvetica Neue',sans-serif}
.td button.td-edit{font-size:22px;line-height:1;min-width:40px;min-height:40px;padding:0;border:0;background:transparent;color:#f4f4e9}
.td button.td-edit:hover{background:transparent;color:#9ce2bb}
.td-cancel{border-color:#69796f}
.td-dialog-open{position:fixed;inset:0;z-index:10000;display:grid;place-items:center;padding:20px;background:#0c1612b8}
.td-dialog-open[hidden]{display:none}
.td-edit-dialog{width:min(560px,100%);max-height:min(80vh,720px);display:flex;flex-direction:column;background:#1d2825;border:1px solid #526459;box-shadow:0 16px 44px #0c161280;color:#f4f4e9}
.td-dialog-head{padding:16px 20px;border-bottom:1px solid #405149;background:#202e29}
.td-dialog-head h2{margin:0;font:500 20px Georgia,serif}
.td-dialog-head p{margin:5px 0 0;color:#a9b7ac;font-size:12px}
.td-dialog-list{min-height:0;overflow:auto;padding:8px 20px}
.td-edit-row{display:flex;align-items:center;gap:11px;padding:10px 4px;border-bottom:1px solid #cfddcf14;cursor:pointer}
.td-edit-row input{width:18px;height:18px;flex:0 0 18px;margin:0;accent-color:#52bd8b}
.td-edit-row span{min-width:0;display:flex;flex-direction:column;gap:2px}
.td-edit-row strong{font-weight:600;overflow-wrap:anywhere}
.td-edit-row small{color:#9fac9f;font-size:11px}
.td-dialog-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 20px;border-top:1px solid #405149;background:#202e29}
.td-dialog-actions{display:flex;justify-content:flex-end;gap:8px}
.td-dialog-footer button:disabled{opacity:.5;cursor:wait}
.td-dialog-status{min-height:16px;color:#a9b7ac;font-size:11px}
.td-dialog-status[data-error="1"]{color:#ef9a8b}
.td-grid{padding:12px;display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,310px),1fr));gap:12px}
.td-card{min-width:0;background:#202e29;border:1px solid #46544c}
.td-card[data-hidden="1"]{display:none}
.td.edit-mode .td-card[data-hidden="1"]{display:block;opacity:.55;border-style:dashed}
.td-card-head{padding:12px 14px;display:flex;justify-content:space-between;align-items:flex-start;gap:10px;border-bottom:1px solid #3a463f}
.td-room{font-size:10px;font-weight:700;letter-spacing:1px;color:#9fb3a8;text-transform:uppercase}
.td-name{font:500 18px Georgia,serif;margin:2px 0 0;overflow-wrap:anywhere}
.td-model{color:#9fb3a8;font-size:11px;text-align:right}
.td-values{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:14px}
.td-value{padding:10px;background:#1d2825;border:1px solid #3a463f}
.td-value-label{display:block;color:#9fb3a8;font-size:10px;text-transform:uppercase;letter-spacing:.8px}
.td-value strong{display:block;margin-top:3px;font-size:24px;line-height:1.15;font-weight:600;white-space:nowrap}
.td-value small{font-size:13px;font-weight:400;color:#a9b7ac}
.td-target-control{display:flex;align-items:baseline;gap:5px;margin-top:3px}
.td-target-control input{width:100%;min-width:0;padding:0;border:0;outline:0;background:transparent;color:#f4f4e9;font:600 24px/1.15 'Avenir Next','Helvetica Neue',sans-serif;font-variant-numeric:tabular-nums}
.td-target-control input::-webkit-inner-spin-button,.td-target-control input::-webkit-outer-spin-button{opacity:.65}
.td-target-control input:focus{color:#9ce2bb}
.td-meta{display:flex;flex-wrap:wrap;gap:7px;padding:0 14px 12px}
.td-badge{padding:3px 7px;border:1px solid #46544c;color:#c7d0c8;font-size:11px}
.td-controls{padding:12px 14px;border-top:1px solid #3a463f}
.td button{min-height:34px;padding:6px 11px;background:#26342d;color:#f4f4e9;border:1px solid #52bd8b;font:600 12px 'Helvetica Neue',sans-serif;cursor:pointer}
.td button:hover{background:#30453a}
.td button:disabled{opacity:.5;cursor:wait}
.td-modes{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
.td-modes button{min-height:30px;padding:4px 9px;border-color:#69796f}
.td-modes button[data-active="1"]{background:#52bd8b;color:#17231e;border-color:#9ce2bb;box-shadow:0 0 0 2px #52bd8b40}
.td-modes button[data-active="1"]:hover{background:#52bd8b;color:#17231e}
.td-status{min-height:18px;margin-top:7px;color:#a9b7ac;font-size:11px}
.td-status[data-error="1"]{color:#ef9a8b}
.td-status[data-success="1"]{color:#9ce2bb}
.td-empty{margin:12px;padding:18px;background:#202e29;border:1px solid #46544c;color:#c7d0c8}
@media(max-width:600px){.td-head{padding:12px 15px;align-items:flex-start;flex-direction:row;gap:8px}.td-head-actions{width:auto;justify-content:flex-end;margin-left:auto}.td-grid{padding:8px;gap:8px}.td-dialog-open{padding:10px}.td-dialog-list{padding:6px 14px}.td-dialog-head,.td-dialog-footer{padding:13px 14px}}
</style>
CSS
}

sub ThermostatDashboard_BuildDashboard {
    my ($hash, $options) = @_;
    $options ||= {};
    my $name = $hash->{NAME};
    my $devices = ThermostatDashboard_Discover($name);
    my $hidden = ThermostatDashboard_LoadHidden($name);
    my $base = ThermostatDashboard_Escape(ThermostatDashboard_BasePath());
    my $csrf = $main::FW_CSRF // '';
    $csrf =~ s/^&?fwcsrf=//;
    $csrf = ThermostatDashboard_Escape($csrf);
    my $refresh = AttrVal($name, 'autoRefresh', 15);
    $refresh = 15 if ($refresh !~ /^(?:0|15|30|60)$/);
    my $showDeviceType = AttrVal($name, 'showDeviceType', 1) ? 1 : 0;
    my $showRoom = AttrVal($name, 'showRoom', 1) ? 1 : 0;
    my $html = ThermostatDashboard_Css()
        . '<div class="td" data-base="' . $base . '" data-csrf="' . $csrf . '" data-device="'
        . ThermostatDashboard_Escape($name) . '" data-refresh="' . $refresh . '">'
        . '<header class="td-head"><div class="td-brand"><span class="td-brand-mark" aria-hidden="true">'
        . '<svg viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="13" rx="1"/>'
        . '<path d="M8 6v11m4-11v11m4-11v11M6 18v2m12-2v2M20 9h2v5h-2"/></svg></span>'
        . '<div><small>HEIZUNG / THERMOSTATE</small><h1>Thermostate</h1></div></div>'
        . '<div class="td-head-actions">'
        . ($options->{editable} ? '<button type="button" class="td-edit" title="Bearbeiten" aria-label="Thermostate bearbeiten">&#9998;</button>' : '')
        . '</div></header>';

    if ($options->{editable}) {
        $html .= '<div class="td-dialog-open" data-dialog-backdrop hidden><section class="td-edit-dialog" role="dialog" '
        . 'aria-modal="true" aria-labelledby="td-dialog-title"><header class="td-dialog-head">'
        . '<h2 id="td-dialog-title">Thermostate anzeigen</h2><p>W&auml;hle aus, welche Ger&auml;te im Dashboard erscheinen.</p></header>'
        . '<div class="td-dialog-list">';
        for my $device (@{$devices}) {
            my $isHidden = $hidden->{$device->{name}} ? 1 : 0;
            my $room = $device->{room} ne '' ? $device->{room} : 'Ohne Raum';
            $html .= '<label class="td-edit-row"><input type="checkbox" data-visible data-device="'
                . ThermostatDashboard_Escape($device->{name}) . '"' . ($isHidden ? '' : ' checked') . '>'
                . '<span><strong>' . ThermostatDashboard_Escape($device->{alias}) . '</strong><small>'
                . ThermostatDashboard_Escape($room) . ' &middot; ' . ThermostatDashboard_Escape($device->{model})
                . '</small></span></label>';
        }
        $html .= '</div><footer class="td-dialog-footer"><span class="td-dialog-status" aria-live="polite"></span>'
            . '<div class="td-dialog-actions"><button type="button" class="td-cancel">Abbrechen</button>'
            . '<button type="button" class="td-save">Speichern</button></div></footer></section></div>';
    }

    if (!@{$devices}) {
        $html .= '<div class="td-empty">Keine kompatiblen Thermostate gefunden. Unterst&uuml;tzt werden '
            . 'CUL_HM-Ger&auml;te mit Temperatur- und Sollwert-Readings sowie MAX-Heizungs-'
            . 'thermostate.</div>';
    } else {
        $html .= '<main class="td-grid">';
        for my $device (@{$devices}) {
            my $actual = ThermostatDashboard_Number($device->{actual}{value});
            my $target = ThermostatDashboard_Number($device->{target}{value});
            my $mode = $device->{mode} ? $device->{mode}{value} : '';
            my $valve = $device->{valve} ? $device->{valve}{value} : '';
            my $battery = $device->{battery} ? $device->{battery}{value} : '';
            my $targetValue = defined($target) ? sprintf('%.1f', $target) : '';
            my $room = $device->{room} ne '' ? $device->{room} : 'Ohne Raum';
            my $isHidden = $hidden->{$device->{name}} ? 1 : 0;
            $html .= '<section class="td-card" data-hidden="' . $isHidden . '" data-device="' . ThermostatDashboard_Escape($device->{name})
                . '" data-actual="' . ThermostatDashboard_Escape($device->{actual}{name})
                . '" data-target="' . ThermostatDashboard_Escape($device->{target}{name})
                . '" data-mode="' . ThermostatDashboard_Escape($device->{mode} ? $device->{mode}{name} : '')
                . '" data-valve="' . ThermostatDashboard_Escape($device->{valve} ? $device->{valve}{name} : '')
                . '" data-battery="' . ThermostatDashboard_Escape($device->{battery} ? $device->{battery}{name} : '')
                . '" data-command="' . ThermostatDashboard_Escape($device->{temperatureCommand})
                . '" data-min="' . $device->{minimum} . '" data-max="' . $device->{maximum} . '">'
                . '<header class="td-card-head"><div>'
                . ($showRoom ? '<div class="td-room">' . ThermostatDashboard_Escape($room) . '</div>' : '')
                . '<h2 class="td-name">'
                . ThermostatDashboard_Escape($device->{alias}) . '</h2></div><div class="td-model">'
                . ($showDeviceType ? ThermostatDashboard_Escape($device->{model}) : '') . '</div></header>'
                . '<div class="td-values"><div class="td-value"><span class="td-value-label">Isttemperatur</span>'
                . '<strong data-value="actual">' . (defined($actual) ? sprintf('%.1f', $actual) : '&ndash;')
                . ' <small>&deg;C</small></strong></div><div class="td-value">'
                . '<span class="td-value-label">Solltemperatur</span><div class="td-target-control">'
                . '<input data-temp type="number" min="' . $device->{minimum} . '" max="' . $device->{maximum}
                . '" step="0.5" value="' . $targetValue . '" aria-label="Solltemperatur in Grad Celsius">'
                . '<small>&deg;C</small></div></div></div>'
                . '<div class="td-meta">'
                . '<span class="td-badge" data-value="mode">' . ($mode ne '' ? ThermostatDashboard_Escape($mode) : 'Modus unbekannt') . '</span>'
                . ($valve ne '' ? '<span class="td-badge" data-dynamic="1">Ventil ' . ThermostatDashboard_Escape($valve) . '%</span>' : '')
                . ($battery ne '' ? '<span class="td-badge" data-dynamic="1">Batterie ' . ThermostatDashboard_Escape($battery) . '</span>' : '')
                . '</div><div class="td-controls">';
            if (@{$device->{modes}}) {
                $html .= '<div class="td-modes">';
                for my $mode (@{$device->{modes}}) {
                    $html .= '<button type="button" data-mode-command="'
                        . ThermostatDashboard_Escape($mode->[0]) . '" data-mode-value="'
                        . ThermostatDashboard_Escape($mode->[1]) . '" data-active="'
                        . ($device->{mode} && lc($device->{mode}{value}) eq lc($mode->[1]) ? '1' : '0') . '">'
                        . ThermostatDashboard_Escape($mode->[2]) . '</button>';
                }
                $html .= '</div>';
            }
            $html .= '<div class="td-status" aria-live="polite"></div></div></section>';
        }
        $html .= '</main>';
    }

    $html .= '</div>' . ThermostatDashboard_Javascript();
    return $html;
}

sub ThermostatDashboard_Javascript {
    return <<'JS';
<script>(function(){
var root=document.querySelector(".td");if(!root)return;
var base=root.getAttribute("data-base").replace(/\/$/,""),csrf=root.getAttribute("data-csrf")||"";
if(!csrf){var match=document.cookie.match(/(?:^|;\s*)fwcsrf=([^;]+)/);csrf=match?decodeURIComponent(match[1]):"";}
function request(command){var url=base+"?cmd="+encodeURIComponent(command)+"&XHR=1";if(csrf)url+="&fwcsrf="+encodeURIComponent(csrf);
return fetch(url,{cache:"no-store",credentials:"same-origin"}).then(function(response){return response.text().then(function(text){
if(!response.ok)throw new Error(text.trim().slice(0,160)||"HTTP "+response.status);return text;});});}
function status(card,text,error,success){var node=card.querySelector(".td-status");window.clearTimeout(card._tdStatusTimer);node.textContent=text;node.setAttribute("data-error",error?"1":"0");node.setAttribute("data-success",success?"1":"0");}
var cards=Array.prototype.slice.call(root.querySelectorAll(".td-card")),editButton=root.querySelector(".td-edit");
var cancelButton=root.querySelector(".td-cancel"),saveButton=root.querySelector(".td-save");
var backdrop=root.querySelector("[data-dialog-backdrop]"),dialog=backdrop&&backdrop.querySelector('[role="dialog"]');
var dialogStatus=root.querySelector(".td-dialog-status");
var checkboxes=root.querySelectorAll("[data-visible]");
if(editButton&&backdrop){
var originalHidden=[];
function updateVisibility(card,visible){card.setAttribute("data-hidden",visible?"0":"1");}
function setEditMode(editing){root.classList.toggle("edit-mode",editing);backdrop.hidden=!editing;Array.prototype.forEach.call(checkboxes,function(checkbox){checkbox.disabled=!editing;});dialogStatus.textContent="";dialogStatus.setAttribute("data-error","0");if(editing){var first=dialog.querySelector("input");(first||cancelButton).focus();}else editButton.focus();}
function cancelEdit(){cards.forEach(function(card,index){updateVisibility(card,!originalHidden[index]);});Array.prototype.forEach.call(checkboxes,function(checkbox,index){checkbox.checked=!originalHidden[index];});setEditMode(false);}
function fail(text){dialogStatus.textContent=text;dialogStatus.setAttribute("data-error","1");}
editButton.addEventListener("click",function(){originalHidden=cards.map(function(card){return card.getAttribute("data-hidden")==="1";});setEditMode(true);});
cancelButton.addEventListener("click",cancelEdit);
backdrop.addEventListener("click",function(event){if(event.target===backdrop)cancelEdit();});
document.addEventListener("keydown",function(event){if(event.key==="Escape"&&!backdrop.hidden)cancelEdit();});
Array.prototype.forEach.call(checkboxes,function(checkbox){checkbox.addEventListener("change",function(){var card=cards.filter(function(item){return item.getAttribute("data-device")===checkbox.getAttribute("data-device");})[0];if(card)updateVisibility(card,checkbox.checked);});});
saveButton.addEventListener("click",function(){var hidden=cards.filter(function(card){return card.getAttribute("data-hidden")==="1";}).map(function(card){return card.getAttribute("data-device");});
var encoded=btoa(unescape(encodeURIComponent(JSON.stringify({hidden:hidden})))),command="set "+root.getAttribute("data-device")+" saveConfig "+encoded;
Array.prototype.forEach.call(checkboxes,function(checkbox){checkbox.disabled=true;});saveButton.disabled=true;cancelButton.disabled=true;dialogStatus.textContent="Konfiguration wird gespeichert ...";
request(command).then(function(text){if(/unknown argument|forbidden|invalid csrf|not allowed|error|fehler|fehlgeschlagen|ungueltig|unbekannt/i.test(text))throw new Error(text.trim().slice(0,160));setEditMode(false);})
.catch(function(error){fail("Speichern fehlgeschlagen: "+error.message);Array.prototype.forEach.call(checkboxes,function(checkbox){checkbox.disabled=false;});})
.then(function(){saveButton.disabled=false;cancelButton.disabled=false;});});
}
function refreshCard(card){var command="jsonlist2 "+card.getAttribute("data-device");
return request(command).then(function(text){var result=JSON.parse(text),device=result.Results&&result.Results[0];if(!device)throw new Error("Geraet nicht gefunden");
var readings=device.Readings||{};
function value(attr){var name=card.getAttribute(attr);return name&&readings[name]?readings[name]:null;}
var actual=value("data-actual"),target=value("data-target"),mode=value("data-mode"),valve=value("data-valve"),battery=value("data-battery");
var actualNode=card.querySelector('[data-value="actual"]'),modeNode=card.querySelector('[data-value="mode"]');
if(actual&&actualNode){var actualNumber=Number(String(actual.Value).replace(",","."));actualNode.innerHTML=(Number.isFinite(actualNumber)?actualNumber.toFixed(1):"&ndash;")+' <small>&deg;C</small>';}
if(target){var targetNumber=Number(String(target.Value).replace(",",".")),input=card.querySelector("[data-temp]");if(input&&document.activeElement!==input&&!input._tdTimer&&!input.disabled&&Number.isFinite(targetNumber))input.value=targetNumber.toFixed(1);}
if(mode&&modeNode){modeNode.textContent=mode.Value;var normalizedMode=String(mode.Value).toLowerCase();Array.prototype.forEach.call(card.querySelectorAll("[data-mode-value]"),function(button){button.setAttribute("data-active",String(button.getAttribute("data-mode-value")).toLowerCase()===normalizedMode?"1":"0");});}
var badges=card.querySelector(".td-meta"),dynamic=badges.querySelectorAll("[data-dynamic]");
Array.prototype.forEach.call(dynamic,function(node){node.parentNode.removeChild(node);});
[[valve,"Ventil ","%"],[battery,"Batterie ",""]].forEach(function(item){if(!item[0])return;var badge=document.createElement("span");badge.className="td-badge";badge.setAttribute("data-dynamic","1");badge.textContent=item[1]+item[0].Value+item[2];badges.appendChild(badge);});
})
.catch(function(error){status(card,"Aktualisierung fehlgeschlagen: "+error.message,true);});}
function sendTemperature(card,input){if(root.classList.contains("edit-mode"))return;
var value=Number(input.value),minimum=Number(card.getAttribute("data-min")),maximum=Number(card.getAttribute("data-max"));
if(!Number.isFinite(value)||value<minimum||value>maximum){status(card,"Temperatur muss zwischen "+minimum.toFixed(1)+" und "+maximum.toFixed(1)+" \u00b0C liegen.",true);return;}
var halfStep=Math.round(value*2)/2;if(Math.abs(value-halfStep)>0.001){status(card,"Bitte die Temperatur in 0,5-Grad-Schritten angeben.",true);return;}
value=halfStep;input.value=value.toFixed(1);var command="set "+card.getAttribute("data-device")+" "+card.getAttribute("data-command")+" "+value.toFixed(1);
input.disabled=true;status(card,"Befehl wird gesendet ...",false);
request(command).then(function(text){if(/unknown argument|forbidden|invalid csrf|not allowed|error|fehler|fehlgeschlagen|ungueltig|unbekannt/i.test(text))throw new Error(text.trim().slice(0,160));status(card,"Wert gesendet",false,true);card._tdStatusTimer=window.setTimeout(function(){status(card,"",false);},3000);window.setTimeout(function(){refreshCard(card);},1000);})
.catch(function(error){status(card,"Befehl fehlgeschlagen: "+error.message,true);})
.then(function(){input.disabled=false;});}
root.addEventListener("input",function(event){var input=event.target;if(!input.matches("[data-temp]")||root.classList.contains("edit-mode"))return;
var card=input.closest(".td-card");if(!card)return;window.clearTimeout(input._tdTimer);status(card,"",false);input._tdTimer=window.setTimeout(function(){input._tdTimer=null;sendTemperature(card,input);},1500);});
root.addEventListener("click",function(event){var button=event.target.closest("button");if(!button||!button.hasAttribute("data-mode-command"))return;var card=button.closest(".td-card");if(!card||root.classList.contains("edit-mode"))return;
var command="set "+card.getAttribute("data-device")+" "+button.getAttribute("data-mode-command")+" "+button.getAttribute("data-mode-value"),buttons=card.querySelectorAll("button");
Array.prototype.forEach.call(buttons,function(item){item.disabled=true;});status(card,"Befehl wird gesendet ...",false);
request(command).then(function(text){if(/unknown argument|forbidden|invalid csrf|not allowed|error|fehler|fehlgeschlagen|ungueltig|unbekannt/i.test(text))throw new Error(text.trim().slice(0,160));status(card,"Befehl an FHEM gesendet.",false);window.setTimeout(function(){refreshCard(card);},1000);})
.catch(function(error){status(card,"Befehl fehlgeschlagen: "+error.message,true);})
.then(function(){Array.prototype.forEach.call(buttons,function(item){item.disabled=false;});});});
function refreshAll(){if(document.hidden)return;Array.prototype.forEach.call(cards,function(card){if(card.getAttribute("data-hidden")!=="1")refreshCard(card);});}
refreshAll();var seconds=Number(root.getAttribute("data-refresh"))||0;if(seconds)window.setInterval(refreshAll,seconds*1000);
})();</script>
JS
}

sub ThermostatDashboard_QueryValue {
    my ($request, $key) = @_;
    return undef if (!defined($request) || $request !~ /(?:^|[?&])\Q$key\E=([^&]*)/);
    my $value = $1;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $value;
}

sub main::ThermostatDashboard_CGI {
    my ($request) = @_;
    $request = '' if (!defined($request));
    my ($path) = split(/\?/, $request, 2);
    my $name = (split('/', $path))[-1];
    $name = '' if (!defined($name));
    $name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    my $hash = $main::defs{$name};
    return ('text/plain; charset=utf-8', 'Unknown ThermostatDashboard device')
        if (!$hash || ($hash->{TYPE} || '') ne 'ThermostatDashboard');

    my $html = ThermostatDashboard_BuildDashboard($hash);
    return ('text/html; charset=utf-8', $html)
        if (ThermostatDashboard_QueryValue($request, 'embed'));
    return ('text/html; charset=utf-8', '<!doctype html><html lang="de"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>Thermostate - ' . ThermostatDashboard_Escape($name)
        . '</title></head><body style="margin:0;padding:12px;background:#151f1b">'
        . $html . '</body></html>');
}

1;

=pod
=item device
=item summary Dashboard für Homematic- und MAX-Thermostate
=item summary_DE Zeigt und steuert Homematic- und eQ-3 MAX-Thermostate
=begin html

<a id="ThermostatDashboard"></a>
<h3>ThermostatDashboard</h3>
<p>Zeigt kompatible Homematic- (CUL_HM) und eQ-3 MAX-Heizkörperthermostate in einem
Dashboard. Ist- und Solltemperatur, Betriebsart, Ventilstellung und Batteriestatus
werden angezeigt. Die Solltemperatur und vom jeweiligen Ger&auml;t unterst&uuml;tzte
Betriebsarten lassen sich direkt einstellen.</p>
<a id="ThermostatDashboard-define"></a>
<b>Define</b>
<ul><code>define &lt;name&gt; ThermostatDashboard</code></ul>
<a id="ThermostatDashboard-set"></a>
<b>Get</b>
<ul>
    <li><code>get &lt;name&gt; _showDashboard</code> - Dashboard in FHEMWEB anzeigen</li>
    <li><code>get &lt;name&gt; _dashboardURL</code> - eigenst&auml;ndige Ansicht</li>
    <li><code>get &lt;name&gt; _dashboardEmbedURL</code> - Fragment f&uuml;r DashboardHub</li>
    <li><code>get &lt;name&gt; list</code> - erkannte Thermostate auflisten</li>
    <li><code>get &lt;name&gt; diagnose</code> - Erkennung kompatibler CUL_HM-/MAX-Ger&auml;te pr&uuml;fen</li>
</ul>
<a id="ThermostatDashboard-attr"></a>
<b>Attribute</b>
<ul>
    <li><code>includeDevices</code>, <code>excludeDevices</code> - Regex auf Ger&auml;tenamen</li>
    <li><code>autoRefresh</code> - Aktualisierung in Sekunden: 0 (aus), 15, 30 oder 60</li>
    <li><code>showDeviceType</code>, <code>showRoom</code> - Typzeile bzw. Raum ein-/ausblenden</li>
</ul>

=end html
=cut
