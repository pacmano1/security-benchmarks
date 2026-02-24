<#
.SYNOPSIS
    Entry point: rolls back CIS Benchmark changes from a backup.
.DESCRIPTION
    Restores GPO state from a prior backup created by Invoke-CISApply.
    Can restore specific modules or all, and optionally remove GPOs entirely.
.PARAMETER ProjectRoot
    Path to the security_benchmarks project root.
.PARAMETER BackupPath
    Explicit backup folder path. If omitted, uses the most recent backup.
.PARAMETER Module
    Rollback only a specific module (e.g., 'SecurityOptions').
.PARAMETER RemoveGPOs
    Remove CIS GPOs entirely instead of restoring prior state.
.PARAMETER Force
    Skip confirmation prompt.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),

    [string]$BackupPath,

    [string]$Module,

    [switch]$RemoveGPOs,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Clear-Host
Write-Host ''
Write-Host '  CIS Benchmark L1 - Rollback' -ForegroundColor White
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host ''

# ── Import module ──
$modulePath = Join-Path $ProjectRoot 'src' 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# ── Initialize (minimal - just logging + config) ──
Write-Host '  [1/4] Initializing...' -ForegroundColor Cyan
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck

# ── Find backup ──
Write-Host '  [2/4] Locating backup...' -ForegroundColor Cyan

if (-not $BackupPath) {
    $backupsDir = Join-Path $ProjectRoot 'backups'
    $latest = Get-ChildItem -Path $backupsDir -Directory -Filter 'CIS-Backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($latest) {
        $BackupPath = $latest.FullName
        Write-Host "    +  Found: $($latest.Name)" -ForegroundColor Green
    } else {
        Write-Host '    x  No backups found. Cannot rollback.' -ForegroundColor Red
        Write-Host ''
        exit 1
    }
} else {
    Write-Host "    +  Using: $(Split-Path $BackupPath -Leaf)" -ForegroundColor Green
}

# ── Confirmation ──
if (-not $Force) {
    Write-Host ''
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  |  ROLLBACK: This will revert CIS Benchmark changes!       |' -ForegroundColor Yellow
    Write-Host "  |  Backup: $(($BackupPath | Split-Path -Leaf).PadRight(47))|" -ForegroundColor Yellow
    if ($Module) {
        Write-Host "  |  Module: $($Module.PadRight(47))|" -ForegroundColor Yellow
    }
    if ($RemoveGPOs) {
        Write-Host '  |  Mode:   REMOVE GPOs entirely                           |' -ForegroundColor Red
    } else {
        Write-Host '  |  Mode:   Restore GPOs to pre-apply state                |' -ForegroundColor Yellow
    }
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host ''

    $confirm = Read-Host '  Type YES to proceed with rollback'
    if ($confirm -ne 'YES') {
        Write-Host ''
        Write-Host '    -  Rollback cancelled by user.' -ForegroundColor Yellow
        Write-Host ''
        exit 0
    }
    Write-Host ''
}

# ── Pre-flight ──
Write-Host '  [3/4] Pre-flight connectivity check...' -ForegroundColor Cyan
$preFlight = Test-AWSConnectivity
if (-not $preFlight.Pass) {
    Write-Host '    !  Connectivity issues detected. Proceeding anyway.' -ForegroundColor Yellow
} else {
    Write-Host '    +  Connectivity OK' -ForegroundColor Green
}

# ── Restore ──
Write-Host ''
Write-Host '  [4/4] Restoring...' -ForegroundColor Cyan

$restoreParams = @{
    BackupPath = $BackupPath
}
if ($Module) { $restoreParams.Module = $Module }
if ($RemoveGPOs) { $restoreParams.RemoveGPOs = $true }

Restore-CISState @restoreParams

Write-Host '    +  Restore complete' -ForegroundColor Green

# ── Post-flight ──
Write-Host ''
Write-Host '  Post-rollback connectivity check...' -ForegroundColor Cyan
$postFlight = Test-AWSConnectivity

Write-Host ''
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host '  Rollback Complete' -ForegroundColor White
Write-Host '  ----------------------------' -ForegroundColor DarkGray
if ($postFlight.Pass) {
    Write-Host '    +  Connectivity: ALL PASSED' -ForegroundColor Green
} else {
    Write-Host '    !  Connectivity: ISSUES DETECTED' -ForegroundColor Yellow
    Write-Host '       Review the results above.' -ForegroundColor DarkGray
}
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host ''
