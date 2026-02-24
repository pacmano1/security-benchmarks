<#
.SYNOPSIS
    Installs prerequisites required by CIS Benchmark automation.
.DESCRIPTION
    Auto-detects the environment (Windows Server with AD, Windows Server standalone,
    Windows workstation) and installs only what is available and relevant.
    Must be run as Administrator.
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Clear-Host
Write-Host ''
Write-Host '  CIS Benchmark - Install Prerequisites' -ForegroundColor White
Write-Host '  ======================================' -ForegroundColor DarkGray
Write-Host ''

# -- Status helper --
function Write-Status {
    param([string]$Symbol, [string]$Message, [ConsoleColor]$Color = 'White')
    Write-Host "  $Symbol " -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

# -- Detect environment --
Write-Host '  Detecting environment...' -ForegroundColor DarkGray
Write-Host ''

$isWindows = ($PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows) -or ($PSVersionTable.PSVersion.Major -le 5)
if (-not $isWindows) {
    Write-Status 'i' 'Non-Windows OS detected. No prerequisites to install.' Yellow
}

$isServer = $false
$isDomainJoined = $false

if ($isWindows) {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os.ProductType -gt 1) {
        $isServer = $true
        Write-Status '+' "Windows Server: $($os.Caption)" Green
    } else {
        Write-Status '+' "Windows Workstation: $($os.Caption)" Green
    }

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs.PartOfDomain) {
        $isDomainJoined = $true
        Write-Status '+' "Domain-joined: $($cs.Domain)" Green
    } else {
        Write-Status '-' 'Not domain-joined (AD/GPO features will be limited)' Yellow
    }
}

Write-Host ''

# -- Windows Features (RSAT) - Server only --
if ($isServer) {
    Write-Host '  RSAT Features' -ForegroundColor White
    Write-Host '  -------------' -ForegroundColor DarkGray

    $features = @(
        'RSAT-AD-PowerShell'        # ActiveDirectory module
        'GPMC'                      # Group Policy Management Console
    )

    if (-not $isDomainJoined) {
        Write-Status '!' 'RSAT will install but AD/GPO commands require a domain' Yellow
    }

    foreach ($feat in $features) {
        $installed = Get-WindowsFeature -Name $feat -ErrorAction SilentlyContinue
        if ($installed -and $installed.Installed) {
            Write-Status '+' "$feat" Green
        } else {
            Write-Status '~' "Installing $feat ..." Yellow
            try {
                Install-WindowsFeature -Name $feat -IncludeManagementTools -ErrorAction Stop
                Write-Status '+' "$feat installed" Green
            } catch {
                Write-Status 'x' "Could not install $feat - $($_.Exception.Message)" Red
            }
        }
    }
    Write-Host ''
} elseif ($isWindows) {
    Write-Host '  RSAT Optional Features' -ForegroundColor White
    Write-Host '  ----------------------' -ForegroundColor DarkGray

    $rsatCapabilities = @(
        'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
        'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
    )

    foreach ($cap in $rsatCapabilities) {
        $shortName = ($cap -split '~~~~')[0]
        $state = Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue
        if ($state -and $state.State -eq 'Installed') {
            Write-Status '+' "$shortName" Green
        } elseif ($state) {
            Write-Status '~' "Installing $shortName ..." Yellow
            try {
                Add-WindowsCapability -Online -Name $cap -ErrorAction Stop
                Write-Status '+' "$shortName installed" Green
            } catch {
                Write-Status 'x' "Could not install $shortName - $($_.Exception.Message)" Red
            }
        } else {
            Write-Status '-' "$shortName not available on this OS" Yellow
        }
    }
    Write-Host ''
} else {
    Write-Status '-' 'RSAT features are Windows-only' Yellow
    Write-Host ''
}

# -- Verify critical modules import (AD/GPO - only if relevant) --
if ($isWindows) {
    Write-Host '  Module Verification' -ForegroundColor White
    Write-Host '  -------------------' -ForegroundColor DarkGray

    $critical = @('GroupPolicy', 'ActiveDirectory')
    foreach ($mod in $critical) {
        try {
            Import-Module $mod -ErrorAction Stop
            Write-Status '+' "$mod" Green
        } catch {
            if ($isDomainJoined) {
                Write-Status 'x' "$mod - $($_.Exception.Message)" Red
            } else {
                Write-Status '-' "$mod (requires domain)" Yellow
            }
        }
    }

    # -- Verify system tools --
    $auditpol = Get-Command auditpol.exe -ErrorAction SilentlyContinue
    if ($auditpol) {
        Write-Status '+' 'auditpol.exe' Green
    } else {
        Write-Status 'x' 'auditpol.exe not found' Red
    }

    $secedit = Get-Command secedit.exe -ErrorAction SilentlyContinue
    if ($secedit) {
        Write-Status '+' 'secedit.exe' Green
    } else {
        Write-Status 'x' 'secedit.exe not found' Red
    }

    Write-Host ''
}

# -- Summary --
Write-Host '  ======================================' -ForegroundColor DarkGray
if ($isDomainJoined) {
    Write-Status '+' 'Ready: Domain-joined - all features available' Green
} elseif ($isServer) {
    Write-Status '!' 'Ready: Standalone server - audit OK, GPO apply requires domain' Yellow
} elseif ($isWindows) {
    Write-Status '!' 'Ready: Workstation - audit OK, GPO apply requires domain server' Yellow
} else {
    Write-Status '!' 'Non-Windows - this tool requires Windows' Yellow
}
Write-Host ''
Write-Host '  Next: .\Invoke-CISAudit.ps1' -ForegroundColor White
Write-Host ''
