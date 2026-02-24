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

# ── Import module ──
$modulePath = Join-Path $ProjectRoot 'src' 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# ── Initialize (minimal — just logging + config) ──
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck

# ── Find backup ──
if (-not $BackupPath) {
    $backupsDir = Join-Path $ProjectRoot 'backups'
    $latest = Get-ChildItem -Path $backupsDir -Directory -Filter 'CIS-Backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($latest) {
        $BackupPath = $latest.FullName
        Write-CISLog -Message "Using most recent backup: $BackupPath" -Level Info
    } else {
        Write-CISLog -Message 'No backups found. Cannot rollback without a backup.' -Level Error
        exit 1
    }
}

# ── Confirmation ──
if (-not $Force) {
    Write-Host ''
    Write-Host '+========================================================+' -ForegroundColor Yellow
    Write-Host '|  ROLLBACK: This will revert CIS Benchmark changes!   |' -ForegroundColor Yellow
    Write-Host "|  Backup: $($BackupPath | Split-Path -Leaf)".PadRight(55) + '|' -ForegroundColor Yellow
    if ($Module) {
        Write-Host "|  Module: $Module".PadRight(55) + '|' -ForegroundColor Yellow
    }
    if ($RemoveGPOs) {
        Write-Host '|  Mode: REMOVE GPOs entirely                          |' -ForegroundColor Red
    } else {
        Write-Host '|  Mode: Restore GPOs to pre-apply state               |' -ForegroundColor Yellow
    }
    Write-Host '+========================================================+' -ForegroundColor Yellow
    Write-Host ''

    $confirm = Read-Host 'Type YES to proceed with rollback'
    if ($confirm -ne 'YES') {
        Write-CISLog -Message 'Rollback cancelled by user.' -Level Warning
        exit 0
    }
}

Write-CISLog -Message '=== CIS Benchmark - Rollback ===' -Level Info

# ── Pre-flight ──
$preFlight = Test-AWSConnectivity
if (-not $preFlight.Pass) {
    Write-CISLog -Message 'WARNING: Connectivity issues detected before rollback. Proceeding anyway.' -Level Warning
}

# ── Restore ──
$restoreParams = @{
    BackupPath = $BackupPath
}
if ($Module) { $restoreParams.Module = $Module }
if ($RemoveGPOs) { $restoreParams.RemoveGPOs = $true }

Restore-CISState @restoreParams

# ── Post-flight ──
Write-CISLog -Message 'Running post-rollback connectivity check...' -Level Info
$postFlight = Test-AWSConnectivity

if ($postFlight.Pass) {
    Write-CISLog -Message 'Post-rollback connectivity: ALL PASSED' -Level Info
} else {
    Write-CISLog -Message 'Post-rollback connectivity: ISSUES DETECTED - check results above' -Level Warning
}

Write-CISLog -Message '=== CIS Benchmark Rollback - Complete ===' -Level Info
