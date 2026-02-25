<#
.SYNOPSIS
    Emergency RDP fix — removes CIS policy overrides that block Remote Desktop.
.DESCRIPTION
    Run this from an elevated console session when RDP is broken after
    applying CIS hardening on a standalone (non-domain) machine.

    What it does:
      1. Removes NLA/TLS/encryption policy overrides from Terminal Services
      2. Ensures RDP is enabled (fDenyTSConnections = 0)
      3. Resets the WinStations RDP-Tcp listener to defaults
      4. Removes entire firewall policy tree + resets via netsh
      5. Enables Remote Desktop firewall rules
      6. Restarts TermService
      7. Prints diagnostic info
.NOTES
    No reboot required. Try RDP immediately after running.
#>
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '  RDP Emergency Fix' -ForegroundColor White
Write-Host '  =================' -ForegroundColor DarkGray
Write-Host ''

# -- Step 1: Remove all RDP policy overrides --
Write-Host '  [1/6] Removing RDP policy overrides...' -ForegroundColor Cyan
$tsPolPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$policyValues = @('UserAuthentication', 'SecurityLayer', 'MinEncryptionLevel', 'fPromptForPassword', 'fEncryptRPCTraffic')

if (Test-Path $tsPolPath) {
    foreach ($name in $policyValues) {
        $current = Get-ItemProperty -Path $tsPolPath -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $current.$name) {
            Remove-ItemProperty -Path $tsPolPath -Name $name -ErrorAction SilentlyContinue
            Write-Host "    -  Removed: $name (was $($current.$name))" -ForegroundColor Yellow
        } else {
            Write-Host "    .  $name (not set)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host '    .  No Terminal Services policy key found' -ForegroundColor DarkGray
}

# -- Step 2: Ensure RDP is enabled --
Write-Host '  [2/6] Ensuring RDP is enabled...' -ForegroundColor Cyan
$tsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$fDeny = (Get-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
if ($fDeny -ne 0) {
    Set-ItemProperty -Path $tsPath -Name 'fDenyTSConnections' -Value 0
    Write-Host "    +  Set fDenyTSConnections = 0 (was $fDeny)" -ForegroundColor Green
} else {
    Write-Host '    .  Already enabled (fDenyTSConnections = 0)' -ForegroundColor DarkGray
}

# -- Step 3: Reset WinStations listener --
Write-Host '  [3/6] Resetting WinStations RDP-Tcp listener...' -ForegroundColor Cyan
$rdpTcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
if (Test-Path $rdpTcpPath) {
    $listenerNLA = (Get-ItemProperty -Path $rdpTcpPath -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
    $listenerSL  = (Get-ItemProperty -Path $rdpTcpPath -Name 'SecurityLayer' -ErrorAction SilentlyContinue).SecurityLayer

    if ($listenerNLA -ne 0) {
        Set-ItemProperty -Path $rdpTcpPath -Name 'UserAuthentication' -Value 0
        Write-Host "    +  UserAuthentication = 0 (was $listenerNLA)" -ForegroundColor Green
    } else {
        Write-Host '    .  UserAuthentication already 0' -ForegroundColor DarkGray
    }
    if ($listenerSL -ne 0) {
        Set-ItemProperty -Path $rdpTcpPath -Name 'SecurityLayer' -Value 0
        Write-Host "    +  SecurityLayer = 0 (was $listenerSL)" -ForegroundColor Green
    } else {
        Write-Host '    .  SecurityLayer already 0' -ForegroundColor DarkGray
    }
} else {
    Write-Host '    !  RDP-Tcp path not found' -ForegroundColor Red
}

# -- Step 4: Remove ENTIRE firewall policy tree (nuke all CIS firewall overrides) --
Write-Host '  [4/6] Removing all firewall policy overrides...' -ForegroundColor Cyan

$fwPolicyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall'
if (Test-Path $fwPolicyRoot) {
    # Show what we're removing
    $fwProfiles = @('DomainProfile', 'PrivateProfile', 'PublicProfile')
    foreach ($profileName in $fwProfiles) {
        $profilePath = Join-Path $fwPolicyRoot $profileName
        if (Test-Path $profilePath) {
            $props = Get-ItemProperty -Path $profilePath -ErrorAction SilentlyContinue
            $items = $props.PSObject.Properties | Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSProvider','PSDrive') }
            foreach ($item in $items) {
                Write-Host "    -  $profileName\$($item.Name) = $($item.Value)" -ForegroundColor Yellow
            }
        }
    }
    # Delete the entire tree
    Remove-Item -Path $fwPolicyRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '    +  Removed entire WindowsFirewall policy tree' -ForegroundColor Green
} else {
    Write-Host '    .  No firewall policy tree found' -ForegroundColor DarkGray
}

# Also reset firewall to defaults via netsh as a backstop
Write-Host '    +  Resetting firewall via netsh...' -ForegroundColor Cyan
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound | Out-Null
netsh advfirewall set allprofiles settings localfirewallrules enable | Out-Null
netsh advfirewall set allprofiles settings localconsecrules enable | Out-Null
Write-Host '    +  Firewall reset: block inbound default, local rules enabled' -ForegroundColor Green

# Show active network profile
try {
    $netProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    if ($netProfile) {
        Write-Host "    i  Active network profile: $($netProfile.NetworkCategory)" -ForegroundColor Cyan
    }
} catch { }

# -- Step 5: Enable firewall rules --
Write-Host '  [5/6] Enabling Remote Desktop firewall rules...' -ForegroundColor Cyan
try {
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
    $rdpRules = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Where-Object { $_.Enabled -eq 'True' }
    Write-Host "    +  $($rdpRules.Count) firewall rules enabled" -ForegroundColor Green
} catch {
    Write-Host "    !  Failed: $_" -ForegroundColor Red
}

# -- Step 6: Restart TermService --
Write-Host '  [6/6] Restarting TermService...' -ForegroundColor Cyan
try {
    Restart-Service TermService -Force -ErrorAction Stop
    Write-Host '    +  TermService restarted' -ForegroundColor Green
} catch {
    Write-Host "    !  Failed: $_" -ForegroundColor Red
}

# -- Diagnostics --
Write-Host ''
Write-Host '  Diagnostics' -ForegroundColor White
Write-Host '  -----------' -ForegroundColor DarkGray

$diag = @{
    'fDenyTSConnections' = (Get-ItemProperty $tsPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    'Listener NLA'       = (Get-ItemProperty $rdpTcpPath -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
    'Listener Security'  = (Get-ItemProperty $rdpTcpPath -Name 'SecurityLayer' -ErrorAction SilentlyContinue).SecurityLayer
    'TermService Status' = (Get-Service TermService).Status
}

foreach ($key in $diag.Keys) {
    $val = $diag[$key]
    $color = if ($key -eq 'TermService Status' -and $val -eq 'Running') { 'Green' }
             elseif ($val -eq 0) { 'Green' }
             else { 'Yellow' }
    Write-Host "    $($key.PadRight(22)) $val" -ForegroundColor $color
}

# Firewall policy state
Write-Host ''
Write-Host '  Firewall Policy State' -ForegroundColor White
Write-Host '  ---------------------' -ForegroundColor DarkGray
$fwPolicyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall'
if (Test-Path $fwPolicyRoot) {
    Write-Host '    !  WindowsFirewall policy tree still exists' -ForegroundColor Red
    Get-ChildItem $fwPolicyRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "    $($_.Name)" -ForegroundColor Yellow
    }
} else {
    Write-Host '    +  WindowsFirewall policy tree removed (clean)' -ForegroundColor Green
}

# Effective firewall state
Write-Host ''
Write-Host '  Effective Firewall (netsh)' -ForegroundColor White
Write-Host '  --------------------------' -ForegroundColor DarkGray
$fwState = netsh advfirewall show allprofiles 2>&1
foreach ($line in $fwState) {
    $trimmed = "$line".Trim()
    if ($trimmed -match 'Profile|Firewall Policy|State') {
        Write-Host "    $trimmed" -ForegroundColor DarkGray
    }
}

# RDP firewall rules
Write-Host ''
Write-Host '  RDP Firewall Rules' -ForegroundColor White
Write-Host '  ------------------' -ForegroundColor DarkGray
try {
    Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | ForEach-Object {
        $color = if ($_.Enabled -eq 'True') { 'Green' } else { 'Red' }
        Write-Host "    $($_.DisplayName.PadRight(45)) Enabled=$($_.Enabled)  Dir=$($_.Direction)" -ForegroundColor $color
    }
} catch {
    Write-Host "    !  Could not query rules: $_" -ForegroundColor Red
}

# Check for lingering TS policy values
Write-Host ''
if (Test-Path $tsPolPath) {
    $remaining = Get-ItemProperty -Path $tsPolPath -ErrorAction SilentlyContinue
    $props = $remaining.PSObject.Properties | Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSProvider','PSDrive') }
    if ($props) {
        Write-Host '  Remaining policy values:' -ForegroundColor Yellow
        foreach ($p in $props) {
            Write-Host "    $($p.Name) = $($p.Value)" -ForegroundColor Yellow
        }
    } else {
        Write-Host '  No lingering TS policy overrides' -ForegroundColor Green
    }
} else {
    Write-Host '  No Terminal Services policy key exists' -ForegroundColor Green
}

Write-Host ''
Write-Host '  Done — try RDP now (no reboot needed)' -ForegroundColor White
Write-Host ''
