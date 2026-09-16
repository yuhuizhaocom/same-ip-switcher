<#
    Portable network switch (green).
    Auto-detects wired (Ethernet) and wireless (WLAN) adapters by media type,
    so it works regardless of adapter names. Switches the active adapter to the
    configured static IP, and isolates the idle one (clears its IP + disables)
    so a single IP is never held by two adapters at the same time.
    Usage: powershell -ExecutionPolicy Bypass -File switch-network.ps1 [auto|eth|wifi]
    Run as administrator. Config: network-config.ps1 (same folder).
#>

param([string]$Target = "auto")

# [CONFIG]  -- loaded from network-config.ps1 in the same folder
$cfgFile = Join-Path $PSScriptRoot "network-config.ps1"
if (Test-Path $cfgFile) {
    . $cfgFile
}
else {
    Write-Host "WARN: network-config.ps1 not found next to the script - using defaults." -ForegroundColor Yellow
    $IpActive  = "10.2.5.199"
    $Mask      = "255.255.248.0"
    $Gw        = "10.2.3.254"
    $WifiSsids = @("ENUO-12")
}

# run log: append a timestamped copy of every message (same text as console) here.
$LogFile = Join-Path $PSScriptRoot "network-switch.log"

# Unified output: console and log carry the SAME full timestamp + text.
# level is just a log tag (info/step/error/result); console shows the message only.
function Msg([string]$m, [ConsoleColor]$fg = [ConsoleColor]::Gray, [string]$level = "info") {
    $ts  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ("[" + $ts + "] " + $m) -ForegroundColor $fg
    Add-Content -LiteralPath $LogFile -Value ($ts + " [" + $level + "] " + $m) -Encoding UTF8 -ErrorAction SilentlyContinue
}
function Step([string]$m) { Msg ("  " + $m) ([ConsoleColor]::DarkGray) "step" }

# run netsh fully silently, only returning the exit code.
# Used for resource/cleanup calls (delete/release) whose failure is harmless.
function Silent-Netsh([string]$line) {
    $null = & 'netsh.exe' $line 2>&1
    return $LASTEXITCODE
}
# run netsh, showing the real error text (decoded with the system ANSI
# codepage so it does not turn into mojibake). Used for the critical SET step.
function Show-Netsh([string]$line) {
    $o = Join-Path $env:TEMP "netsh_o.txt"
    $x = Join-Path $env:TEMP "netsh_e.txt"
    cmd.exe /c "netsh $line > `"$o`" 2> `"$x`"" | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        $enc = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $msg = ([IO.File]::ReadAllText($o, $enc) + [IO.File]::ReadAllText($x, $enc)).Trim()
        if ($msg) { Msg ("    [netsh rc=" + $rc + "] " + $msg) ([ConsoleColor]::Magenta) "error" }
    }
    Remove-Item $o,$x -ErrorAction SilentlyContinue
    return $rc
}

# ---- adapter auto-detection (by media type, name independent) ----
function Get-EthAdapter {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.PhysicalMediaType -and ($_.PhysicalMediaType -match '802\.3') } |
        Select-Object -First 1
}
function Get-WifiAdapter {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.PhysicalMediaType -and ($_.PhysicalMediaType -match '802\.11|Native') } |
        Select-Object -First 1
}
function IsAdapter($a) {
    if ($null -eq $a) { return $false }
    if ($a -is [System.Array]) { return $false }      # empty/single-element array from pipeline
    return [bool]$a.Name
}
function Ref($a)         { if (-not (IsAdapter $a)) { $null } else { Get-NetAdapter -Name $a.Name -ErrorAction SilentlyContinue } }
function Adp-Up($a)      { $r = Ref $a; return ($null -ne $r -and $r.Status -eq "Up") }
function Ensure-Up($a) {
    if ($null -eq $a) { return }
    $r = Ref $a
    if ($r -and $r.Status -ne "Up") { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
}
function Wait-ForUp($a, [int]$seconds = 25) {
    for ($i = 0; $i -lt $seconds * 2; $i++) {
        if (Adp-Up $a) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
# wait until the adapter holds a real (non-APIPA / non-empty) IPv4 address
function Wait-Stable-IPv4($a, [int]$seconds = 20) {
    for ($i = 0; $i -lt $seconds * 2; $i++) {
        $ip = Get-Adp-IP $a
        if ($ip -and -not $ip.StartsWith("169.254.")) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Set-Adp-IP($a, [string]$ip, [int]$retries = 2) {
    if ($null -eq $a) { Msg "  no adapter" Red "error"; return $false }
    Ensure-Up $a
    Start-Sleep -Milliseconds 400
    $idx = $a.ifIndex
    foreach ($try in 1..$retries) {
        Show-Netsh "interface ipv4 set address name=$idx static $ip $Mask $Gw store=persistent" | Out-Null
        Start-Sleep -Milliseconds 800
        if ((Get-Adp-IP $a) -eq $ip) {
            Msg ("  set " + $a.InterfaceDescription + " = " + $ip + " OK") ([ConsoleColor]::DarkGray) "step"
            return $true
        }
        Msg ("  set " + $a.InterfaceDescription + " = " + $ip + " failed (try " + $try + ")") ([ConsoleColor]::Red) "error"
        Start-Sleep -Milliseconds 1200
    }
    return $false
}
function Del-Adp-IP($a, [string]$ip) {
    if ($null -eq $a) { return }
    $idx = $a.ifIndex
    Silent-Netsh "interface ipv4 delete address name=$idx addr=$ip store=persistent" | Out-Null
    Silent-Netsh "interface ipv4 delete address name=$idx addr=$ip store=active" | Out-Null
}
function Release-IP($a) {
    Del-Adp-IP $a $IpActive
    Start-Sleep -Milliseconds 800
}
function Clean-Active($a, [string]$keep) {
    if ($null -eq $a) { return }
    foreach ($ip in (Get-NetIPAddress -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        if ($ip.IPAddress -ne $keep) { Del-Adp-IP $a $ip.IPAddress }
    }
}
function Connect-Wifi($a) {
    Ensure-Up $a
    $linked = $false
    foreach ($ssid in $WifiSsids) {
        Step ("try connect '" + $ssid + "'")
        Silent-Netsh "wlan connect name=$ssid ssid=$ssid interface=$($a.ifIndex)" | Out-Null
        Start-Sleep -Seconds 4
        if (Adp-Up $a) { $linked = $true; Msg ("  linked to '" + $ssid + "'") ([ConsoleColor]::Green) "step"; break }
    }
    if (-not $linked) { Msg "  auto-connect failed -> connect WiFi in tray." ([ConsoleColor]::Yellow) "warn" }
    Wait-ForUp $a 20 | Out-Null
    $stable = Wait-Stable-IPv4 $a 20
    Msg ("  WiFi IPv4 now: " + (Get-Adp-IP $a) + " (stable=" + $stable + ")") ([ConsoleColor]::DarkGray) "step"
}
# keep the outgoing adapter disabled and clear the active IP belonging to it,
# so a later switch never hits the "IP already held by another adapter" conflict.
function Quarantine($a) {
    if ($null -eq $a) { return }
    Release-IP $a
    Disable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue
}
function Get-Adp-IP($a) {
    if (-not (IsAdapter $a)) { return "" }
    $x = Get-NetIPAddress -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($x) { return $x.IPAddress } else { return "" }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: run as administrator." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

Msg ("==== Portable Network Switch ====  Target=" + $Target) ([ConsoleColor]::Cyan) "info"

$Eth  = Get-EthAdapter
$Wifi = Get-WifiAdapter
if ($Eth)  { Msg ("Ethernet: " + $Eth.InterfaceDescription + "  [idx " + $Eth.ifIndex + "]  " + (Get-Adp-IP $Eth) + " (up=" + (Adp-Up $Eth) + ")") ([ConsoleColor]::Gray) "info" }
else       { Msg "Ethernet: NOT FOUND" ([ConsoleColor]::Red) "warn" }
if ($Wifi) { Msg ("WiFi:     " + $Wifi.InterfaceDescription + "  [idx " + $Wifi.ifIndex + "]  " + (Get-Adp-IP $Wifi) + " (up=" + (Adp-Up $Wifi) + ")") ([ConsoleColor]::Gray) "info" }
else       { Msg "WiFi:     NOT FOUND" ([ConsoleColor]::Red) "warn" }

$ethIP  = Get-Adp-IP $Eth
$wifiIP = Get-Adp-IP $Wifi
$ethOn  = Adp-Up $Eth
$wifiOn = Adp-Up $Wifi

# decide the goal of this run; failures must not abort before cleanup/exit.
$toWifi    = $false
$alreadyOk = $false
try {
    switch ($Target.ToLower()) {
        "eth"  { $toWifi = $false }
        "wifi" { $toWifi = $true }
        default {
            # Cable decides first: once the wired adapter link is up, we switch
            # to Ethernet (and fix it to the active IP), even if WiFi still
            # holds it. Only when there is NO cable do we keep/join WiFi.
            if (Adp-Up $Eth) {
                $toWifi = $false
                Msg "Cable link found -> Ethernet." ([ConsoleColor]::Green) "info"
            }
            elseif ($wifiOn -and $wifiIP -eq $IpActive) {
                $toWifi = $true
                Msg ("No cable & WiFi already on " + $IpActive + " -> keep WiFi.") ([ConsoleColor]::Green) "info"
            }
            else {
                $toWifi = $true
                Msg "No cable -> WiFi." ([ConsoleColor]::DarkGray) "info"
            }
        }
    }

    # fast-exit: if the target adapter is already live on the active IP, done.
    if ($toWifi) {
        if ($wifiOn -and $wifiIP -eq $IpActive) {
            $alreadyOk = $true
            Msg ("Already OK - WiFi is up on " + $IpActive + ", no change needed (Ethernet up=" + (Adp-Up $Eth) + ").") ([ConsoleColor]::Green) "info"
        }
    }
    else {
        if ($ethOn -and $ethIP -eq $IpActive) {
            $alreadyOk = $true
            Msg ("Already OK - Ethernet is up on " + $IpActive + ", no change needed (WiFi up=" + (Adp-Up $Wifi) + ").") ([ConsoleColor]::Green) "info"
        }
    }

    if (-not $alreadyOk) {
        if ($toWifi) {
            Msg "-> Switching to WiFi" ([ConsoleColor]::Yellow) "info"
            Connect-Wifi $Wifi
            Step ("disable Ethernet first (release " + $IpActive + ")")
            Disable-NetAdapter -Name $Eth.Name -Confirm:$false -ErrorAction SilentlyContinue
            Release-IP $Eth
            Start-Sleep -Seconds 2
            Step ("set WiFi = " + $IpActive)
            $null = Set-Adp-IP $Wifi $IpActive
            Clean-Active $Wifi $IpActive
            Step "quarantine Ethernet (clear IP, keep disabled)"
            Quarantine $Eth
        }
        else {
            Msg "-> Switching to Ethernet" ([ConsoleColor]::Yellow) "info"
            Step ("disable WiFi first (release " + $IpActive + ")")
            Disable-NetAdapter -Name $Wifi.Name -Confirm:$false -ErrorAction SilentlyContinue
            Release-IP $Wifi
            Start-Sleep -Seconds 2
            Step ("enable Ethernet (need cable) and set = " + $IpActive)
            Ensure-Up $Eth
            $null = Set-Adp-IP $Eth $IpActive
            Clean-Active $Eth $IpActive
            Step "quarantine WiFi (clear IP, keep disabled)"
            Quarantine $Wifi
        }
    }
}
catch {
    Msg ("Unhandled error: " + $_.Exception.Message) ([ConsoleColor]::Red) "error"
}

if (-not $alreadyOk) { Start-Sleep -Seconds 2 }
$rEthIP  = Get-Adp-IP $Eth
$rEthOn  = Adp-Up $Eth
$rWifiIP = Get-Adp-IP $Wifi
$rWifiOn = Adp-Up $Wifi
Msg ("Result:  Ethernet=" + $rEthIP + " (up=" + $rEthOn + ")   WiFi=" + $rWifiIP + " (up=" + $rWifiOn + ")") ([ConsoleColor]::Cyan) "result"
Write-Host "`n==============================" -ForegroundColor Cyan

# auto-close after a short pause so the result is readable; abort on any key
Write-Host "`nClosing automatically in 5s (press any key to close now)..." -ForegroundColor DarkGray
for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 100
    if ([Console]::KeyAvailable) { break }
}
exit 0