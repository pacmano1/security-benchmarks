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

# -- Import module --
$modulePath = Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# -- Initialize (minimal - just logging + config) --
Write-Host '  [1/4] Initializing...' -ForegroundColor Cyan
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck

# -- Find backup --
Write-Host '  [2/4] Locating backup...' -ForegroundColor Cyan

if (-not $BackupPath) {
    $backupsDir = Join-Path $ProjectRoot 'backups'
    $allBackups = @(Get-ChildItem -Path $backupsDir -Directory -Filter 'CIS-Backup-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending)

    if ($allBackups.Count -eq 0) {
        Write-Host '    x  No backups found. Cannot rollback.' -ForegroundColor Red
        Write-Host ''
        exit 1
    }

    if ($allBackups.Count -gt 1 -and -not $Force) {
        Write-Host ''
        Write-Host '  Available backups:' -ForegroundColor White
        for ($i = 0; $i -lt $allBackups.Count; $i++) {
            $bkName = $allBackups[$i].Name
            # Extract timestamp from folder name (CIS-Backup-yyyyMMdd-HHmmss)
            $ts = $bkName -replace '^CIS-Backup-', ''
            $label = if ($i -eq 0) { "$bkName (most recent)" } else { $bkName }
            Write-Host "    $($i + 1). $label" -ForegroundColor $(if ($i -eq 0) { 'Cyan' } else { 'White' })
        }
        Write-Host ''
        $bkChoice = Read-Host "  ? Select a backup [1] (default: most recent)"
        $bkIndex = if ($bkChoice -match '^\d+$') { [int]$bkChoice - 1 } else { 0 }
        if ($bkIndex -lt 0 -or $bkIndex -ge $allBackups.Count) { $bkIndex = 0 }
        $BackupPath = $allBackups[$bkIndex].FullName
        Write-Host "    +  Selected: $($allBackups[$bkIndex].Name)" -ForegroundColor Green
    } else {
        $BackupPath = $allBackups[0].FullName
        Write-Host "    +  Found: $($allBackups[0].Name)" -ForegroundColor Green
    }
} else {
    Write-Host "    +  Using: $(Split-Path $BackupPath -Leaf)" -ForegroundColor Green
}

# -- Module scope prompt --
if (-not $Module -and -not $Force) {
    Write-Host ''
    $modChoice = Read-Host '  ? Rollback all modules or a specific one? [A/s]'
    if ($modChoice -match '^[Ss]') {
        # List modules from the backup directory (subfolders)
        $backupModules = @(Get-ChildItem -Path $BackupPath -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($backupModules.Count -gt 0) {
            Write-Host ''
            Write-Host '  Modules in backup:' -ForegroundColor White
            for ($i = 0; $i -lt $backupModules.Count; $i++) {
                Write-Host "    $($i + 1). $($backupModules[$i])" -ForegroundColor Cyan
            }
            Write-Host ''
            $modPick = Read-Host '  Enter module number'
            $modIdx = if ($modPick -match '^\d+$') { [int]$modPick - 1 } else { -1 }
            if ($modIdx -ge 0 -and $modIdx -lt $backupModules.Count) {
                $Module = $backupModules[$modIdx]
                Write-Host "    +  Selected module: $Module" -ForegroundColor Green
            } else {
                Write-Host '    !  No valid selection — rolling back all modules' -ForegroundColor Yellow
            }
        } else {
            Write-Host '    !  No module subfolders found in backup — rolling back all' -ForegroundColor Yellow
        }
    }
}

# -- Confirmation --
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

# -- Detect domain membership --
$isDomainJoined = $false
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $isDomainJoined = [bool]$cs.PartOfDomain
} catch { }

# -- Pre-flight --
if ($isDomainJoined) {
    Write-Host '  [3/4] Pre-flight connectivity check...' -ForegroundColor Cyan
    $preFlight = Test-AWSConnectivity
    if (-not $preFlight.Pass) {
        Write-Host '    !  Connectivity issues detected. Proceeding anyway.' -ForegroundColor Yellow
    } else {
        Write-Host '    +  Connectivity OK' -ForegroundColor Green
    }
} else {
    Write-Host '  [3/4] Pre-flight check skipped (standalone)' -ForegroundColor DarkGray
}

# -- Restore --
Write-Host ''
Write-Host '  [4/4] Restoring...' -ForegroundColor Cyan

$restoreParams = @{
    BackupPath = $BackupPath
}
if ($Module) { $restoreParams.Module = $Module }
if ($RemoveGPOs) { $restoreParams.RemoveGPOs = $true }

Restore-CISState @restoreParams

Write-Host '    +  Restore complete' -ForegroundColor Green

# -- Post-flight --
Write-Host ''
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host '  Rollback Complete' -ForegroundColor White
Write-Host '  ----------------------------' -ForegroundColor DarkGray
if ($isDomainJoined) {
    Write-Host '  Post-rollback connectivity check...' -ForegroundColor Cyan
    $postFlight = Test-AWSConnectivity
    if ($postFlight.Pass) {
        Write-Host '    +  Connectivity: ALL PASSED' -ForegroundColor Green
    } else {
        Write-Host '    !  Connectivity: ISSUES DETECTED' -ForegroundColor Yellow
        Write-Host '       Review the results above.' -ForegroundColor DarkGray
    }
} else {
    Write-Host '    +  Local rollback complete' -ForegroundColor Green
}
Write-Host '  ============================' -ForegroundColor DarkGray
Write-Host ''
