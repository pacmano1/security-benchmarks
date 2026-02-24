<#
.SYNOPSIS
    Installs RSAT tools and PowerShell modules required by CIS Benchmark automation.
.DESCRIPTION
    Must be run as Administrator on the target Windows Server 2025 machine.
    Installs: RSAT-AD-PowerShell, GroupPolicy, GPMC, and NuGet/Pester for testing.
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host '=== CIS Benchmark - Installing Prerequisites ===' -ForegroundColor Cyan

# ── Windows Features (RSAT) ──
$features = @(
    'RSAT-AD-PowerShell',       # ActiveDirectory module
    'GPMC',                     # Group Policy Management Console
    'RSAT-DNS-Server'           # DNS management (optional, useful for AD troubleshooting)
)

foreach ($feat in $features) {
    $installed = Get-WindowsFeature -Name $feat -ErrorAction SilentlyContinue
    if ($installed -and $installed.Installed) {
        Write-Host "[OK] $feat is already installed" -ForegroundColor Green
    } else {
        Write-Host "[INSTALLING] $feat ..." -ForegroundColor Yellow
        Install-WindowsFeature -Name $feat -IncludeManagementTools -ErrorAction Stop
        Write-Host "[OK] $feat installed" -ForegroundColor Green
    }
}

# ── PowerShell modules ──
# Ensure NuGet provider
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host '[INSTALLING] NuGet package provider ...' -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

# Pester (for tests/)
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge '5.0' })) {
    Write-Host '[INSTALLING] Pester 5.x ...' -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
} else {
    Write-Host '[OK] Pester 5.x is already installed' -ForegroundColor Green
}

# ── Verify critical modules import ──
$critical = @('GroupPolicy', 'ActiveDirectory')
foreach ($mod in $critical) {
    try {
        Import-Module $mod -ErrorAction Stop
        Write-Host "[OK] Import-Module $mod succeeded" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not import $mod - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ── Verify auditpol is available ──
$auditpol = Get-Command auditpol.exe -ErrorAction SilentlyContinue
if ($auditpol) {
    Write-Host '[OK] auditpol.exe is available' -ForegroundColor Green
} else {
    Write-Host '[WARN] auditpol.exe not found - AuditPolicy module will not work' -ForegroundColor Yellow
}

# ── Verify secedit is available ──
$secedit = Get-Command secedit.exe -ErrorAction SilentlyContinue
if ($secedit) {
    Write-Host '[OK] secedit.exe is available' -ForegroundColor Green
} else {
    Write-Host '[WARN] secedit.exe not found - SecurityOptions/UserRights modules may not work' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== Prerequisites installation complete ===' -ForegroundColor Cyan
Write-Host 'Next: Run Invoke-CISAudit.ps1 to audit your current configuration.' -ForegroundColor White
