<#
.SYNOPSIS
    Entry point: audits the current system against CIS Benchmark L1 controls.
.DESCRIPTION
    Loads configuration, runs Test-CIS* for every enabled module, and generates
    an HTML + JSON compliance report. Does NOT modify any settings.
.PARAMETER ProjectRoot
    Path to the security_benchmarks project root. Defaults to parent of scripts/.
.PARAMETER Modules
    Limit audit to specific modules (e.g., 'SecurityOptions','AuditPolicy').
    If omitted, all enabled modules from master-config are audited.
.PARAMETER SkipPrereqCheck
    Skip prerequisite validation.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),

    [string[]]$Modules,

    [switch]$SkipPrereqCheck
)

$ErrorActionPreference = 'Stop'

# ── Import module ──
$modulePath = Join-Path $ProjectRoot 'src' 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# ── Initialize ──
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck:$SkipPrereqCheck

# ── Pre-flight connectivity ──
if ($config.HaltOnConnectivityFailure -and -not $SkipPrereqCheck) {
    $connectivity = Test-AWSConnectivity
    if (-not $connectivity.Pass) {
        Write-CISLog -Message 'Pre-flight connectivity check FAILED - aborting audit.' -Level Error
        exit 1
    }
}

# ── Determine which modules to audit ──
$modulesToAudit = if ($Modules) {
    $Modules
} else {
    $config.Modules.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }
}

Write-CISLog -Message "Auditing modules: $($modulesToAudit -join ', ')" -Level Info

# ── Run each module's Test function ──
$allResults = @()

foreach ($modName in $modulesToAudit) {
    $testFunc = "Test-CIS$modName"

    if (-not (Get-Command $testFunc -ErrorAction SilentlyContinue)) {
        Write-CISLog -Message "Audit function not found: $testFunc - skipping" -Level Warning
        continue
    }

    Write-CISLog -Message "-- Auditing: $modName --" -Level Info

    try {
        $moduleResults = & $testFunc
        if ($moduleResults) {
            $allResults += $moduleResults
            $modPass = ($moduleResults | Where-Object { $_.Status -eq 'Pass' }).Count
            $modFail = ($moduleResults | Where-Object { $_.Status -eq 'Fail' }).Count
            Write-CISLog -Message "$modName: $modPass passed, $modFail failed (of $($moduleResults.Count) controls)" -Level Info
        }
    } catch {
        Write-CISLog -Message "Error auditing $modName`: $_" -Level Error
        $allResults += [PSCustomObject]@{
            Id       = 'N/A'
            Title    = "$modName module error"
            Module   = $modName
            Status   = 'Error'
            Expected = ''
            Actual   = ''
            Detail   = $_.Exception.Message
        }
    }
}

# ── Generate report ──
if ($allResults.Count -gt 0) {
    $summary = Export-CISReport -Results $allResults -Formats $config.ReportFormats
    Write-CISLog -Message '===========================================' -Level Info
    Write-CISLog -Message "AUDIT COMPLETE - $($summary.Total) controls evaluated" -Level Info
    Write-CISLog -Message "Passed: $($summary.Passed) | Failed: $($summary.Failed) | Skipped: $($summary.Skipped) | Errors: $($summary.Errors)" -Level Info
    Write-CISLog -Message "Compliance: $($summary.PassPercent)%" -Level Info
    Write-CISLog -Message '===========================================' -Level Info
} else {
    Write-CISLog -Message 'No audit results - check that modules are enabled and config files exist.' -Level Warning
}
