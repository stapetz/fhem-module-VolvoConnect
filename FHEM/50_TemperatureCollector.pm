package main;

use strict;
use warnings;
use POSIX qw(strftime);
use Time::Local qw(timelocal);
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(decode_base64);

our ($readingFnAttributes, $FW_wname, $FW_ME);
our (%data, %defs, %FW_httpheader);

sub TemperatureCollector_Initialize {
    my ($modHash) = @_;

    $modHash->{DefFn} = 'TemperatureCollector_Define';
    $modHash->{UndefFn} = 'TemperatureCollector_Undef';
    $modHash->{GetFn} = 'TemperatureCollector_Get';
    $modHash->{SetFn} = 'TemperatureCollector_Set';
    $modHash->{AttrList} = join(' ',
        'dbLog',
        'historyHours',
        'autoRefresh:0,15,30,60,300',
        'showHistoryTable:0,1',
        'showReadingName:0,1',
        'includeDevices',
        'excludeDevices',
        $main::readingFnAttributes,
    );

    $main::data{FWEXT}{'/TemperatureCollector'}{FUNC} = 'TemperatureCollector_CGI';
    $main::data{FWEXT}{'/TemperatureCollector'}{FORKABLE} = 0;
}

sub TemperatureCollector_Define {
    my ($hash, $def) = @_;
    my @args = split(/\s+/, $def);
    return 'Usage: define <name> TemperatureCollector' if (@args != 2);

    $hash->{STATE} = 'defined';
    return undef;
}

sub TemperatureCollector_Undef {
    my ($hash, $arg) = @_;
    return undef;
}

sub TemperatureCollector_Set {
    my ($hash, $name, $cmd, @args) = @_;
    if ($cmd eq 'saveOrder') {
        return TemperatureCollector_SaveOrder($name, decode_base64(join('', @args)));
    }
    return 'Unknown argument refresh, choose one of refresh:noArg'
        if ($cmd ne 'refresh');
    return 'Temperature dashboard refreshed at ' . strftime('%H:%M:%S', localtime());
}

sub TemperatureCollector_SaveOrder {
    my ($name, $json) = @_;
    my $order = eval { decode_json($json || '') };
    return 'Ungueltige Sensorreihenfolge'
        if (ref($order) ne 'ARRAY'
            || grep { !defined($_) || ref($_) || $_ eq '' } @{$order});
    my %seen;
    $order = [grep { !$seen{$_}++ } @{$order}];
    my $error = setKeyValue(TemperatureCollector_OrderKey($name), encode_json($order));
    return 'Speichern der Sensorreihenfolge fehlgeschlagen: ' . $error
        if (defined($error) && $error ne '');
    return undef;
}

sub TemperatureCollector_OrderKey {
    my ($name) = @_;
    return 'TemperatureCollector_order_' . $name;
}

sub TemperatureCollector_LoadOrder {
    my ($name) = @_;
    my ($error, $value) = getKeyValue(TemperatureCollector_OrderKey($name));
    return [] if ($error || !defined($value) || $value eq '');
    my $order = eval { decode_json($value) };
    return ref($order) eq 'ARRAY' ? $order : [];
}

sub TemperatureCollector_ApplyOrder {
    my ($name, $devices) = @_;
    my $stored = TemperatureCollector_LoadOrder($name);
    return $devices if (!@{$stored});
    my %deviceByName = map { $_->{name} => $_ } @{$devices};
    my %used;
    my @ordered = map {
        $used{$_} = 1;
        $deviceByName{$_};
    } grep { exists($deviceByName{$_}) && !$used{$_} } @{$stored};
    push @ordered, grep { !$used{$_->{name}} } @{$devices};
    return \@ordered;
}

sub TemperatureCollector_Get {
    my ($hash, $name, $cmd, @args) = @_;

    return TemperatureCollector_BuildDashboard($hash, {editable => 1})
        if ($cmd eq '_showDashboard');
    return TemperatureCollector_BuildDashboard($hash, {editable => 0})
        if ($cmd eq 'dashboard');
    if ($cmd eq '_dashboardURL') {
        my $scheme = AttrVal($main::FW_wname, 'HTTPS', 0) ? 'https' : 'http';
        my $host = $main::FW_httpheader{Host} || 'localhost';
        return $scheme . '://' . $host . TemperatureCollector_DashboardBasePath()
            . '/TemperatureCollector/'
            . (defined(&urlEncode) ? urlEncode($name) : $name);
    }

    return 'Unknown argument ' . ($cmd // '') . ', choose one of '
        . '_showDashboard:noArg _dashboardURL:noArg';
}

sub TemperatureCollector_DashboardBasePath {
    my $path = $main::FW_ME || '/fhem';
    $path =~ s{/$}{};
    return $path;
}

sub TemperatureCollector_Attr {
    return undef;
}

sub TemperatureCollector_IsNumber {
    my ($value) = @_;
    return 0 if (!defined($value) || ref($value));
    return $value =~ /^\s*[-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)\s*(?:°?\s*[CFK])?\s*$/i;
}

sub TemperatureCollector_Number {
    my ($value) = @_;
    return undef if (!TemperatureCollector_IsNumber($value));
    $value =~ s/,/./g;
    $value =~ /([-+]?(?:\d+(?:\.\d*)?|\.\d+))/;
    return 0 + $1;
}

sub TemperatureCollector_TimeLabel {
    my ($timestamp, $edge) = @_;
    return '' if (!defined($timestamp));
    if ($timestamp =~ /^(\d{4})-(\d{2})-(\d{2})[_ ](\d{2}):(\d{2})/) {
        return $edge ? "$3.$2.$1 $4:$5" : "$4:$5";
    }
    return $timestamp;
}

sub TemperatureCollector_QueryValue {
    my ($request, $key, $default) = @_;
    return $default if (!defined($request) || $request !~ /(?:^|[?&])\Q$key\E=([^&]*)/);
    my $value = $1;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $value;
}

sub TemperatureCollector_HumidityNumber {
    my ($value) = @_;
    return undef if (!defined($value) || ref($value)
        || $value !~ /^\s*([-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+))\s*%?\s*$/);
    my $number = $1;
    $number =~ s/,/./g;
    return 0 + $number;
}

sub TemperatureCollector_Escape {
    my ($value) = @_;
    $value = '' if (!defined($value));
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&#39;/g;
    return $value;
}

sub TemperatureCollector_EscapeJson {
    my ($value) = @_;
    $value = encode_json($value);
    $value =~ s/</\\u003c/g;
    $value =~ s/>/\\u003e/g;
    $value =~ s/&/\\u0026/g;
    return $value;
}

sub TemperatureCollector_TemperatureReading {
    my ($readings) = @_;
    my @candidates;

    for my $reading (keys %{$readings || {}}) {
        next if (lc($reading) ne 'temperature');
        my $entry = $readings->{$reading};
        next if (ref($entry) ne 'HASH' || !TemperatureCollector_IsNumber($entry->{VAL}));
        push @candidates, [0, $reading, $entry];
    }

    return undef if (!@candidates);
    @candidates = sort {
        $a->[0] <=> $b->[0] || lc($a->[1]) cmp lc($b->[1])
    } @candidates;
    return $candidates[0];
}

sub TemperatureCollector_HumidityReading {
    my ($hash) = @_;
    my $readings = $hash->{READINGS};
    my $readingMatch;
    for my $reading (sort keys %{$readings || {}}) {
        next if ($reading !~ /humid|feuchte/i);
        my $entry = $readings->{$reading};
        $readingMatch = [$reading, $entry]
            if (ref($entry) eq 'HASH' && defined(TemperatureCollector_HumidityNumber($entry->{VAL})));
        last if ($readingMatch && TemperatureCollector_HumidityNumber($entry->{VAL}) != 0);
    }

    return $readingMatch;
}

sub TemperatureCollector_DeviceListed {
    my ($name, $list) = @_;
    return 0 if (!defined($list) || $list eq '');
    return scalar grep { $_ eq $name } map { s/^\s+|\s+$//gr } split(/,/, $list);
}

sub TemperatureCollector_IsExternalTemperature {
    my ($reading) = @_;
    return 0 if (!defined($reading) || $reading eq '');
    return 0 if ($reading =~ /^measured[-_]temp(?:erature)?$/i);
    return 0 if ($reading =~ /(?:^|[_-])(?:int|internal|battery|board|inverter|motor|cpu|case|coil|heat_sink|heatsink|charger|boost)/i);
    return 0 if ($reading =~ /(?:desired|setpoint|target|limit|alarm|threshold|requested|request)/i);
    return 1;
}

sub TemperatureCollector_Discover {
    my ($ownName) = @_;
    my @devices;
    my $includeDevices = AttrVal($ownName, 'includeDevices', '');
    my $excludeDevices = AttrVal($ownName, 'excludeDevices', '');

    for my $device (sort keys %main::defs) {
        next if ($device eq $ownName);
        next if ($excludeDevices ne '' && TemperatureCollector_DeviceListed($device, $excludeDevices));
        next if ($includeDevices ne '' && !TemperatureCollector_DeviceListed($device, $includeDevices));
        my $hash = $main::defs{$device};
        next if (ref($hash) ne 'HASH' || ref($hash->{READINGS}) ne 'HASH');

        my $temperature = TemperatureCollector_TemperatureReading($hash->{READINGS});
        next if (!$temperature);
        my $humidity = TemperatureCollector_HumidityReading($hash);
        my $reading = $temperature->[1];
        my $entry = $temperature->[2];
        my $alias = AttrVal($device, 'alias', $device);
        $alias = $device if (!defined($alias) || $alias eq '');
        push @devices, {
            name => $device,
            alias => $alias,
            type => $hash->{TYPE} || '',
            temperatureReading => $reading,
            temperature => TemperatureCollector_Number($entry->{VAL}),
            temperatureTimestamp => $entry->{TIME} || '',
            humidityReading => $humidity ? $humidity->[0] : '',
            humidity => $humidity ? TemperatureCollector_HumidityNumber($humidity->[1]{VAL}) : undef,
            humidityTimestamp => $humidity ? ($humidity->[1]{TIME} || '') : '',
        };
    }

    return \@devices;
}

sub TemperatureCollector_DbLog {
    my ($hash) = @_;
    my $configured = AttrVal($hash->{NAME}, 'dbLog', '');
    if ($configured ne '') {
        return $main::defs{$configured}
            if (ref($main::defs{$configured}) eq 'HASH'
                && ($main::defs{$configured}{TYPE} || '') eq 'DbLog');
        main::Log3($hash->{NAME}, 2, "TemperatureCollector: configured DbLog '$configured' was not found");
        return undef;
    }

    for my $device (sort keys %main::defs) {
        return $main::defs{$device}
            if (ref($main::defs{$device}) eq 'HASH'
                && ($main::defs{$device}{TYPE} || '') eq 'DbLog');
    }
    return undef;
}

sub TemperatureCollector_History {
    my ($hash, $device, $reading, $options, $kind) = @_;
    $options ||= {};
    my $dbHash = TemperatureCollector_DbLog($hash);
    return [] if (!$dbHash || !defined(&DbLog_Get));

    my $hours = AttrVal($hash->{NAME}, 'historyHours', 24);
    $hours = 24 if ($hours !~ /^\d+(?:\.\d+)?$/ || $hours < 1 || $hours > 8760);
    my $offset = $options->{offset} || 0;
    my $step = $options->{step} || 30;
    my $to = time() - ($offset * 3600);
    my $from = $to - ($hours * 3600);
    my $fromText = strftime('%Y-%m-%d_%H:%M:%S', localtime($from));
    my $toText = strftime('%Y-%m-%d_%H:%M:%S', localtime($to));
    my @rows;

    my $error;
    {
        local $@;
        @rows = eval {
            DbLog_Get(
                $dbHash,
                $dbHash->{NAME},
                '-',
                'array',
                $fromText,
                $toText,
                $device . ':' . $reading,
            );
        };
        $error = $@;
    }
    if ($error) {
        main::Log3($hash->{NAME}, 2, "TemperatureCollector: DbLog history query failed: $error");
        return [];
    }

    my @history;
    my %buckets;
    for my $row (@rows) {
        next if (ref($row) ne 'HASH');
        my $number = $kind && $kind eq 'humidity'
            ? TemperatureCollector_HumidityNumber($row->{value})
            : TemperatureCollector_Number($row->{value});
        next if (!defined($number));
        my $entry = {
            timestamp => $row->{tstamp} || '',
            value => $number,
        };
        if ($entry->{timestamp} =~ /^(\d{4})-(\d{2})-(\d{2})[_ ](\d{2}):(\d{2}):(\d{2})/) {
            my $epoch = eval { timelocal($6, $5, $4, $3, $2 - 1, $1) };
            if (defined($epoch)) {
                $buckets{int($epoch / ($step * 60))} = $entry;
                next;
            }
        }
        push @history, $entry;
    }
    push @history, values %buckets;
    @history = sort { $a->{timestamp} cmp $b->{timestamp} } @history;
    splice(@history, 0, @history - 240) if (@history > 240);
    return \@history;
}

sub TemperatureCollector_Svg {
    my ($temperatureHistory, $humidityHistory, $hours, $step, $chartId) = @_;
    return '<p class="tc-muted">Keine DbLog-Historie für dieses Reading verfügbar.</p>'
        if ((!$temperatureHistory || !@{$temperatureHistory})
            && (!$humidityHistory || !@{$humidityHistory}));

    my @temperatureValues = map { $_->{value} } @{$temperatureHistory || []};
    my @humidityValues = map { $_->{value} } @{$humidityHistory || []};
    my ($temperatureMin, $temperatureMax) = @temperatureValues
        ? ($temperatureValues[0], $temperatureValues[0]) : (0, 1);
    for my $value (@temperatureValues) {
        $temperatureMin = $value if ($value < $temperatureMin);
        $temperatureMax = $value if ($value > $temperatureMax);
    }
    my ($humidityMin, $humidityMax) = @humidityValues
        ? ($humidityValues[0], $humidityValues[0]) : (0, 1);
    for my $value (@humidityValues) {
        $humidityMin = $value if ($value < $humidityMin);
        $humidityMax = $value if ($value > $humidityMax);
    }
    my $temperatureRange = $temperatureMax - $temperatureMin || 1;
    my $humidityRange = $humidityMax - $humidityMin || 1;
    my $width = 560;
    my $height = 190;
    my $plotLeft = 52;
    my $plotRight = $width - 14;
    my $plotTop = 12;
    my $plotBottom = $height - 36;
    my $points = sub {
        my ($history, $min, $range) = @_;
        my @points;
        for my $index (0 .. $#{$history}) {
            my $x = @{$history} == 1 ? ($plotLeft + $plotRight) / 2
                : $plotLeft + $index * ($plotRight - $plotLeft) / ($#{$history});
            my $y = $plotBottom - (($history->[$index]{value} - $min)
                / $range * ($plotBottom - $plotTop));
            push @points, sprintf('%.1f,%.1f', $x, $y);
        }
        return join(' ', @points);
    };
    my $temperaturePoints = $points->($temperatureHistory || [], $temperatureMin, $temperatureRange);
    my $humidityPoints = $points->($humidityHistory || [], $humidityMin, $humidityRange);

    my $rangeLabel = defined($hours) ? 'Verlauf der letzten ' . $hours . ' Stunden' : 'Temperaturverlauf';
    my @timeLabels;
    my $labelHistory = @{$temperatureHistory || []} ? $temperatureHistory : $humidityHistory;
    for my $index (0 .. 5) {
        my $valueIndex = int($index * ($#{$labelHistory}) / 5);
        push @timeLabels, {
            x => $plotLeft + $valueIndex * ($plotRight - $plotLeft) / ($#{$labelHistory} || 1),
            label => TemperatureCollector_TimeLabel(
                $labelHistory->[$valueIndex]{timestamp}, $index == 0 || $index == 5
            ),
        };
    }
    my $timeAxis = join('', map {
        '<text class="tc-axis-value" x="' . sprintf('%.1f', $_->{x})
        . '" y="' . ($plotBottom + 18) . '"'
        . ($_->{x} == $plotRight ? ' text-anchor="end"' : '')
        . '>' . TemperatureCollector_Escape($_->{label}) . '</text>'
    } @timeLabels);
    return '<div class="tc-chart-wrap"><div class="tc-chart-title">'
        . '<span>' . TemperatureCollector_Escape($rangeLabel) . ' (' . $step . '-Minuten-Auflösung)</span>'
        . '<span class="tc-chart-controls">'
        . '<button type="button" title="Älteres Zeitfenster" onclick="tcShift(this,1)">←</button>'
        . '<button type="button" title="Neueres Zeitfenster" onclick="tcShift(this,-1)">→</button>'
        . '<button type="button" title="Feinere Auflösung" onclick="tcZoom(this,-1)">+</button>'
        . '<button type="button" title="Gröbere Auflösung" onclick="tcZoom(this,1)">−</button>'
        . '</span></div><svg class="tc-chart" viewBox="0 0 '
        . $width . ' ' . $height . '" role="img" aria-label="Temperaturverlauf">'
        . '<line class="tc-axis" x1="' . $plotLeft . '" y1="' . $plotTop . '" x2="'
        . $plotLeft . '" y2="' . $plotBottom . '" /><line class="tc-axis" x1="'
        . $plotLeft . '" y1="' . $plotBottom . '" x2="' . $plotRight . '" y2="'
        . $plotBottom . '" /><text class="tc-axis-label" transform="translate(14 '
        . (($plotTop + $plotBottom) / 2) . ') rotate(-90)">Temperatur (°C)</text>'
        . '<text class="tc-axis-label" x="' . (($plotLeft + $plotRight) / 2)
        . '" y="' . ($height - 5) . '">Zeit</text><text class="tc-axis-value" x="'
        . ($plotLeft - 8) . '" y="' . ($plotTop + 4) . '" text-anchor="end">'
        . TemperatureCollector_Escape(sprintf('%.1f', $temperatureMax)) . '</text><text class="tc-axis-value" x="'
        . ($plotLeft - 8) . '" y="' . ($plotBottom + 4) . '" text-anchor="end">'
        . TemperatureCollector_Escape(sprintf('%.1f', $temperatureMin)) . '</text>'
        . ($humidityHistory && @{$humidityHistory}
            ? '<text class="tc-axis-label" transform="translate(' . ($width - 10) . ' '
                . (($plotTop + $plotBottom) / 2) . ') rotate(90)">Luftfeuchtigkeit (%)</text>'
                . '<text class="tc-axis-value" x="' . ($plotRight + 8) . '" y="' . ($plotTop + 4) . '">'
                . TemperatureCollector_Escape(sprintf('%.1f', $humidityMax)) . '</text>'
                . '<text class="tc-axis-value" x="' . ($plotRight + 8) . '" y="' . ($plotBottom + 4) . '">'
                . TemperatureCollector_Escape(sprintf('%.1f', $humidityMin)) . '</text>'
            : '')
        . $timeAxis
        . '<g id="' . TemperatureCollector_Escape($chartId . '-temperature') . '" class="tc-series-temperature">'
        . ($temperaturePoints ne '' ? '<polyline points="' . TemperatureCollector_Escape($temperaturePoints) . '" />' : '')
        . '</g>'
        . ($humidityPoints ne '' ? '<g id="' . TemperatureCollector_Escape($chartId . '-humidity') . '" class="tc-series-humidity">'
            . '<polyline points="' . TemperatureCollector_Escape($humidityPoints) . '" /></g>' : '')
        . '</svg><div class="tc-legend">'
        . '<button type="button" class="tc-legend-item" onclick="tcToggleSeries(this,\'' . TemperatureCollector_Escape($chartId . '-temperature') . '\')"><i class="tc-legend-temperature"></i>Temperatur</button>'
        . ($humidityPoints ne '' ? '<button type="button" class="tc-legend-item" onclick="tcToggleSeries(this,\'' . TemperatureCollector_Escape($chartId . '-humidity') . '\')"><i class="tc-legend-humidity"></i>Luftfeuchtigkeit</button>' : '')
        . '</div></div>';
}

sub TemperatureCollector_HistoryTable {
    my ($temperatureHistory, $humidityHistory) = @_;
    return '' if ((!$temperatureHistory || !@{$temperatureHistory})
        && (!$humidityHistory || !@{$humidityHistory}));
    my %rows;
    for my $row (@{$temperatureHistory || []}) {
        $rows{$row->{timestamp}}{temperature} = $row->{value};
    }
    for my $row (@{$humidityHistory || []}) {
        $rows{$row->{timestamp}}{humidity} = $row->{value};
    }
    my @rows = map {
        {timestamp => $_, %{$rows{$_}}}
    } sort { $b cmp $a } keys %rows;
    splice(@rows, 20) if (@rows > 20);
    my $html = '<table class="tc-history"><thead><tr><th>Zeit</th><th>Temperatur</th>'
        . (@{$humidityHistory || []} ? '<th>Luftfeuchtigkeit</th>' : '')
        . '</tr></thead><tbody>';
    for my $row (@rows) {
        $html .= '<tr><td>' . TemperatureCollector_Escape($row->{timestamp})
            . '</td><td>' . (defined($row->{temperature})
                ? TemperatureCollector_Escape(sprintf('%.2f °C', $row->{temperature})) : '–')
            . '</td>';
        $html .= '<td>' . (defined($row->{humidity})
                ? TemperatureCollector_Escape(sprintf('%.2f %%', $row->{humidity})) : '–')
            . '</td>' if (@{$humidityHistory || []});
        $html .= '</tr>';
    }
    return $html . '</tbody></table>';
}

sub TemperatureCollector_BuildDashboard {
    my ($hash, $options) = @_;
    $options ||= {};
    my $devices = TemperatureCollector_Discover($hash->{NAME});
    $devices = TemperatureCollector_ApplyOrder($hash->{NAME}, $devices);
    my $dbHash = TemperatureCollector_DbLog($hash);
    my $refresh = AttrVal($hash->{NAME}, 'autoRefresh', 60);
    $refresh = 60 if ($refresh !~ /^\d+$/ || $refresh > 3600);
    my $historyHours = AttrVal($hash->{NAME}, 'historyHours', 24);
    $historyHours = 24 if ($historyHours !~ /^\d+(?:\.\d+)?$/ || $historyHours < 1 || $historyHours > 8760);
    my $offset = $options->{offset};
    $offset = 0 if (!defined($offset) || $offset !~ /^\d+$/ || $offset > 8760);
    my $step = $options->{step};
    $step = 30 if (!defined($step) || $step !~ /^\d+$/ || $step < 5 || $step > 240);
    my $html = <<'HTML';
<style>
.tc-dashboard{font:14px sans-serif;color:#e8f0ea;background:#151f1b;max-width:980px;padding:14px;border-radius:8px}
.tc-header{position:relative;display:flex;justify-content:space-between;align-items:center;gap:16px;margin:0 0 16px;padding:4px 2px 14px;border-bottom:1px solid #3a4b43}
.tc-header-actions{display:flex;align-items:center;gap:8px}.tc-edit{border:1px solid #587066;border-radius:4px;background:#26382f;color:#e8f0ea;cursor:pointer;font-size:18px;width:30px;height:30px}
.tc-clock{position:absolute;left:56%;transform:translateX(-50%);display:flex;align-items:center;gap:8px;color:#c9d8cd}.tc-clock-face{width:44px;height:44px}.tc-clock-face circle{fill:#1d2a24;stroke:#75c5a0;stroke-width:1.5}.tc-clock-face line{stroke:#9db0a4;stroke-width:1}.tc-clock-face .tc-tick-major{stroke:#e8f0ea;stroke-width:1.8}.tc-clock-face .tc-hand-hour{stroke:#e8f0ea;stroke-width:2}.tc-clock-face .tc-hand-minute{stroke:#75c5a0;stroke-width:1.5}.tc-clock-face .tc-hand-second{stroke:#e07b65;stroke-width:1}.tc-clock-date{font-size:11px;white-space:nowrap;color:#9db0a4}
@media(max-width:640px){.tc-clock{display:none}}
.tc-brand{display:flex;align-items:center;gap:10px}.tc-brand-mark{display:grid;place-items:center;width:34px;height:34px;border-radius:50%;background:#75c5a0;color:#102019;font-size:20px;font-weight:700}
.tc-brand small{display:block;color:#9db0a4;font-size:10px;letter-spacing:.08em}.tc-brand h1{margin:2px 0 0;font-size:22px;line-height:1.1}
.tc-live{display:flex;align-items:center;gap:8px;color:#9db0a4}.tc-led{width:9px;height:9px;border-radius:50%;background:#75c5a0;box-shadow:0 0 8px #75c5a0;animation:tc-live-pulse 4s ease-in-out infinite}@keyframes tc-live-pulse{0%,100%{opacity:.35;box-shadow:0 0 3px #75c5a0}50%{opacity:1;box-shadow:0 0 10px #75c5a0}}
.tc-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px}
.tc-card{border:1px solid #3a4b43;border-radius:8px;background:#1d2a24;overflow:hidden;box-shadow:0 2px 8px #0b100d}
.tc-card summary{cursor:pointer;list-style:none;padding:14px;display:flex;justify-content:space-between;gap:12px}
.tc-card summary::-webkit-details-marker{display:none}
.tc-name{font-weight:600}.tc-type,.tc-meta,.tc-muted{color:#9db0a4;font-size:12px}
.tc-value{display:flex;flex-direction:column;align-items:flex-end;gap:2px;font-size:22px;font-weight:600;white-space:nowrap;color:#f0f7f1}.tc-temperature{font-size:22px}.tc-humidity{font-size:13px;color:#8ec4d3}
.tc-detail{border-top:1px solid #3a4b43;padding:12px}.tc-chart-wrap{overflow-x:auto}.tc-chart-title{display:flex;justify-content:space-between;align-items:center;gap:8px;color:#9db0a4;font-size:12px;margin-bottom:4px}.tc-chart-controls{display:flex;gap:3px}.tc-chart-controls button{border:1px solid #587066;border-radius:4px;background:#26382f;color:#e8f0ea;cursor:pointer;min-width:24px;height:24px}.tc-chart{display:block;width:100%;min-width:560px;height:190px;background:#17231f}
.tc-axis{stroke:#587066;stroke-width:1}.tc-axis-label,.tc-axis-value{fill:#9db0a4;font-size:10px}.tc-history-toggle{border:1px solid #587066;border-radius:50%;background:#26382f;color:#e8f0ea;cursor:pointer;font-size:18px;height:28px;width:28px;line-height:20px;margin-top:12px}.tc-history-panel[hidden]{display:none}
.tc-chart polyline{fill:none;stroke:#75c5a0;stroke-width:3;vector-effect:non-scaling-stroke}.tc-chart .tc-series-humidity polyline{stroke:#79aeca}.tc-series-hidden{display:none}.tc-legend{display:flex;gap:14px;flex-wrap:wrap;margin-top:6px}.tc-legend-item{border:0;background:transparent;color:#9db0a4;cursor:pointer;padding:0;font:inherit;font-size:12px}.tc-legend-item.tc-legend-hidden{opacity:.45;text-decoration:line-through}.tc-legend-item i{display:inline-block;width:8px;height:8px;border-radius:50%;background:#75c5a0;margin-right:5px}.tc-legend-item .tc-legend-humidity{background:#79aeca}
.tc-history{border-collapse:collapse;width:100%;margin-top:12px;font-size:12px}.tc-history th,.tc-history td{padding:4px 6px;border-bottom:1px solid #3a4b43;text-align:left}
.tc-error{padding:12px;border:1px solid #a45b5b;background:#321f1f;color:#ffd9d9}
.tc-reorder-mode .tc-card{cursor:move;outline:1px dashed #75c5a0;outline-offset:3px}.tc-reorder-mode .tc-card summary{pointer-events:none}.tc-card.tc-dragging{opacity:.45}
.tc-list-view .tc-grid{grid-template-columns:1fr}.tc-list-view .tc-card summary{align-items:center}
</style>
<div class="tc-dashboard">
HTML
    $html .= '<header class="tc-header"><div class="tc-brand">'
        . '<span class="tc-brand-mark">T</span><div><small>FHEM / TEMPERATURE COLLECTOR</small>'
        . '<h1>Temperaturübersicht</h1></div></div>'
        . '<div class="tc-clock" aria-label="Aktuelle Uhrzeit und Datum">'
        . '<svg class="tc-clock-face" viewBox="0 0 44 44" role="img" aria-hidden="true">'
        . '<circle cx="22" cy="22" r="20"/>'
        . '<line class="tc-tick-major" x1="22" y1="3" x2="22" y2="8"/>'
        . '<line x1="31.5" y1="4.5" x2="29.5" y2="8"/>'
        . '<line x1="38.5" y1="11.5" x2="35" y2="13.5"/>'
        . '<line class="tc-tick-major" x1="41" y1="22" x2="36" y2="22"/>'
        . '<line x1="38.5" y1="32.5" x2="35" y2="30.5"/>'
        . '<line x1="31.5" y1="39.5" x2="29.5" y2="36"/>'
        . '<line class="tc-tick-major" x1="22" y1="41" x2="22" y2="36"/>'
        . '<line x1="12.5" y1="39.5" x2="14.5" y2="36"/>'
        . '<line x1="5.5" y1="32.5" x2="9" y2="30.5"/>'
        . '<line class="tc-tick-major" x1="3" y1="22" x2="8" y2="22"/>'
        . '<line x1="5.5" y1="11.5" x2="9" y2="13.5"/>'
        . '<line x1="12.5" y1="4.5" x2="14.5" y2="8"/>'
        . '<line class="tc-hand-hour" x1="22" y1="22" x2="22" y2="12"/>'
        . '<line class="tc-hand-minute" x1="22" y1="22" x2="22" y2="7"/>'
        . '<line class="tc-hand-second" x1="22" y1="22" x2="22" y2="6"/>'
        . '<circle cx="22" cy="22" r="1.5" fill="#e07b65" stroke="none"/></svg>'
        . '<span class="tc-clock-date"></span></div>'
        . '<div class="tc-header-actions"><div class="tc-live"><i class="tc-led" title="Aktuelle Sensorwerte"></i></div>'
        . '<button type="button" class="tc-edit" title="Listenansicht/Kachelansicht wechseln" aria-label="Listenansicht/Kachelansicht wechseln"'
        . ' onclick="tcToggleView(this)">☷</button>'
        . ($options->{editable}
            ? '<button type="button" class="tc-edit tc-reorder-edit" title="Sensorreihenfolge bearbeiten" aria-label="Sensorreihenfolge bearbeiten"'
                . ' onclick="tcToggleEdit(this)">✎</button>'
            : '')
        . '</div></header><div class="tc-grid">';

    if (!@{$devices}) {
        return $html . '<div class="tc-error">Keine numerischen Temperatur-Readings gefunden.</div></div></div>';
    }

    my $index = 0;
    for my $device (@{$devices}) {
        my $temperatureHistory = $dbHash
            ? TemperatureCollector_History($hash, $device->{name}, $device->{temperatureReading}, {offset => $offset, step => $step})
            : [];
        my $humidityHistory = $dbHash && $device->{humidityReading}
            ? TemperatureCollector_History($hash, $device->{name}, $device->{humidityReading},
                {offset => $offset, step => $step}, 'humidity')
            : [];
        my $humidity = defined($device->{humidity})
            ? TemperatureCollector_Escape(sprintf('%s', $device->{humidity})) . ' %' : '';
        my $readingName = AttrVal($hash->{NAME}, 'showReadingName', 1);
        my $readingLabel = $readingName
            ? '<br><span class="tc-type">' . TemperatureCollector_Escape($device->{temperatureReading}) . '</span>'
            : '';
        $html .= '<details class="tc-card" data-device="' . TemperatureCollector_Escape($device->{name}) . '"><summary><span><span class="tc-name">'
            . TemperatureCollector_Escape($device->{alias}) . '</span>' . $readingLabel . '</span>'
            . '<span class="tc-value"><span class="tc-temperature">'
            . TemperatureCollector_Escape(sprintf('%s', $device->{temperature})) . ' °C</span>'
            . '<span class="tc-humidity">' . ($humidity || '&nbsp;') . '</span></span></summary>'
            . '<div class="tc-detail">' . TemperatureCollector_Svg(
                $temperatureHistory, $humidityHistory, $historyHours, $step, 'tc-chart-' . $index
            );
        if (AttrVal($hash->{NAME}, 'showHistoryTable', 0)) {
            my $tableId = 'tc-history-' . $index;
            $html .= '<button type="button" class="tc-history-toggle" aria-expanded="false"'
                . ' aria-controls="' . $tableId . '" title="Messwerttabelle ein-/ausblenden"'
                . ' onclick="var p=document.getElementById(\'' . $tableId
                . '\');var o=p.hidden;p.hidden=!o;this.textContent=o?\'−\':\'+\';'
                . 'this.setAttribute(\'aria-expanded\',o?\'true\':\'false\');">+</button>'
                . '<div id="' . $tableId . '" class="tc-history-panel" hidden>'
                . TemperatureCollector_HistoryTable($temperatureHistory, $humidityHistory) . '</div>';
        }
        $html .= '<p class="tc-meta">Aktualisiert: '
            . TemperatureCollector_Escape($device->{temperatureTimestamp}) . '</p></div></details>';
        $index++;
    }
    $html .= '</div></div>';
    $html .= '<script>(function(){var d=document.querySelector(".tc-dashboard");window.tcCurrentUrl=window.location.href;'
        . 'window.tcUpdateClock=function(root){var now=new Date(),s=now.getSeconds(),m=now.getMinutes(),h=now.getHours()%12;'
        . 'var hour=root.querySelector(".tc-hand-hour"),minute=root.querySelector(".tc-hand-minute"),second=root.querySelector(".tc-hand-second"),date=root.querySelector(".tc-clock-date");'
        . 'if(hour)hour.setAttribute("transform","rotate("+(h*30+m*.5)+" 22 22)");'
        . 'if(minute)minute.setAttribute("transform","rotate("+(m*6+s*.1)+" 22 22)");'
        . 'if(second)second.setAttribute("transform","rotate("+(s*6)+" 22 22)");'
        . 'if(date)date.textContent=now.toLocaleDateString("de-DE",{weekday:"short",day:"2-digit",month:"2-digit",year:"numeric"});};'
        . 'window.tcToggleSeries=function(button,id){var series=document.getElementById(id);if(!series)return;'
        . 'var hidden=series.classList.toggle("tc-series-hidden");button.classList.toggle("tc-legend-hidden",hidden);'
        . 'button.setAttribute("aria-pressed",hidden?"false":"true");};'
        . 'tcUpdateClock(d);setInterval(function(){tcUpdateClock(d);},1000);'
        . 'var k="TemperatureCollector:"+'
        . TemperatureCollector_EscapeJson($hash->{NAME}) . ',vk=k+":view",ek=k+":edit",cn='
        . TemperatureCollector_EscapeJson($hash->{NAME}) . ',cp='
        . TemperatureCollector_EscapeJson(TemperatureCollector_DashboardBasePath()) . ',su=cp+"/TemperatureCollector/"+encodeURIComponent(cn);'
        . 'window.tcApplyOrder=function(root){};'
        . 'window.tcApplyView=function(root){var list=localStorage.getItem(vk)==="list";root.classList.toggle("tc-list-view",list);'
        . 'var button=root.querySelector(".tc-header-actions .tc-edit");if(button)button.textContent=list?"▦":"☷";};'
        . 'window.tcToggleView=function(button){var list=d.classList.toggle("tc-list-view");'
        . 'localStorage.setItem(vk,list?"list":"grid");button.textContent=list?"▦":"☷";};'
        . 'window.tcApplyEdit=function(root){var active=localStorage.getItem(ek)==="1";root.classList.toggle("tc-reorder-mode",active);'
        . 'var button=root.querySelector(".tc-reorder-edit");if(!button){root.classList.remove("tc-reorder-mode");'
        . 'root.querySelectorAll(".tc-card").forEach(function(card){card.draggable=false;});return;}'
        . 'button.textContent=active?"✓":"✎";'
        . 'root.querySelectorAll(".tc-card").forEach(function(card){card.draggable=active;});};'
        . 'window.tcToggleEdit=function(button){var active=d.classList.toggle("tc-reorder-mode");'
        . 'localStorage.setItem(ek,active?"1":"0");button.textContent=active?"✓":"✎";button.setAttribute("aria-pressed",active?"true":"false");'
        . 'd.querySelectorAll(".tc-card").forEach(function(card){card.draggable=active;});};'
        . 'window.tcBindReorder=function(d){d.addEventListener("dragstart",function(e){if(!d.classList.contains("tc-reorder-mode"))return;'
        . 'var card=e.target.closest(".tc-card");if(!card)return;e.dataTransfer.setData("text/plain",card.getAttribute("data-device"));card.classList.add("tc-dragging");});'
        . 'd.addEventListener("dragend",function(e){var card=e.target.closest(".tc-card");if(card)card.classList.remove("tc-dragging");});'
        . 'd.addEventListener("dragover",function(e){if(d.classList.contains("tc-reorder-mode")&&e.target.closest(".tc-card")){e.preventDefault();'
        . 'var edge=70,speed=14;if(e.clientY<edge)window.scrollBy(0,-speed);'
        . 'else if(window.innerHeight-e.clientY<edge)window.scrollBy(0,speed);}});'
        . 'd.addEventListener("drop",function(e){if(!d.classList.contains("tc-reorder-mode"))return;e.preventDefault();'
        . 'var source=d.querySelector(".tc-card[data-device=\\"" + e.dataTransfer.getData("text/plain") + "\\"]"),target=e.target.closest(".tc-card");'
        . 'if(!source||!target||source===target)return;var rect=target.getBoundingClientRect();'
        . 'target.parentNode.insertBefore(source,e.clientY<rect.top+rect.height/2?target:target.nextSibling);'
        . 'tcSaveOrder();});};'
        . 'window.tcSaveOrder=function(){if(!d.querySelector(".tc-reorder-edit"))return;'
        . 'var order=Array.prototype.map.call(d.querySelectorAll(".tc-card"),function(c){return c.getAttribute("data-device");});'
        . 'var json=JSON.stringify(order),b64=btoa(unescape(encodeURIComponent(json)));'
        . 'fetch(su+"?tcSaveOrder="+encodeURIComponent(b64),{credentials:"same-origin"}).then(function(response){'
        . 'return response.text().then(function(text){if(!response.ok||text.indexOf("gespeichert")<0)throw new Error(text||"Speichern fehlgeschlagen");});'
        . '}).catch(function(){return fetch(cp+"?cmd=set%20"+encodeURIComponent(cn)+"%20saveOrder%20"+encodeURIComponent(b64)+"&XHR=1",'
        . '{credentials:"same-origin"}).then(function(response){return response.text();}).then(function(text){'
        . 'if(text.indexOf("gespeichert")<0)throw new Error(text||"Speichern fehlgeschlagen");});'
        . '}).catch(function(error){if(window.console)console.error("TemperatureCollector: "+error.message);});};'
        . 'tcBindReorder(d);tcApplyOrder(d);tcApplyView(d);tcApplyEdit(d);'
        . 'window.tcDashboardLoad=function(url){window.tcCurrentUrl=url;var o={},p={};'
        . 'd.querySelectorAll("details[data-device][open]").forEach(function(e){o[e.getAttribute("data-device")]=true;});'
        . 'd.querySelectorAll("details[data-device] .tc-history-panel:not([hidden])").forEach(function(e){'
        . 'var card=e.closest("details[data-device]");if(card)p[card.getAttribute("data-device")]=true;});'
        . 'fetch(url,{cache:"no-store",credentials:"same-origin"}).then(function(x){return x.text();}).then(function(t){'
        . 'var n=new DOMParser().parseFromString(t,"text/html").querySelector(".tc-dashboard");if(!n)return;tcApplyOrder(n);tcApplyView(n);tcApplyEdit(n);tcBindReorder(n);'
        . 'n.querySelectorAll("details[data-device]").forEach(function(e){var name=e.getAttribute("data-device");'
        . 'if(o[name])e.open=true;if(p[name]){var panel=e.querySelector(".tc-history-panel"),button=e.querySelector(".tc-history-toggle");'
        . 'if(panel){panel.hidden=false;if(button){button.textContent="−";button.setAttribute("aria-expanded","true");}}}});'
        . 'd.replaceWith(n);d=n;}).catch(function(){});};'
        . 'window.tcShift=function(button,direction){var u=new URL(window.tcCurrentUrl);'
        . 'var h=parseFloat(u.searchParams.get("tcHours")||"' . (0 + $historyHours) . '");'
        . 'var o=parseInt(u.searchParams.get("tcOffset")||"0",10)||0;'
        . 'u.searchParams.set("tcHours",h);u.searchParams.set("tcOffset",Math.max(0,o+direction*h));window.tcDashboardLoad(u.href);};'
        . 'window.tcZoom=function(button,direction){var u=new URL(window.tcCurrentUrl);'
        . 'var s=[5,10,15,30,60,120,240];var c=parseInt(u.searchParams.get("tcStep")||"' . (0 + $step) . '",10)||30;'
        . 'var i=s.indexOf(c);if(i<0)i=3; i=Math.max(0,Math.min(s.length-1,i+direction));'
        . 'u.searchParams.set("tcStep",s[i]);window.tcDashboardLoad(u.href);};})();</script>';
    if ($refresh) {
        $html .= '<script>setInterval(function(){if(!document.querySelector(".tc-reorder-mode"))'
            . 'window.tcDashboardLoad(window.tcCurrentUrl);},'
            . (0 + $refresh) * 1000 . ');</script>';
    }
    return $html;
}

sub main::TemperatureCollector_CGI {
    my ($request) = @_;
    $request = '' if (!defined($request));
    my ($path) = split(/\?/, $request, 2);
    my @parts = split('/', $path);
    my $name = $parts[-1];
    my $hash = $main::defs{$name};
    return ('text/plain; charset=utf-8', "Unknown TemperatureCollector device: $name")
        if (!$hash || ($hash->{TYPE} || '') ne 'TemperatureCollector');

    my $encodedOrder = TemperatureCollector_QueryValue($request, 'tcSaveOrder', undef);
    if (defined($encodedOrder)) {
        my $error = TemperatureCollector_SaveOrder($name, decode_base64($encodedOrder));
        return ('text/plain; charset=utf-8', $error)
            if (defined($error));
        return ('text/plain; charset=utf-8', 'Sensorreihenfolge gespeichert');
    }

    my $options = {
        offset => TemperatureCollector_QueryValue($request, 'tcOffset', 0),
        step => TemperatureCollector_QueryValue($request, 'tcStep', 30),
    };
    my $html = TemperatureCollector_BuildDashboard($hash, $options);
    return ('text/html; charset=utf-8', '<!doctype html><html lang="de"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>TemperatureCollector - ' . TemperatureCollector_Escape($name)
        . '</title></head><body style="margin:0;padding:16px;background:#151f1b">'
        . $html . '</body></html>');
}

1;

=pod
=item device
=item summary Automatische Temperaturübersicht für FHEM
=item summary_DE Sammelt Temperatur-Readings und optionale DbLog-Verläufe
=begin html

<a id="TemperatureCollector"></a>
<h3>TemperatureCollector</h3>
<p>
    TemperatureCollector ist ein Meta-Modul. Es durchsucht die in FHEM
    definierten Geräte automatisch nach einem numerischen Reading mit dem
    exakten Namen <code>temperature</code> und stellt sie in
    einem aufklappbaren Dashboard dar. Optionale Feuchte-Readings werden
    ebenfalls angezeigt.
</p>

<b>Define</b>
<ul>
    <code>define &lt;name&gt; TemperatureCollector</code>
</ul>

<b>Get</b>
<ul>
    <li><code>get &lt;name&gt; _showDashboard</code> - Dashboard mit allen erkannten Thermometern</li>
    <li><code>get &lt;name&gt; _dashboardURL</code> - URL für die eigenständige FHEMWEB-Ansicht</li>
</ul>
<p>
    Der Editierstift für die Sensorreihenfolge wird nur bei
    <code>_showDashboard</code> angezeigt. In der isolierten URL-Ansicht bleibt
    nur der Umschalter zwischen Listen- und Kachelansicht verfügbar.
</p>

<b>Attributes</b>
<ul>
    <li><code>dbLog &lt;name&gt;</code> - optionales DbLog-Gerät; ohne Angabe wird das erste DbLog-Gerät verwendet</li>
    <li><code>historyHours &lt;1..8760&gt;</code> - Zeitraum der DbLog-Historie, Standard: 24</li>
    <li><code>autoRefresh 0|15|30|60|300</code> - Aktualisierung ohne vollständigen Seiten-Reload in Sekunden, Standard: 60</li>
    <li><code>showHistoryTable 0|1</code> - Plus-Schalter für die Messwerttabelle aktivieren, Standard: 0</li>
    <li><code>showReadingName 0|1</code> - Reading-Namen unter dem Alias anzeigen, Standard: 1</li>
    <li><code>includeDevices &lt;name,...&gt;</code> - optional ausschließlich diese Geräte anzeigen</li>
    <li><code>excludeDevices &lt;name,...&gt;</code> - diese Geräte aus der Erkennung ausschließen</li>
</ul>

<b>DbLog</b>
<p>
    Wenn ein DbLog-Gerät vorhanden ist, fragt das Modul die historische
    Temperatur über die FHEM-interne DbLog-Schnittstelle ab. Ohne DbLog werden
    die aktuellen Readings weiterhin angezeigt; historische Diagramme sind dann
    nicht verfügbar. Das Diagramm zeigt die Achsen Temperatur (Y) und Zeit (X)
    sowie den gewählten Zeitraum und mehrere Zeitmarken. Beim automatischen
    Aktualisieren bleibt der Aufklappzustand der Karten erhalten. Bei
    <code>showHistoryTable 1</code> wird die Messwerttabelle erst nach Klick
    auf den Plus-Schalter eingeblendet.
    Wenn eine Feuchte-Historie vorhanden ist, zeigt das Diagramm eine zweite
    blaue Kurve mit eigener Y-Achse und eine anklickbare Legende zum Ein- und
    Ausblenden der Temperatur- und Feuchtereihe. Die Tabelle enthält dann
    ebenfalls beide Werte.
    Die Diagrammsteuerung navigiert mit <code>←</code> und <code>→</code>
    durch 24-Stunden-Fenster. <code>+</code> und <code>−</code> ändern die
    Auflösung; standardmäßig werden 30-Minuten-Intervalle verwendet.
</p>

<p>
    Über das Stift-Symbol kann die Reihenfolge der automatisch erkannten
    Sensorkarten per Drag-and-drop angepasst werden. Die Reihenfolge wird
    serverseitig im FHEM-Key-Value-Speicher je TemperatureCollector gespeichert;
    neue Geräte werden automatisch angefügt.
</p>

=end html
=cut
