package main;

use strict;
use warnings;

our $TemperatureCollector_VERSION = '1.0.3';
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
        'fileLog',
        'historySource:auto,dblog,filelog',
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
    $hash->{VERSION} = $TemperatureCollector_VERSION;

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
    if ($cmd eq '_dashboardEmbedURL') {
        return TemperatureCollector_DashboardBasePath() . '/TemperatureCollector/'
            . (defined(&urlEncode) ? urlEncode($name) : $name) . '?tcEmbed=1';
    }
    if ($cmd eq '_dashboardURL') {
        my $scheme = AttrVal($main::FW_wname, 'HTTPS', 0) ? 'https' : 'http';
        my $host = $main::FW_httpheader{Host} || 'localhost';
        return $scheme . '://' . $host . TemperatureCollector_DashboardBasePath()
            . '/TemperatureCollector/'
            . (defined(&urlEncode) ? urlEncode($name) : $name);
    }

    return 'Unknown argument ' . ($cmd // '') . ', choose one of '
        . '_showDashboard:noArg _dashboardURL:noArg _dashboardEmbedURL:noArg';
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
    my ($timestamp, $edge, $longRange) = @_;
    return '' if (!defined($timestamp));
    if ($timestamp =~ /^(\d{4})-(\d{2})-(\d{2})[_ ](\d{2}):(\d{2})/) {
        return "$3.$2.$1" if ($longRange);
        return $edge ? "$3.$2.$1 $4:$5" : "$4:$5";
    }
    return $timestamp;
}

sub TemperatureCollector_GermanTime {
    my ($timestamp) = @_;
    return '' if (!defined($timestamp));
    return "$3.$2.$1 $4:$5" if ($timestamp =~ /^(\d{4})-(\d{2})-(\d{2})[_ T](\d{2}):(\d{2})/);
    return $timestamp;
}

sub TemperatureCollector_StepLabel {
    my ($step) = @_;
    return $step % 1440 == 0 ? ($step / 1440) . '-Tages-Auflösung'
        : $step % 60 == 0 ? ($step / 60) . '-Stunden-Auflösung'
        : $step . '-Minuten-Auflösung';
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

sub TemperatureCollector_FileLog {
    my ($hash) = @_;
    my $configured = AttrVal($hash->{NAME}, 'fileLog', '');
    if ($configured ne '') {
        return $main::defs{$configured}
            if (ref($main::defs{$configured}) eq 'HASH'
                && ($main::defs{$configured}{TYPE} || '') eq 'FileLog');
        main::Log3($hash->{NAME}, 2, "TemperatureCollector: configured FileLog '$configured' was not found");
        return undef;
    }

    # Without an explicit FileLog, use the first one whose regexp matches a collected device.
    my $devices = TemperatureCollector_Discover($hash->{NAME});
    for my $name (sort keys %main::defs) {
        my $fl = $main::defs{$name};
        next if (ref($fl) ne 'HASH' || ($fl->{TYPE} || '') ne 'FileLog');
        my $regexp = $fl->{REGEXP};
        next if (!defined($regexp));
        for my $device (@{$devices}) {
            my $line = $device->{name} . ':' . $device->{temperatureReading} . ': 0';
            return $fl if (eval { $line =~ /^(?:$regexp)$/ });
        }
    }
    return undef;
}

# 'dblog' or 'filelog' for the effective history source, undef if none is usable.
sub TemperatureCollector_HistorySource {
    my ($hash) = @_;
    my $mode = AttrVal($hash->{NAME}, 'historySource', 'auto');
    my $db = defined(&DbLog_Get) && TemperatureCollector_DbLog($hash);
    return $db ? 'dblog' : undef if ($mode eq 'dblog');
    return TemperatureCollector_FileLog($hash) ? 'filelog' : undef if ($mode eq 'filelog');
    return 'dblog' if ($db);
    return 'filelog' if (TemperatureCollector_FileLog($hash));
    return undef;
}

sub TemperatureCollector_FileLogRows {
    my ($hash, $device, $reading, $from, $to) = @_;
    my $fl = TemperatureCollector_FileLog($hash);
    return [] if (!$fl || !defined($fl->{logfile}));

    my $logdir = ($main::attr{global} && $main::attr{global}{logdir}) || './log';
    my %files;
    for (my $day = $from - ($from % 86400); $day <= $to + 86400; $day += 86400) {
        my $name = $fl->{logfile};
        $name =~ s/%L/$logdir/g;
        $name = strftime($name, localtime($day));
        $files{$name} = 1 if (-r $name);
    }

    my @rows;
    for my $file (sort keys %files) {
        open(my $fh, '<', $file) or next;
        while (my $line = <$fh>) {
            next if ($line !~ /^(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2})\s+\Q$device\E\s+\Q$reading\E:\s*(\S+)/);
            my ($d, $t, $value) = ($1, $2, $3);
            my ($y, $m, $dd) = split /-/, $d;
            my ($hh, $mm, $ss) = split /:/, $t;
            my $epoch = eval { timelocal($ss, $mm, $hh, $dd, $m - 1, $y) };
            next if (!defined($epoch) || $epoch < $from || $epoch > $to);
            push @rows, {tstamp => "$d $t", value => $value};
        }
        close($fh);
    }
    return \@rows;
}

sub TemperatureCollector_History {
    my ($hash, $device, $reading, $options, $kind) = @_;
    $options ||= {};
    my $source = TemperatureCollector_HistorySource($hash);
    return [] if (!$source);
    my $dbHash = $source eq 'dblog' ? TemperatureCollector_DbLog($hash) : undef;

    my $hours = $options->{hours} || 24;
    my $offset = $options->{offset} || 0;
    my $step = $options->{step} || 30;
    my $to = time() - ($offset * 3600);
    if (($options->{range} || '') eq 'day') {
        # Calendar day: end of the current day, shifted back in whole days
        my @lt = localtime(time());
        my $midnight = timelocal(0, 0, 0, $lt[3], $lt[4], $lt[5] + 1900);
        $to = $midnight + 86400 - ($offset * 3600);
    }
    my $from = $to - ($hours * 3600);
    if (defined($options->{from}) && defined($options->{to})) {
        $to = $options->{to} - ($offset * 3600);
        $from = $options->{from} - ($offset * 3600);
    }
    my $fromText = strftime('%Y-%m-%d_%H:%M:%S', localtime($from));
    my $toText = strftime('%Y-%m-%d_%H:%M:%S', localtime($to));
    my @rows;

    my $error;
    if ($source eq 'filelog') {
        @rows = @{TemperatureCollector_FileLogRows($hash, $device, $reading, $from, $to)};
    } else {
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
                my $bucket = $buckets{int($epoch / ($step * 60))} ||= {sum => 0, count => 0};
                $bucket->{sum} += $number;
                $bucket->{count}++;
                # Keep the latest timestamp of the bucket for axis labels and tooltips
                $bucket->{timestamp} = $entry->{timestamp}
                    if (!defined($bucket->{timestamp}) || $entry->{timestamp} gt $bucket->{timestamp});
                next;
            }
        }
        push @history, $entry;
    }
    push @history, map { {timestamp => $_->{timestamp}, value => $_->{sum} / $_->{count}} } values %buckets;
    @history = sort { $a->{timestamp} cmp $b->{timestamp} } @history;
    splice(@history, 0, @history - 400) if (@history > 400);
    return \@history;
}

sub TemperatureCollector_Svg {
    my ($temperatureHistory, $humidityHistory, $hours, $step, $chartId, $range, $fromValue, $toValue) = @_;
    return '<p class="tc-muted">Keine Historie (DbLog/FileLog) für dieses Reading verfügbar.</p>'
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
    my $hasHumidity = ($humidityHistory && @{$humidityHistory}) ? 1 : 0;
    my $plotRight = $width - ($hasHumidity ? 56 : 14);
    my $plotTop = 12;
    my $plotBottom = $height - 36;
    # Catmull-Rom spline converted to cubic Beziers; control-point Y is clamped to avoid overshoot.
    my $points = sub {
        my ($history, $min, $range) = @_;
        my @p;
        for my $index (0 .. $#{$history}) {
            my $x = @{$history} == 1 ? ($plotLeft + $plotRight) / 2
                : $plotLeft + $index * ($plotRight - $plotLeft) / ($#{$history});
            my $y = $plotBottom - (($history->[$index]{value} - $min)
                / $range * ($plotBottom - $plotTop));
            push @p, [$x, $y];
        }
        return ('', '') if (!@p);
        my $data = join(';', map {
            sprintf('%.1f,%.1f,%s,%s', @{$p[$_]}, $history->[$_]{value}, $history->[$_]{timestamp} || '')
        } 0 .. $#p);
        my $d = sprintf('M%.1f,%.1f', @{$p[0]});
        $d .= sprintf(' L%.1f,%.1f', @{$p[0]}) if (@p == 1);
        for my $i (0 .. $#p - 1) {
            my ($p0, $p1, $p2, $p3) = ($p[$i ? $i - 1 : 0], $p[$i], $p[$i + 1], $p[$i + 2 > $#p ? $#p : $i + 2]);
            my @c1 = ($p1->[0] + ($p2->[0] - $p0->[0]) / 6, $p1->[1] + ($p2->[1] - $p0->[1]) / 6);
            my @c2 = ($p2->[0] - ($p3->[0] - $p1->[0]) / 6, $p2->[1] - ($p3->[1] - $p1->[1]) / 6);
            my ($lo, $hi) = $p1->[1] < $p2->[1] ? ($p1->[1], $p2->[1]) : ($p2->[1], $p1->[1]);
            for my $v (\$c1[1], \$c2[1]) { ${$v} = $lo if (${$v} < $lo); ${$v} = $hi if (${$v} > $hi); }
            $d .= sprintf(' C%.1f,%.1f %.1f,%.1f %.1f,%.1f', @c1, @c2, @{$p2});
        }
        return ($d, $data);
    };
    my ($temperaturePoints, $temperatureData) = $points->($temperatureHistory || [], $temperatureMin, $temperatureRange);
    my ($humidityPoints, $humidityData) = $points->($humidityHistory || [], $humidityMin, $humidityRange);

    my $rangeLabel = 'Temperaturverlauf';
    my @timeLabels;
    my $labelHistory = @{$temperatureHistory || []} ? $temperatureHistory : $humidityHistory;
    my $longRange = ($hours || 24) > 48;
    my $labelCount = $#{$labelHistory} < 5 ? $#{$labelHistory} : 5;
    my $previousDate = '';
    for my $index (0 .. $labelCount) {
        my $valueIndex = $labelCount ? int($index * ($#{$labelHistory}) / $labelCount + 0.5) : 0;
        my $timestamp = $labelHistory->[$valueIndex]{timestamp} || '';
        my ($date, $time) = ('', '');
        if ($timestamp =~ /^(\d{4})-(\d{2})-(\d{2})[_ ](\d{2}):(\d{2})/) {
            $date = $longRange ? "$3.$2.$1" : "$3.$2.";
            $time = "$4:$5";
        } else {
            $time = $timestamp;
        }
        push @timeLabels, {
            x => $plotLeft + $valueIndex * ($plotRight - $plotLeft) / ($#{$labelHistory} || 1),
            lines => $longRange ? [$date] : [$time, ($date ne $previousDate ? $date : ())],
            first => $index == 0,
            last => $index == $labelCount && $index > 0,
        };
        $previousDate = $date;
    }
    my $timeAxis = join('', map {
        my $label = $_;
        my $anchor = $label->{first} ? 'start' : $label->{last} ? 'end' : 'middle';
        my $line = 0;
        '<text class="tc-axis-value" text-anchor="' . $anchor . '" x="' . sprintf('%.1f', $label->{x}) . '">'
        . join('', map {
            '<tspan x="' . sprintf('%.1f', $label->{x}) . '" y="' . ($plotBottom + 14 + 11 * $line++) . '">'
            . TemperatureCollector_Escape($_) . '</tspan>'
        } @{$label->{lines}}) . '</text>'
    } @timeLabels);
    return '<div class="tc-chart-wrap"><div class="tc-tip" hidden></div><div class="tc-chart-title">'
        . '<span><select class="tc-range" onchange="tcRange(this)" title="Zeitraum">'
        . join('', map {
            '<option value="' . $_->[0] . '"' . ($_->[0] eq ($range || '24h') ? ' selected' : '') . '>' . $_->[1] . '</option>'
        } (['24h', 'Letzte 24 Stunden'], ['day', 'Tag'], ['week', 'Woche'], ['month', 'Monat'], ['year', 'Jahr'], ['span', 'Eigener Zeitraum'],
           (($range || '') eq 'custom' ? (['custom', 'Letzte ' . $hours . ' Stunden']) : ())))
        . '</select> <span class="tc-muted">' . TemperatureCollector_Escape($rangeLabel) . ' (' . TemperatureCollector_StepLabel($step) . ')</span></span>'
        . '<span class="tc-chart-controls">'
        . '<button type="button" title="Älteres Zeitfenster" onclick="tcShift(this,1)">←</button>'
        . '<button type="button" title="Neueres Zeitfenster" onclick="tcShift(this,-1)">→</button>'
        . '<button type="button" title="Feinere Auflösung" onclick="tcZoom(this,-1)">+</button>'
        . '<button type="button" title="Gröbere Auflösung" onclick="tcZoom(this,1)">−</button>'
        . '</span></div>'
        . '<div class="tc-span"' . (($range || '') eq 'span' ? '' : ' hidden') . '>Von <input type="datetime-local" class="tc-from" value="'
        . TemperatureCollector_Escape($fromValue || '') . '"> bis <input type="datetime-local" class="tc-to" value="'
        . TemperatureCollector_Escape($toValue || '') . '"><button type="button" onclick="tcSpan(this)">Anwenden</button></div>'
        . '<svg class="tc-chart" viewBox="0 0 '
        . $width . ' ' . $height . '" role="img" aria-label="Temperaturverlauf">'
        . '<line class="tc-axis" x1="' . $plotLeft . '" y1="' . $plotTop . '" x2="'
        . $plotLeft . '" y2="' . $plotBottom . '" /><line class="tc-axis" x1="'
        . $plotLeft . '" y1="' . $plotBottom . '" x2="' . $plotRight . '" y2="'
        . $plotBottom . '" /><text class="tc-axis-label" transform="translate(14 '
        . (($plotTop + $plotBottom) / 2) . ') rotate(-90)">Temperatur (°C)</text>'
        . '<text class="tc-axis-value" x="'
        . ($plotLeft - 8) . '" y="' . ($plotTop + 4) . '" text-anchor="end">'
        . TemperatureCollector_Escape(sprintf('%.1f', $temperatureMax)) . '</text><text class="tc-axis-value" x="'
        . ($plotLeft - 8) . '" y="' . ($plotBottom + 4) . '" text-anchor="end">'
        . TemperatureCollector_Escape(sprintf('%.1f', $temperatureMin)) . '</text>'
        . ($humidityHistory && @{$humidityHistory}
            ? '<text class="tc-axis-label" transform="translate(' . ($width - 6) . ' '
                . (($plotTop + $plotBottom) / 2) . ') rotate(-90)">Luftfeuchtigkeit (%)</text>'
                . '<text class="tc-axis-value" x="' . ($plotRight + 8) . '" y="' . ($plotTop + 4) . '">'
                . TemperatureCollector_Escape(sprintf('%.1f', $humidityMax)) . '</text>'
                . '<text class="tc-axis-value" x="' . ($plotRight + 8) . '" y="' . ($plotBottom + 4) . '">'
                . TemperatureCollector_Escape(sprintf('%.1f', $humidityMin)) . '</text>'
            : '')
        . $timeAxis
        . '<g id="' . TemperatureCollector_Escape($chartId . '-temperature') . '" class="tc-series-temperature" data-unit="°C" data-pts="' . TemperatureCollector_Escape($temperatureData) . '">'
        . ($temperaturePoints ne '' ? '<path d="' . TemperatureCollector_Escape($temperaturePoints) . '" />' : '')
        . '</g>'
        . ($humidityPoints ne '' ? '<g id="' . TemperatureCollector_Escape($chartId . '-humidity') . '" class="tc-series-humidity" data-unit="%" data-pts="' . TemperatureCollector_Escape($humidityData) . '">'
            . '<path d="' . TemperatureCollector_Escape($humidityPoints) . '" /></g>' : '')
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

sub TemperatureCollector_HistoryParams {
    my ($hash, $options) = @_;
    $options ||= {};
    my $attrHours = AttrVal($hash->{NAME}, 'historyHours', 24);
    $attrHours = 24 if ($attrHours !~ /^\d+(?:\.\d+)?$/ || $attrHours < 1 || $attrHours > 8760);
    my %rangeHours = (day => 24, week => 168, month => 720, year => 8760, '24h' => 24);
    my %rangeStep = (day => 30, week => 60, month => 240, year => 1440, '24h' => 30);
    my ($spanFrom, $spanTo);
    my $range = $options->{range};
    if (defined($range) && $range eq 'span') {
        my $parse = sub {
            return undef if (!defined($_[0]) || $_[0] !~ /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?$/);
            return eval { timelocal(0, $5 || 0, $4 || 0, $3, $2 - 1, $1) };
        };
        $spanFrom = $parse->($options->{from});
        $spanTo = $parse->($options->{to});
        # A date-only end value includes that whole day
        $spanTo += 86400 if (defined($spanTo) && ($options->{to} || '') !~ /[T ]/);
        if (!defined($spanFrom) || !defined($spanTo) || $spanTo <= $spanFrom || $spanTo - $spanFrom > 366 * 86400) {
            $spanFrom = $spanTo = undef;
            $range = undef;
        }
    }
    $range = ($attrHours == 24 ? '24h' : 'custom') if (!defined($range) || !exists($rangeHours{$range}));
    my $hours = defined($spanFrom) ? ($spanTo - $spanFrom) / 3600
        : $range eq 'custom' ? $attrHours : $rangeHours{$range};
    $range = 'span' if (defined($spanFrom));
    my $offset = $options->{offset};
    $offset = 0 if (!defined($offset) || $offset !~ /^-?\d+$/ || $offset > 8760 || $offset < -8760);
    $offset = 0 if ($offset < 0 && !defined($spanFrom));
    $rangeStep{span} = $hours <= 48 ? 30 : $hours <= 200 ? 60 : $hours <= 800 ? 240 : 1440;
    my $step = $options->{step};
    $step = ($rangeStep{$range} || 30) if (!defined($step) || $step !~ /^\d+$/ || $step < 5 || $step > 1440);
    return {offset => $offset, step => $step, hours => $hours, range => $range,
        from => $spanFrom, to => $spanTo};
}

# Chart and history table of one card; only built when the card is opened.
sub TemperatureCollector_DetailHtml {
    my ($hash, $device, $index, $options) = @_;
    my $params = TemperatureCollector_HistoryParams($hash, $options);
    my $temperatureHistory = [];
    my $humidityHistory = [];
    if (TemperatureCollector_HistorySource($hash)) {
        $temperatureHistory = TemperatureCollector_History(
            $hash, $device->{name}, $device->{temperatureReading}, $params);
        $humidityHistory = TemperatureCollector_History(
            $hash, $device->{name}, $device->{humidityReading}, $params, 'humidity')
            if ($device->{humidityReading});
    }
    my $html = '<div data-hours="' . $params->{hours} . '" data-step="' . $params->{step} . '">'
        . TemperatureCollector_Svg($temperatureHistory, $humidityHistory, $params->{hours},
            $params->{step}, 'tc-chart-' . $index, $params->{range},
            strftime('%Y-%m-%dT%H:%M', localtime(defined($params->{from}) ? $params->{from} : time() - 86400)),
            strftime('%Y-%m-%dT%H:%M', localtime(defined($params->{to}) ? $params->{to} : time())));
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
    return $html . '</div>';
}

sub TemperatureCollector_EmbedCss {
    return <<'CSS';
.tc-dashboard,.tc-dashboard *{box-sizing:border-box;letter-spacing:normal;text-transform:none;text-shadow:none}
.tc-dashboard{line-height:1.4;text-align:left;font-size:14px!important}
.tc-dashboard select,.tc-dashboard input,.tc-dashboard button{margin:0!important;font-family:'Helvetica Neue',sans-serif!important;line-height:normal!important;float:none!important;box-shadow:none!important;width:auto!important;max-width:100%;text-transform:none!important}
.tc-dashboard select.tc-range{-webkit-appearance:menulist;appearance:auto;height:26px!important;padding:0 6px!important;font-size:12px!important;background:#26342d!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important}
.tc-dashboard .tc-span input{height:26px!important;padding:0 6px!important;font-size:12px!important;background:#26342d!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important}
.tc-dashboard .tc-chart-controls button,.tc-dashboard .tc-span button{height:26px!important;min-width:26px!important;padding:0 8px!important;font-size:12px!important;font-weight:600!important;background:#26342d!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important}
.tc-dashboard .tc-history-toggle{width:28px!important;height:28px!important;padding:0!important;font-size:18px!important;background:#26342d!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important}
.tc-dashboard .tc-edit{width:40px!important;height:40px!important;padding:0!important;font-size:28px!important;background:none!important;border:0!important;color:#f4f4e9!important}
.tc-dashboard .tc-save{padding:8px 12px!important;font-size:12px!important;background:#26342d!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important}
.tc-dashboard .tc-chart-title{font-size:12px!important;line-height:1.3!important}.tc-dashboard .tc-chart-title .tc-muted{font-size:12px!important}
.tc-dashboard h1,.tc-dashboard h2,.tc-dashboard h3,.tc-dashboard p{margin-top:0;text-transform:none}
.tc-dashboard .tc-brand h1{margin:3px 0!important;font:500 22px Georgia,serif!important;line-height:1.1!important}
.tc-dashboard table{width:100%;margin:12px 0 0!important}.tc-dashboard th,.tc-dashboard td{font-size:12px!important;padding:4px 6px!important}
CSS
}

sub TemperatureCollector_BuildDashboard {
    my ($hash, $options) = @_;
    $options ||= {};
    my $devices = TemperatureCollector_Discover($hash->{NAME});
    $devices = TemperatureCollector_ApplyOrder($hash->{NAME}, $devices);
    my $refresh = AttrVal($hash->{NAME}, 'autoRefresh', 60);
    $refresh = 60 if ($refresh !~ /^\d+$/ || $refresh > 3600);
    my $html = <<'HTML';
<style>
.tc-dashboard{font:14px 'Avenir Next','Helvetica Neue',sans-serif;color:#f4f4e9;background:#1d2825;line-height:1.4;width:100%;max-width:1120px;margin:0 auto;border:1px solid #46544c;box-shadow:0 16px 44px #0c16124a;overflow:hidden}
.tc-header{position:relative;display:flex!important;flex-direction:row!important;flex-wrap:nowrap!important;justify-content:space-between;align-items:center;gap:12px;box-sizing:border-box;height:76px;margin:0;padding:0 24px;background:#202e29;border-bottom:1px solid #405149}
.tc-header-actions{display:flex!important;flex:0 0 auto;margin-left:auto;align-items:center;gap:8px}.tc-edit{width:40px;height:40px;padding:0;border:0;border-radius:0;background:none;color:#f4f4e9;cursor:pointer;font:600 28px 'Helvetica Neue',sans-serif;line-height:1}.tc-edit:hover{color:#9ce2bb}.tc-save{display:none;padding:8px 12px;border:1px solid #52bd8b;border-radius:0;background:#26342d;color:#f4f4e9;cursor:pointer;font:600 12px 'Helvetica Neue',sans-serif}.tc-save:hover{background:#34463c}.tc-reorder-mode .tc-save{display:inline-block}
.tc-clock{position:absolute;left:56%;transform:translateX(-50%);display:flex;align-items:center;gap:8px;color:#c9d8cd}.tc-clock-face{width:44px;height:44px}.tc-clock-face circle{fill:#1d2825;stroke:#52bd8b;stroke-width:1.5}.tc-clock-face line{stroke:#a9b7ac;stroke-width:1}.tc-clock-face .tc-tick-major{stroke:#f4f4e9;stroke-width:1.8}.tc-clock-face .tc-hand-hour{stroke:#f4f4e9;stroke-width:2}.tc-clock-face .tc-hand-minute{stroke:#52bd8b;stroke-width:1.5}.tc-clock-face .tc-hand-second{stroke:#e07b65;stroke-width:1}.tc-clock-date{font-size:11px;white-space:nowrap;color:#a9b7ac}
.tc-brand{display:flex;align-items:center;gap:12px;margin-right:auto;min-width:0}.tc-brand-mark{display:grid;place-items:center;width:39px;height:39px;flex:0 0 39px;border:2px solid #52bd8b;border-radius:50%;background:transparent;color:#52bd8b}.tc-brand-mark svg{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.tc-brand small{display:block;color:#a9b7ac;font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px}.tc-brand h1{margin:3px 0;font:500 22px Georgia,serif;letter-spacing:0;line-height:1.1}
.tc-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:10px;padding:22px 24px 24px;background:linear-gradient(155deg,#26352e,#1b2823 62%,#202c27)}
.tc-card{border:0;border-top:1px solid #46544c;border-radius:0;background:#26342d;overflow:hidden;box-shadow:none;padding:0 15px 0}
.tc-card summary{cursor:pointer;list-style:none;padding:14px 0;display:flex;justify-content:space-between;gap:12px}
.tc-card summary::-webkit-details-marker{display:none}
.tc-name{font-weight:600}.tc-type,.tc-meta,.tc-muted{color:#a9b7ac;font-size:12px}
.tc-value{display:flex;flex-direction:column;align-items:flex-end;gap:2px;font-size:22px;font-weight:600;white-space:nowrap;color:#edf0e6}.tc-temperature{font-size:22px}.tc-humidity{font-size:13px;color:#8ab6d1}
.tc-detail{border-top:1px solid #46534a;padding:12px 0}.tc-chart-wrap{overflow-x:auto;position:relative}.tc-tip{position:absolute;pointer-events:none;background:#101a16;color:#f4f4e9;border:1px solid #52bd8b;padding:3px 7px;font-size:12px;white-space:nowrap;z-index:5}.tc-tip[hidden]{display:none}.tc-tip-time{display:block;font-size:10px;color:#a9b7ac;margin-top:1px}.tc-dot{pointer-events:none}.tc-chart-title{display:flex;justify-content:space-between;align-items:center;gap:8px;color:#a9b7ac;font-size:12px;margin-bottom:4px}.tc-chart-controls{display:flex;gap:3px}.tc-chart-controls button{border:1px solid #52bd8b;border-radius:0;background:#26342d;color:#f4f4e9;cursor:pointer;min-width:24px;height:24px;font:600 12px 'Helvetica Neue',sans-serif}.tc-chart{display:block;width:100%;min-width:560px;height:190px;background:#202e29}
.tc-range{background:#26342d;color:#f4f4e9;border:1px solid #52bd8b;border-radius:0;font-size:12px;height:24px}.tc-axis-humidity{fill:#8ab6d1!important}.tc-axis{stroke:#69796f;stroke-width:1}.tc-axis-label,.tc-axis-value{fill:#a9b7ac;font-size:10px}.tc-history-toggle{border:1px solid #52bd8b;border-radius:0;background:#26342d;color:#f4f4e9;cursor:pointer;font-size:18px;height:28px;width:28px;line-height:20px;margin-top:12px}.tc-history-panel[hidden]{display:none}
.tc-chart path{fill:none;stroke:#52bd8b;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;vector-effect:non-scaling-stroke}.tc-chart .tc-series-humidity path{stroke:#8ab6d1}.tc-span{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin:4px 0;font-size:12px;color:#a9b7ac}.tc-span[hidden]{display:none}.tc-span input{background:#26342d;color:#f4f4e9;border:1px solid #52bd8b;border-radius:0;font-size:12px;height:24px;color-scheme:dark}.tc-span button{border:1px solid #52bd8b;border-radius:0;background:#26342d;color:#f4f4e9;cursor:pointer;height:26px;font-size:12px}.tc-series-hidden{display:none}.tc-legend{display:flex;gap:14px;flex-wrap:wrap;margin-top:6px}.tc-legend-item{border:0;background:transparent;color:#a9b7ac;cursor:pointer;padding:0;font:inherit;font-size:12px}.tc-legend-item.tc-legend-hidden{opacity:.45;text-decoration:line-through}.tc-legend-item i{display:inline-block;width:8px;height:8px;border-radius:50%;background:#52bd8b;margin-right:5px}.tc-legend-item .tc-legend-humidity{background:#8ab6d1}
.tc-history{border-collapse:collapse;width:100%;margin-top:12px;font-size:12px}.tc-history th,.tc-history td{padding:4px 6px;border-bottom:1px solid #46534a;text-align:left}
.tc-error{padding:12px;border:1px solid #a45b5b;background:#321f1f;color:#ffd9d9}
.tc-reorder-mode .tc-card{cursor:move;outline:1px dashed #52bd8b;outline-offset:3px}.tc-reorder-mode .tc-card summary{pointer-events:none}.tc-card.tc-dragging{opacity:.45}
.tc-list-view .tc-grid{grid-template-columns:1fr}.tc-list-view .tc-card summary{align-items:center}
@media(max-width:760px){.tc-header{padding:0 15px}.tc-grid{padding:16px 15px}}
@media(max-width:640px){.tc-clock{display:none}}
</style>
<div class="tc-dashboard">
HTML
    # Host pages such as FTUI style form controls globally; pin the dashboard's own look
    $html =~ s{</style>\n<div class="tc-dashboard">\n\z}{@{[TemperatureCollector_EmbedCss()]}</style>\n<div class="tc-dashboard">\n} if ($options->{embed});
    $html .= '<div class="tc-header"><div class="tc-brand">'
        . '<span class="tc-brand-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M10 14.7V5a2.5 2.5 0 0 1 5 0v9.7a5 5 0 1 1-5 0Z"/><path d="M12.5 8v9"/><circle cx="12.5" cy="18" r="1.4"/><path d="M17 6h2m-2 3h2"/></svg></span><div><small>FHEM / TEMPERATURE COLLECTOR</small>'
        . '<h1>Temperaturübersicht</h1></div></div>'
        . ($options->{embed} ? '' : (
            '<div class="tc-clock" aria-label="Aktuelle Uhrzeit und Datum">'
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
        ))
        . '<div class="tc-header-actions">'
        . '<button type="button" class="tc-edit" title="Listenansicht/Kachelansicht wechseln" aria-label="Listenansicht/Kachelansicht wechseln"'
        . ' onclick="tcToggleView(this)">☷</button>'
        . ($options->{editable}
            ? '<button type="button" class="tc-edit tc-reorder-edit" title="Sensorreihenfolge bearbeiten" aria-label="Sensorreihenfolge bearbeiten"'
                . ' onclick="tcToggleEdit(this)">✎</button>'
                . '<button type="button" class="tc-save" onclick="tcSaveClick()">💾 Speichern</button>'
            : '')
        . '</div></div><div class="tc-grid">';

    if (!@{$devices}) {
        return $html . '<div class="tc-error">Keine numerischen Temperatur-Readings gefunden.</div></div></div>';
    }

    my $index = 0;
    for my $device (@{$devices}) {
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
            . '<div class="tc-detail"><div class="tc-slot"><p class="tc-muted">Lade Verlauf …</p></div>'
            . '<p class="tc-meta">Aktualisiert: '
            . TemperatureCollector_Escape(TemperatureCollector_GermanTime($device->{temperatureTimestamp})) . '</p></div></details>';
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
        . ($options->{embed} ? 'window.tcCurrentUrl=su+"?tcEmbed=1";' : '')
        . 'window.tcApplyOrder=function(root){};'
        . 'window.tcApplyView=function(root){var list=localStorage.getItem(vk)==="list";root.classList.toggle("tc-list-view",list);'
        . 'var button=root.querySelector(".tc-header-actions .tc-edit");if(button)button.textContent=list?"▦":"☷";};'
        . 'window.tcToggleView=function(button){var list=d.classList.toggle("tc-list-view");'
        . 'localStorage.setItem(vk,list?"list":"grid");button.textContent=list?"▦":"☷";};'
        . 'window.tcApplyEdit=function(root){var active=localStorage.getItem(ek)==="1";root.classList.toggle("tc-reorder-mode",active);'
        . 'var button=root.querySelector(".tc-reorder-edit");if(!button){root.classList.remove("tc-reorder-mode");'
        . 'root.querySelectorAll(".tc-card").forEach(function(card){card.draggable=false;});return;}'
        . 'root.querySelectorAll(".tc-card").forEach(function(card){card.draggable=active;});};'
        . 'window.tcOrder=function(){return Array.prototype.map.call(d.querySelectorAll(".tc-card"),function(c){return c.getAttribute("data-device");}).join("|");};'
        . 'window.tcTake=function(){var cards=Array.prototype.slice.call(d.querySelectorAll(".tc-card"));'
        . 'window.tcSnap={sig:tcOrder(),cards:cards,parent:cards.length?cards[0].parentNode:null,anchor:cards.length?cards[cards.length-1].nextSibling:null};};'
        . 'window.tcRestore=function(){var s=window.tcSnap;if(!s||!s.parent)return;s.cards.forEach(function(c){s.parent.insertBefore(c,s.anchor);});};'
        . 'window.tcAsk=function(onDiscard,onSave){var o=document.createElement(\'div\');o.style.cssText=\'position:fixed;top:0;right:0;bottom:0;left:0;background:rgba(0,0,0,.6);z-index:99999;display:flex;align-items:center;justify-content:center\';var b=document.createElement(\'div\');b.style.cssText=\'background:#1d2825;color:#f4f4e9;border:1px solid #46544c;padding:20px 24px;font:14px sans-serif;max-width:360px\';var p=document.createElement(\'p\');p.style.cssText=\'margin:0 0 16px\';p.textContent=\'\\u00c4nderungen verwerfen?\';b.appendChild(p);function mk(t,fn){var x=document.createElement(\'button\');x.type=\'button\';x.textContent=t;x.style.cssText=\'margin:0 8px 0 0;padding:8px 12px;border:1px solid #52bd8b;background:#26342d;color:#f4f4e9;cursor:pointer;font:600 12px sans-serif\';x.onclick=function(){o.remove();if(fn)fn();};b.appendChild(x);}mk(\'OK\',onDiscard);mk(\'Abbrechen\',null);mk(\'\\u00c4nderungen speichern\',onSave);o.appendChild(b);document.body.appendChild(o);};'
        . 'window.tcToggleEdit=function(button){var s=window.tcSnap;'
        . 'if(d.classList.contains("tc-reorder-mode")&&s&&tcOrder()!==s.sig){tcAsk(function(){tcRestore();tcFlip(button);},function(){tcSaveClick();});return;}'
        . 'tcFlip(button);};'
        . 'window.tcFlip=function(button){'
        . 'var active=d.classList.toggle("tc-reorder-mode");'
        . 'localStorage.setItem(ek,active?"1":"0");button.setAttribute("aria-pressed",active?"true":"false");'
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
        . '});};'
        . 'window.tcSaveOrder=function(){if(!d.querySelector(".tc-reorder-edit"))return Promise.resolve(false);'
        . 'var order=Array.prototype.map.call(d.querySelectorAll(".tc-card"),function(c){return c.getAttribute("data-device");});'
        . 'var json=JSON.stringify(order),b64=btoa(unescape(encodeURIComponent(json)));'
        . 'return fetch(su+"?tcSaveOrder="+encodeURIComponent(b64),{credentials:"same-origin"}).then(function(response){'
        . 'return response.text().then(function(text){if(!response.ok||text.indexOf("gespeichert")<0)throw new Error(text||"Speichern fehlgeschlagen");});'
        . '}).catch(function(){return fetch(cp+"?cmd=set%20"+encodeURIComponent(cn)+"%20saveOrder%20"+encodeURIComponent(b64)+"&XHR=1",'
        . '{credentials:"same-origin"}).then(function(response){return response.text();}).then(function(text){'
        . 'if(text.indexOf("gespeichert")<0)throw new Error(text||"Speichern fehlgeschlagen");});'
        . '}).then(function(){return true;},function(error){if(window.console)console.error("TemperatureCollector: "+error.message);return false;});};'
        . 'window.tcSaveClick=function(){tcSaveOrder().then(function(ok){if(!ok)return;tcTake();d.classList.remove("tc-reorder-mode");localStorage.setItem(ek,"0");'
        . 'd.querySelectorAll(".tc-card").forEach(function(card){card.draggable=false;});});};'
        . 'tcTake();tcBindReorder(d);tcApplyOrder(d);tcApplyView(d);tcApplyEdit(d);'
        . 'window.tcDetailLoad=function(card){var slot=card.querySelector(".tc-slot");if(!slot)return;'
        . 'var u=new URL(su,window.location.href),st=card.tcState||{};'
        . 'Object.keys(st).forEach(function(n){if(st[n]!==undefined&&st[n]!=="")u.searchParams.set(n,st[n]);});'
        . 'u.searchParams.set("tcDetail",card.getAttribute("data-device"));'
        . 'var wasOpen=!!slot.querySelector(".tc-history-panel:not([hidden])");'
        . 'fetch(u.href,{cache:"no-store",credentials:"same-origin"}).then(function(x){return x.text();}).then(function(t){'
        . 'if(!card.open)return;slot.innerHTML=t;if(wasOpen){var np=slot.querySelector(".tc-history-panel"),nb=slot.querySelector(".tc-history-toggle");'
        . 'if(np){np.hidden=false;if(nb){nb.textContent="−";nb.setAttribute("aria-expanded","true");}}}}).catch(function(){});};'
        . 'window.tcHover=function(e){var svg=e.target.closest&&e.target.closest("svg.tc-chart");if(!svg)return;'
        . 'var wrap=svg.closest(".tc-chart-wrap"),tip=wrap.querySelector(".tc-tip"),dot=svg.querySelector(".tc-dot");'
        . 'var m=svg.getScreenCTM();if(!m)return;var pt=svg.createSVGPoint();pt.x=e.clientX;pt.y=e.clientY;pt=pt.matrixTransform(m.inverse());'
        . 'var best=null;svg.querySelectorAll("g[data-pts]").forEach(function(g){if(g.classList.contains("tc-series-hidden"))return;'
        . '(g.getAttribute("data-pts")||"").split(";").forEach(function(r){var a=r.split(",");if(a.length<4)return;'
        . 'var dx=Math.abs(pt.x-parseFloat(a[0])),dy=Math.abs(pt.y-parseFloat(a[1]));'
        . 'if(dy<=14&&(!best||dx<best.dx||(dx===best.dx&&dy<best.dy)))best={dx:dx,dy:dy,x:parseFloat(a[0]),y:parseFloat(a[1]),v:a[2],t:a.slice(3).join(","),u:g.getAttribute("data-unit")};});});'
        . 'if(!best||best.dx>12){tip.hidden=true;if(dot)dot.setAttribute("r","0");return;}'
        . 'if(!dot){dot=document.createElementNS("http://www.w3.org/2000/svg","circle");dot.setAttribute("class","tc-dot");dot.setAttribute("fill","#f4f4e9");svg.appendChild(dot);}'
        . 'dot.setAttribute("cx",best.x);dot.setAttribute("cy",best.y);dot.setAttribute("r","3");'
        . 'tip.textContent="";var tv=document.createElement("div");tv.textContent=parseFloat(best.v).toFixed(1)+" "+best.u;tip.appendChild(tv);var td=document.createElement("small");td.className="tc-tip-time";td.textContent=best.t.replace(/_/g," ").replace(/^(\\d{4})-(\\d{2})-(\\d{2})/,"$3.$2.$1").replace(/(\\d{2}:\\d{2}):\\d{2}/,"$1");tip.appendChild(td);tip.hidden=false;'
        . 'var wr=wrap.getBoundingClientRect(),sx=best.x*m.a+m.e-wr.left+wrap.scrollLeft,sy=best.y*m.d+m.f-wr.top;'
        . 'tip.style.left=Math.max(0,sx-tip.offsetWidth/2)+"px";tip.style.top=Math.max(0,sy-tip.offsetHeight-10)+"px";};'
        . 'window.tcBindDetails=function(root){root.addEventListener("mousemove",tcHover);root.addEventListener("mouseleave",function(){root.querySelectorAll(".tc-tip").forEach(function(t){t.hidden=true;});});root.addEventListener("toggle",function(e){var card=e.target;'
        . 'if(card.matches&&card.matches("details[data-device]")&&card.open)tcDetailLoad(card);},true);};'
        . 'window.tcReloadOpen=function(){d.querySelectorAll("details[data-device][open]").forEach(tcDetailLoad);};'
        . 'tcBindDetails(d);'
        . 'window.tcDashboardLoad=function(url){window.tcCurrentUrl=url;var o={};'
        . 'd.querySelectorAll("details[data-device][open]").forEach(function(e){o[e.getAttribute("data-device")]={html:e.querySelector(".tc-slot").innerHTML,st:e.tcState};});'
        . 'fetch(url,{cache:"no-store",credentials:"same-origin"}).then(function(x){return x.text();}).then(function(t){'
        . 'var n=new DOMParser().parseFromString(t,"text/html").querySelector(".tc-dashboard");if(!n)return;tcApplyOrder(n);tcApplyView(n);tcApplyEdit(n);tcBindReorder(n);tcBindDetails(n);'
        . 'n.querySelectorAll("details[data-device]").forEach(function(e){var name=e.getAttribute("data-device");'
        . 'if(o[name]){e.querySelector(".tc-slot").innerHTML=o[name].html;e.tcState=o[name].st;e.open=true;}});'
        . 'd.replaceWith(n);d=n;tcReloadOpen();}).catch(function(){});};'
        . 'window.tcState=function(el){var card=el.closest("details[data-device]");if(!card.tcState)card.tcState={};return card;};'
        . 'window.tcShift=function(button,direction){var card=tcState(button),w=button.closest("[data-hours]"),h=parseFloat(w.getAttribute("data-hours"))||24;'
        . 'var o=parseInt(card.tcState.tcOffset||"0",10)||0;card.tcState.tcOffset=Math.round(o+direction*h);'
        . 'if(card.tcState.tcRange!=="span"&&card.tcState.tcOffset<0)card.tcState.tcOffset=0;tcDetailLoad(card);};'
        . 'window.tcRange=function(sel){var card=tcState(sel);'
        . 'if(sel.value==="span"){var row=card.querySelector(".tc-span");if(row)row.hidden=false;return;}'
        . 'card.tcState={tcRange:sel.value};tcDetailLoad(card);};'
        . 'window.tcSpan=function(button){var card=tcState(button),row=button.closest(".tc-span"),f=row.querySelector(".tc-from").value,t=row.querySelector(".tc-to").value;'
        . 'if(!f||!t||t<=f){alert("Bitte einen gültigen Zeitraum (von < bis) wählen.");return;}'
        . 'card.tcState={tcRange:"span",tcFrom:f,tcTo:t};tcDetailLoad(card);};'
        . 'window.tcZoom=function(button,direction){var card=tcState(button),w=button.closest("[data-step]"),c=parseInt(w.getAttribute("data-step"),10)||30;'
        . 'var s=[5,10,15,30,60,120,240,480,1440],i=s.indexOf(c);if(i<0)i=3;i=Math.max(0,Math.min(s.length-1,i+direction));'
        . 'card.tcState.tcStep=s[i];tcDetailLoad(card);};})();</script>';
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
        step => TemperatureCollector_QueryValue($request, 'tcStep', undef),
        range => TemperatureCollector_QueryValue($request, 'tcRange', undef),
        from => TemperatureCollector_QueryValue($request, 'tcFrom', undef),
        to => TemperatureCollector_QueryValue($request, 'tcTo', undef),
    };
    my $detail = TemperatureCollector_QueryValue($request, 'tcDetail', undef);
    if (defined($detail)) {
        my $devices = TemperatureCollector_ApplyOrder($name,
            TemperatureCollector_Discover($name));
        for my $index (0 .. $#{$devices}) {
            next if ($devices->[$index]{name} ne $detail);
            return ('text/html; charset=utf-8',
                TemperatureCollector_DetailHtml($hash, $devices->[$index], $index, $options));
        }
        return ('text/plain; charset=utf-8', 'Unknown sensor');
    }
    # Fragment for embedding (e.g. FTUI): no html/head/body, base URL independent of the host page
    if (TemperatureCollector_QueryValue($request, 'tcEmbed', 0) || TemperatureCollector_QueryValue($request, 'embed', 0)) {
        $options->{embed} = 1;
        return ('text/html; charset=utf-8', TemperatureCollector_BuildDashboard($hash, $options));
    }
    my $html = TemperatureCollector_BuildDashboard($hash, $options);
    return ('text/html; charset=utf-8', '<!doctype html><html lang="de"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>TemperatureCollector - ' . TemperatureCollector_Escape($name)
        . '</title></head><body style="margin:0;padding:12px;background:#151f1b">'
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
    <li><code>get &lt;name&gt; _dashboardEmbedURL</code> - relative URL des Dashboard-Fragments ohne html/head/body, z.B. für FTUI</li>
</ul>
<p>
    Der Editierstift für die Sensorreihenfolge wird nur bei
    <code>_showDashboard</code> angezeigt. In der isolierten URL-Ansicht bleibt
    nur der Umschalter zwischen Listen- und Kachelansicht verfügbar.
</p>

<b>Attributes</b>
<ul>
    <li><code>dbLog &lt;name&gt;</code> - optionales DbLog-Gerät; ohne Angabe wird das erste DbLog-Gerät verwendet</li>
    <li><code>fileLog &lt;name&gt;</code> - optionales FileLog-Gerät für die Historie; ohne Angabe wird das erste FileLog verwendet, dessen Regexp zu einem Temperatur-Reading passt</li>
    <li><code>historySource auto|dblog|filelog</code> - Quelle der Historie; <code>auto</code> bevorzugt DbLog und fällt auf FileLog zurück, Standard: auto</li>
    <li><code>historyHours &lt;1..8760&gt;</code> - Zeitraum der Historie, Standard: 24</li>
    <li><code>autoRefresh 0|15|30|60|300</code> - Aktualisierung ohne vollständigen Seiten-Reload in Sekunden, Standard: 60</li>
    <li><code>showHistoryTable 0|1</code> - Plus-Schalter für die Messwerttabelle aktivieren, Standard: 0</li>
    <li><code>showReadingName 0|1</code> - Reading-Namen unter dem Alias anzeigen, Standard: 1</li>
    <li><code>includeDevices &lt;name,...&gt;</code> - optional ausschließlich diese Geräte anzeigen</li>
    <li><code>excludeDevices &lt;name,...&gt;</code> - diese Geräte aus der Erkennung ausschließen</li>
</ul>

<b>FileLog</b>
<p>
    Wird im Dateisystem statt in einer Datenbank geloggt, liest das Modul die
    Logdateien des FileLog-Geräts direkt aus. Erwartet werden Zeilen im
    Standardformat <code>2024-01-01_12:00:00 Geraet reading: wert</code>
    (FileLog-Regexp z.B. <code>Geraet:temperature:.*</code>). Der Rest
    (Diagramm, Navigation, Tabelle) verhält sich wie bei DbLog.
</p>

<b>DbLog</b>
<p>
    Wenn ein DbLog-Gerät vorhanden ist, fragt das Modul die historische
    Temperatur über die FHEM-interne DbLog-Schnittstelle ab. Ohne DbLog und FileLog werden
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

<a name="TemperatureCollectorFeedback"></a>
<b>Feedback</b>
<ul>
    Fragen, Fehlermeldungen und Ideen: <a href="https://github.com/stapetz/fhem-modules/issues/new/choose">GitHub-Issues</a>.
    Issues sind &ouml;ffentlich, bitte keine Passw&ouml;rter, Tokens oder Adressen posten.
</ul>

=end html
=cut
