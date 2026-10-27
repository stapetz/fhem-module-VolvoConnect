package main;

use strict;
use warnings;
use utf8;
use HttpUtils;
use JSON;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(sha256);

# PKCE-Verifier zum testen
my $GLOBAL_VERIFIER = "fhem_volvo_connect_secure_code_verifier_long_string_77_characters";

# Dummy-Werte nur als Platzhalter
my $DUMMY_VIN       = "HIER_VIN_EINTRAGEN";
my $DUMMY_CLIENT_ID = "HIER_CLIENT_ID_EINTRAGEN";
my $DUMMY_SECRET    = "HIER_CLIENT_SECRET_EINTRAGEN";
my $DUMMY_VCC_KEY   = "HIER_VCC_API_KEY_EINTRAGEN";
my $DUMMY_REDIRECT  = "http://localhost";

sub VolvoConnect_TokenKey($) {
    my ($hash) = @_;
    return "VolvoConnect_v2_" . $hash->{NAME};
}

sub VolvoConnect_DashboardConfigKey($) {
    my ($name) = @_;
    return "VolvoConnect_dashboard_" . $name;
}

sub VolvoConnect_EndpointFetchTimesKey($) {
    my ($name) = @_;
    return "VolvoConnect_fetchTimes_" . $name;
}

sub VolvoConnect_LoadEndpointFetchTimes($) {
    my ($hash) = @_;
    return $hash->{helper}{endpointFetchTimes}
        if (ref($hash->{helper}{endpointFetchTimes}) eq "HASH");

    my ($err, $value) = getKeyValue(VolvoConnect_EndpointFetchTimesKey($hash->{NAME}));
    my $times = (!$err && defined($value) && $value ne "")
        ? eval { decode_json($value) } : {};
    $times = {} if (ref($times) ne "HASH");
    $hash->{helper}{endpointFetchTimes} = $times;
    return $times;
}

sub VolvoConnect_MarkEndpointFetched($$) {
    my ($hash, $endpoint) = @_;
    my $times = VolvoConnect_LoadEndpointFetchTimes($hash);
    $times->{$endpoint} = time();
    my $err = setKeyValue(
        VolvoConnect_EndpointFetchTimesKey($hash->{NAME}),
        encode_json($times)
    );
    Log3 $hash->{NAME}, 2, "VolvoConnect ($hash->{NAME}) - Could not store fetch time for $endpoint: $err"
        if (defined($err) && $err ne "");
}

sub VolvoConnect_ClearEndpointFetchTimes($) {
    my ($hash) = @_;
    delete $hash->{helper}{endpointFetchTimes};
    setKeyValue(VolvoConnect_EndpointFetchTimesKey($hash->{NAME}), undef);
}

sub VolvoConnect_LoadDashboardConfig($) {
    my ($name) = @_;
    my ($err, $value) = getKeyValue(VolvoConnect_DashboardConfigKey($name));
    return {} if ($err || !defined($value) || $value eq "");
    my $config = eval { decode_json($value) };
    return (ref($config) eq "HASH") ? $config : {};
}

sub VolvoConnect_SaveDashboardConfig($$) {
    my ($name, $json) = @_;
    my $decoded = eval { decode_json($json) };
    return "Ungueltiges JSON: $@" if (!$decoded || ref($decoded) ne "HASH");
    my $err = setKeyValue(VolvoConnect_DashboardConfigKey($name), $json);
    return "Fehler beim Speichern: $err" if (defined($err) && $err ne "");
    return undef;
}

sub VolvoConnect_SetAuthStatus($$);

sub VolvoConnect_LoadTokensFromKey($$) {
    my ($hash, $key) = @_;
    my ($err, $value) = getKeyValue($key);
    return if ($err || !defined($value) || $value eq "");

    my $tokens = eval { decode_json($value) };
    return if (!$tokens || ref($tokens) ne "HASH");

    $hash->{helper}{accessToken} = $tokens->{accessToken}
        if (defined($tokens->{accessToken}));
    $hash->{helper}{refreshToken} = $tokens->{refreshToken}
        if (defined($tokens->{refreshToken}));
    $hash->{helper}{tokenValidUntil} = $tokens->{tokenValidUntil}
        if (defined($tokens->{tokenValidUntil}));
    my $hasAccessToken = defined($hash->{helper}{accessToken})
        && $hash->{helper}{accessToken} ne "";
    my $hasRefreshToken = defined($hash->{helper}{refreshToken})
        && $hash->{helper}{refreshToken} ne "";
    Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - Stored token data loaded "
        . "(access token: " . ($hasAccessToken ? "yes" : "no")
        . ", refresh token: " . ($hasRefreshToken ? "yes" : "no") . ").";
        VolvoConnect_SetAuthStatus($hash, "authenticated")
            if ($hasAccessToken || $hasRefreshToken);
    return 1;
}

sub VolvoConnect_LoadTokens($) {
    my ($hash) = @_;
    my $currentKey = VolvoConnect_TokenKey($hash);
    return if (VolvoConnect_LoadTokensFromKey($hash, $currentKey));

    my $legacyKey = "VolvoConnect_" . $hash->{NAME};
    if (VolvoConnect_LoadTokensFromKey($hash, $legacyKey)) {
        VolvoConnect_SaveTokens($hash);
        return;
    }

    Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - No stored token found.";
}

sub VolvoConnect_RestoreState($) {
    my ($hash) = @_;
    return if (!defined($hash->{helper}{accessToken})
        && !defined($hash->{helper}{refreshToken}));

    my $state = defined($hash->{helper}{accessToken})
        && $hash->{helper}{accessToken} ne ""
        && ($hash->{helper}{tokenValidUntil} || 0) > time()
        ? "authenticated"
        : "token_refreshing";
    VolvoConnect_SetAuthStatus($hash, $state);
}

sub VolvoConnect_StateIcon($) {
    my ($name) = @_;
    my $state = ReadingsVal($name, "state", "");

    if ($state eq "auth_required") {
        my $hash = $defs{$name};
        my $loginUrl = $hash ? $hash->{helper}{loginUrl} : undef;
        if (defined($loginUrl) && $loginUrl ne "") {
            return '<a href="' . VolvoConnect_HtmlEscape($loginUrl)
                . '" target="_blank" rel="noopener noreferrer" style="'
                . 'display:inline-block; padding:2px 8px; '
                . 'background-color:#2e5e87; color:white; text-decoration:none; '
                . 'border-radius:4px; font-size:0.85em;">'
                . 'Bei Volvo anmelden / Auth-Code anfordern</a>';
        }
    }

    my %iconMap = (
        authenticated    => "10px-kreis-gruen",
        auth_required    => "10px-kreis-gelb",
        token_refreshing => "10px-kreis-gelb",
        disabled         => "10px-kreis-rot",
        error            => "10px-kreis-rot",
    );
    my $icon = $iconMap{$state} // "10px-kreis-grau";
    return "<span title=\"$state\">" . FW_makeImage($icon) . "</span>";
}

sub VolvoConnect_SetAuthStatus($$) {
    my ($hash, $status) = @_;
    $hash->{helper}{authStatus} = $status;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "authStatus", $status);
    readingsBulkUpdate($hash, "state", $status);
    readingsEndUpdate($hash, 1);
    Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - authStatus set to '$status'.";
}

sub VolvoConnect_CheckAuthAndFetch($);

sub VolvoConnect_StartupCheck($) {
    my ($hash) = @_;
    if (!$main::init_done) {
        Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - Startup delayed: init_done not set.";
        InternalTimer(time() + 5, "VolvoConnect_StartupCheck", $hash, 0);
        return;
    }

    Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - Startup check started "
        . "(init_done=$main::init_done, saved authStatus="
        . (ReadingsVal($hash->{NAME}, "authStatus", "missing")) . ").";
    VolvoConnect_LoadTokens($hash);
    readingsDelete($hash, "authStatus");
    VolvoConnect_RestoreState($hash);
    VolvoConnect_ForceAuthStatus($hash);
    Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - Startup status after restore: "
        . ($hash->{helper}{authStatus} // "missing") . ".";
    InternalTimer(time() + 1, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
}

sub VolvoConnect_ForceAuthStatus($) {
    my ($hash) = @_;
    if (defined($hash->{helper}{accessToken})
        && $hash->{helper}{accessToken} ne ""
        && ($hash->{helper}{tokenValidUntil} || 0) > time()) {
        VolvoConnect_SetAuthStatus($hash, "authenticated");
    } elsif (defined($hash->{helper}{refreshToken}) && $hash->{helper}{refreshToken} ne "") {
        VolvoConnect_SetAuthStatus($hash, "token_refreshing");
    }
}

sub VolvoConnect_SaveTokens($) {
    my ($hash) = @_;
    my $tokens = {
        accessToken     => $hash->{helper}{accessToken},
        refreshToken    => $hash->{helper}{refreshToken},
        tokenValidUntil => $hash->{helper}{tokenValidUntil}
    };
    my $err = setKeyValue(VolvoConnect_TokenKey($hash), encode_json($tokens));
    if (defined($err) && $err ne "") {
        Log3 $hash->{NAME}, 2, "VolvoConnect ($hash->{NAME}) - Could not store token data: $err";
        return;
    }

    my ($readErr, $storedValue) = getKeyValue(VolvoConnect_TokenKey($hash));
    if ($readErr || !defined($storedValue) || $storedValue eq "") {
        Log3 $hash->{NAME}, 2, "VolvoConnect ($hash->{NAME}) - Stored token data could not be verified.";
    } else {
        my $hasRefreshToken = defined($hash->{helper}{refreshToken})
            && $hash->{helper}{refreshToken} ne "";
        Log3 $hash->{NAME}, 4, "VolvoConnect ($hash->{NAME}) - Token data stored successfully "
            . "(refresh token: " . ($hasRefreshToken ? "yes" : "no") . ").";
    }
}

sub VolvoConnect_ClearTokens($) {
    my ($hash) = @_;
    delete $hash->{helper}{accessToken};
    delete $hash->{helper}{refreshToken};
    delete $hash->{helper}{tokenValidUntil};
    delete $hash->{helper}{loginUrl};
    delete $hash->{helper}{authCodeProcessing};
    delete $hash->{helper}{pendingCommand};
    delete $hash->{helper}{tokenRefreshInFlight};
    setKeyValue(VolvoConnect_TokenKey($hash), undef);
    setKeyValue("VolvoConnect_" . $hash->{NAME}, undef);
    VolvoConnect_ClearAuthCode($hash);
}

sub VolvoConnect_ClearAuthCode($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    delete $attr{$name}{authCode};
    CommandAttr(undef, "del $name authCode") if (defined($defs{$name}));
}

sub VolvoConnect_ScopeEnabled($$) {
    my ($name, $scopeAttribute) = @_;
    my $value = AttrVal($name, $scopeAttribute, "0");
    return 0 if ($value =~ /^0(?:-|\s|$)/i || $value =~ /deaktiviert|inaktiv|nein/i);
    return 1 if ($value =~ /^1(?:-|\s|$)/i || $value =~ /^(?:aktiviert|aktiv|ja)$/i);
    return 0;
}

sub VolvoConnect_ScopeDefinitions() {
    return [
        {
            title => "Fahrzeugdaten",
            scopes => [
                ["scope_capabilities", "Fahrzeugfunktionen", "Verfügbare Funktionen und Ausstattungsmerkmale des Fahrzeugs."],
                ["scope_warnings", "Warnungen", "Fahrzeugwarnungen und zugehörige Statusmeldungen."],
                ["scope_brakes", "Bremsen", "Bremsstatus und zugehörige Fahrzeugdaten."],
                ["scope_doors", "Türen und Fenster", "Tür-, Verriegelungs- und Fensterstatus."],
                ["scope_windows", "Fensterstatus", "Status der Fahrzeugfenster."],
                ["scope_engine_status", "Motorstatus", "Aktueller Status des Fahrzeugmotors."],
                ["scope_vehicle_relation", "Fahrzeugzuordnung", "Zuordnung des Fahrzeugs zum Volvo-ID-Konto."],
            ],
        },
        {
            title => "Energie, Fahrten und Diagnose",
            scopes => [
                ["scope_fuel", "Kraftstoff", "Kraftstoffstand und Kraftstoffstatus."],
                ["scope_battery_charge", "Batterieladung", "Ladezustand der Hochvoltbatterie."],
                ["scope_odometer", "Kilometerstand", "Kilometerstand des Fahrzeugs."],
                ["scope_statistics", "Fahrtstatistik", "Fahrten- und Verbrauchsstatistiken."],
                ["scope_tyres", "Reifen", "Reifenstatus und verfügbare Reifendaten."],
                ["scope_location", "Standort", "Standortdaten des Fahrzeugs."],
                ["scope_engine_diagnostics", "Motordiagnose", "Diagnosedaten des Motors."],
                ["scope_workshop_diagnostics", "Werkstattdiagnose", "Diagnose- und Werkstattinformationen."],
            ],
        },
        {
            title => "Fahrzeugbefehle",
            scopes => [
                ["scope_commands", "Befehle", "Allgemeine Berechtigung zum Abrufen verfügbarer Fahrzeugbefehle."],
                ["scope_command_accessibility", "Befehlsverfügbarkeit", "Prüft, ob einzelne Fahrzeugbefehle aktuell verfügbar sind."],
                ["scope_honk_flash", "Hupe und Lichtsignal", "Berechtigung zum Hupen und Auslösen des Lichtsignals."],
                ["scope_lock", "Verriegeln", "Berechtigung zum Verriegeln des Fahrzeugs."],
                ["scope_unlock", "Entriegeln", "Berechtigung zum Entriegeln des Fahrzeugs."],
                ["scope_climatization", "Klimatisierung", "Berechtigung zum Starten und Stoppen der Klimatisierung."],
                ["scope_engine_commands", "Motorbefehle", "Berechtigung für Motorstart- und Vorkonditionierungsbefehle."],
            ],
        },
    ];
}

sub VolvoConnect_BuildEntityConfig($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $basePath = defined($main::FW_ME) && $main::FW_ME ne "" ? $main::FW_ME : "/fhem";
    $basePath =~ s{/$}{};
    $basePath = "/fhem" if ($basePath eq "");
    my $device = VolvoConnect_HtmlEscape($name);
    my $base = VolvoConnect_HtmlEscape($basePath);
    my $csrf = VolvoConnect_HtmlEscape($main::FW_CSRF // "");
    my $configNote = VolvoConnect_HtmlEscape(
        "Nur im Volvo-Entwicklerportal verfügbare Berechtigungen können angefordert werden. Eine geänderte Auswahl startet die erneute Autorisierung.");
    my $html = "<div class='vcc-entity-config' data-device='$device' data-fhem-base='$base' data-csrf='$csrf'>"
        . "<header class='vcc-config-head'><div class='vcc-config-brand'><span class='vcc-brand-mark'>V</span>"
        . "<div><small>VOLVO CONNECT / BERECHTIGUNGEN</small><h1>Scope-Konfiguration</h1></div></div>"
        . "<div class='vcc-config-actions'><button type='button' class='vcc-edit' title='Bearbeiten' aria-label='Bearbeiten'>&#9998;</button>"
        . "<div class='vcc-edit-actions'><button type='button' class='vcc-cancel'>Abbrechen</button>"
        . "<button type='button' class='vcc-save'>Speichern</button></div>"
        . "<button type='button' class='vcc-toggle-all'>Alle ausw&#228;hlen</button>"
        . "<span class='vcc-status' aria-live='polite'></span></div></header>"
        . "<div class='vcc-config-note'>$configNote</div>"
        . "<main class='vcc-scope-list'>";

    for my $group (@{VolvoConnect_ScopeDefinitions()}) {
        $html .= "<section class='vcc-scope-group'><h2>" . VolvoConnect_HtmlEscape($group->{title}) . "</h2>";
        for my $scope (@{$group->{scopes}}) {
            my ($attribute, $label, $description) = @{$scope};
            my $checked = VolvoConnect_ScopeEnabled($name, $attribute) ? " checked" : "";
            $html .= "<label class='vcc-scope-row'><input type='checkbox' data-scope='" . $attribute . "'" . $checked . " disabled>"
                . "<span><strong>" . VolvoConnect_HtmlEscape($label) . "</strong><small>"
                . VolvoConnect_HtmlEscape($description) . "</small></span></label>";
        }
        $html .= "</section>";
    }

    $html .= "</main></div><style>"
        . ".vcc-entity-config{font:14px 'Avenir Next','Helvetica Neue',sans-serif;color:#f4f4e9;background:#1d2825;max-width:1120px;height:100vh;margin:0 auto;display:flex;flex-direction:column;overflow:hidden;border:1px solid #46544c;box-shadow:0 16px 44px #0c16124a;}"
        . ".vcc-entity-config *{box-sizing:border-box}.vcc-config-head{min-height:76px;flex:0 0 auto;padding:15px 24px;display:flex;justify-content:space-between;align-items:center;gap:20px;background:#202e29;border-bottom:1px solid #405149;}"
        . ".vcc-config-brand{display:flex;align-items:center;gap:12px;min-width:0}.vcc-brand-mark{width:39px;height:39px;flex:0 0 39px;border:2px solid #52bd8b;border-radius:50%;color:#52bd8b;display:grid;place-items:center;font:700 22px Georgia,serif;}"
        . ".vcc-config-head small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac}.vcc-config-head h1{font:500 22px Georgia,serif;margin:3px 0;letter-spacing:0;}"
        . ".vcc-config-actions{display:flex;align-items:center;justify-content:flex-end;gap:8px;flex-wrap:wrap}.vcc-config-note{flex:0 0 auto;padding:10px 24px;background:#26342d;color:#c7d0c8;border-bottom:1px solid #46534a;font-size:12px;line-height:1.45;}"
        . ".vcc-scope-list{flex:1 1 auto;min-height:0;overflow:auto;padding:4px 24px 18px;background:linear-gradient(155deg,#26352e,#1b2823 62%,#202c27);}"
        . ".vcc-scope-group{padding-top:14px}.vcc-scope-group h2{font:500 18px Georgia,serif;color:#52bd8b;margin:0 0 8px;padding-bottom:7px;border-bottom:1px solid #46534a;}"
        . ".vcc-scope-row{display:flex;align-items:center;gap:12px;padding:10px 12px;border-bottom:1px solid #cfddcf14;cursor:pointer;}.vcc-scope-row input{width:18px;height:18px;flex:0 0 18px;accent-color:#52bd8b;margin:0;}"
        . ".vcc-scope-row input:disabled{opacity:.7}.vcc-scope-row span{display:flex;flex-direction:column;gap:3px;min-width:0}.vcc-scope-row strong{font-weight:600}.vcc-scope-row small{color:#9fac9f;line-height:1.4;}"
        . ".vcc-config-actions button{padding:8px 12px;border:1px solid #52bd8b;background:#26342d;color:#f4f4e9;cursor:pointer;font:600 12px 'Helvetica Neue',sans-serif;}"
        . ".vcc-config-actions button:hover{background:#34463c}.vcc-edit{font-size:18px!important;line-height:1;min-width:38px;min-height:36px}.vcc-edit-actions{display:none;gap:8px}.vcc-edit-actions .vcc-cancel{border-color:#69796f;}"
        . ".vcc-toggle-all{display:none;border-color:#69796f!important}.vcc-entity-config.edit-mode .vcc-edit{display:none}.vcc-entity-config.edit-mode .vcc-edit-actions,.vcc-entity-config.edit-mode .vcc-toggle-all{display:flex;}"
        . ".vcc-config-actions button:disabled{opacity:.5;cursor:wait}.vcc-status{font-size:12px;color:#a9b7ac;min-height:16px;}"
        . "\@media(max-width:760px){.vcc-config-head{padding:13px 15px}.vcc-config-note{padding:10px 15px}.vcc-scope-list{padding:4px 15px 16px}}"
        . "\@media(max-width:500px){.vcc-config-head{align-items:flex-start;flex-wrap:wrap;gap:10px}.vcc-config-actions{width:100%;justify-content:flex-start}.vcc-config-note{padding:9px 12px}.vcc-scope-list{padding:2px 12px 12px}.vcc-scope-row{padding:9px 6px;align-items:flex-start}.vcc-scope-row input{margin-top:2px}}"
        . "</style><script>(function(){"
        . "var root=document.querySelector('.vcc-entity-config');if(!root)return;"
        . "var device=root.getAttribute('data-device'),base=root.getAttribute('data-fhem-base'),csrf=root.getAttribute('data-csrf')||'';while(base.charAt(base.length-1)==='/')base=base.slice(0,-1);"
        . "if(!csrf){var cookie=document.cookie.match(/(?:^|;\\s*)fwcsrf=([^;]+)/);csrf=cookie?decodeURIComponent(cookie[1]):'';}"
        . "var status=root.querySelector('.vcc-status'),editButton=root.querySelector('.vcc-edit'),cancelButton=root.querySelector('.vcc-cancel'),saveButton=root.querySelector('.vcc-save'),toggleAll=root.querySelector('.vcc-toggle-all');"
        . "var fields=root.querySelectorAll('input[type=checkbox][data-scope]'),finishing=false,originalStates=[];"
        . "function requestCommand(command){var url=base+'?cmd='+encodeURIComponent(command)+'&XHR=1';if(csrf)url+='&fwcsrf='+encodeURIComponent(csrf);return fetch(url,{cache:'no-store',credentials:'same-origin'}).then(function(response){return response.text().then(function(text){if(!response.ok||/error|unknown|forbidden|fehler|fehlgeschlagen|ungueltig|unbekannt/i.test(text))throw new Error('HTTP '+response.status+' '+text.slice(0,120));return text;});});}"
        . "function setEditMode(editing){root.classList.toggle('edit-mode',editing);Array.prototype.forEach.call(fields,function(field){field.disabled=!editing;});toggleAll.disabled=!editing;status.textContent='';}"
        . "function refreshToggleButton(){var allSelected=fields.length>0&&Array.prototype.every.call(fields,function(field){return field.checked;});toggleAll.textContent=allSelected?'Alle ab\\u00e4hlen':'Alle ausw\\u00e4hlen';}"
        . "editButton.addEventListener('click',function(){originalStates=Array.prototype.map.call(fields,function(field){return field.checked;});setEditMode(true);});"
        . "cancelButton.addEventListener('click',function(){Array.prototype.forEach.call(fields,function(field,index){field.checked=originalStates[index];});setEditMode(false);refreshToggleButton();});"
        . "Array.prototype.forEach.call(fields,function(field){field.addEventListener('change',refreshToggleButton);});"
        . "toggleAll.addEventListener('click',function(){var selectAll=Array.prototype.some.call(fields,function(field){return !field.checked;});Array.prototype.forEach.call(fields,function(field){field.checked=selectAll;});refreshToggleButton();});"
        . "saveButton.addEventListener('click',function(){if(finishing)return;finishing=true;saveButton.disabled=true;cancelButton.disabled=true;toggleAll.disabled=true;var values={};Array.prototype.forEach.call(fields,function(field){values[field.getAttribute('data-scope')]=field.checked?1:0;});var payload=btoa(JSON.stringify(values));status.textContent='Speichere Scope-Konfiguration...';requestCommand('set '+device+' saveScopeConfig '+payload).then(function(){return requestCommand('save config');}).then(function(){originalStates=Array.prototype.map.call(fields,function(field){return field.checked;});finishing=false;saveButton.disabled=false;cancelButton.disabled=false;setEditMode(false);refreshToggleButton();status.textContent='Scope-Konfiguration gespeichert.';}).catch(function(error){status.textContent='Fehler: '+error.message;finishing=false;saveButton.disabled=false;cancelButton.disabled=false;toggleAll.disabled=false;});});"
        . "refreshToggleButton();})();</script>";
    return $html;
}

sub VolvoConnect_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = "VolvoConnect_Define";
    $hash->{UndefFn}    = "VolvoConnect_Undef";
    $hash->{SetFn}      = "VolvoConnect_Set";
    $hash->{GetFn}      = "VolvoConnect_Get";
    $hash->{AttrFn}     = "VolvoConnect_Attr";

    $data{FWEXT}{"/VolvoConnect"}{FUNC}     = "VolvoConnect_CGI";
    $data{FWEXT}{"/VolvoConnect"}{FORKABLE} = 0;

    $hash->{AttrList} = "vin client_id client_secret vcc_api_key redirect_uri interval interval_slow interval_location "
        . "disable:0,1 disabledForIntervals "
        . "scope_capabilities:0-deaktiviert,1-aktiviert "
        . "scope_warnings:0-deaktiviert,1-aktiviert "
        . "scope_brakes:0-deaktiviert,1-aktiviert "
        . "scope_doors:0-deaktiviert,1-aktiviert "
        . "scope_windows:0-deaktiviert,1-aktiviert "
        . "scope_engine_status:0-deaktiviert,1-aktiviert "
        . "scope_vehicle_relation:0-deaktiviert,1-aktiviert "
        . "scope_commands:0-deaktiviert,1-aktiviert "
        . "scope_command_accessibility:0-deaktiviert,1-aktiviert "
        . "scope_honk_flash:0-deaktiviert,1-aktiviert "
        . "scope_lock:0-deaktiviert,1-aktiviert "
        . "scope_unlock:0-deaktiviert,1-aktiviert "
        . "scope_climatization:0-deaktiviert,1-aktiviert "
        . "scope_engine_commands:0-deaktiviert,1-aktiviert "
        . "scope_fuel:0-deaktiviert,1-aktiviert "
        . "scope_battery_charge:0-deaktiviert,1-aktiviert "
        . "scope_odometer:0-deaktiviert,1-aktiviert "
        . "scope_statistics:0-deaktiviert,1-aktiviert "
        . "scope_tyres:0-deaktiviert,1-aktiviert "
        . "scope_engine_diagnostics:0-deaktiviert,1-aktiviert "
        . "scope_workshop_diagnostics:0-deaktiviert,1-aktiviert "
        . "scope_location:0-deaktiviert,1-aktiviert "
        . "location_reverse_geocode:0,1 "
        . $readingFnAttributes;
}

sub VolvoConnect_Notify($$) {
    my ($hash, $dev) = @_;
    return if ($dev->{NAME} ne "global");
    return if (!defined($dev->{CHANGED}));
    return if (join(" ", @{$dev->{CHANGED}}) !~ /\bINITIALIZED\b/);

    VolvoConnect_StartupCheck($hash);
}

sub VolvoConnect_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);

    if (@a < 2) {
        return "Usage: define <name> VolvoConnect";
    }

    my $name = $a[0];
    $hash->{NOTIFYDEV} = "global";
    VolvoConnect_LoadTokens($hash);
    readingsDelete($hash, "login_url");
    readingsDelete($hash, "accessToken");
    readingsDelete($hash, "refreshToken");
    readingsDelete($hash, "tokenValidUntil");

    Log3 $name, 4, "VolvoConnect ($name) - Defined. Pre-populating default attributes.";

    $attr{$name}{vin}           = $DUMMY_VIN;
    $attr{$name}{client_id}     = $DUMMY_CLIENT_ID;
    $attr{$name}{client_secret} = $DUMMY_SECRET;
    $attr{$name}{vcc_api_key}   = $DUMMY_VCC_KEY;
    $attr{$name}{redirect_uri}  = $DUMMY_REDIRECT;
    $attr{$name}{interval}      = 300;
    $attr{$name}{interval_slow} = 1800;
    $attr{$name}{interval_location} = 900;
    $attr{$name}{location_reverse_geocode} = 1;
    $attr{$name}{stateFormat}   = "{VolvoConnect_StateIcon('$name')}";

    RemoveInternalTimer($hash);
    InternalTimer(time() + 60, "VolvoConnect_StartupCheck", $hash, 0);

    return undef;
}

sub VolvoConnect_Undef($$) {
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

sub VolvoConnect_Attr($$$$) {
    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};

    if ($cmd eq "set") {
        VolvoConnect_ClearEndpointFetchTimes($hash)
            if ($attrName eq "vin");
        if (grep { $_ eq $attrName } ("vin", "client_id", "client_secret", "vcc_api_key", "redirect_uri")) {
            RemoveInternalTimer($hash);
            InternalTimer(time() + 2, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
        }
    }

    if ($attrName =~ /^interval(?:_slow|_location)?$/ && ($cmd eq "set" || $cmd eq "del")) {
        RemoveInternalTimer($hash);
        InternalTimer(time() + 1, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
    }

    if ($main::init_done && !$hash->{helper}{scopeConfigUpdating}
        && $attrName =~ /^scope_/ && ($cmd eq "set" || $cmd eq "del")) {
        VolvoConnect_ClearTokens($hash);
        RemoveInternalTimer($hash);
        InternalTimer(time() + 2, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
    }

    return undef;
}

sub VolvoConnect_Set($$@) {
    my ($hash, $name, $cmd, @args) = @_;

    if ($cmd eq "saveScopeConfig") {
        my $encoded = join("", @args);
        my $json = eval { decode_base64($encoded) };
        my $values = eval { decode_json($json // "") };
        return "Ungueltige Scope-Konfiguration." if (ref($values) ne "HASH");

        my %allowed = map { $_->[0] => 1 }
            map { @{$_->{scopes}} } @{VolvoConnect_ScopeDefinitions()};
        for my $scope (keys %{$values}) {
            return "Unbekannter Scope: $scope" if (!$allowed{$scope});
            return "Ungueltiger Wert fuer $scope" if (!defined($values->{$scope})
                || $values->{$scope} !~ /^[01]$/);
        }

        my @changed = grep {
            (VolvoConnect_ScopeEnabled($name, $_) ? 1 : 0) != $values->{$_}
        } keys %{$values};
        $hash->{helper}{scopeConfigUpdating} = 1;
        my $attrError;
        for my $scope (@changed) {
            my $attrValue = $values->{$scope} ? "1-aktiviert" : "0-deaktiviert";
            my $result = CommandAttr(undef, "$name $scope $attrValue");
            if (defined($result) && $result ne "") {
                $attrError = $result;
                last;
            }
        }
        delete $hash->{helper}{scopeConfigUpdating};
        if (!defined($attrError)) {
            for my $scope (keys %{$values}) {
                if ((VolvoConnect_ScopeEnabled($name, $scope) ? 1 : 0) != $values->{$scope}) {
                    $attrError = "Wert fuer $scope wurde nicht uebernommen";
                    last;
                }
            }
        }
        return "ERROR: Scope-Aenderung fehlgeschlagen: $attrError" if (defined($attrError));

        if (@changed && $main::init_done) {
            VolvoConnect_ClearTokens($hash);
            RemoveInternalTimer($hash);
            InternalTimer(time() + 2, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
        }
        return "Scope-Konfiguration gespeichert.";
    }

    if ($cmd eq "saveDashboardConfig") {
        my $b64  = join("", @args);
        my $json = eval { decode_base64($b64) };
        if (!defined($json) || $json eq "") {
            return "Ungueltige Dashboard-Konfiguration (Base64-Dekodierung fehlgeschlagen).";
        }
        my $err = VolvoConnect_SaveDashboardConfig($name, $json);
        return $err if (defined($err));
        return "Dashboard-Konfiguration gespeichert.";
    }

    if ($cmd eq "authCode") {
        my $code = join(" ", @args);

        if (exists($hash->{helper}{authCodeProcessing}) && $hash->{helper}{authCodeProcessing}) {
            return "Auth-Code wird bereits verarbeitet.";
        }

        $hash->{helper}{authCodeProcessing} = 1;
        RemoveInternalTimer($hash);
        InternalTimer(time() + 1, sub { VolvoConnect_ExchangeCodeForToken($hash, $code) }, $hash, 0);
        return "Auth-Code angenommen, Verarbeitung gestartet.";
    }

    if ($cmd eq "update") {
        RemoveInternalTimer($hash);
        $hash->{helper}{forceFullUpdate} = 1;
        VolvoConnect_CheckAuthAndFetch($hash);
        return "Aktualisierung ausgelöst.";
    }

    if ($cmd eq "reauth") {
        VolvoConnect_ClearTokens($hash);
        RemoveInternalTimer($hash);
        VolvoConnect_CheckAuthAndFetch($hash);
        my $loginUrl = $hash->{helper}{loginUrl};
        return "Neuanmeldung gestartet. Bitte klicke auf „Bei Volvo anmelden / Auth-Code anfordern“ "
            . "neben dem Gerätestatus."
            if (defined($loginUrl) && $loginUrl ne "");
        return "Neuanmeldung gestartet, aber der Volvo-Login-Link konnte nicht erzeugt werden. "
            . "Bitte prüfe die Zugangsdaten und ob das Device aktiviert ist.";
    }

    if ($cmd eq "login") {
        return $hash->{helper}{loginUrl}
            if (defined($hash->{helper}{loginUrl}) && $hash->{helper}{loginUrl} ne "");
        return "Aktuell ist keine Anmeldung erforderlich.";
    }

    # Horn / Hupen
    if ($cmd eq "horn") {
        VolvoConnect_SendCommand($hash, "horn", {});
        return "Hupen-Befehl gesendet.";
    }

    # Lock / Türen verriegeln
    if ($cmd eq "lock") {
        VolvoConnect_SendCommand($hash, "lock", {});
        return "Verriegeln-Befehl gesendet.";
    }

    # Unlock / Türen entriegeln
    if ($cmd eq "unlock") {
        VolvoConnect_SendCommand($hash, "unlock", {});
        return "Entriegeln-Befehl gesendet.";
    }

    # Climate / Klimaanlage starten
    if ($cmd eq "climate") {
        VolvoConnect_SendCommand($hash, "climate", {});
        return "Klimatisierung gestartet.";
    }

    # Climate Stop
    if ($cmd eq "climate_stop") {
        VolvoConnect_SendCommand($hash, "climate_stop", {});
        return "Klimatisierung gestoppt.";
    }

    # Start Charging
    if ($cmd eq "charge_start") {
        VolvoConnect_SendCommand($hash, "charge_start", {});
        return "Ladevorgang gestartet.";
    }

    # Stop Charging
    if ($cmd eq "charge_stop") {
        VolvoConnect_SendCommand($hash, "charge_stop", {});
        return "Ladevorgang gestoppt.";
    }

    # Set Charge Limit
    if ($cmd eq "charge_limit") {
        my $limitStr = $args[0] // "80";
        my $limit = int($limitStr);
        if ($limit < 10 || $limit > 100) {
            return "Ladelimit muss zwischen 10 und 100 Prozent liegen.";
        }
        VolvoConnect_SendCommand($hash, "charge_limit", { chargeLimit => $limit });
        return "Ladelimit auf ${limit}% gesetzt.";
    }

    # Precondition (Vorkonditionierung) / Wärmepumpe
    if ($cmd eq "precondition") {
        VolvoConnect_SendCommand($hash, "precondition", {});
        return "Vorkonditionierung gestartet.";
    }

    return "Unknown argument $cmd, choose one of update:noArg reauth:noArg login:noArg authCode horn lock unlock climate:noArg climate_stop charge_start charge_stop charge_limit:10..100 precondition saveScopeConfig saveDashboardConfig";
}

sub VolvoConnect_PrettyLabel($) {
    my ($key) = @_;
    my %map = (
        batteryChargeLevel => "Akkustand",
        chargerConnectionStatus => "Ladekabel",
        chargerPowerStatus => "Ladeleistung-Status",
        chargingCurrentLimit => "Lade-Stromlimit",
        chargingPower => "Ladeleistung",
        chargingStatus => "Ladestatus",
        chargingType => "Lade-Typ",
        electricRange => "Elektrische Reichweite",
        estimatedChargingTimeToTargetBatteryChargeLevel => "Restladezeit",
        targetBatteryChargeLevel => "Ziel-Ladestand",
        isSupported => "Unterstützt",
        centralLock => "Zentralverriegelung",
        frontLeftDoor => "Tür vorne links",
        frontRightDoor => "Tür vorne rechts",
        rearLeftDoor => "Tür hinten links",
        rearRightDoor => "Tür hinten rechts",
        hood => "Motorhaube",
        tailgate => "Heckklappe",
        tankLid => "Tankdeckel",
        odometer => "Kilometerstand",
        averageFuelConsumption => "Durchschnittlicher Verbrauch",
        averageSpeed => "Durchschnittsgeschwindigkeit",
        averageEnergyConsumption => "Durchschnittlicher Energieverbrauch",
        averageSpeedAutomatic => "Durchschnittsgeschwindigkeit automatisch",
        distanceToService => "Strecke bis zur Wartung",
        engineHoursToService => "Betriebsstunden bis zur Wartung",
        serviceWarning => "Servicewarnung",
        timeToService => "Zeit bis zur Wartung",
        washerFluidLevelWarning => "Wischwasser",
        distanceToEmptyBattery => "Reichweite Akku",
        distanceToEmptyTank => "Reichweite Tank",
        tripMeterAutomatic => "Tageskilometer automatisch",
        tripMeterManual => "Tageskilometer manuell",
        chargingSystemStatus => "Lade-Systemstatus",
        transferLimit => "Transferlimit",
        availabilityStatus => "Verfügbarkeitsstatus",
        unavailableReason => "Grund der Nichtverfügbarkeit",
        engineCoolantLevelWarning => "Kühlmittelstand",
        oilLevelWarning => "Ölstand",
        engineStatus => "Motor",
        serviceWarning => "Service",
        fuelAmount => "Kraftstoffmenge",
        batteryCapacityKWH => "Batteriekapazität",
        modelYear => "Modelljahr",
        gearbox => "Getriebe",
        fuelType => "Antriebsart",
        externalColour => "Außenfarbe",
        vin => "Fahrgestellnummer",
        descriptions_model => "Modell",
        descriptions_steering => "Lenkradseite",
        descriptions_upholstery => "Polsterung",
        images_exteriorImageUrl => "Außenbild",
        images_internalImageUrl => "Innenbild",
        frontLeft => "Vorne links",
        frontRight => "Vorne rechts",
        rearLeft => "Hinten links",
        rearRight => "Hinten rechts",
        invokeStatus => "Befehlsstatus",
        command => "Befehl",
        href => "Befehlsadresse",
        frontLeftWindow => "Fenster vorne links",
        frontRightWindow => "Fenster vorne rechts",
        rearLeftWindow => "Fenster hinten links",
        rearRightWindow => "Fenster hinten rechts",
        sunroof => "Schiebedach",
        brakeFluidLevelWarning => "Bremsflüssigkeitsstand",
        brakeLightCenterWarning => "Bremslicht Mitte",
        brakeLightLeftWarning => "Bremslicht links",
        brakeLightRightWarning => "Bremslicht rechts",
        daytimeRunningLightLeftWarning => "Tagfahrlicht links",
        daytimeRunningLightRightWarning => "Tagfahrlicht rechts",
        fogLightFrontWarning => "Nebelscheinwerfer vorne",
        fogLightRearWarning => "Nebelschlussleuchte",
        hazardLightsWarning => "Warnblinkanlage",
        highBeamLeftWarning => "Fernlicht links",
        highBeamRightWarning => "Fernlicht rechts",
        lowBeamLeftWarning => "Abblendlicht links",
        lowBeamRightWarning => "Abblendlicht rechts",
        positionLightFrontLeftWarning => "Positionslicht vorne links",
        positionLightFrontRightWarning => "Positionslicht vorne rechts",
        positionLightRearLeftWarning => "Positionslicht hinten links",
        positionLightRearRightWarning => "Positionslicht hinten rechts",
        registrationPlateLightWarning => "Kennzeichenbeleuchtung",
        reverseLightsWarning => "Rückfahrlicht",
        sideMarkLightsWarning => "Seitenmarkierungsleuchten",
        turnIndicationFrontLeftWarning => "Blinker vorne links",
        turnIndicationFrontRightWarning => "Blinker vorne rechts",
        turnIndicationRearLeftWarning => "Blinker hinten links",
        turnIndicationRearRightWarning => "Blinker hinten rechts",
        address       => "Adresse",
        house_number  => "Hausnummer",
        road          => "Straße",
        postcode      => "Postleitzahl",
        city          => "Ort",
        state         => "Bundesland",
        country       => "Land",
        latitude      => "Breitengrad",
        longitude     => "Längengrad",
        altitude      => "Höhe",
        heading       => "Fahrtrichtung",
        timestamp     => "Positionszeitpunkt",
    );
    return $map{$key} if (exists($map{$key}));

    # capability flags come as "getEnergyState_<feature>_isSupported"
    my $clean = $key;
    $clean =~ s/^getEnergyState_//;
    $clean =~ s/_isSupported$//;
    my $label = $map{$clean} // $clean;
    $label =~ s/([a-z0-9])([A-Z])/$1 $2/g;
    $label = ucfirst($label);
    $label .= " unterstützt" if ($key =~ /_isSupported$/);
    return $label;
}

sub VolvoConnect_FormatCoordinate($$) {
    my ($coordinate, $axis) = @_;
    return $coordinate if (!defined($coordinate) || $coordinate !~ /^-?\d+(?:\.\d+)?$/);

    my $limit = $axis eq "latitude" ? 90 : 180;
    return $coordinate if (abs($coordinate) > $limit);

    my $direction = $axis eq "latitude"
        ? ($coordinate < 0 ? "S" : "N")
        : ($coordinate < 0 ? "W" : "O");
    my $absolute = abs($coordinate);
    my $degrees = int($absolute);
    my $minutesValue = ($absolute - $degrees) * 60;
    my $minutes = int($minutesValue);
    my $seconds = ($minutesValue - $minutes) * 60;
    if ($seconds >= 59.9995) {
        $seconds = 0;
        $minutes++;
    }
    if ($minutes >= 60) {
        $minutes = 0;
        $degrees++;
    }
    return sprintf("%d&#176; %02d' %06.3f\" %s", $degrees, $minutes, $seconds, $direction);
}

sub VolvoConnect_FormatTimestamp($) {
    my ($timestamp) = @_;
    return $timestamp if (!defined($timestamp));
    return sprintf("%02d.%02d.%04d  %02d:%02d Uhr", $3, $2, $1, $4, $5)
        if ($timestamp =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
    return $timestamp;
}

sub VolvoConnect_PrettyValue($$;$) {
    my ($prefix, $value, $key) = @_;
    return VolvoConnect_FormatTimestamp($value)
        if ($prefix eq "location" && $key eq "timestamp");
    if ($prefix eq "state" && defined($key) && defined($value)) {
        my %stateValues = (
            chargingStatus => {
                DONE    => "Beendet",
                ONGOING => "Lädt",
                STOPPED => "Gestoppt",
            },
            chargingType => {
                AC => "Wechselstrom (AC)",
                DC => "Gleichstrom (DC)",
            },
            chargerConnectionStatus => {
                CONNECTED    => "Verbunden",
                DISCONNECTED => "Nicht verbunden",
            },
            chargerPowerStatus => {
                PROVIDING_POWER  => "Liefert Leistung",
                CHARGING_STOPPED => "Laden gestoppt",
            },
            chargingSystemStatus => {
                OK    => "OK",
                ERROR => "Fehler",
            },
        );
        return $stateValues{$key}{$value}
            if (exists($stateValues{$key}) && exists($stateValues{$key}{$value}));
    }
    if ($prefix eq "location" && defined($value) && $value =~ /^-?\d+(?:\.\d+)?$/) {
        return VolvoConnect_FormatCoordinate($value, $key)
            if ($key eq "latitude" || $key eq "longitude");
        my @directions = ("Nord", "Nordost", "Ost", "Südost", "Süd", "Südwest", "West", "Nordwest");
        return $directions[int(($value + 22.5) / 45) % 8]
            if ($key eq "heading" && $value >= 0 && $value <= 360);
    }
    return "Ja"   if ($prefix eq "capabilities" && $value eq "1");
    return "Nein" if ($prefix eq "capabilities" && $value eq "0");
    return "OK" if ($value eq "NO_WARNING");
    return "on" if ($value eq "RUNNING");
    return "off" if ($value eq "STOPPED");
    return "Ja" if ($value eq "AVAILABLE");
    return "Nein" if ($value eq "UNAVAILABLE");
    return "Nicht verfügbar" if ($value eq "ERROR_READING_PROPERTY");
    return $value;
}

sub VolvoConnect_ValueHtml($) {
    my ($value) = @_;
    my %exact = (
        "Ja"           => "<span class='dot dot-pos' title=\"Ja\">&#10003;</span>",
        "OK"           => "<span class='dot dot-pos' title=\"OK\">&#10003;</span>",
        "on"           => "<span class='state-badge state-running' title=\"Motor läuft\">Läuft</span>",
        "off"          => "<span class='state-badge state-off' title=\"Motor aus\">Aus</span>",
        "Verbunden"    => "<span class='cable-state cable-connected' role='img' aria-label=\"Ladekabel verbunden\" title=\"Ladekabel verbunden\">&#128268;</span>",
        "Nicht verbunden" => "<span class='cable-state cable-disconnected' role='img' aria-label=\"Ladekabel nicht verbunden\" title=\"Ladekabel nicht verbunden\">&#128268;</span>",
        "LOCKED"       => "<span title=\"LOCKED\">&#128274;</span>",
        "UNLOCKED"     => "<span title=\"UNLOCKED\">&#128275;</span>",
        "CLOSED"       => "<span title=\"CLOSED\">&#128274;</span>",
        "OPEN"         => "<span title=\"OPEN\">&#128275;</span>",
        "NONE"         => "<span class='dot dot-neg' title=\"NONE\">&minus;</span>",
        "IDLE"         => "<span class='dot dot-neg' title=\"IDLE\">&#9208;</span>",
        "CHARGING"     => "<span title=\"CHARGING\">&#9889;</span>",
        "CONNECTED"    => "<span title=\"CONNECTED\">&#128267;</span>",
        "DISCONNECTED" => "<span class='dot dot-neg' title=\"DISCONNECTED\">&minus;</span>",
        "NO_POWER_AVAILABLE" => "<span class='dot dot-neg' title=\"NO_POWER_AVAILABLE\">&minus;</span>",
    );
    return $exact{$value} if (exists($exact{$value}));

    if ($value =~ /WARNING|VERY_LOW|LOW_PRESSURE|HIGH_PRESSURE|TOO_LOW|TOO_HIGH/i) {
        return "<span class='dot dot-warn' title=\"$value\">&#9888;</span>";
    }

    if ($value eq "Nein" || $value =~ /ERROR_READING_PROPERTY|not[_ ]?supported|not[_ ]?found|not[_ ]?available|nicht verfügbar|unspecified/i) {
        return "<span class='dot dot-neg' title=\"" . $value . "\">&minus;</span>";
    }
    return $value;
}

sub VolvoConnect_HtmlEscape($) {
    my ($s) = @_;
    $s = "" if (!defined($s));
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/([^\x00-\x7F])/"&#" . ord($1) . ";"/ge;
    return $s;
}

sub VolvoConnect_CGI($) {
    my ($request) = @_;
    my ($path) = split(/\?/, $request, 2);
    my @parts = split("/", $path);
    my $name = $parts[-1];

    my $hash = $defs{$name};
    return ("text/plain; charset=utf-8", "Unknown VolvoConnect device: $name")
        if (!$hash || $hash->{TYPE} ne "VolvoConnect");

    my $html = eval { VolvoConnect_BuildDashboard($hash) };
    if ($@ || !defined($html)) {
        Log3 $name, 2, "VolvoConnect ($name) - Dashboard rendering failed: $@";
        return ("text/plain; charset=utf-8", "Dashboard-Fehler: $@");
    }
    return ("text/html; charset=utf-8", $html);
}

sub VolvoConnect_BuildDashboard($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $dashboardRefresh = int(AttrVal($name, "interval", 300));
    $dashboardRefresh = 300 if ($dashboardRefresh < 10);
    my $fhemPath = defined($main::FW_ME) && $main::FW_ME ne "" ? $main::FW_ME : "/fhem";
    $fhemPath =~ s{/$}{};
    $fhemPath = "/fhem" if ($fhemPath eq "");
    my $csrf = VolvoConnect_HtmlEscape($main::FW_CSRF // "");

    my %labels = (
        state        => "Energie & Akku",
        capabilities => "Fähigkeiten",
        warnings     => "Licht",
        brakes       => "Bremsen",
        doors        => "Türen & Verriegelung",
        windows      => "Fenster",
        engineDiagnostics => "Diagnose",
        workshopDiagnostics => "Werkstattdiagnose",
        commandAccessibility => "Befehlsverfügbarkeit",
        commands     => "Fahrzeugbefehle",
        statistics   => "Statistik",
        tyres        => "Reifen",
        vehicle      => "Allgemeine Fahrzeuginformationen",
        location     => "Fahrzeugstandort",
    );
    my %scopeAttr = (
        capabilities => "scope_capabilities",
        warnings     => "scope_warnings",
        brakes       => "scope_brakes",
        doors        => "scope_doors",
        windows      => "scope_windows",
        engineDiagnostics => "scope_engine_diagnostics",
        workshopDiagnostics => "scope_workshop_diagnostics",
        commandAccessibility => "scope_command_accessibility",
        commands     => "scope_commands",
        statistics   => "scope_statistics",
        tyres        => "scope_tyres",
        vehicle      => "scope_vehicle_relation",
        location     => "scope_location",
    );

    my $config = VolvoConnect_LoadDashboardConfig($name);
    my $tileVisibility = ref($config->{_tileVisibility}) eq "HASH" ? $config->{_tileVisibility} : {};
    my $authStatus = ReadingsVal($name, "state", "");
    my $tokenValid = $authStatus eq "authenticated";
    my $authStatusTitle = $tokenValid ? "API-Token gültig"
        : $authStatus eq "auth_required" ? "Neuer API-Token erforderlich"
        : $authStatus eq "token_refreshing" ? "API-Token wird erneuert"
        : $authStatus eq "disabled" ? "VolvoConnect deaktiviert"
        : $authStatus eq "error" ? "API-Token ungültig oder API-Fehler"
        : "API-Token-Status unbekannt";

    my $html = "<!DOCTYPE html><html lang='de'><head><meta charset='UTF-8'>"
        . "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        . "<title>$name Dashboard</title>"
        . "<style>"
        . "*{box-sizing:border-box;}"
        . "body{font-family:'Avenir Next','Helvetica Neue',sans-serif;background:#151f1b;color:#f4f4e9;margin:0;padding:12px;overflow-x:hidden;font-size:14px;}"
        . "h1{font:500 22px Georgia,serif;margin:3px 0;letter-spacing:0;}"
        . ".wrap{width:100%;max-width:1120px;margin:0 auto;padding-bottom:0;background:#1d2825;border:1px solid #46544c;box-shadow:0 16px 44px #0c16124a;overflow:hidden;}"
        . ".toolbar{min-height:76px;padding:15px 24px;background:#202e29;border-bottom:1px solid #405149;display:flex;align-items:center;gap:12px;}"
        . ".brand{display:flex;align-items:center;gap:12px;margin-right:auto;min-width:0;}"
        . ".brand-mark{width:39px;height:39px;flex:0 0 39px;border:2px solid #52bd8b;border-radius:50%;color:#52bd8b;display:grid;place-items:center;font:700 22px Georgia,serif;}"
        . ".brand small{font:700 10px 'Helvetica Neue',sans-serif;letter-spacing:1.2px;color:#a9b7ac;}"
        . ".toolbar-controls{display:flex;align-items:center;gap:8px;flex-wrap:wrap;justify-content:flex-end;}"
        . ".grid{column-width:280px;column-gap:10px;column-fill:balance;padding:22px 24px 24px;background:linear-gradient(155deg,#26352e,#1b2823 62%,#202c27);}"
        . ".tile{display:inline-block;vertical-align:top;--tile-accent:#52bd8b;background:#26342d;border-top:2px solid var(--tile-accent);padding:14px 15px;width:100%;min-width:0;margin:0 0 10px;break-inside:avoid;}"
        . ".tile:nth-child(3n){--tile-accent:#e3b953;} .tile:nth-child(3n+2){--tile-accent:#8ab6d1;}"
        . ".tile h2{font:500 17px Georgia,serif;margin:0 0 8px;color:var(--tile-accent);border-bottom:1px solid #46534a;padding-bottom:9px;display:flex;align-items:center;gap:8px;}"
        . ".tile.tile-hidden{display:none;}"
        . "body.edit-mode .tile.tile-hidden{display:block;opacity:.55;outline:1px dashed #69796f;}"
        . ".tile-edit-controls{display:none;margin-left:auto;align-items:center;gap:4px;color:#a9b7ac;font:normal 10px 'Helvetica Neue',sans-serif;}"
        . "body.edit-mode .tile-edit-controls{display:flex;}"
        . ".tile-edit-controls input{margin:0;}"
        . ".tile.tile-dragging{position:relative;opacity:.92;outline:2px solid #52bd8b;transform:scale(1.015);z-index:2;}"
        . ".tile-reorder-mode .grid{background-image:linear-gradient(#52bd8b24 1px,transparent 1px),linear-gradient(90deg,#52bd8b24 1px,transparent 1px),linear-gradient(155deg,#26352e,#1b2823 62%,#202c27);background-size:28px 28px,28px 28px,auto;}"
        . ".tile-reorder-mode .tile{min-height:48px;padding:10px 14px;margin-bottom:10px;transition:transform .12s ease,opacity .12s ease;}"
        . ".tile-reorder-mode .tile h2{margin:0;border:0;padding:0;}"
        . ".tile-reorder-mode .tile .row,.tile-reorder-mode .tile .location-map,.tile-reorder-mode .vehicle-image-tile{display:none!important;}"
        . ".tile-reorder-mode .tile-edit-controls{display:none!important;}"
        . ".tile-reorder-mode .tile{cursor:move;touch-action:none;user-select:none;}"
        . ".tile .row{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:7px 0;border-top:1px solid #cfddcf14;font-size:12px;min-width:0;}"
        . ".tile .row.row-hidden{display:none;}"
        . "body.edit-mode .tile .row.row-hidden{display:flex;opacity:0.5;}"
        . ".tile .key{color:#9fac9f;word-break:normal;min-width:0;flex:1 1 auto;overflow:hidden;text-overflow:ellipsis;}"
        . ".tile .val{font-weight:600;color:#edf0e6;font-variant-numeric:tabular-nums;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;justify-content:flex-end;flex:0 1 42%;min-width:24px;max-width:42%;}"
        . ".location-map{width:100%;height:220px;margin-top:10px;border:1px solid #536054;background:#202e29;}"
        . ".location-map iframe{width:100%;height:100%;border:0;}"
        . ".vehicle-image-tile{column-span:all;text-align:center;break-inside:avoid;}"
        . ".vehicle-image-gallery{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap;}"
        . ".vehicle-image{display:block;max-width:calc(50% - 6px);max-height:420px;width:auto;height:auto;margin:0;}"
        . ".vehicle-image-gallery.count-1 .vehicle-image{max-width:100%;}"
        . ".dot{display:inline-block;width:16px;height:16px;line-height:16px;border-radius:50%;"
        . "text-align:center;font-size:11px;font-weight:bold;color:#fff;}"
        . ".auth-indicator{display:inline-flex;width:16px;height:16px;flex:0 0 16px;align-items:center;justify-content:center;}"
        . ".auth-dot{display:block;width:12px;height:12px;border-radius:50%;}"
        . ".auth-dot-valid{background:#52bd8b;} .auth-dot-invalid{background:#d45b45;}"
        . ".dot-neg{background:#d45b45;}"
        . ".dot-pos{background:#52bd8b;font-size:12px;}"
        . ".dot-warn{background:#e3b953;color:#1d2825;}"
        . ".state-badge{display:inline-flex;align-items:center;padding:2px 8px;border:1px solid;border-radius:3px;font-size:11px;font-weight:700;line-height:1.5;}"
        . ".state-running{border-color:#52bd8b;background:#214132;color:#9ce2bb;}"
        . ".state-off{border-color:#718078;background:#3b4540;color:#ccd3ce;}"
        . ".cable-state{position:relative;display:inline-block;font-size:16px;line-height:1;}"
        . ".cable-disconnected:after{content:'';position:absolute;left:-1px;top:50%;width:19px;height:2px;background:#d45b45;box-shadow:0 0 0 1px #26342d;transform:rotate(-45deg);}"
        . ".btn{display:inline-block;padding:8px 12px;margin:0;background:#26342d;color:#f4f4e9;"
        . "border:1px solid #52bd8b;cursor:pointer;font:600 12px 'Helvetica Neue',sans-serif;}"
        . ".icon-btn{width:38px;height:38px;padding:0;font-size:18px;line-height:1;}"
        . ".btn:hover{background:#34463c;}"
        . ".tile.wide{grid-column:1 / -1;}"
        . ".edit-controls{display:none;gap:2px;margin-right:2px;}"
        . "body.edit-mode .edit-controls{display:flex;align-items:center;}"
        . ".drag-handle{cursor:grab;color:#a9b7ac;font-size:0.9em;}"
        . ".tile-move-toggle{display:none;align-items:center;justify-content:center;flex:0 0 36px;width:36px;height:32px;margin-left:auto;padding:2px;border:1px solid #69796f;background:#26342d;color:#a9b7ac;cursor:pointer;touch-action:manipulation;}"
        . ".tile-move-toggle span{font-size:11px;line-height:.7;text-align:center;}"
        . "body.edit-mode .tile-move-toggle{display:inline-flex;}"
        . "body.tile-reorder-mode .tile-move-toggle{border-color:#52bd8b;color:#9ce2bb;}"
        . ".key-input{background:transparent;border:none;color:#9fac9f;font:inherit;width:auto;min-width:0;flex:1 1 auto;overflow:hidden;text-overflow:ellipsis;pointer-events:none;padding:0;}"
        . "body.edit-mode .key-input{pointer-events:auto;border-bottom:1px dashed #69796f;color:#f4f4e9;}"
        . ".actions{width:100%;margin:0;background:#202e29;border-bottom:1px solid #405149;padding:16px 24px 18px;}"
        . ".actions h2{font:500 17px Georgia,serif;margin:0 0 10px;color:#52bd8b;}"
        . ".actions>div{display:flex;flex-wrap:wrap;gap:6px;width:100%;}"
        . ".actions .btn{margin:0;flex:0 1 auto;max-width:100%;}"
        . ".actions .btn:disabled{opacity:.55;cursor:wait;}"
        . ".actions .btn.action-highlight{background:#52bd8b;color:#1d2825;border-color:#b9e7ce;box-shadow:0 0 0 3px #52bd8b40;}"
        . ".action-status{display:block;min-height:16px;margin-top:8px;color:#a9b7ac;font-size:12px;}"
        . ".save-btn{display:none;}"
        . "body.edit-mode .save-btn{display:inline-block;}"
        . "\@media(max-width:760px){body{padding:8px}.grid{padding:16px 15px 18px}.actions{padding:14px 15px}.toolbar{padding:13px 15px}}"
        . "\@media(max-width:500px){.toolbar{align-items:flex-start;flex-wrap:wrap;gap:10px}.brand{flex:1 1 100%}.toolbar-controls{width:100%;justify-content:flex-start}.grid{gap:7px;padding:14px 12px}.actions{padding:13px 12px}.actions .btn{font-size:11px;padding:7px 8px}.vehicle-image-gallery .vehicle-image{max-width:100%;}}"
        . "</style></head><body><div class='wrap' data-device='" . VolvoConnect_HtmlEscape($name)
        . "' data-fhem-path='" . VolvoConnect_HtmlEscape($fhemPath)
        . "' data-csrf='$csrf'>"
        . "<div class='toolbar'><div class='brand'><span class='brand-mark'>V</span><div><small>VOLVO CONNECT / FAHRZEUG</small><h1>$name</h1></div></div>"
        . "<span class='auth-indicator' role='img' aria-label='" . VolvoConnect_HtmlEscape($authStatusTitle)
        . "' title='" . VolvoConnect_HtmlEscape($authStatusTitle) . "'><span class='auth-dot "
        . ($tokenValid ? "auth-dot-valid" : "auth-dot-invalid") . "'></span></span><div class='toolbar-controls'>"
        . "<button type='button' class='btn icon-btn' title='Bearbeiten' aria-label='Bearbeiten' onclick='toggleEdit()'>&#9998;</button>"
        . "<button type='button' class='btn save-btn' onclick='saveDashboardConfig()'>&#128190; Speichern</button>"
        . "</div></div>";

    my @actions = (
        ["lock",          "&#128274; Verriegeln"],
        ["unlock",        "&#128275; Entriegeln"],
        ["climate",       "&#10052; Klima starten"],
        ["climate_stop",  "&#9209; Klima stoppen"],
        ["charge_start",  "&#9889; Laden starten"],
        ["charge_stop",   "&#9209; Laden stoppen"],
        ["precondition",  "&#127777; Vorkonditionieren"],
        ["horn",          "&#128266; Hupe"],
    );
    $html .= "<div class='actions'><h2>Aktionen</h2><div>";
    for my $action (@actions) {
        my ($cmd, $label) = @{$action};
        $html .= "<button type='button' class='btn' data-action='$cmd'>$label</button>";
    }
    $html .= "</div><span class='action-status' aria-live='polite'></span></div><div class='grid'>";

    my @prefixes = ("state", "capabilities", "warnings", "brakes", "doors", "windows", "engineDiagnostics", "workshopDiagnostics", "commandAccessibility", "commands", "statistics", "tyres", "vehicle", "location");
    if (ref($config->{_tileOrder}) eq "ARRAY") {
        my %tileRank;
        for my $index (0 .. $#{$config->{_tileOrder}}) {
            $tileRank{$config->{_tileOrder}[$index]} = $index;
        }
        @prefixes = sort {
            ($tileRank{$a} // 9999) <=> ($tileRank{$b} // 9999)
                || $a cmp $b
        } @prefixes;
    }

    for my $prefix (@prefixes) {
        my $attrName = $scopeAttr{$prefix};
        if ($prefix eq "engineDiagnostics") {
            next if (!VolvoConnect_ScopeEnabled($name, "scope_engine_diagnostics")
                && !VolvoConnect_ScopeEnabled($name, "scope_engine_status"));
        } else {
            next if (defined($attrName) && !VolvoConnect_ScopeEnabled($name, $attrName));
        }

        my @entities;
        for my $reading (keys %{$hash->{READINGS}}) {
            my $key;
            if ($prefix eq "engineDiagnostics" && $reading =~ /^engine_(.+)$/) {
                next if (!VolvoConnect_ScopeEnabled($name, "scope_engine_status"));
                $key = $1;
            } elsif ($prefix eq "engineDiagnostics" && $reading eq "workshopDiagnostics_washerFluidLevelWarning") {
                $key = "washerFluidLevelWarning";
            } elsif ($prefix eq "engineDiagnostics" && $reading eq "brakes_brakeFluidLevelWarning") {
                $key = "brakeFluidLevelWarning";
            } elsif ($prefix eq "workshopDiagnostics" && $reading eq "workshopDiagnostics_washerFluidLevelWarning") {
                next;
            } elsif ($prefix eq "brakes" && $reading eq "brakes_brakeFluidLevelWarning") {
                next;
            } elsif ($prefix eq "state" && $reading =~ /^(state|fuel)_(.+)$/) {
                $key = $2;
            } elsif ($prefix eq "statistics" && $reading =~ /^(statistics|odometer)_(.+)$/) {
                $key = $2;
            } elsif ($reading =~ /^${prefix}_(.+)$/) {
                $key = $1;
            } else {
                next;
            }
            next if ($key =~ /_unit$/);
            next if ($prefix eq "vehicle" && $key =~ /^images_(?:exterior|internal)ImageUrl$/);
            next if ($prefix eq "location" && $key =~ /^(?:address|altitude|heading)$/);
            my $value = $hash->{READINGS}{$reading}{VAL};
            my $unitReading = $reading . "_unit";
            my $unit = exists($hash->{READINGS}{$unitReading}) ? $hash->{READINGS}{$unitReading}{VAL} : "";
            $unit = "Monat" if ($unit eq "month");
            $unit = "Monate" if ($unit eq "months");
            $unit = "A" if ($unit eq "ampere" || $unit eq "amperes");
            my $prettyValue = VolvoConnect_PrettyValue($prefix, $value, $key);
            my $displayValue;
            if ($unit eq "percentage") {
                $displayValue = $prettyValue . "%";
            } elsif ($unit eq "minutes" && $prettyValue =~ /^\d+$/) {
                $displayValue = sprintf("%02d:%02d h", int($prettyValue / 60), $prettyValue % 60);
            } else {
                $displayValue = $prettyValue . ($unit ne "" ? " $unit" : "");
            }

            my $entryConfig = $config->{$reading} // {};
            my $defaultLabel = VolvoConnect_PrettyLabel($key);
            my $entryLabel = (defined($entryConfig->{label}) && $entryConfig->{label} ne "")
                ? $entryConfig->{label} : $defaultLabel;
            $entryLabel = $defaultLabel if ($key eq "modelYear" && $entryLabel eq "Baujahr");
            $entryLabel = $defaultLabel if ($key eq "washerFluidLevelWarning" && $entryLabel eq "Waschwasserstand-Warnung");
            $entryLabel = $defaultLabel if ($key eq "engineCoolantLevelWarning" && $entryLabel eq "Kühlmittelstand-Warnung");
            $entryLabel = $defaultLabel if ($key eq "oilLevelWarning" && $entryLabel eq "Ölstand-Warnung");
            $entryLabel = $defaultLabel if ($key eq "serviceWarning" && $entryLabel eq "Servicewarnung");
            $entryLabel = $defaultLabel if ($key eq "engineStatus" && $entryLabel eq "Engine Status");
            my $legacyLabel = $key;
            $legacyLabel =~ s/([a-z0-9])([A-Z])/$1 $2/g;
            $legacyLabel =~ s/_/ /g;
            $legacyLabel = ucfirst($legacyLabel);
            $entryLabel = $defaultLabel if ($entryLabel eq $legacyLabel);
            my $normalizedLabel = lc($entryLabel);
            my $normalizedKey = lc($key);
            $normalizedLabel =~ s/[^a-z0-9]//g;
            $normalizedKey =~ s/[^a-z0-9]//g;
            $entryLabel = $defaultLabel if ($normalizedLabel eq $normalizedKey);
            $entryLabel = $defaultLabel if ($entryLabel =~ /\x{FFFD}|Ã|Â|â/);
            push @entities, {
                reading => $reading,
                key     => $key,
                value   => $displayValue,
                label   => $entryLabel,
                hidden  => $entryConfig->{hidden} ? 1 : 0,
                order   => $entryConfig->{order},
            };
        }
        next if (!@entities);

        if ($prefix eq "location") {
            my ($road) = grep { $_->{key} eq "road" } @entities;
            my ($houseNumber) = grep { $_->{key} eq "house_number" } @entities;
            if ($road) {
                $road->{value} = join(" ", grep { defined($_) && $_ ne "" }
                    $road->{value}, $houseNumber ? $houseNumber->{value} : undef);
                $road->{label} = "Straße";
            } elsif ($houseNumber) {
                $houseNumber->{key} = "road";
                $houseNumber->{label} = "Straße";
            }

            my ($city) = grep { $_->{key} eq "city" } @entities;
            my ($postcode) = grep { $_->{key} eq "postcode" } @entities;
            if ($city) {
                $city->{value} = join(" ", grep { defined($_) && $_ ne "" }
                    $postcode ? $postcode->{value} : undef, $city->{value});
                $city->{label} = "Ort";
            } elsif ($postcode) {
                $postcode->{key} = "city";
                $postcode->{label} = "Ort";
            }

            @entities = grep { $_->{key} ne "house_number" && $_->{key} ne "postcode" } @entities;
        }

        my %locationOrder = (
            road        => 0,
            house_number => 1,
            postcode    => 2,
            city        => 3,
            state       => 4,
            country     => 5,
            latitude    => 6,
            longitude   => 7,
            timestamp   => 8,
        );
        my @ordered = sort {
            $prefix eq "location"
                ? (($locationOrder{$a->{key}} // 999) <=> ($locationOrder{$b->{key}} // 999)
                    || $a->{key} cmp $b->{key})
                : ((defined($a->{order}) ? $a->{order} : 9999) <=> (defined($b->{order}) ? $b->{order} : 9999)
                    || $a->{key} cmp $b->{key})
        } @entities;

        my $tileVisible = !exists($tileVisibility->{$prefix}) || $tileVisibility->{$prefix};
        $html .= "<div class='tile" . ($tileVisible ? "" : " tile-hidden") . "' data-prefix='$prefix'><h2>"
            . VolvoConnect_HtmlEscape($labels{$prefix} // $prefix)
            . "<span class='tile-edit-controls'><label>anzeigen <input type='checkbox' class='tile-vis-toggle'"
            . ($tileVisible ? " checked" : "") . "></label></span>"
            . "<button type='button' class='tile-move-toggle' aria-label='Kacheln verschieben' aria-pressed='false' title='Kacheln verschieben' onclick='toggleTileReorderMode()'><span aria-hidden='true'>&#8598;&#8599;<br>&#8601;&#8600;</span></button></h2>";
        for my $entity (@ordered) {
            my $hiddenClass = $entity->{hidden} ? " row-hidden" : "";
            $html .= "<div class='row$hiddenClass' draggable='true' data-reading='" . $entity->{reading} . "'>"
                . "<span class='edit-controls'>"
                . "<span class='drag-handle' title=\"Ziehen zum Verschieben\">&#9776;</span>"
                . "<input type='checkbox' class='vis-toggle'" . ($entity->{hidden} ? "" : " checked") . ">"
                . "</span>"
                . "<input type='text' class='key key-input' value=\"" . VolvoConnect_HtmlEscape($entity->{label}) . "\" readonly>"
                . "<span class='val'>" . VolvoConnect_ValueHtml($entity->{value}) . "</span>"
                . "</div>";
        }
        if ($prefix eq "location"
            && defined($hash->{READINGS}{location_latitude}{VAL})
            && defined($hash->{READINGS}{location_longitude}{VAL})
            && $hash->{READINGS}{location_latitude}{VAL} =~ /^-?\d+(?:\.\d+)?$/
            && $hash->{READINGS}{location_longitude}{VAL} =~ /^-?\d+(?:\.\d+)?$/) {
            my $latitude = $hash->{READINGS}{location_latitude}{VAL};
            my $longitude = $hash->{READINGS}{location_longitude}{VAL};
            my $bbox = sprintf("%.6f,%.6f,%.6f,%.6f",
                $longitude - 0.01, $latitude - 0.006,
                $longitude + 0.01, $latitude + 0.006);
            my $mapUrl = "https://www.openstreetmap.org/export/embed.html"
                . "?bbox=" . urlEncode($bbox)
                . "&layer=mapnik&marker=" . urlEncode($latitude . "," . $longitude);
            $html .= "<div class='location-map'><iframe loading='lazy' title='Fahrzeugstandort' src='"
                . VolvoConnect_HtmlEscape($mapUrl) . "'></iframe></div>";
        }
        $html .= "</div>";
    }

    my @vehicleImages = (
        ["Außenansicht", $hash->{READINGS}{vehicle_images_exteriorImageUrl}{VAL}],
        ["Innenansicht", $hash->{READINGS}{vehicle_images_internalImageUrl}{VAL}],
    );
    @vehicleImages = grep { defined($_->[1]) && $_->[1] =~ m{^https?://}i } @vehicleImages;
    if (@vehicleImages) {
        $html .= "<div class='vehicle-image-tile'><div class='vehicle-image-gallery count-"
            . scalar(@vehicleImages) . "'>";
        for my $vehicleImage (@vehicleImages) {
            $html .= "<img class='vehicle-image' src=\""
                . VolvoConnect_HtmlEscape($vehicleImage->[1])
                . "\" alt=\"" . VolvoConnect_HtmlEscape($vehicleImage->[0])
                . "\" loading=\"lazy\">";
        }
        $html .= "</div></div>";
    }

    $html .= "</div></div>";

    $html .= "<script>"
        . "setInterval(function(){"
        . "  if(!document.body.classList.contains('edit-mode')) window.location.reload();"
        . "}, " . ($dashboardRefresh * 1000) . ");"
        . "var dashboard=document.querySelector('.wrap[data-device]');"
        . "var actionStatus=dashboard&&dashboard.querySelector('.action-status');"
        . "var csrf=dashboard&&dashboard.getAttribute('data-csrf')||'';"
        . "var actionStatusTimer=null;"
        . "function showActionStatus(message){if(!actionStatus)return;window.clearTimeout(actionStatusTimer);actionStatus.textContent=message;actionStatusTimer=window.setTimeout(function(){actionStatus.textContent='';},15000);}"
        . "if(!csrf){var csrfCookie=document.cookie.match(/(?:^|;\\s*)fwcsrf=([^;]+)/);csrf=csrfCookie?decodeURIComponent(csrfCookie[1]):'';}"
        . "document.querySelectorAll('.actions [data-action]').forEach(function(button){"
        . "  button.addEventListener('click',function(){"
        . "    if(!dashboard||button.disabled)return;"
        . "    window.clearTimeout(button._highlightTimer);button.classList.add('action-highlight');"
        . "    button._highlightTimer=window.setTimeout(function(){button.classList.remove('action-highlight');button._highlightTimer=null;},15000);"
        . "    var path=dashboard.getAttribute('data-fhem-path')||'/fhem';"
        . "    var command='set '+dashboard.getAttribute('data-device')+' '+button.getAttribute('data-action');"
        . "    var url=path+'?cmd='+encodeURIComponent(command)+'&XHR=1'+(csrf?'&fwcsrf='+encodeURIComponent(csrf):'');"
        . "    button.disabled=true;if(actionStatus)actionStatus.textContent='Befehl wird an FHEM übergeben...';"
        . "    fetch(url,{cache:'no-store',credentials:'same-origin'}).then(function(response){"
        . "      return response.text().then(function(text){if(!response.ok||/error|unknown|forbidden/i.test(text))throw new Error(text||'HTTP '+response.status);return text;});"
        . "    }).then(function(){showActionStatus('Befehl an FHEM \\u00fcbergeben. Die Fahrzeugreaktion kann verz\\u00f6gert erfolgen.');"
        . "    }).catch(function(error){showActionStatus('Aktion fehlgeschlagen: '+error.message);"
        . "    }).then(function(){button.disabled=false;});"
        . "  });"
        . "});"
        . "function toggleEdit(){"
        . "  if(document.body.classList.contains('tile-reorder-mode'))setTileReorderMode(false);"
        . "  document.body.classList.toggle('edit-mode');"
        . "  document.querySelectorAll('.key-input').forEach(function(el){ el.readOnly = !document.body.classList.contains('edit-mode'); });"
        . "}"
        . "var dragSrc = null;"
        . "document.querySelectorAll('.row').forEach(function(row){"
        . "  row.addEventListener('dragstart', function(e){"
        . "    if(!document.body.classList.contains('edit-mode')){ e.preventDefault(); return; }"
        . "    dragSrc = row; e.dataTransfer.effectAllowed = 'move';"
        . "  });"
        . "  row.addEventListener('dragover', function(e){"
        . "    if(document.body.classList.contains('edit-mode')) e.preventDefault();"
        . "  });"
        . "  row.addEventListener('drop', function(e){"
        . "    e.preventDefault();"
        . "    if(!dragSrc || dragSrc === row) return;"
        . "    if(dragSrc.closest('.tile') !== row.closest('.tile')) return;"
        . "    row.parentNode.insertBefore(dragSrc, row);"
        . "    dragSrc = null;"
        . "  });"
        . "});"
        . "var tileDragSrc = null;"
        . "var tileDragPointerId = null;"
        . "var tileDragStartX = 0;"
        . "var tileDragStartY = 0;"
        . "var tileDragActive = false;"
        . "function finishTileDrag(){"
        . "  if(tileDragSrc) tileDragSrc.classList.remove('tile-dragging');"
        . "  tileDragSrc = null; tileDragPointerId = null; tileDragActive = false;"
        . "}"
        . "function setTileReorderMode(active){"
        . "  if(!active)finishTileDrag();"
        . "  document.body.classList.toggle('tile-reorder-mode',active);"
        . "  document.querySelectorAll('.tile-move-toggle').forEach(function(button){button.setAttribute('aria-pressed',active?'true':'false');button.title=active?'Verschieben beenden':'Kacheln verschieben';button.setAttribute('aria-label',button.title);});"
        . "}"
        . "function toggleTileReorderMode(){setTileReorderMode(!document.body.classList.contains('tile-reorder-mode'));}"
        . "document.addEventListener('keydown',function(e){if(e.key==='Escape'&&document.body.classList.contains('tile-reorder-mode'))setTileReorderMode(false);});"
        . "document.querySelectorAll('.tile[data-prefix]').forEach(function(tile){"
        . "  tile.addEventListener('pointerdown',function(e){"
        . "    if(!document.body.classList.contains('tile-reorder-mode')||tileDragSrc||e.target.closest('.tile-move-toggle'))return;"
        . "    e.preventDefault();tileDragSrc=tile;tileDragPointerId=e.pointerId;tileDragStartX=e.clientX;tileDragStartY=e.clientY;tileDragActive=false;"
        . "  });"
        . "});"
        . "document.addEventListener('pointermove',function(e){"
        . "  if(!tileDragSrc||e.pointerId!==tileDragPointerId)return;"
        . "  if(!tileDragActive){if(Math.hypot(e.clientX-tileDragStartX,e.clientY-tileDragStartY)<6)return;tileDragActive=true;tileDragSrc.classList.add('tile-dragging');}"
        . "  e.preventDefault();"
        . "  var target=document.elementFromPoint(e.clientX,e.clientY);"
        . "  var tile=target&&target.closest('.tile[data-prefix]');"
        . "  if(!tile||tile===tileDragSrc||tile.parentNode!==tileDragSrc.parentNode)return;"
        . "  var rect=tile.getBoundingClientRect();"
        . "  if(e.clientY<rect.top+rect.height/2)tile.parentNode.insertBefore(tileDragSrc,tile);"
        . "  else tile.parentNode.insertBefore(tileDragSrc,tile.nextSibling);"
        . "});"
        . "document.addEventListener('pointerup',function(e){if(tileDragSrc&&e.pointerId===tileDragPointerId)finishTileDrag();});"
        . "document.addEventListener('pointercancel',function(e){if(tileDragSrc&&e.pointerId===tileDragPointerId)finishTileDrag();});"
        . "window.addEventListener('blur',finishTileDrag);"
        . "function asciiSafeJson(obj){"
        . "  return JSON.stringify(obj).replace(/[\\u0080-\\uffff]/g, function(c){"
        . "    return '\\\\u' + ('000' + c.charCodeAt(0).toString(16)).slice(-4);"
        . "  });"
        . "}"
        . "function saveDashboardConfig(){"
        . "  var config = {};"
        . "  config._tileOrder = [];"
        . "  config._tileVisibility = {};"
        . "  document.querySelectorAll('.tile[data-prefix]').forEach(function(tile){ config._tileOrder.push(tile.getAttribute('data-prefix')); });"
        . "  document.querySelectorAll('.tile[data-prefix]').forEach(function(tile){"
        . "    var visibility = tile.querySelector('.tile-vis-toggle');"
        . "    config._tileVisibility[tile.getAttribute('data-prefix')] = visibility && visibility.checked ? 1 : 0;"
        . "  });"
        . "  document.querySelectorAll('.tile').forEach(function(tile){"
        . "    var rows = tile.querySelectorAll('.row');"
        . "    rows.forEach(function(row, idx){"
        . "      var key = row.getAttribute('data-reading');"
        . "      if(!key) return;"
        . "      var labelInput = row.querySelector('.key-input');"
        . "      var visCheckbox = row.querySelector('.vis-toggle');"
        . "      config[key] = {"
        . "        label: labelInput ? labelInput.value : '',"
        . "        hidden: (visCheckbox && !visCheckbox.checked) ? 1 : 0,"
        . "        order: idx"
        . "      };"
        . "    });"
        . "  });"
        . "  var json = asciiSafeJson(config);"
        . "  var b64 = btoa(json);"
        . "  var url = '/fhem?cmd=set%20" . urlEncode($name) . "%20saveDashboardConfig%20' + b64 + '&XHR=1';"
        . "  fetch(url).then(function(response){"
        . "    if(!response.ok) throw new Error('Speichern fehlgeschlagen');"
        . "    document.querySelectorAll('.tile[data-prefix]').forEach(function(tile){"
        . "      var visibility = tile.querySelector('.tile-vis-toggle');"
        . "      tile.classList.toggle('tile-hidden', !(visibility && visibility.checked));"
        . "    });"
        . "    document.body.classList.remove('edit-mode');"
        . "    setTileReorderMode(false);"
        . "    document.querySelectorAll('.key-input').forEach(function(el){ el.readOnly = true; });"
        . "  }).catch(function(error){ window.alert(error.message); });"
        . "}"
        . "</script>";

    $html .= "</body></html>";
    return $html;
}

sub VolvoConnect_Get($$@) {
    my ($hash, $name, $cmd, @args) = @_;

    if ($cmd eq "_dashboardURL") {
        my $fhemPath = defined($main::FW_ME) && $main::FW_ME ne "" ? $main::FW_ME : "/fhem";
        $fhemPath =~ s{/$}{};
        my $webName = $main::FW_wname;
        my $webHash = defined($webName) ? $main::defs{$webName} : undef;
        my $scheme = $webName && AttrVal($webName, "HTTPS", 0) ? "https" : "http";
        my $host = $main::FW_httpheader{Host};
        my $forwardedProto = $main::FW_httpheader{"X-Forwarded-Proto"};
        if (defined($forwardedProto) && $forwardedProto =~ /^\s*(https?)(?:\s|,|$)/i) {
            $scheme = lc($1);
        }
        if (!defined($host) || $host eq "") {
            my $port = $webHash && defined($webHash->{PORT}) ? $webHash->{PORT} : undef;
            $host = "localhost" . (defined($port) && $port ne "" ? ":$port" : "");
        }
        return $scheme . "://" . $host . $fhemPath . "/VolvoConnect/" . urlEncode($name);
    }

    if ($cmd eq "summary") {
        return "authStatus: " . ReadingsVal($name, "authStatus", "unbekannt") . "\n"
            . "lastUpdate: " . ReadingsVal($name, "lastUpdate", "-") . "\n"
            . "lastError: " . ReadingsVal($name, "lastError", "-") . "\n"
            . "lastCommand: " . ReadingsVal($name, "last_command", "-")
            . " (" . ReadingsVal($name, "command_state", "-") . ")";
    }

    if ($cmd eq "list") {
        my $out = CommandList(undef, $name);
        # shorten only the known long values (tokens, login URL), keep everything else intact
        $out =~ s/(accessToken\s+)(\S{20})\S*/$1$2.../g;
        $out =~ s/(refreshToken\s+)(\S{20})\S*/$1$2.../g;
        $out =~ s/(loginUrl\s+)(\S{40})\S*/$1$2.../g;
        return $out;
    }

    if ($cmd eq "tokenInfo") {
        my $validUntil = $hash->{helper}{tokenValidUntil};
        my $remaining  = defined($validUntil) ? $validUntil - time() : undef;
        return "accessToken: " . (defined($hash->{helper}{accessToken}) && $hash->{helper}{accessToken} ne "" ? "vorhanden" : "fehlt") . "\n"
            . "refreshToken: " . (defined($hash->{helper}{refreshToken}) && $hash->{helper}{refreshToken} ne "" ? "vorhanden" : "fehlt") . "\n"
            . "gültig bis: " . (defined($validUntil) ? FmtDateTime($validUntil) : "-") . "\n"
            . "verbleibend: " . (defined($remaining) ? ($remaining > 0 ? "${remaining}s" : "abgelaufen") : "-");
    }

    if ($cmd eq "scopes") {
        my @scopeAttrs = grep { /^scope_/ } map { (split(":", $_))[0] } split(" ", $modules{VolvoConnect}{AttrList});
        my @enabled  = grep { VolvoConnect_ScopeEnabled($name, $_) } @scopeAttrs;
        my @disabled = grep { !VolvoConnect_ScopeEnabled($name, $_) } @scopeAttrs;
        return "aktiviert:\n" . (@enabled ? join("\n", map { "  $_" } @enabled) : "  -") . "\n\n"
            . "deaktiviert:\n" . (@disabled ? join("\n", map { "  $_" } @disabled) : "  -");
    }

    if ($cmd eq "_showDashboard") {
        return VolvoConnect_BuildDashboard($hash);
    }

    if ($cmd eq "_showEntityConfig") {
        return VolvoConnect_BuildEntityConfig($hash);
    }

    return "Unknown argument $cmd, choose one of _dashboardURL:noArg summary:noArg list:noArg tokenInfo:noArg scopes:noArg _showDashboard:noArg _showEntityConfig:noArg";
}


sub VolvoConnect_SendCommand($$$;$) {
    my ($hash, $command, $params, $commandRetry) = @_;
    my $name = $hash->{NAME};

    my $vin = AttrVal($name, "vin", "");
    my $accessToken = $hash->{helper}{accessToken};
    my $refreshToken = $hash->{helper}{refreshToken};
    my $vcc_api_key = AttrVal($name, "vcc_api_key", "");

    if ((!defined($accessToken) || $accessToken eq "")
        && (!defined($refreshToken) || $refreshToken eq "")) {
        Log3 $name, 2, "VolvoConnect ($name) - No access token available for command: $command";
        readingsSingleUpdate($hash, "lastError", "Kein Access Token vorhanden für Befehl: $command", 1);
        return;
    }

    if (!$commandRetry && defined($refreshToken) && $refreshToken ne ""
        && (!defined($accessToken) || $accessToken eq ""
            || ($hash->{helper}{tokenValidUntil} || 0) <= time())) {
        $hash->{helper}{pendingCommand} = { command => $command, params => $params };
        VolvoConnect_RefreshAccessToken($hash, $refreshToken)
            if (!$hash->{helper}{tokenRefreshInFlight});
        return;
    }

    my $url;
    my $payload;

    # Command-specific URL and payload
    if ($command eq "horn") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/honk";
        $payload = "";
    }
    elsif ($command eq "lock") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/lock";
        $payload = "";
    }
    elsif ($command eq "unlock") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/unlock";
        $payload = "";
    }
    elsif ($command eq "climate") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/climatization-start";
        $payload = "";
    }
    elsif ($command eq "climate_stop") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/climatization-stop";
        $payload = "";
    }
    elsif ($command eq "charge_start") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/charging-start";
        $payload = "{}";
    }
    elsif ($command eq "charge_stop") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/charging-stop";
        $payload = "{}";
    }
    elsif ($command eq "charge_limit") {
        $url = "https://api.volvocars.com/energy/v1/vehicles/$vin/charging-limit";
        my $limit = $params->{chargeLimit} // 80;
        $payload = '{"chargeLimit":' . $limit . '}';
    }
    elsif ($command eq "precondition") {
        $url = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin/commands/engine-start";
        $payload = '{"runtimeMinutes":10}';
    }
    else {
        Log3 $name, 2, "VolvoConnect ($name) - Unknown command: $command";
        return;
    }

    my $param = {
        url     => $url,
        timeout => 30,
        method  => "POST",
        header  => "Authorization: Bearer $accessToken\r\n"
                 . "vcc-api-key: $vcc_api_key\r\n"
                 . "Content-Type: application/json",
        data    => $payload,
        hash    => $hash,
        command => $command,
        commandParams => $params,
        commandRetry => $commandRetry ? 1 : 0,
        callback => \&VolvoConnect_CommandCallback
    };

    Log3 $name, 4, "VolvoConnect ($name) - Sending command: $command to $url";
    HttpUtils_NonblockingGet($param);
}

sub VolvoConnect_CommandCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $command = $param->{command};

    Log3 $name, 4, "VolvoConnect ($name) - Command '$command' response received.";

    if (defined($param->{code}) && $param->{code} eq "401"
        && !$param->{commandRetry}
        && defined($hash->{helper}{refreshToken})
        && $hash->{helper}{refreshToken} ne "") {
        $hash->{helper}{pendingCommand} = { command => $command, params => $param->{commandParams} };
        $hash->{helper}{pendingCommand}{params} = {}
            if (!defined($hash->{helper}{pendingCommand}{params}));
        VolvoConnect_RefreshAccessToken($hash, $hash->{helper}{refreshToken})
            if (!$hash->{helper}{tokenRefreshInFlight});
        Log3 $name, 2, "VolvoConnect ($name) - Access token rejected for '$command'; refreshing and retrying once.";
        return;
    }

    if ($err ne "") {
        Log3 $name, 2, "VolvoConnect ($name) - Error executing command '$command': $err";
        readingsSingleUpdate($hash, "command_state", "error_$command", 1);
        readingsSingleUpdate($hash, "lastErrorCode", $param->{code} // "transport", 1);
        readingsSingleUpdate($hash, "lastError", "Befehl $command: $err", 1);
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (defined($param->{code}) && $param->{code} =~ /^2/ && (!defined($data) || $data eq "")) {
        readingsSingleUpdate($hash, "command_state", "success_$command", 1);
        readingsSingleUpdate($hash, "last_command", $command, 1);
        Log3 $name, 4, "VolvoConnect ($name) - Command '$command' accepted (HTTP $param->{code}).";
        return;
    }

    if (!$decoded) {
        Log3 $name, 2, "VolvoConnect ($name) - Command response was not valid JSON.";
        readingsSingleUpdate($hash, "command_state", "parse_error_$command", 1);
        readingsSingleUpdate($hash, "lastErrorCode", $param->{code} // "unknown", 1);
        readingsSingleUpdate($hash, "lastError", "Befehl $command: Antwort war kein gültiges JSON", 1);
        return;
    }

    if (exists($decoded->{error})) {
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : ($decoded->{error} // "unbekannter Fehler");
        my $description = $decoded->{error_description} // "";
        Log3 $name, 2, "VolvoConnect ($name) - Command API error (HTTP " . ($param->{code} // "unknown") . "): $error / $description";
        readingsSingleUpdate($hash, "command_state", "api_error_$command", 1);
        readingsSingleUpdate($hash, "lastErrorCode", $param->{code} // "unknown", 1);
        readingsSingleUpdate($hash, "lastError", "Befehl $command: $error" . ($description ne "" ? " / $description" : ""), 1);
        return;
    }

    # Success
    readingsSingleUpdate($hash, "command_state", "success_$command", 1);
    readingsSingleUpdate($hash, "last_command", $command, 1);

    Log3 $name, 3, "VolvoConnect ($name) - Command '$command' executed successfully.";

    # Trigger data refresh after command execution
    RemoveInternalTimer($hash);
    InternalTimer(time() + 2, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
}

sub VolvoConnect_GenerateChallengeS256($) {
    my ($verifier) = @_;
    my $binary_sha = sha256($verifier);
    my $b64 = encode_base64($binary_sha, "");
    $b64 =~ tr/+\//-_/;
    $b64 =~ s/=+$//;
    return $b64;
}

sub VolvoConnect_CheckAuthAndFetch($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if (IsDisabled($name)) {
        delete $hash->{helper}{forceFullUpdate};
        readingsSingleUpdate($hash, "state", "disabled", 1);
        VolvoConnect_Reschedule($hash, 60);
        return;
    }

    if (!defined($hash->{helper}{accessToken})
        || !defined($hash->{helper}{refreshToken})) {
        VolvoConnect_LoadTokens($hash);
    }

    my $vin           = AttrVal($name, "vin", undef);
    my $client_id     = AttrVal($name, "client_id", undef);
    my $client_secret = AttrVal($name, "client_secret", undef);
    my $vcc_api_key   = AttrVal($name, "vcc_api_key", undef);
    my $redirect_uri  = AttrVal($name, "redirect_uri", undef);

    my @missing;
    push(@missing, "vin")           if (!defined($vin)           || $vin eq ""           || $vin eq $DUMMY_VIN);
    push(@missing, "client_id")     if (!defined($client_id)     || $client_id eq ""     || $client_id eq $DUMMY_CLIENT_ID);
    push(@missing, "client_secret") if (!defined($client_secret) || $client_secret eq "" || $client_secret eq $DUMMY_SECRET);
    push(@missing, "vcc_api_key")   if (!defined($vcc_api_key)   || $vcc_api_key eq ""   || $vcc_api_key eq $DUMMY_VCC_KEY);
    push(@missing, "redirect_uri")  if (!defined($redirect_uri)  || $redirect_uri eq ""  || $redirect_uri eq $DUMMY_REDIRECT);

    if (@missing > 0) {
        delete $hash->{helper}{forceFullUpdate};
        my $error_msg = "Please replace dummy values for: " . join(", ", @missing);
        readingsSingleUpdate($hash, "state", $error_msg, 1);
        VolvoConnect_Reschedule($hash, 30);
        return;
    }

    my $accessToken     = $hash->{helper}{accessToken};
    my $refreshToken    = $hash->{helper}{refreshToken};
    my $tokenValidUntil = $hash->{helper}{tokenValidUntil} || 0;
    my $now             = time();

    Log3 $name, 4, "VolvoConnect ($name) - Auth decision: access="
        . (defined($accessToken) && $accessToken ne "" ? "yes" : "no")
        . ", refresh=" . (defined($refreshToken) && $refreshToken ne "" ? "yes" : "no")
        . ", validUntil=$tokenValidUntil, now=$now.";

    VolvoConnect_SetAuthStatus($hash, "authenticated")
        if (defined($accessToken) && $accessToken ne "");

    if (defined($accessToken) && $accessToken ne "" && $now < $tokenValidUntil) {
        my $remaining = $tokenValidUntil - $now;
        VolvoConnect_SetAuthStatus($hash, "authenticated");
        Log3 $name, 4, "VolvoConnect ($name) - Using cached Access Token (valid for another $remaining sec).";
        VolvoConnect_FetchVehicleData($hash, $accessToken);
        VolvoConnect_Reschedule($hash, AttrVal($name, "interval", 300));
        return;
    }

    if (defined($refreshToken) && $refreshToken ne "") {
        VolvoConnect_SetAuthStatus($hash, "token_refreshing");
        Log3 $name, 4, "VolvoConnect ($name) - Access Token expired. Refreshing token...";
        VolvoConnect_RefreshAccessToken($hash, $refreshToken);
        return;
    }

    my $authCodeAttr = AttrVal($name, "authCode", undef);
    Log3 $name, 4, "VolvoConnect ($name) - Login decision: authCode="
        . (defined($authCodeAttr) && $authCodeAttr ne "" ? "present" : "missing") . ".";
    if (!defined($authCodeAttr) || $authCodeAttr eq "") {
        my $code_challenge = VolvoConnect_GenerateChallengeS256($GLOBAL_VERIFIER);

        my $enc_client_id    = urlEncode($client_id);
        my $enc_redirect_uri = urlEncode($redirect_uri);
        my @scopes = ("openid", "energy:state:read");
        push(@scopes, "energy:capability:read")
            if (VolvoConnect_ScopeEnabled($name, "scope_capabilities"));
        push(@scopes, "conve:warnings")
            if (VolvoConnect_ScopeEnabled($name, "scope_warnings"));
        push(@scopes, "conve:brake_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_brakes"));
        push(@scopes, "conve:doors_status", "conve:lock_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_doors"));
        push(@scopes, "conve:windows_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_windows"));
        push(@scopes, "conve:engine_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_engine_status"));
        push(@scopes, "conve:vehicle_relation")
            if (VolvoConnect_ScopeEnabled($name, "scope_vehicle_relation"));
        push(@scopes, "conve:commands")
            if (VolvoConnect_ScopeEnabled($name, "scope_commands"));
        push(@scopes, "conve:command_accessibility")
            if (VolvoConnect_ScopeEnabled($name, "scope_command_accessibility"));
        push(@scopes, "conve:honk_flash")
            if (VolvoConnect_ScopeEnabled($name, "scope_honk_flash"));
        push(@scopes, "conve:lock")
            if (VolvoConnect_ScopeEnabled($name, "scope_lock"));
        push(@scopes, "conve:unlock")
            if (VolvoConnect_ScopeEnabled($name, "scope_unlock"));
        push(@scopes, "conve:climatization_start_stop")
            if (VolvoConnect_ScopeEnabled($name, "scope_climatization"));
        push(@scopes, "conve:engine_start_stop")
            if (VolvoConnect_ScopeEnabled($name, "scope_engine_commands"));
        push(@scopes, "conve:fuel_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_fuel"));
        push(@scopes, "conve:battery_charge_level")
            if (VolvoConnect_ScopeEnabled($name, "scope_battery_charge"));
        push(@scopes, "conve:odometer_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_odometer"));
        push(@scopes, "conve:trip_statistics")
            if (VolvoConnect_ScopeEnabled($name, "scope_statistics"));
        push(@scopes, "conve:tyre_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_tyres"));
        push(@scopes, "conve:diagnostics_engine_status")
            if (VolvoConnect_ScopeEnabled($name, "scope_engine_diagnostics"));
        push(@scopes, "conve:diagnostics_workshop")
            if (VolvoConnect_ScopeEnabled($name, "scope_workshop_diagnostics"));
        push(@scopes, "location:read")
            if (VolvoConnect_ScopeEnabled($name, "scope_location"));
        my $enc_scopes = urlEncode(join(" ", @scopes));
        my $enc_challenge    = urlEncode($code_challenge);

        my $loginUrl =
            "https://volvoid.eu.volvocars.com/as/authorization.oauth2"
            . "?response_type=code"
            . "&client_id=" . $enc_client_id
            . "&redirect_uri=" . $enc_redirect_uri
            . "&scope=" . $enc_scopes
            . "&state=fhemstate"
            . "&code_challenge=" . $enc_challenge
            . "&code_challenge_method=S256";

        $hash->{helper}{loginUrl} = $loginUrl;

        VolvoConnect_SetAuthStatus($hash, "auth_required");
    }

    VolvoConnect_Reschedule($hash, 60);
}

sub VolvoConnect_ExchangeCodeForToken($$) {
    my ($hash, $code) = @_;
    my $name = $hash->{NAME};

    my $client_id     = AttrVal($name, "client_id", "");
    my $client_secret = AttrVal($name, "client_secret", "");
    my $redirect_uri  = AttrVal($name, "redirect_uri", "");

    my $credentials = $client_id . ":" . $client_secret;
    my $basicAuth   = encode_base64($credentials, "");
    $basicAuth =~ s/\s+//g;

    my $url = "https://volvoid.eu.volvocars.com/as/token.oauth2";

    my $payload =
        "grant_type=authorization_code"
        . "&code=" . urlEncode($code)
        . "&redirect_uri=" . urlEncode($redirect_uri)
        . "&code_verifier=" . urlEncode($GLOBAL_VERIFIER);

    my $param = {
        url     => $url,
        timeout => 15,
        method  => "POST",
        header  => "Content-Type: application/x-www-form-urlencoded\r\n"
                 . "Authorization: Basic " . $basicAuth,
        data    => $payload,
        hash    => $hash,
        callback => \&VolvoConnect_TokenCallback
    };

    HttpUtils_NonblockingGet($param);
}

sub VolvoConnect_RefreshAccessToken($$) {
    my ($hash, $old_refresh_token) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{tokenRefreshInFlight} = 1;

    my $client_id     = AttrVal($name, "client_id", "");
    my $client_secret = AttrVal($name, "client_secret", "");
    my $credentials   = $client_id . ":" . $client_secret;
    my $basicAuth     = encode_base64($credentials, "");
    $basicAuth =~ s/\s+//g;

    my $url = "https://volvoid.eu.volvocars.com/as/token.oauth2";

    my $payload =
        "grant_type=refresh_token"
        . "&refresh_token=" . urlEncode($old_refresh_token);

    my $param = {
        url     => $url,
        timeout => 15,
        method  => "POST",
        header  => "Content-Type: application/x-www-form-urlencoded\r\n"
                 . "Authorization: Basic " . $basicAuth,
        data    => $payload,
        hash    => $hash,
        callback => \&VolvoConnect_TokenCallback
    };

    HttpUtils_NonblockingGet($param);
}

sub VolvoConnect_TokenCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    $hash->{helper}{authCodeProcessing} = 0;
    delete $hash->{helper}{tokenRefreshInFlight};

    Log3 $name, 4, "VolvoConnect ($name) - Token response received.";

    if ($err ne "") {
        delete $hash->{helper}{pendingCommand};
        Log3 $name, 2, "VolvoConnect ($name) - Auth Error: $err";
        readingsSingleUpdate($hash, "lastError", "Auth-Fehler: $err", 1);
        VolvoConnect_SetAuthStatus($hash, "error");
        VolvoConnect_Reschedule($hash, 30);
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        delete $hash->{helper}{pendingCommand};
        Log3 $name, 2, "VolvoConnect ($name) - Token response was not valid JSON.";
        readingsSingleUpdate($hash, "lastError", "Token-Antwort war kein gültiges JSON.", 1);
        VolvoConnect_SetAuthStatus($hash, "error");
        VolvoConnect_Reschedule($hash, 30);
        return;
    }

    if (exists($decoded->{error})) {
        delete $hash->{helper}{pendingCommand};
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : $decoded->{error};
        my $description = $decoded->{error_description} // "";
        Log3 $name, 2, "VolvoConnect ($name) - OAuth error: $error / $description";
        readingsSingleUpdate($hash, "lastError", "OAuth-Fehler: $error / $description", 1);
        VolvoConnect_SetAuthStatus($hash, "error");
        VolvoConnect_Reschedule($hash, 30);
        return;
    }

    if (!$decoded->{access_token}) {
        delete $hash->{helper}{pendingCommand};
        Log3 $name, 2, "VolvoConnect ($name) - Token response missing access_token.";
        readingsSingleUpdate($hash, "lastError", "Token-Antwort enthält keinen access_token.", 1);
        VolvoConnect_SetAuthStatus($hash, "error");
        VolvoConnect_Reschedule($hash, 30);
        return;
    }

    my $expires_in = $decoded->{expires_in} // 3600;
    my $refresh_margin = $expires_in > 600 ? 600 : int($expires_in / 10);
    my $valid_until = time() + $expires_in - $refresh_margin;

    $hash->{helper}{accessToken} = $decoded->{access_token};
    $hash->{helper}{tokenValidUntil} = $valid_until;
    $hash->{helper}{refreshToken} = $decoded->{refresh_token}
        if (exists($decoded->{refresh_token}));
    VolvoConnect_SaveTokens($hash);

    VolvoConnect_ClearAuthCode($hash);
    VolvoConnect_SetAuthStatus($hash, "authenticated");
    Log3 $name, 3, "VolvoConnect ($name) - Token request successful.";
    VolvoConnect_FetchVehicleData($hash, $decoded->{access_token});
    VolvoConnect_Reschedule($hash, AttrVal($name, "interval", 300));

    my $pendingCommand = delete $hash->{helper}{pendingCommand};
    if ($pendingCommand) {
        VolvoConnect_SendCommand(
            $hash,
            $pendingCommand->{command},
            $pendingCommand->{params} || {},
            1
        );
    }
}

sub VolvoConnect_FetchVehicleData($$) {
    my ($hash, $accessToken) = @_;
    my $name = $hash->{NAME};

    my $vin = AttrVal($name, "vin", "");
    my $vcc_api_key = AttrVal($name, "vcc_api_key", "");
    my $fastInterval = AttrVal($name, "interval", 300);
    my $slowInterval = AttrVal($name, "interval_slow", 1800);
    my $locationInterval = AttrVal($name, "interval_location", 900);
    $fastInterval = 300 if ($fastInterval !~ /^\d+$/ || $fastInterval < 10);
    $slowInterval = 1800 if ($slowInterval !~ /^\d+$/ || $slowInterval < 60);
    $locationInterval = 900 if ($locationInterval !~ /^\d+$/ || $locationInterval < 60);
    my $lastFetchTimes = VolvoConnect_LoadEndpointFetchTimes($hash);
    my $now = time();
    my $forceUpdate = delete $hash->{helper}{forceFullUpdate};

    # Energy Endpoints
    my $stateUrl = "https://api.volvocars.com/energy/v2/vehicles/$vin/state";
    my $capUrl = "https://api.volvocars.com/energy/v2/vehicles/$vin/capabilities";

    # Connected Vehicle endpoints
    my $baseUrl = "https://api.volvocars.com/connected-vehicle/v2/vehicles/$vin";

    my @urls = (
        { url => $stateUrl, callback => \&VolvoConnect_StateCallback, name => "state", cadence => "fast" },
    );

    push(@urls, { url => $capUrl, callback => \&VolvoConnect_CapabilitiesCallback, name => "capabilities", prefix => "capabilities", cadence => "static" })
        if (VolvoConnect_ScopeEnabled($name, "scope_capabilities"));

    push(@urls, { url => "$baseUrl/warnings", callback => \&VolvoConnect_ConnectedDataCallback, name => "warnings", prefix => "warnings", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_warnings"));
    push(@urls, { url => "$baseUrl/brakes", callback => \&VolvoConnect_ConnectedDataCallback, name => "brakes", prefix => "brakes", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_brakes"));
    push(@urls, { url => "$baseUrl/doors", callback => \&VolvoConnect_ConnectedDataCallback, name => "doors", prefix => "doors", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_doors"));
    push(@urls, { url => "$baseUrl/windows", callback => \&VolvoConnect_ConnectedDataCallback, name => "windows", prefix => "windows", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_windows"));
    push(@urls, { url => "$baseUrl/engine-status", callback => \&VolvoConnect_ConnectedDataCallback, name => "engine", prefix => "engine", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_engine_status"));
    push(@urls, { url => "$baseUrl/odometer", callback => \&VolvoConnect_ConnectedDataCallback, name => "odometer", prefix => "odometer", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_odometer"));
    push(@urls, { url => "$baseUrl/statistics", callback => \&VolvoConnect_ConnectedDataCallback, name => "statistics", prefix => "statistics", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_statistics"));
    push(@urls, { url => "$baseUrl/fuel", callback => \&VolvoConnect_ConnectedDataCallback, name => "fuel", prefix => "fuel", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_fuel")
            || VolvoConnect_ScopeEnabled($name, "scope_battery_charge"));
    push(@urls, { url => "$baseUrl/tyres", callback => \&VolvoConnect_ConnectedDataCallback, name => "tyres", prefix => "tyres", cadence => "slow" })
        if (VolvoConnect_ScopeEnabled($name, "scope_tyres"));
    push(@urls, { url => "$baseUrl/engine", callback => \&VolvoConnect_ConnectedDataCallback, name => "engineDiagnostics", prefix => "engineDiagnostics", cadence => "slow" })
        if (VolvoConnect_ScopeEnabled($name, "scope_engine_diagnostics"));
    push(@urls, { url => "$baseUrl/diagnostics", callback => \&VolvoConnect_ConnectedDataCallback, name => "workshopDiagnostics", prefix => "workshopDiagnostics", cadence => "slow" })
        if (VolvoConnect_ScopeEnabled($name, "scope_workshop_diagnostics"));
    push(@urls, { url => "https://api.volvocars.com/location/v1/vehicles/$vin/location", callback => \&VolvoConnect_LocationCallback, name => "location", prefix => "location", cadence => "location" })
        if (VolvoConnect_ScopeEnabled($name, "scope_location"));
    push(@urls, { url => "$baseUrl/command-accessibility", callback => \&VolvoConnect_ConnectedDataCallback, name => "commandAccessibility", prefix => "commandAccessibility", cadence => "fast" })
        if (VolvoConnect_ScopeEnabled($name, "scope_command_accessibility"));
    push(@urls, { url => "$baseUrl/commands", callback => \&VolvoConnect_ConnectedDataCallback, name => "commands", prefix => "commands", cadence => "static" })
        if (VolvoConnect_ScopeEnabled($name, "scope_commands"));
    push(@urls, { url => $baseUrl, callback => \&VolvoConnect_ConnectedDataCallback, name => "vehicle", prefix => "vehicle", cadence => "static" })
        if (VolvoConnect_ScopeEnabled($name, "scope_vehicle_relation"));

    for my $endpoint (@urls) {
        my $lastFetched = $lastFetchTimes->{$endpoint->{name}} || 0;
        my $interval = $endpoint->{cadence} eq "fast" ? $fastInterval
            : $endpoint->{cadence} eq "slow" ? $slowInterval
            : $endpoint->{cadence} eq "location" ? $locationInterval
            : 0;
        my $isDue = $forceUpdate || !$lastFetched
            || ($interval > 0 && $now - $lastFetched >= $interval);
        next if (!$isDue || $hash->{helper}{apiInFlight}{$endpoint->{name}});

        $hash->{helper}{apiInFlight}{$endpoint->{name}} = 1;
        my $param = {
            url      => $endpoint->{url},
            timeout  => 15,
            method   => "GET",
            header   => "Authorization: Bearer $accessToken\r\n"
                      . "vcc-api-key: $vcc_api_key\r\n"
                      . "Accept: application/json",
            hash     => $hash,
            endpointName => $endpoint->{name},
            readingPrefix => $endpoint->{prefix},
            forceUpdate => $forceUpdate ? 1 : 0,
            callback => $endpoint->{callback}
        };

        HttpUtils_NonblockingGet($param);
    }
}

sub VolvoConnect_RecordApiError($$$$) {
    my ($hash, $endpoint, $code, $message) = @_;
    my $name = $hash->{NAME};
    $code = "unknown" if (!defined($code) || $code eq "");
    $message = "Unbekannter API-Fehler" if (!defined($message) || $message eq "");
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastErrorCode", $code);
    readingsBulkUpdate($hash, "lastError", "$endpoint: $message");
    readingsEndUpdate($hash, 1);
    VolvoConnect_EndpointFetchComplete($hash, $endpoint, 0);
    Log3 $name, 2, "VolvoConnect ($name) - $endpoint API error (HTTP $code): $message";
}

sub VolvoConnect_EndpointFetchComplete($$$) {
    my ($hash, $endpoint, $success) = @_;
    delete $hash->{helper}{apiInFlight}{$endpoint};
    VolvoConnect_MarkEndpointFetched($hash, $endpoint) if ($success);
}

sub VolvoConnect_StateCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        VolvoConnect_RecordApiError($hash, "state", $param->{code}, $err);
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        VolvoConnect_RecordApiError($hash, "state", $param->{code}, "Antwort war kein gültiges JSON");
        return;
    }

    if (exists($decoded->{error})) {
        VolvoConnect_RecordApiError($hash, "state", $param->{code}, $decoded->{error});
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;

    readingsBeginUpdate($hash);
    VolvoConnect_FlattenReadings($hash, $root, "state", $param->{forceUpdate});
    readingsBulkUpdate($hash, "lastUpdate", FmtDateTime(time()));
    readingsEndUpdate($hash, 1);
    VolvoConnect_EndpointFetchComplete($hash, "state", 1);

    Log3 $name, 4, "VolvoConnect ($name) - Vehicle state fetched successfully.";
}

sub VolvoConnect_CapabilitiesCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        VolvoConnect_RecordApiError($hash, "capabilities", $param->{code}, $err);
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        VolvoConnect_RecordApiError($hash, "capabilities", $param->{code}, "Antwort war kein gültiges JSON");
        return;
    }

    if (exists($decoded->{error})) {
        VolvoConnect_RecordApiError($hash, "capabilities", $param->{code}, $decoded->{error});
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;

    readingsBeginUpdate($hash);
    VolvoConnect_FlattenReadings($hash, $root, "capabilities", 1);
    readingsBulkUpdate($hash, "lastUpdate", FmtDateTime(time()));
    readingsEndUpdate($hash, 1);
    VolvoConnect_EndpointFetchComplete($hash, "capabilities", 1);

    Log3 $name, 4, "VolvoConnect ($name) - Vehicle capabilities fetched successfully.";
}

sub VolvoConnect_ConnectedDataCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $endpointName = $param->{endpointName};
    my $readingPrefix = $param->{readingPrefix};

    if ($err ne "") {
        VolvoConnect_RecordApiError($hash, $endpointName, $param->{code}, $err);
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        VolvoConnect_RecordApiError($hash, $endpointName, $param->{code}, "Antwort war kein gültiges JSON");
        return;
    }

    if (exists($decoded->{error})) {
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : $decoded->{error};
        VolvoConnect_RecordApiError($hash, $endpointName, $param->{code}, $error);
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;
    readingsBeginUpdate($hash);
    VolvoConnect_FlattenReadings($hash, $root, $readingPrefix, $param->{forceUpdate});
    readingsBulkUpdate($hash, "lastUpdate", FmtDateTime(time()));
    readingsEndUpdate($hash, 1);
    VolvoConnect_EndpointFetchComplete($hash, $endpointName, 1);
}

sub VolvoConnect_LocationCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        VolvoConnect_RecordApiError($hash, "location", $param->{code}, $err);
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded || ref($decoded) ne "HASH") {
        VolvoConnect_RecordApiError($hash, "location", $param->{code}, "Antwort war kein gültiges JSON");
        return;
    }
    if (exists($decoded->{error})) {
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : $decoded->{error};
        VolvoConnect_RecordApiError($hash, "location", $param->{code}, $error);
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;
    my $coordinates = ref($root->{geometry}) eq "HASH" ? $root->{geometry}{coordinates} : undef;
    if (ref($coordinates) ne "ARRAY" || @{$coordinates} < 2
        || !defined($coordinates->[0]) || !defined($coordinates->[1])
        || $coordinates->[0] !~ /^-?\d+(?:\.\d+)?$/
        || $coordinates->[1] !~ /^-?\d+(?:\.\d+)?$/) {
        VolvoConnect_RecordApiError($hash, "location", $param->{code}, "GeoJSON enthält keine gültigen Koordinaten");
        return;
    }

    my ($longitude, $latitude, $altitude) = @{$coordinates}[0 .. 2];
    my $properties = ref($root->{properties}) eq "HASH" ? $root->{properties} : {};
    my $locationKey = sprintf("%.5f,%.5f", $latitude, $longitude);

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "location_longitude", $longitude);
    readingsBulkUpdate($hash, "location_latitude", $latitude);
    readingsBulkUpdate($hash, "location_altitude", $altitude) if (defined($altitude));
    readingsBulkUpdate($hash, "location_heading", $properties->{heading})
        if (defined($properties->{heading}));
    readingsBulkUpdate($hash, "location_timestamp", $properties->{timestamp})
        if (defined($properties->{timestamp}));
    readingsEndUpdate($hash, 1);
    VolvoConnect_EndpointFetchComplete($hash, "location", 1);

    if (AttrVal($name, "location_reverse_geocode", 1)
        && (!defined($hash->{helper}{locationGeocodeKey})
            || $hash->{helper}{locationGeocodeKey} ne $locationKey)
        && (!defined($hash->{helper}{locationGeocodeInFlight})
            || $hash->{helper}{locationGeocodeInFlight} ne $locationKey)) {
        VolvoConnect_RequestReverseGeocode($hash, $latitude, $longitude, $locationKey);
    }
}

sub VolvoConnect_RequestReverseGeocode($$$$) {
    my ($hash, $latitude, $longitude, $locationKey) = @_;
    my $url = "https://nominatim.openstreetmap.org/reverse"
        . "?format=jsonv2&lat=" . urlEncode($latitude)
        . "&lon=" . urlEncode($longitude)
        . "&zoom=18&addressdetails=1&accept-language=de";

    $hash->{helper}{locationGeocodeInFlight} = $locationKey;
    HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => 15,
        method   => "GET",
        header   => "Accept: application/json\r\n"
                  . "User-Agent: FHEM-VolvoConnect/1.0",
        hash     => $hash,
        locationKey => $locationKey,
        callback => \&VolvoConnect_ReverseGeocodeCallback
    });
}

sub VolvoConnect_ReverseGeocodeCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $locationKey = $param->{locationKey};
    delete $hash->{helper}{locationGeocodeInFlight};

    return if (defined($hash->{helper}{locationGeocodeKey})
        && $hash->{helper}{locationGeocodeKey} ne $locationKey);
    if ($err ne "") {
        Log3 $name, 4, "VolvoConnect ($name) - Reverse geocoding failed: $err";
        return;
    }

    my $decoded = eval { decode_json($data) };
    return if (!$decoded || ref($decoded) ne "HASH");
    my $address = ref($decoded->{address}) eq "HASH" ? $decoded->{address} : {};
    my $displayName = $decoded->{display_name};
    return if (!defined($displayName) || $displayName eq "");

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "location_address", $displayName);
    readingsBulkUpdate($hash, "location_house_number", $address->{house_number}) if ($address->{house_number});
    readingsBulkUpdate($hash, "location_road", $address->{road}) if ($address->{road});
    readingsBulkUpdate($hash, "location_postcode", $address->{postcode}) if ($address->{postcode});
    readingsBulkUpdate($hash, "location_city", $address->{city} || $address->{town} || $address->{village})
        if ($address->{city} || $address->{town} || $address->{village});
    readingsBulkUpdate($hash, "location_state", $address->{state}) if ($address->{state});
    readingsBulkUpdate($hash, "location_country", $address->{country}) if ($address->{country});
    readingsEndUpdate($hash, 1);
    $hash->{helper}{locationGeocodeKey} = $locationKey;
}

sub VolvoConnect_ConnectedVehicleCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        Log3 $name, 2, "VolvoConnect ($name) - Error fetching connected vehicle data: $err";
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        Log3 $name, 2, "VolvoConnect ($name) - Connected vehicle response was not valid JSON.";
        return;
    }

    if (exists($decoded->{error})) {
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : $decoded->{error};
        Log3 $name, 2, "VolvoConnect ($name) - Connected vehicle API error: $error";
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;

    readingsBeginUpdate($hash);
    VolvoConnect_FlattenReadings($hash, $root, "vehicle");
    readingsEndUpdate($hash, 1);

    Log3 $name, 4, "VolvoConnect ($name) - Connected vehicle data fetched successfully.";
}

sub VolvoConnect_ConnectedVehicleStatusCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        Log3 $name, 2, "VolvoConnect ($name) - Error fetching vehicle status: $err";
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        Log3 $name, 2, "VolvoConnect ($name) - Vehicle status response was not valid JSON.";
        return;
    }

    if (exists($decoded->{error})) {
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : $decoded->{error};
        Log3 $name, 2, "VolvoConnect ($name) - Vehicle status API error: $error";
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;

    readingsBeginUpdate($hash);
    VolvoConnect_FlattenReadings($hash, $root, "status");
    readingsEndUpdate($hash, 1);

    Log3 $name, 4, "VolvoConnect ($name) - Vehicle status fetched successfully.";
}

sub VolvoConnect_EnergyCallback($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err ne "") {
        VolvoConnect_RecordApiError($hash, "energy", $param->{code}, $err);
        VolvoConnect_Reschedule($hash, AttrVal($name, "interval", 300));
        return;
    }

    my $decoded = eval { decode_json($data) };
    if (!$decoded) {
        VolvoConnect_RecordApiError($hash, "energy", $param->{code}, "Antwort war kein gültiges JSON");
        VolvoConnect_Reschedule($hash, AttrVal($name, "interval", 300));
        return;
    }

    if (exists($decoded->{error})) {
        my $error = ref($decoded->{error}) ? encode_json($decoded->{error}) : $decoded->{error};
        VolvoConnect_RecordApiError($hash, "energy", $param->{code}, $error);
        VolvoConnect_Reschedule($hash, AttrVal($name, "interval", 300));
        return;
    }

    my $root = exists($decoded->{data}) ? $decoded->{data} : $decoded;

    readingsBeginUpdate($hash);
    VolvoConnect_FlattenReadings($hash, $root, "energy");
    readingsBulkUpdate($hash, "state", "all_data_fetched");
    readingsEndUpdate($hash, 1);

    Log3 $name, 4, "VolvoConnect ($name) - Energy data fetched successfully.";
    VolvoConnect_Reschedule($hash, AttrVal($name, "interval", 300));
}

sub VolvoConnect_FlattenReadings {
    my ($hash, $data, $prefix, $forceUpdate) = @_;
    return if (!defined($data) || ref($data) ne "HASH");

    for my $key (keys %{$data}) {
        my $value = $data->{$key};
        my $readingName = $prefix . "_" . $key;

        if (ref($value) eq "HASH") {
            if (exists($value->{value})) {
                ($forceUpdate ? \&readingsBulkUpdate : \&readingsBulkUpdateIfChanged)->($hash, $readingName, $value->{value});
                ($forceUpdate ? \&readingsBulkUpdate : \&readingsBulkUpdateIfChanged)->($hash, $readingName . "_unit", $value->{unit})
                    if (defined($value->{unit}) && $value->{unit} ne "");
            } elsif (exists($value->{code})) {
                ($forceUpdate ? \&readingsBulkUpdate : \&readingsBulkUpdateIfChanged)->($hash, $readingName, $value->{code});
            } else {
                VolvoConnect_FlattenReadings($hash, $value, $readingName, $forceUpdate);
            }
        } elsif (ref($value) eq "ARRAY") {
            my $joined = join(", ", grep { defined($_) } @{$value});
            ($forceUpdate ? \&readingsBulkUpdate : \&readingsBulkUpdateIfChanged)->($hash, $readingName, $joined) if ($joined);
        } else {
            ($forceUpdate ? \&readingsBulkUpdate : \&readingsBulkUpdateIfChanged)->($hash, $readingName, $value) if (defined($value));
        }
    }
}

sub VolvoConnect_Reschedule($$) {
    my ($hash, $interval) = @_;
    RemoveInternalTimer($hash);
    InternalTimer(time() + $interval, "VolvoConnect_CheckAuthAndFetch", $hash, 0);
}

1;

=encoding UTF-8

=pod

=over 4

=item device
=item summary    Connects a Volvo vehicle via the Volvo Cars Developer API (energy + connected vehicle data)
=item summary_DE Bindet ein Volvo-Fahrzeug über die Volvo Cars Developer API an (Energie- und Fahrzeugdaten)

=back

=begin html

<a name="VolvoConnect"></a>
<h3>VolvoConnect</h3>
<ul>
    Connects a Volvo vehicle to FHEM via the official Volvo Cars Developer API (OAuth2/PKCE).
    Reads energy state, capabilities and connected-vehicle data (warnings, brakes, doors,
    windows, engine status) and allows sending vehicle commands (lock, climate, charging, ...).
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <li>FHEM with Perl modules <code>JSON</code>, <code>MIME::Base64</code> and
            <code>Digest::SHA</code>.</li>
        <li>A Volvo ID and a vehicle linked to that account.</li>
        <li>A Volvo Cars Developer Portal account and an application.</li>
        <li>The application's VCC API key, client ID and client secret.</li>
        <li>A redirect URI accepted by Volvo. The URI must match exactly between the
            Developer Portal and the FHEM attribute. Volvo generally requires HTTPS for
            public redirect URIs; <code>http://localhost</code> is commonly allowed for
            local development. This module currently uses the manual code handover, so
            the redirect page only has to display the returned authorization code.</li>
    </ul>
    <br>
    <b>Volvo Cars Developer Portal</b>
    <ol>
        <li>Log in to the Developer Portal and create an application under the application
            management section.</li>
        <li>Copy the generated VCC API key. It is sent as the
            <code>vcc-api-key</code> header with every vehicle API request.</li>
        <li>Copy the OAuth client ID and client secret from the application's credentials.</li>
        <li>Configure the redirect URI. It must be identical character by character to
            <code>redirect_uri</code> in FHEM, including scheme, host, port, path and
            trailing slash.</li>
        <li>Enable or request the APIs and permissions required by the application. The
            selected <code>scope_*</code> attributes in FHEM must correspond to permissions
            available to the application.</li>
        <li>For personal testing, use the portal's test/development mode if available.
            Publishing may be required before other Volvo ID users can authorize the application.</li>
    </ol>
    <br>
    <b>OAuth token workflow</b>
    <p>
        The module uses OAuth2 Authorization Code with PKCE. Run <code>set Volvo1 reauth</code>
        to clear stored tokens; then click the login link next to the device status to open
        Volvo's authorization URL with the configured scopes. After the Volvo ID login, Volvo redirects the browser to
        the configured URI, for example:
    </p>
    <code>http://localhost/?code=AUTH_CODE_EXAMPLE&amp;state=fhemstate</code>
    <p>
        Copy only the value after <code>code=</code>, up to the next <code>&amp;</code>.
        Do not copy <code>state</code> and do not copy the complete URL. Then submit it in FHEM:
    </p>
    <code>set Volvo1 authCode AUTH_CODE_EXAMPLE</code>
    <p>
        FHEM exchanges this short-lived authorization code at
        <code>https://volvoid.eu.volvocars.com/as/token.oauth2</code> using the client
        credentials and the PKCE verifier. The returned access and refresh tokens are stored
        in FHEM's key-value store. The access token is refreshed automatically when it expires;
        <code>get Volvo1 tokenInfo</code> shows only token presence and validity, never the token
        itself.
    </p>
    <p>
        If Volvo rejects a non-HTTPS redirect URI, use <code>http://localhost</code> where the
        portal permits it, or put FHEM behind an HTTPS reverse proxy. A plain HTTP LAN address
        cannot be used as a public OAuth redirect URI when Volvo requires HTTPS.
    </p>
    <p>
        Dynamic endpoints use <code>interval</code> (default 300 seconds), slower diagnostics and
        tyre data use <code>interval_slow</code> (default 1800 seconds), and location uses
        <code>interval_location</code> (default 900 seconds). Capabilities, commands and vehicle
        details are fetched once per VIN and successful fetch times persist across restarts.
        <code>set &lt;name&gt; update</code> forces all enabled endpoints to refresh. The standalone
        dashboard refreshes itself using <code>interval</code>; while its layout editor is open,
        automatic refresh is paused. Vehicle commands are sent only when their corresponding
        command scope is enabled.
    </p>
    <br>
    <a name="VolvoConnectdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; VolvoConnect</code><br>
        After defining the device, set all required attributes to the values from the Developer
        Portal and start the login from the link shown next to the status icon. Copy the
        authorization code from the redirect URL and use
        <code>set &lt;name&gt; authCode &lt;code&gt;</code>.
        Example:
        <pre>define Volvo1 VolvoConnect
    attr Volvo1 vin YV1EXAMPLEVIN
    attr Volvo1 client_id YOUR_CLIENT_ID
    attr Volvo1 client_secret YOUR_CLIENT_SECRET
    attr Volvo1 vcc_api_key YOUR_VCC_API_KEY
    attr Volvo1 redirect_uri http://localhost
    set Volvo1 reauth</pre>
    </ul>
    <br>
    <a name="VolvoConnectset"></a>
    <b>Set</b>
    <ul>
        <li><code>update</code> - force an immediate refresh of all enabled API endpoints</li>
        <li><code>reauth</code> - clear stored tokens and show the Volvo login link next to the device status</li>
        <li><code>authCode &lt;code&gt;</code> - submit the OAuth authorization code after login</li>
        <li><code>login</code> - show the current login URL, if required</li>
        <li><code>lock</code> / <code>unlock</code> - lock or unlock the vehicle</li>
        <li><code>climate</code> / <code>climate_stop</code> - start or stop climatization</li>
        <li><code>charge_start</code> / <code>charge_stop</code> - start or stop charging</li>
        <li><code>charge_limit &lt;10-100&gt;</code> - set the charging limit in percent</li>
        <li><code>precondition</code> - start engine preconditioning</li>
        <li><code>horn</code> - honk the horn</li>
    </ul>
    <br>
    <a name="VolvoConnectget"></a>
    <b>Get</b>
    <ul>
        <li><code>_dashboardURL</code> - return the complete dashboard URL using the current host, protocol and configured FHEM web path</li>
        <li><code>summary</code> - show authStatus, lastUpdate, lastError and last command state</li>
        <li><code>list</code> - show the standard FHEM "list" output for this device</li>
        <li><code>tokenInfo</code> - show access/refresh token presence and remaining validity</li>
        <li><code>scopes</code> - show which scope_* attributes are currently enabled/disabled</li>
        <li><code>_showEntityConfig</code> - edit and save the grouped Volvo API scopes</li>
        <li><code>_showDashboard</code> - render a standalone HTML dashboard with one tile per active
            scope, including an OpenStreetMap map for the vehicle location and the vehicle's exterior image;
            use edit mode to show/hide complete tiles or individual readings; usable directly as a bookmarkable URL:
            <code>&lt;fhemurl&gt;/VolvoConnect/&lt;name&gt;</code></li>
    </ul>
    <br>
    <a name="VolvoConnectattr"></a>
    <b>Attributes</b>
    <ul>
        <li><code>vin, client_id, client_secret, vcc_api_key, redirect_uri</code> - Volvo API credentials</li>
        <li><code>interval</code> - fast endpoint and dashboard refresh interval in seconds (default 300; minimum 10)</li>
        <li><code>interval_slow</code> - diagnostics and tyre endpoint interval in seconds (default 1800; minimum 60)</li>
        <li><code>interval_location</code> - location endpoint interval in seconds (default 900; minimum 60)</li>
        <li><code>disable</code>, <code>disabledForIntervals</code> - pause polling</li>
        <li><code>scope_*</code> - enable/disable individual data scopes and command permissions.
            Available scopes are capabilities, warnings, brakes, doors, windows, engine status,
            vehicle relation, commands, command accessibility, horn/flash, lock, unlock,
            climatization, engine commands, fuel, battery charge, odometer, statistics, tyres,
            engine diagnostics, workshop diagnostics and location. Use <code>get &lt;name&gt; _showEntityConfig</code>
            to edit them by group. A changed selection clears the tokens and starts a new authorization.</li>
        <li><code>location_reverse_geocode</code> - resolve new vehicle coordinates to an address
            through OpenStreetMap Nominatim (default 1). Set to 0 to keep coordinates private
            and disable external address lookup.</li>
        <li>The Location API returns the latest known position, normally updated at the end of
            a trip; it is not a live tracking API. Volvo documents availability for Volvo On Call
            cars from model year 2010-2024 and Google Built-in cars from model year 2020, with
            regional restrictions for published applications.</li>
        <li><code>stateFormat</code> - defaults to <code>{VolvoConnect_StateIcon('&lt;name&gt;')}</code>,
            showing a colored status dot (green/yellow/red) with the status as tooltip, plus a
            login button when auth_required</li>
    </ul>
    <br>
    <b>Readings</b>
    <ul>
        <li><code>state</code> - mirrors authStatus (authenticated, auth_required, token_refreshing, error, disabled)</li>
        <li><code>authStatus</code> - current authentication status</li>
        <li><code>lastUpdate</code> - timestamp of the last successful data fetch</li>
        <li><code>lastError</code>, <code>lastErrorCode</code> - last API error and HTTP code</li>
        <li><code>state_*, capabilities_*, warnings_*, brakes_*, doors_*, windows_*, engine_*,
            commandAccessibility_*, commands_*, vehicle_*, odometer_*, statistics_*, tyres_*,
            fuel_*, batteryCharge_*, location_*</code> - flattened vehicle data, including units where
            supplied by the API</li>
        <li><code>command_state</code>, <code>last_command</code> - result of the last vehicle command</li>
    </ul>
</ul>

=end html

=begin html_DE

<a name="VolvoConnect"></a>
<h3>VolvoConnect</h3>
<ul>
    Bindet ein Volvo-Fahrzeug über die offizielle Volvo Cars Developer API (OAuth2/PKCE) an FHEM an.
    Liest Energiestatus, Fahrzeugfähigkeiten und Connected-Vehicle-Daten (Warnungen, Bremsen, Türen,
    Fenster, Motorstatus) und ermöglicht das Senden von Fahrzeugbefehlen (Verriegeln, Klimatisierung,
    Laden, ...).
    <br><br>
    <b>Voraussetzungen</b>
    <ul>
        <li>FHEM mit den Perl-Modulen <code>JSON</code>, <code>MIME::Base64</code> und
            <code>Digest::SHA</code>.</li>
        <li>Eine Volvo ID und ein mit diesem Konto verknüpftes Fahrzeug.</li>
        <li>Ein Konto im Volvo Cars Developer Portal und eine dort angelegte Anwendung.</li>
        <li>VCC API Key, OAuth Client ID und Client Secret dieser Anwendung.</li>
        <li>Eine von Volvo akzeptierte Redirect-URI. Sie muss im Developer Portal und im FHEM-
            Attribut exakt übereinstimmen. Für öffentliche Redirect-URIs verlangt Volvo in der
            Regel HTTPS; <code>http://localhost</code> ist für lokale Tests häufig zulässig.
            Dieses Modul verwendet derzeit die manuelle Übergabe des Codes.</li>
    </ul>
    <br>
    <b>Einrichtung im Volvo Cars Developer Portal</b>
    <ol>
        <li>Im Developer Portal anmelden und im Bereich für Anwendungen eine neue Anwendung
            anlegen.</li>
        <li>Den erzeugten VCC API Key kopieren. Das Modul sendet ihn bei jeder API-Abfrage im
            Header <code>vcc-api-key</code>.</li>
        <li>OAuth Client ID und Client Secret aus den Zugangsdaten der Anwendung kopieren.</li>
        <li>Die Redirect-URI konfigurieren. Sie muss einschließlich Schema, Host, Port, Pfad und
            abschließendem Slash exakt dem FHEM-Attribut <code>redirect_uri</code> entsprechen.</li>
        <li>Die benötigten APIs und Berechtigungen für die Anwendung aktivieren bzw. beantragen.
            Die in FHEM aktivierten <code>scope_*</code>-Attribute müssen zu den im Portal
            verfügbaren Berechtigungen passen.</li>
        <li>Für persönliche Tests den Test-/Entwicklungsmodus des Portals verwenden, sofern er
            angeboten wird. Für weitere Volvo-ID-Nutzer kann eine Veröffentlichung der Anwendung
            erforderlich sein.</li>
    </ol>
    <br>
    <b>Erstmalige Einrichtung und Token holen</b>
    <p>
        Das Modul verwendet OAuth2 Authorization Code mit PKCE. Mit <code>set Volvo1 reauth</code>
        werden gespeicherte Tokens gelöscht. Anschließend den Login-Link neben dem Gerätestatus
        anklicken, um die Volvo-Anmeldung mit den konfigurierten Scopes zu öffnen. Nach der
        Anmeldung leitet Volvo den Browser zur Redirect-URI zurück, zum Beispiel:
    </p>
    <code>http://localhost/?code=AUTH_CODE_BEISPIEL&amp;state=fhemstate</code>
    <p>
        Aus dieser URL wird nur der Wert zwischen <code>code=</code> und dem nächsten
        <code>&amp;</code> kopiert. <code>state</code> und die komplette URL werden nicht
        übernommen. Der Code wird anschließend in FHEM eingegeben:
    </p>
    <pre>define Volvo1 VolvoConnect
attr Volvo1 vin YV1EXAMPLEVIN
attr Volvo1 client_id DEINE_CLIENT_ID
attr Volvo1 client_secret DEIN_CLIENT_SECRET
attr Volvo1 vcc_api_key DEIN_VCC_API_KEY
attr Volvo1 redirect_uri http://localhost
set Volvo1 reauth

# Nach dem Volvo-Login, Beispiel:
set Volvo1 authCode AUTH_CODE_BEISPIEL</pre>
    <p>
        FHEM tauscht den kurzlebigen Autorisierungscode am Endpoint
        <code>https://volvoid.eu.volvocars.com/as/token.oauth2</code> gegen Access- und
        Refresh-Token. Dabei werden Client-Zugangsdaten und der PKCE-Verifier verwendet. Die
        Tokens werden im FHEM-Key-Value-Store gespeichert. Läuft der Access-Token ab, wird er
        automatisch mit dem Refresh-Token erneuert. Mit
        <code>get Volvo1 tokenInfo</code> werden nur Vorhandensein und Gültigkeit angezeigt,
        niemals die geheimen Tokenwerte.
    </p>
    <p>
        Wenn Volvo eine HTTP-Redirect-URI ablehnt, kann für lokale Tests eine vom Portal erlaubte
        <code>http://localhost</code>-URI verwendet werden. Alternativ muss FHEM über einen
        HTTPS-Reverse-Proxy erreichbar gemacht werden. Eine normale HTTP-Adresse im LAN genügt
        nicht, wenn Volvo für öffentliche Redirect-URIs HTTPS voraussetzt.
    </p>
    <p>
        Dynamische Endpunkte verwenden <code>interval</code> (Standard 300 Sekunden), langsamere
        Diagnose- und Reifendaten <code>interval_slow</code> (Standard 1800 Sekunden) und der
        Standort <code>interval_location</code> (Standard 900 Sekunden). Fähigkeiten, Befehlsliste
        und Fahrzeugdetails werden einmal je VIN geladen; erfolgreiche Abrufzeitpunkte bleiben
        über Neustarts erhalten. <code>set &lt;name&gt; update</code> erzwingt den Abruf aller
        aktivierten Endpunkte. Das eigenständige Dashboard aktualisiert sich mit <code>interval</code>;
        während der Layout-Bearbeitung ist der Refresh pausiert. Fahrzeugbefehle werden nur gesendet,
        wenn der zugehörige Befehls-Scope aktiviert ist.
    </p>
    <br>
    <a name="VolvoConnectdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; VolvoConnect</code><br>
        Nach dem Anlegen alle erforderlichen Attribute mit den Werten aus dem Developer Portal
        setzen. Danach den Login-Link neben dem Status-Punkt öffnen, den Code aus der Rücksprung-
        URL kopieren und mit <code>set &lt;name&gt; authCode &lt;code&gt;</code> übergeben.
    </ul>
    <br>
    <a name="VolvoConnectset"></a>
    <b>Set</b>
    <ul>
        <li><code>update</code> - sofortigen Vollabruf aller aktivierten API-Endpunkte erzwingen</li>
        <li><code>reauth</code> - gespeicherte Tokens löschen und den Volvo-Login-Link neben dem Gerätestatus anzeigen</li>
        <li><code>authCode &lt;code&gt;</code> - OAuth-Autorisierungscode nach dem Login übermitteln</li>
        <li><code>login</code> - aktuelle Login-URL anzeigen, falls erforderlich</li>
        <li><code>lock</code> / <code>unlock</code> - Fahrzeug ver-/entriegeln</li>
        <li><code>climate</code> / <code>climate_stop</code> - Klimatisierung starten/stoppen</li>
        <li><code>charge_start</code> / <code>charge_stop</code> - Ladevorgang starten/stoppen</li>
        <li><code>charge_limit &lt;10-100&gt;</code> - Ladelimit in Prozent setzen</li>
        <li><code>precondition</code> - Vorkonditionierung starten</li>
        <li><code>horn</code> - Hupe auslösen</li>
    </ul>
    <br>
    <a name="VolvoConnectget"></a>
    <b>Get</b>
    <ul>
        <li><code>_dashboardURL</code> - vollständige Dashboard-URL mit aktuellem Host, Protokoll und konfiguriertem FHEM-Webpfad zurückgeben</li>
        <li><code>summary</code> - authStatus, lastUpdate, lastError und letzten Befehlsstatus anzeigen</li>
        <li><code>list</code> - regulären FHEM "list"-Output für dieses Gerät anzeigen</li>
        <li><code>tokenInfo</code> - Vorhandensein von Access-/Refresh-Token und verbleibende Gültigkeit anzeigen</li>
        <li><code>scopes</code> - aktivierte/deaktivierte scope_*-Attribute anzeigen</li>
        <li><code>_showEntityConfig</code> - gruppierte Volvo-API-Scopes bearbeiten und speichern</li>
        <li><code>_showDashboard</code> - eigenständiges HTML-Dashboard mit einer Kachel je aktivem
            Scope, OpenStreetMap-Karte beim Fahrzeugstandort und Außenbild anzeigen. Im Edit Mode
            lassen sich ganze Kacheln oder einzelne Readings ein-/ausblenden; auch direkt als Lesezeichen-URL nutzbar:
            <code>&lt;fhemurl&gt;/VolvoConnect/&lt;name&gt;</code></li>
    </ul>
    <br>
    <a name="VolvoConnectattr"></a>
    <b>Attribute</b>
    <ul>
        <li><code>vin, client_id, client_secret, vcc_api_key, redirect_uri</code> - Volvo-API-Zugangsdaten</li>
        <li><code>interval</code> - Intervall für dynamische Endpunkte und Dashboard in Sekunden (Standard 300, Minimum 10)</li>
        <li><code>interval_slow</code> - Intervall für Diagnose- und Reifendaten in Sekunden (Standard 1800, Minimum 60)</li>
        <li><code>interval_location</code> - Standortintervall in Sekunden (Standard 900, Minimum 60)</li>
        <li><code>disable</code>, <code>disabledForIntervals</code> - Abfrage pausieren</li>
        <li><code>scope_*</code> - einzelne Datenbereiche und Befehlsrechte aktivieren/deaktivieren.
            Verfügbar sind capabilities, warnings, brakes, doors, windows, engine status, vehicle
            relation, commands, command accessibility, horn/flash, lock, unlock, climatization,
            engine commands, fuel, battery charge, odometer, statistics, tyres, engine diagnostics,
            workshop diagnostics und location. Zur gruppierten Bearbeitung <code>get &lt;name&gt; _showEntityConfig</code>
            verwenden. Eine geänderte Auswahl löscht die Tokens und startet eine neue Autorisierung.</li>
        <li><code>location_reverse_geocode</code> - neue Fahrzeugkoordinaten über OpenStreetMap
            Nominatim in eine Adresse umwandeln (Standard 1). Mit 0 wird die externe
            Adressabfrage deaktiviert und die Position bleibt bei FHEM.</li>
        <li>Die Location API liefert die zuletzt bekannte Position, üblicherweise aktualisiert am
            Ende einer Fahrt; sie ist keine Live-Ortung. Volvo nennt als unterstützte Fahrzeuge
            Volvo-On-Call-Fahrzeuge der Modelljahre 2010-2024 sowie Fahrzeuge mit Google Built-in
            ab Modelljahr 2020. Für veröffentlichte Anwendungen gelten regionale Einschränkungen.</li>
        <li><code>stateFormat</code> - standardmäßig <code>{VolvoConnect_StateIcon('&lt;name&gt;')}</code>,
            zeigt einen farbigen Status-Punkt (grün/gelb/rot) mit dem Status als Tooltip sowie bei
            auth_required einen Anmelde-Button</li>
    </ul>
    <br>
    <b>Readings</b>
    <ul>
        <li><code>state</code> - spiegelt authStatus (authenticated, auth_required, token_refreshing, error, disabled)</li>
        <li><code>authStatus</code> - aktueller Authentifizierungsstatus</li>
        <li><code>lastUpdate</code> - Zeitpunkt der letzten erfolgreichen Datenabfrage</li>
        <li><code>lastError</code>, <code>lastErrorCode</code> - letzte API-Fehlermeldung und HTTP-Code</li>
        <li><code>state_*, capabilities_*, warnings_*, brakes_*, doors_*, windows_*, engine_*,
            commandAccessibility_*, commands_*, vehicle_*, odometer_*, statistics_*, tyres_*,
            fuel_*, batteryCharge_*, location_*</code> - aufgeschlüsselte Fahrzeugdaten, teilweise mit
            separatem Einheiten-Reading</li>
        <li><code>command_state</code>, <code>last_command</code> - Ergebnis des letzten
            Fahrzeugbefehls</li>
    </ul>
</ul>

=end html_DE

=cut
