package main;

use strict;
use warnings;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(decode_base64);

our $ThermostatDashboard_VERSION = '1.2.1-dev';
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
        if ($type eq 'CUL_HM') {
            if ($usage =~ /\b\Q$temperatureCommand\E:([A-Za-z0-9.,|+-]+)/) {
                my @options = grep { defined($_) }
                    map { ThermostatDashboard_Number($_) } split(/[|,]/, $1);
                if (@options) {
                    ($minimum, $maximum) = ($options[0], $options[0]);
                    for my $option (@options) {
                        $minimum = $option if ($option < $minimum);
                        $maximum = $option if ($option > $maximum);
                    }
                }
            } elsif ($usage =~ /\b\Q$temperatureCommand\E\s+\([^)]*?([-+]?\d+(?:\.\d+)?)\.\.([-+]?\d+(?:\.\d+)?)/) {
                ($minimum, $maximum) = ($1, $2);
            }
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
            battery => ThermostatDashboard_Reading($device, 'batteryPercent', 'batteryLevel', 'batteryState', 'battery'),
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
.td-target-control{margin-top:3px}
.td-target-value{display:flex;align-items:baseline;gap:5px}
.td-target-control input[type=range]{display:block;width:100%;height:22px;margin:9px 0 0;accent-color:#52bd8b;cursor:pointer}
.td-meta{display:flex;flex-wrap:wrap;align-items:center;gap:9px;padding:0 14px 12px}
.td-mode-select{height:34px;max-width:145px;padding:5px 25px 5px 8px;border:1px solid #69796f;border-radius:0;background:#26342d;color:#f4f4e9;font:12px 'Helvetica Neue',sans-serif}
.td-valve{position:relative;display:grid;place-items:center;min-width:86px;height:34px;overflow:hidden;border:1px solid #46544c;background:linear-gradient(90deg,#2679ce 0%,#338b81 50%,#741d2d 100%);color:#fff;font-size:11px;font-weight:700;text-shadow:0 1px 2px #111}
.td-valve::before{position:absolute;top:0;bottom:0;left:var(--td-valve,0%);width:2px;background:#fff;box-shadow:0 0 3px #111;content:""}
.td-valve span{position:relative}
.td-battery{display:inline-flex;align-items:center;gap:5px;color:#58cf8e;font-size:11px}
.td-battery[data-level="medium"]{color:#e8bc57}
.td-battery[data-level="low"]{color:#ef695e}
.td-battery[data-level="unknown"]{color:#a9b7ac}
.td-battery svg{width:23px;height:14px;overflow:visible}
.td-battery-outline{fill:none;stroke:currentColor;stroke-width:1.5}
.td-battery-bar{fill:currentColor}
.td-sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
.td button{min-height:34px;padding:6px 11px;background:#26342d;color:#f4f4e9;border:1px solid #52bd8b;font:600 12px 'Helvetica Neue',sans-serif;cursor:pointer}
.td button:hover{background:#30453a}
.td button:disabled{opacity:.5;cursor:wait}
.td-status{margin:0 14px 10px;color:#a9b7ac;font-size:11px}
.td-status:empty{display:none}
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
            my $sliderMaximum = $device->{maximum} < 25 ? $device->{maximum} : 25;
            my $sliderValue = defined($target) ? $target : $device->{minimum};
            $sliderValue = $device->{minimum} if ($sliderValue < $device->{minimum});
            $sliderValue = $sliderMaximum if ($sliderValue > $sliderMaximum);
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
                . '<div class="td-target-value"><strong data-target-value>' . (defined($target) ? sprintf('%.1f', $target) : '&ndash;')
                . '</strong><small>&deg;C</small></div><label class="td-sr-only" for="td-temp-'
                . ThermostatDashboard_Escape($device->{name}) . '">Solltemperatur</label>'
                . '<input id="td-temp-' . ThermostatDashboard_Escape($device->{name})
                . '" data-temp type="range" min="' . $device->{minimum} . '" max="' . $sliderMaximum
                . '" step="0.5" value="' . sprintf('%.1f', $sliderValue)
                . '" aria-label="Solltemperatur in Grad Celsius"></div></div></div>'
                . '<div class="td-meta">';
            if (@{$device->{modes}}) {
                $html .= '<label><span class="td-sr-only">Betriebsart</span><select class="td-mode-select" data-mode-select'
                    . ' data-mode-command="' . ThermostatDashboard_Escape($device->{modes}[0][0]) . '">';
                for my $mode (@{$device->{modes}}) {
                    $html .= '<option value="' . ThermostatDashboard_Escape($mode->[1]) . '"'
                        . ($device->{mode} && lc($device->{mode}{value}) eq lc($mode->[1]) ? ' selected' : '')
                        . '>' . ThermostatDashboard_Escape($mode->[2]) . '</option>';
                }
                $html .= '</select></label>';
            } elsif ($mode ne '') {
                $html .= '<span class="td-mode-value">' . ThermostatDashboard_Escape($mode) . '</span>';
            }
            if ($device->{valve}) {
                my $valvePercent = ThermostatDashboard_Number($valve);
                my $valvePosition = defined($valvePercent) ? $valvePercent : 0;
                $valvePosition = 0 if ($valvePosition < 0);
                $valvePosition = 100 if ($valvePosition > 100);
                $html .= '<div class="td-valve" data-valvebar style="--td-valve:' . $valvePosition
                    . '%" role="img" aria-label="Ventil ' . ThermostatDashboard_Escape($valve)
                    . '%"><span data-valve-value>' . ThermostatDashboard_Escape($valve) . '%</span></div>';
            }
            if ($device->{battery}) {
                $html .= '<div class="td-battery" data-battery-indicator data-level="unknown" data-battery-value="'
                    . ThermostatDashboard_Escape($battery) . '" role="img" aria-label="Batterie '
                    . ThermostatDashboard_Escape($battery) . '"><svg viewBox="0 0 24 14" aria-hidden="true">'
                    . '<rect class="td-battery-outline" x="1" y="1" width="19" height="12" rx="1"/>'
                    . '<path class="td-battery-outline" d="M22 4v6"/>'
                    . '<rect class="td-battery-bar" data-battery-bar x="3" y="3" width="4" height="8"/>'
                    . '<rect class="td-battery-bar" data-battery-bar x="8" y="3" width="4" height="8"/>'
                    . '<rect class="td-battery-bar" data-battery-bar x="13" y="3" width="4" height="8"/></svg>'
                    . '<span data-battery-text>' . ThermostatDashboard_Escape($battery) . '</span></div>';
            }
            $html .= '</div>';
            $html .= '<div class="td-status" aria-live="polite"></div></section>';
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
function formatTemperature(value){return value.toFixed(1).replace(".",",");}
function updateBattery(node,raw){var text=String(raw==null?"":raw).trim(),normalized=text.toLowerCase(),level="unknown",filled=0;
var numeric=normalized.match(/^(\d+(?:[.,]\d+)?)\s*%?$/);
if(numeric){var percent=Number(numeric[1].replace(",","."));if(Number.isFinite(percent)){filled=percent>=66?3:percent>=33?2:percent>0?1:0;level=percent>60?"good":percent>25?"medium":"low";}}
else if(/\b(nok|not ok|low|empty|critical|replace|error|weak|bad)\b/.test(normalized)){filled=/\b(low|weak)\b/.test(normalized)?1:0;level="low";}
else if(/\b(ok|good|full|charged)\b/.test(normalized)){filled=3;level="good";}
var displayText=numeric&&text.indexOf("%")<0?text+"%":text;
node.setAttribute("data-level",level);node.setAttribute("data-battery-value",text);node.setAttribute("aria-label","Batterie "+displayText);
var label=node.querySelector("[data-battery-text]");if(label)label.textContent=displayText;
Array.prototype.forEach.call(node.querySelectorAll("[data-battery-bar]"),function(bar,index){bar.style.display=index<filled?"":"none";});}
function updateValve(node,raw){var text=String(raw==null?"":raw).trim(),value=Number(text.replace(",","."));if(!Number.isFinite(value))return;
value=Math.max(0,Math.min(100,value));node.style.setProperty("--td-valve",value+"%");
node.setAttribute("aria-label","Ventil "+text+"%");
var label=node.querySelector("[data-valve-value]");if(label)label.textContent=text+"%";}
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
Array.prototype.forEach.call(root.querySelectorAll("[data-battery-indicator]"),function(node){updateBattery(node,node.getAttribute("data-battery-value"));});
function refreshCard(card){var command="jsonlist2 "+card.getAttribute("data-device");
return request(command).then(function(text){var result=JSON.parse(text),device=result.Results&&result.Results[0];if(!device)throw new Error("Geraet nicht gefunden");
var readings=device.Readings||{};
function value(attr){var name=card.getAttribute(attr);return name&&readings[name]?readings[name]:null;}
var actual=value("data-actual"),target=value("data-target"),mode=value("data-mode"),valve=value("data-valve"),battery=value("data-battery");
var actualNode=card.querySelector('[data-value="actual"]'),targetNode=card.querySelector("[data-target-value]"),input=card.querySelector("[data-temp]");
if(actual&&actualNode){var actualNumber=Number(String(actual.Value).replace(",","."));actualNode.innerHTML=(Number.isFinite(actualNumber)?actualNumber.toFixed(1):"&ndash;")+' <small>&deg;C</small>';}
if(target){var targetNumber=Number(String(target.Value).replace(",","."));if(Number.isFinite(targetNumber)&&targetNode)targetNode.textContent=formatTemperature(targetNumber);
if(input&&document.activeElement!==input&&!input._tdTimer&&!input.disabled&&Number.isFinite(targetNumber)){var sliderMin=Number(input.min),sliderMax=Number(input.max);input.value=Math.max(sliderMin,Math.min(sliderMax,targetNumber));}}
if(mode){var select=card.querySelector("[data-mode-select]");if(select&&!select.disabled){var normalizedMode=String(mode.Value).toLowerCase();if(Array.prototype.some.call(select.options,function(option){return option.value.toLowerCase()===normalizedMode;}))select.value=normalizedMode;}}
if(valve){var valveNode=card.querySelector("[data-valvebar]");if(valveNode)updateValve(valveNode,valve.Value);}
if(battery){var batteryNode=card.querySelector("[data-battery-indicator]");if(batteryNode)updateBattery(batteryNode,battery.Value);}
})
.catch(function(error){status(card,"Aktualisierung fehlgeschlagen: "+error.message,true);});}
function sendTemperature(card,input){if(root.classList.contains("edit-mode"))return;
var value=Number(input.value),minimum=Number(card.getAttribute("data-min")),maximum=Number(card.getAttribute("data-max"));
if(!Number.isFinite(value)||value<minimum||value>maximum){status(card,"Temperatur muss zwischen "+minimum.toFixed(1)+" und "+maximum.toFixed(1)+" \u00b0C liegen.",true);return;}
var halfStep=Math.round(value*2)/2;if(Math.abs(value-halfStep)>0.001){status(card,"Bitte die Temperatur in 0,5-Grad-Schritten angeben.",true);return;}
value=halfStep;input.value=value;var targetNode=card.querySelector("[data-target-value]");if(targetNode)targetNode.textContent=formatTemperature(value);
var command="set "+card.getAttribute("data-device")+" "+card.getAttribute("data-command")+" "+value.toFixed(1);
input.disabled=true;status(card,"Befehl wird gesendet ...",false);
request(command).then(function(text){if(/unknown argument|forbidden|invalid csrf|not allowed|error|fehler|fehlgeschlagen|ungueltig|unbekannt/i.test(text))throw new Error(text.trim().slice(0,160));status(card,"Wert gesendet",false,true);card._tdStatusTimer=window.setTimeout(function(){status(card,"",false);},3000);window.setTimeout(function(){refreshCard(card);},1000);})
.catch(function(error){status(card,"Befehl fehlgeschlagen: "+error.message,true);})
.then(function(){input.disabled=false;});}
root.addEventListener("input",function(event){var input=event.target;if(!input.matches("[data-temp]")||root.classList.contains("edit-mode"))return;
var card=input.closest(".td-card");if(!card)return;var targetNode=card.querySelector("[data-target-value]"),number=Number(input.value);if(targetNode&&Number.isFinite(number))targetNode.textContent=formatTemperature(number);
window.clearTimeout(input._tdTimer);status(card,"",false);input._tdTimer=window.setTimeout(function(){input._tdTimer=null;sendTemperature(card,input);},1500);});
root.addEventListener("change",function(event){var select=event.target;if(!select.matches("[data-mode-select]")||root.classList.contains("edit-mode"))return;
var card=select.closest(".td-card");if(!card)return;var command="set "+card.getAttribute("data-device")+" "+select.getAttribute("data-mode-command")+" "+select.value;
select.disabled=true;status(card,"Befehl wird gesendet ...",false);
request(command).then(function(text){if(/unknown argument|forbidden|invalid csrf|not allowed|error|fehler|fehlgeschlagen|ungueltig|unbekannt/i.test(text))throw new Error(text.trim().slice(0,160));status(card,"Betriebsart gesendet",false,true);card._tdStatusTimer=window.setTimeout(function(){status(card,"",false);},3000);window.setTimeout(function(){refreshCard(card);},1000);})
.catch(function(error){status(card,"Befehl fehlgeschlagen: "+error.message,true);})
.then(function(){select.disabled=false;});});
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
werden angezeigt. Die Solltemperatur wird &uuml;ber einen Schieberegler eingestellt;
die Betriebsart l&auml;sst sich &uuml;ber ein Auswahlfeld direkt wechseln.</p>
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
