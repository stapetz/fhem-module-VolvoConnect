package main;

use strict;
use warnings;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(decode_base64);

our ($readingFnAttributes, $FW_wname, $FW_ME, $FW_CSRF);
our (%data, %defs, %modules, %FW_httpheader);
our $DashboardHub_VERSION = '1.0.0-dev';

sub DashboardHub_Initialize {
    my ($modHash) = @_;

    $modHash->{DefFn} = 'DashboardHub_Define';
    $modHash->{UndefFn} = 'DashboardHub_Undef';
    $modHash->{GetFn} = 'DashboardHub_Get';
    $modHash->{SetFn} = 'DashboardHub_Set';
    $modHash->{AttrList} = join(' ',
        'includeDevices',
        'excludeDevices',
        'navWidth',
        'frameHeight',
        $main::readingFnAttributes,
    );

    $main::data{FWEXT}{'/DashboardHub'}{FUNC} = 'DashboardHub_CGI';
    $main::data{FWEXT}{'/DashboardHub'}{FORKABLE} = 0;
}

sub DashboardHub_Define {
    my ($hash, $def) = @_;
    my @args = split(/\s+/, $def);
    return 'Usage: define <name> DashboardHub' if (@args != 2);
    $hash->{VERSION} = $DashboardHub_VERSION;
    $hash->{STATE} = 'defined';
    return undef;
}

sub DashboardHub_Undef {
    my ($hash, $arg) = @_;
    setKeyValue(DashboardHub_ConfigKey($hash->{NAME}), undef);
    return undef;
}

sub DashboardHub_Set {
    my ($hash, $name, $cmd, @args) = @_;
    if (defined($cmd) && $cmd eq 'saveConfig') {
        my $error = DashboardHub_SaveConfig($name, decode_base64(join('', @args)));
        return $error if (defined($error));
        return 'Dashboard-Konfiguration gespeichert.';
    }
    return 'Unknown argument ' . ($cmd // '') . ', choose one of saveConfig';
}

sub DashboardHub_BasePath {
    my $path = $main::FW_ME || '/fhem';
    $path =~ s{/$}{};
    return $path;
}

sub DashboardHub_Get {
    my ($hash, $name, $cmd, @args) = @_;
    $cmd = '' if (!defined($cmd));

    return DashboardHub_BuildDashboard($hash, {editable => 1}) if ($cmd eq '_showDashboard');
    if ($cmd eq '_dashboardEmbedURL') {
        return DashboardHub_BasePath() . '/DashboardHub/' . urlEncode($name) . '?embed=1';
    }
    if ($cmd eq '_dashboardURL') {
        my $scheme = AttrVal($main::FW_wname, 'HTTPS', 0) ? 'https' : 'http';
        my $host = $main::FW_httpheader{Host} || 'localhost';
        return $scheme . '://' . $host . DashboardHub_BasePath() . '/DashboardHub/' . urlEncode($name);
    }
    if ($cmd eq 'list') {
        my $items = DashboardHub_Items($hash);
        return 'Keine Dashboards gefunden' if (!@{$items});
        return join("\n", map { sprintf('%s (%s, %s)', $_->{label}, $_->{name}, $_->{type}) } @{$items});
    }

    if ($cmd eq 'diagnose') {
        return DashboardHub_Diagnose($name);
    }

    return 'Unknown argument ' . $cmd . ', choose one of list:noArg diagnose:noArg _showDashboard:noArg '
        . '_dashboardURL:noArg _dashboardEmbedURL:noArg';
}

sub DashboardHub_Diagnose {
    my ($hubName) = @_;
    my @lines;
    for my $name (sort keys %main::defs) {
        my $dev = $main::defs{$name};
        next if (ref($dev) ne 'HASH' || $name eq $hubName);
        my $type = $dev->{TYPE} // '';
        next if ($type eq '' || !$main::modules{$type} || !$main::modules{$type}{GetFn});
        my $why;
        if (AttrVal($name, 'disable', 0)) { $why = 'disable gesetzt'; }
        else {
            my $usage = eval { CallFn($name, 'GetFn', $dev, $name, '?') };
            my $err = $@; $err =~ s/\s+$//;
            if ($err ne '') { $why = 'GetFn ? Fehler: ' . $err; }
            elsif (!defined($usage) || ref($usage)) { $why = 'GetFn ? liefert keine Zeichenkette'; }
            elsif ($usage !~ /(?:^|\s)_dashboardEmbedURL(?::|\s|$)/) { next if ($usage !~ /_dashboard/); $why = 'kein _dashboardEmbedURL in: ' . substr($usage, 0, 120); }
            else {
                my $embed = eval { CallFn($name, 'GetFn', $dev, $name, '_dashboardEmbedURL') };
                $why = (defined($embed) && !ref($embed) && $embed =~ m{^/[^\s]*$}) ? 'OK ' . $embed : 'ungueltige Embed-URL: ' . (defined($embed) ? $embed : 'undef');
            }
        }
        push @lines, "$name ($type): $why";
    }
    return @lines ? join("\n", @lines) : 'Keine Geraete mit GetFn gefunden';
}

sub DashboardHub_ConfigKey {
    my ($name) = @_;
    return 'DashboardHub_config_' . $name;
}

sub DashboardHub_LoadConfig {
    my ($name) = @_;
    my ($error, $value) = getKeyValue(DashboardHub_ConfigKey($name));
    my $config = (!$error && defined($value) && $value ne '') ? eval { decode_json($value) } : undef;
    $config = {} if (ref($config) ne 'HASH');
    $config->{order} = [] if (ref($config->{order}) ne 'ARRAY');
    $config->{names} = {} if (ref($config->{names}) ne 'HASH');
    $config->{title} = '' if (!defined($config->{title}) || ref($config->{title}));
    # decode_json yields characters; FHEM and the attribute values (alias) use UTF-8 bytes
    utf8::encode($config->{title});
    for my $device (keys %{$config->{names}}) {
        my $label = $config->{names}{$device};
        if (defined($label) && !ref($label)) { utf8::encode($label); $config->{names}{$device} = $label; }
        else { delete $config->{names}{$device}; }
    }
    return $config;
}

sub DashboardHub_SaveConfig {
    my ($name, $json) = @_;
    Log3($name, 2, "DashboardHub ($name): saveConfig " . length($json // '') . ' bytes');
    my $config = eval { decode_json($json || '') };
    return 'Ungueltige Konfiguration'
        if (ref($config) ne 'HASH' || ref($config->{order}) ne 'ARRAY' || ref($config->{names}) ne 'HASH'
            || grep { !defined($_) || ref($_) || $_ eq '' } @{$config->{order}});
    my %seen;
    my @order = grep { !$seen{$_}++ } @{$config->{order}};
    my %names;
    for my $device (keys %{$config->{names}}) {
        my $label = $config->{names}{$device};
        next if (!defined($label) || ref($label));
        $label =~ s/^\s+|\s+$//g;
        $names{$device} = substr($label, 0, 80) if ($label ne '');
    }
    my $title = $config->{title};
    $title = '' if (!defined($title) || ref($title));
    $title =~ s/^\s+|\s+$//g;
    $title = substr($title, 0, 80);
    my $error = setKeyValue(DashboardHub_ConfigKey($name),
        encode_json({order => \@order, names => \%names, title => $title}));
    if (defined($error) && $error ne '') {
        Log3($name, 1, "DashboardHub ($name): setKeyValue failed: $error");
        return 'Speichern fehlgeschlagen: ' . $error;
    }
    Log3($name, 2, "DashboardHub ($name): config saved");
    return undef;
}

sub DashboardHub_Matches {
    my ($regex, $value) = @_;
    return 0 if (!defined($regex) || $regex eq '');
    my $matched = eval { $value =~ /$regex/ };
    return $matched ? 1 : 0;
}

# A device counts as a dashboard if its Get usage advertises _dashboardEmbedURL.
sub DashboardHub_Discover {
    my ($hubName) = @_;
    my $include = AttrVal($hubName, 'includeDevices', '');
    my $exclude = AttrVal($hubName, 'excludeDevices', '');
    my @found;

    for my $name (sort keys %main::defs) {
        my $dev = $main::defs{$name};
        next if (ref($dev) ne 'HASH');
        my $type = $dev->{TYPE} // '';
        next if ($type eq '' || $type eq 'DashboardHub' || $name eq $hubName);
        next if ($include ne '' && !DashboardHub_Matches($include, $name));
        next if (DashboardHub_Matches($exclude, $name));
        next if (AttrVal($name, 'disable', 0));
        next if (!$main::modules{$type} || !$main::modules{$type}{GetFn});

        my $usage = eval { CallFn($name, 'GetFn', $dev, $name, '?') };
        next if (!defined($usage) || ref($usage) || $usage !~ /(?:^|\s)_dashboardEmbedURL(?::|\s|$)/);
        my $embed = eval { CallFn($name, 'GetFn', $dev, $name, '_dashboardEmbedURL') };
        next if (!defined($embed) || ref($embed) || $embed !~ m{^/[^\s]*$});

        push @found, {
            name => $name,
            type => $type,
            alias => AttrVal($name, 'alias', $name),
            url => $embed,
        };
    }
    return \@found;
}

sub DashboardHub_Items {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $config = DashboardHub_LoadConfig($name);
    my %byName = map { $_->{name} => $_ } @{DashboardHub_Discover($name)};
    my %used;
    my @items;
    for my $device (@{$config->{order}}) {
        next if (!$byName{$device} || $used{$device}++);
        push @items, $byName{$device};
    }
    push @items, sort { lc($a->{alias}) cmp lc($b->{alias}) } grep { !$used{$_->{name}} } values %byName;
    for my $item (@items) {
        my $custom = $config->{names}{$item->{name}};
        $item->{custom} = defined($custom) ? $custom : '';
        $item->{label} = $item->{custom} ne '' ? $item->{custom} : $item->{alias};
    }
    return \@items;
}

sub DashboardHub_Escape {
    my ($text) = @_;
    $text = '' if (!defined($text));
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&#39;/g;
    return $text;
}

sub DashboardHub_Css {
    return <<'CSS';
<style>
.dh,.dh *{box-sizing:border-box;letter-spacing:normal;text-transform:none;text-shadow:none}
.dh{display:flex;width:100%;min-height:__HEIGHT__;background:#151f1b;color:#f4f4e9;border:1px solid #46544c;font:14px 'Avenir Next','Helvetica Neue',sans-serif!important;text-align:left;line-height:1.4}
.dh-nav{flex:0 0 __NAVWIDTH__;display:flex;flex-direction:column;align-self:flex-start;margin:6px 0 6px 6px;background:#26342d;border:1px solid #46544c;padding:10px 0}
.dh-brand{display:flex;align-items:center;justify-content:space-between;padding:4px 12px 12px;font:500 18px Georgia,serif}
.dh-list{flex:1;overflow-y:auto}
.dh-item{display:flex;align-items:center;gap:6px;padding:10px 14px;cursor:pointer;border-left:3px solid transparent;color:#f4f4e9;font-size:14px;user-select:none}
.dh-item:hover{background:#2f4037}
.dh-item.dh-active{background:#1d2825;border-left-color:#52bd8b;font-weight:600}
.dh-item .dh-label{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dh-item .dh-type{font-size:11px;color:#9fb3a8}
.dh-editing .dh-item{cursor:default;padding:6px 8px}
.dh.dh-editing .dh-item.dh-dragover{outline:1px dashed #52bd8b}
.dh .dh-btn{height:26px!important;min-width:26px!important;padding:0 8px!important;margin:0!important;font-size:12px!important;background:#26342d!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important;cursor:pointer;width:auto!important;float:none!important}
.dh .dh-edit{width:32px!important;height:32px!important;font-size:20px!important;background:none!important;border:0!important;padding:0!important}
.dh input.dh-name{flex:1;min-width:0;height:26px!important;margin:0!important;padding:0 6px!important;font-size:13px!important;background:#1d2825!important;color:#f4f4e9!important;border:1px solid #52bd8b!important;border-radius:0!important;width:auto!important}
.dh-grip{cursor:grab;color:#9fb3a8}
.dh-status{padding:0 12px 6px;font-size:12px;color:#9fb3a8}.dh-status:empty{display:none}
.dh-main{flex:1;min-width:0;background:#151f1b}
.dh-content{padding:6px 12px 12px;min-height:__HEIGHT__;line-height:1.4}
.dh-content .tc-dashboard,.dh-content .wrap,.dh-content .gavazzi-dashboard,.dh-content .solax-dashboard,.dh-content .vcc-embed{width:100%!important;max-width:none!important;margin-left:0!important;margin-right:0!important}
.dh-content>.vcc-embed>.wrap{margin:0!important}
.dh-content .vcc-embed{padding:0!important}
.dh-loading{padding:24px;color:#9fb3a8}
.dh-empty{padding:24px;color:#9fb3a8}
@media (max-width:700px){.dh{flex-direction:column}.dh-nav{flex:none;align-self:stretch;margin:6px 6px 0}.dh-list{display:flex;overflow-x:auto}.dh-item{border-left:0;border-bottom:3px solid transparent;white-space:nowrap}.dh-item.dh-active{border-bottom-color:#52bd8b}.dh-editing .dh-list{display:block}}
</style>
CSS
}

sub DashboardHub_Js {
    return <<'JS';
<script>(function(){
var root=document.getElementById("__ID__");if(!root)return;
var list=root.querySelector(".dh-list"),frame=root.querySelector(".dh-content"),status=root.querySelector(".dh-status");
var editBtn=root.querySelector(".dh-edit");
var editable=__EDITABLE__,cp=__CP__,hub=__HUB__,csrf=__CSRF__,storeKey="dashboardHub_"+hub;
var editing=false,sig0="",busy=false,titleEl=root.querySelector(".dh-title"),titleInput=null,DEFTITLE="Dashboards";
function items(){return Array.prototype.slice.call(list.querySelectorAll(".dh-item"));}
var sayTimer=null;function say(t,keep){if(!status)return;window.clearTimeout(sayTimer);status.textContent=t||"";if(t&&!keep)sayTimer=window.setTimeout(function(){status.textContent="";},4000);}
var timers=[],origSetInterval=window.setInterval,token=0;
window.setInterval=function(){var id=origSetInterval.apply(window,arguments);if(loadedUrl)timers.push(id);return id;};
var loadedUrl=null;
function cleanup(){timers.forEach(function(id){window.clearInterval(id);});timers=[];}
function load(url){var my=++token;cleanup();loadedUrl=null;frame.innerHTML='<div class="dh-loading">Lade ...</div>';
fetch(url,{credentials:"same-origin",cache:"no-store"}).then(function(r){if(!r.ok)throw new Error("HTTP "+r.status);return r.text();}).then(function(t){
if(my!==token)return;loadedUrl=url;frame.innerHTML="";frame.appendChild(document.createRange().createContextualFragment(t));
}).catch(function(err){if(my!==token)return;frame.innerHTML='<div class="dh-loading">Dashboard konnte nicht geladen werden: '+String(err.message).replace(/[<>&]/g,"")+"</div>";});}
function select(el,force){var all=items();if(!el)el=all[0];if(!el){if(frame)frame.innerHTML="";return;}
all.forEach(function(n){n.classList.toggle("dh-active",n===el);});
var url=el.getAttribute("data-url");if(frame&&(force||frame.getAttribute("data-url")!==url)){frame.setAttribute("data-url",url);load(url);}
try{localStorage.setItem(storeKey,el.getAttribute("data-dev"));}catch(e){}}
function initial(){var dev=null;try{dev=localStorage.getItem(storeKey);}catch(e){}
var m=/[?&]hubSel=([^&]*)/.exec(window.location.search);if(m)dev=decodeURIComponent(m[1]);
var f=items().filter(function(n){return n.getAttribute("data-dev")===dev;})[0];select(f);}
list.addEventListener("click",function(e){if(editing)return;var el=e.target.closest(".dh-item");if(el)select(el);});
function decorate(el){var label=el.querySelector(".dh-label"),type=el.querySelector(".dh-type");
var grip=document.createElement("span");grip.className="dh-grip";grip.textContent="\u2630";grip.title="Ziehen zum Sortieren";
var input=document.createElement("input");input.type="text";input.className="dh-name";input.maxLength=80;
input.value=el.getAttribute("data-custom")||"";input.placeholder=el.getAttribute("data-alias");input.title="Anzeigename (leer = Alias)";
input.addEventListener("click",function(e){e.stopPropagation();});
label.style.display="none";if(type)type.style.display="none";
el.insertBefore(grip,label);el.insertBefore(input,label);
el.draggable=true;}
function undecorate(el){Array.prototype.slice.call(el.querySelectorAll(".dh-grip,.dh-name")).forEach(function(n){el.removeChild(n);});
var label=el.querySelector(".dh-label"),type=el.querySelector(".dh-type");label.style.display="";if(type)type.style.display="";el.draggable=false;}
var dragged=null;
list.addEventListener("dragstart",function(e){if(!editing)return;dragged=e.target.closest(".dh-item");if(e.dataTransfer){e.dataTransfer.effectAllowed="move";try{e.dataTransfer.setData("text/plain","");}catch(x){}}});
list.addEventListener("dragover",function(e){if(!editing||!dragged)return;e.preventDefault();var t=e.target.closest(".dh-item");
items().forEach(function(n){n.classList.toggle("dh-dragover",n===t&&n!==dragged);});});
list.addEventListener("drop",function(e){if(!editing||!dragged)return;e.preventDefault();var t=e.target.closest(".dh-item");
if(t&&t!==dragged){var after=items().indexOf(dragged)<items().indexOf(t);list.insertBefore(dragged,after?t.nextElementSibling:t);}
dragged=null;items().forEach(function(n){n.classList.remove("dh-dragover");});});
list.addEventListener("dragend",function(){dragged=null;items().forEach(function(n){n.classList.remove("dh-dragover");});});
function startEdit(){editing=true;root.classList.add("dh-editing");
items().forEach(decorate);
titleInput=document.createElement("input");titleInput.type="text";titleInput.className="dh-name";titleInput.maxLength=80;titleInput.value=titleEl.getAttribute("data-custom")||"";titleInput.placeholder=DEFTITLE;titleInput.title="\u00dcberschrift (leer = "+DEFTITLE+")";titleEl.style.display="none";titleEl.parentNode.insertBefore(titleInput,titleEl);
sig0=sig();say("Bearbeiten: Namen \u00e4ndern, Eintr\u00e4ge ziehen. Erneut auf den Stift klicken zum Speichern",true);}
function stopEdit(){if(titleInput){titleInput.parentNode.removeChild(titleInput);titleInput=null;titleEl.style.display="";}editing=false;root.classList.remove("dh-editing");items().forEach(undecorate);}
function sig(){return JSON.stringify([items().map(function(n){var i=n.querySelector(".dh-name");return [n.getAttribute("data-dev"),i?i.value.trim():""];}),titleInput?titleInput.value.trim():""]);}
function ck(r){return r.text().then(function(t){if(!r.ok)throw new Error("HTTP "+r.status);if(/error|unknown|ungueltig|fehlgeschlagen/i.test(t))throw new Error(t.trim().slice(0,160));});}
function post(b64){var tok=csrf;if(!tok){var m=document.cookie.match(/(?:^|;\s*)fwcsrf=([^;]+)/);tok=m?decodeURIComponent(m[1]):"";}
var url=cp+"?cmd="+encodeURIComponent("set "+hub+" saveConfig "+b64)+"&XHR=1"+(tok?"&fwcsrf="+encodeURIComponent(tok):"");
return fetch(url,{credentials:"same-origin",cache:"no-store"}).then(ck);}
function save(){var order=[],names={};items().forEach(function(n){var d=n.getAttribute("data-dev");order.push(d);
var v=n.querySelector(".dh-name").value.trim();if(v!==""&&v!==n.getAttribute("data-alias"))names[d]=v;});
var ttl=titleInput?titleInput.value.trim():"";var json=JSON.stringify({order:order,names:names,title:ttl});var b64=btoa(unescape(encodeURIComponent(json)));busy=true;say("Speichere ...",true);
post(b64).then(function(){items().forEach(function(n){var d=n.getAttribute("data-dev"),v=names[d]||"";n.setAttribute("data-custom",v);
n.querySelector(".dh-label").textContent=v||n.getAttribute("data-alias");});titleEl.setAttribute("data-custom",ttl);titleEl.textContent=ttl||DEFTITLE;stopEdit();busy=false;say("Gespeichert");}).catch(function(err){busy=false;say("Fehler: "+err.message);window.alert("Speichern fehlgeschlagen: "+err.message);});}
if(editable&&editBtn){editBtn.addEventListener("click",function(){if(busy)return;if(!editing)startEdit();else if(sig()===sig0){stopEdit();say("");}else save();});}
initial();
})();</script>
JS
}

sub DashboardHub_BuildDashboard {
    my ($hash, $options) = @_;
    $options ||= {};
    my $name = $hash->{NAME};
    my $items = DashboardHub_Items($hash);
    my $editable = $options->{editable} ? 1 : 0;
    my $id = 'dh-' . $name;
    $id =~ s/[^A-Za-z0-9_-]/_/g;

    my $navWidth = AttrVal($name, 'navWidth', 220);
    $navWidth = 220 if ($navWidth !~ /^\d+$/ || $navWidth < 120 || $navWidth > 600);
    my $height = AttrVal($name, 'frameHeight', 800);
    $height = 800 if ($height !~ /^\d+$/ || $height < 300 || $height > 3000);

    my $config = DashboardHub_LoadConfig($name);
    my $title = $config->{title} ne '' ? $config->{title} : 'Dashboards';
    my $csrf = $main::FW_CSRF // '';
    $csrf =~ s/^&?fwcsrf=//;

    my $css = DashboardHub_Css();
    $css =~ s/__NAVWIDTH__/${navWidth}px/g;
    $css =~ s/__HEIGHT__/${height}px/g;

    my $html = $css . '<div class="dh" id="' . DashboardHub_Escape($id) . '"><div class="dh-nav">'
        . '<div class="dh-brand"><span class="dh-title" data-custom="'
        . DashboardHub_Escape($config->{title}) . '">' . DashboardHub_Escape($title) . '</span>'
        . ($editable && @{$items}
            ? '<button type="button" class="dh-btn dh-edit" title="Reihenfolge und Namen bearbeiten">&#9998;</button>'
            : '')
        . '</div><div class="dh-status"></div><div class="dh-list">';
    for my $item (@{$items}) {
        $html .= '<div class="dh-item" data-dev="' . DashboardHub_Escape($item->{name})
            . '" data-url="' . DashboardHub_Escape($item->{url})
            . '" data-alias="' . DashboardHub_Escape($item->{alias})
            . '" data-custom="' . DashboardHub_Escape($item->{custom})
            . '"><span class="dh-label">' . DashboardHub_Escape($item->{label}) . '</span></div>';
    }
    $html .= '</div></div><div class="dh-main">'
        . (@{$items}
            ? '<div class="dh-content"></div>'
            : '<div class="dh-empty">Keine Dashboards gefunden. Es werden Ger&auml;te erkannt, die '
              . '<code>get &lt;name&gt; _dashboardEmbedURL</code> unterst&uuml;tzen.</div>')
        . '</div></div>';

    my $js = DashboardHub_Js();
    my $cp = DashboardHub_BasePath();
    $js =~ s/__ID__/$id/g;
    $js =~ s/__EDITABLE__/$editable/g;
    my $csrfJson = encode_json([$csrf]);
    $csrfJson =~ s/^\[|\]$//g;
    $js =~ s/__CSRF__/$csrfJson/g;
    my $cpJson = encode_json([$cp]);
    my $hubJson = encode_json([$name]);
    $cpJson =~ s/^\[|\]$//g;
    $hubJson =~ s/^\[|\]$//g;
    $cpJson =~ s{</}{<\\/}g;
    $hubJson =~ s{</}{<\\/}g;
    $js =~ s/__CP__/$cpJson/g;
    $js =~ s/__HUB__/$hubJson/g;
    return $html . $js;
}

sub DashboardHub_QueryValue {
    my ($request, $key, $default) = @_;
    return $default if (!defined($request) || $request !~ /(?:^|[?&])\Q$key\E=([^&]*)/);
    my $value = $1;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $value;
}

sub main::DashboardHub_CGI {
    my ($request) = @_;
    $request = '' if (!defined($request));
    my ($path) = split(/\?/, $request, 2);
    my $name = (split('/', $path))[-1];
    $name = '' if (!defined($name));
    $name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    my $hash = $main::defs{$name};
    return ('text/plain; charset=utf-8', 'Unknown DashboardHub device')
        if (!$hash || ($hash->{TYPE} || '') ne 'DashboardHub');

    my $encoded = DashboardHub_QueryValue($request, 'hubSave', undef);
    if (defined($encoded)) {
        my $error = DashboardHub_SaveConfig($name, decode_base64($encoded));
        return ('text/plain; charset=utf-8', defined($error) ? $error : 'gespeichert');
    }

    my $html = DashboardHub_BuildDashboard($hash, {editable => 0});
    return ('text/html; charset=utf-8', $html)
        if (DashboardHub_QueryValue($request, 'embed', 0));
    return ('text/html; charset=utf-8', '<!doctype html><html lang="de"><head><meta charset="utf-8">'
        . '<meta name="viewport" content="width=device-width, initial-scale=1">'
        . '<title>DashboardHub - ' . DashboardHub_Escape($name)
        . '</title></head><body style="margin:0;padding:12px;background:#151f1b">'
        . $html . '</body></html>');
}

1;

=pod
=item device
=item summary Navigation und Anzeige aller erkannten Dashboards
=item summary_DE Erkennt Dashboard-Geräte automatisch und zeigt sie mit Navigation links
=begin html

<a id="DashboardHub"></a>
<h3>DashboardHub</h3>
<p>
    DashboardHub ist ein Meta-Modul. Es erkennt automatisch alle FHEM-Geräte, die ein
    Dashboard anbieten (Get-Befehl <code>_dashboardEmbedURL</code>, z.B.
    TemperatureCollector, GavazziEM24, SolaxModbus und VolvoConnect), zeigt sie links als
    Navigation an und stellt rechts das gewählte Dashboard dar.
</p>
<a id="DashboardHub-define"></a>
<b>Define</b>
<ul><code>define &lt;name&gt; DashboardHub</code></ul>
<a id="DashboardHub-get"></a>
<b>Get</b>
<ul>
    <li><code>list</code> - erkannte Dashboards in der aktuellen Reihenfolge ausgeben</li>
    <li><code>diagnose</code> - pro Ger&auml;t anzeigen, ob und warum es als Dashboard erkannt wird</li>
    <li><code>_showDashboard</code> - Dashboard mit Navigation anzeigen; mit dem Stift lassen sich
        Anzeigenamen und Reihenfolge der Menüpunkte sowie die Überschrift der Navigation ändern</li>
    <li><code>_dashboardURL</code> - URL der eigenständigen Ansicht (nicht editierbar)</li>
    <li><code>_dashboardEmbedURL</code> - relative URL des Fragments ohne html/head/body, z.B. für FTUI</li>
</ul>
<a id="DashboardHub-set"></a>
<b>Set</b>
<ul>
    <li><code>saveConfig &lt;base64-json&gt;</code> - wird von der Bearbeitungsansicht verwendet</li>
</ul>
<a id="DashboardHub-attr"></a>
<b>Attribute</b>
<ul>
    <li><code>includeDevices</code> - Regex; nur passende Gerätenamen werden berücksichtigt</li>
    <li><code>excludeDevices</code> - Regex; passende Gerätenamen werden ausgeblendet</li>
    <li><code>navWidth</code> - Breite der Navigation in Pixel (120-600, Standard 220)</li>
    <li><code>frameHeight</code> - Mindesthöhe der Anzeige in Pixel (300-3000, Standard 800)</li>
</ul>
<p>
    Der Standardname eines Menüpunkts ist das Attribut <code>alias</code> des Dashboard-Geräts
    (ersatzweise der Gerätename). Eigene Namen und die Reihenfolge werden serverseitig
    gespeichert; neue Dashboards werden automatisch am Ende angefügt.
</p>

=end html
=cut
