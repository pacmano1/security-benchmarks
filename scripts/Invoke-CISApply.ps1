<#
.SYNOPSIS
    Entry point: creates GPOs and applies CIS Benchmark L1 settings.
.DESCRIPTION
    1. Initializes environment and loads configuration
    2. Runs pre-flight connectivity check
    3. Creates state backup
    4. Creates GPO framework (one GPO per module)
    5. Applies settings for each enabled module
    6. Runs post-flight connectivity check
    7. If post-flight fails, offers rollback
.PARAMETER ProjectRoot
    Path to the security_benchmarks project root.
.PARAMETER Modules
    Limit apply to specific modules.
.PARAMETER DryRun
    Override DryRun setting. If not specified, uses master config value.
.PARAMETER SkipPrereqCheck
    Skip prerequisite validation.
.PARAMETER Force
    Skip confirmation prompts.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),

    [string[]]$Modules,

    [Nullable[bool]]$DryRun,

    [switch]$SkipPrereqCheck,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ── Import module ──
$modulePath = Join-Path $ProjectRoot 'src' 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# ── Initialize ──
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck:$SkipPrereqCheck

# Override DryRun if explicitly passed
$isDryRun = if ($null -ne $DryRun) { $DryRun } else { $config.DryRun }

Write-CISLog -Message "=== CIS Benchmark - Apply Mode (DryRun: $isDryRun) ===" -Level Info

# ── Safety confirmation ──
if (-not $isDryRun -and -not $Force) {
    Write-Host ''
    Write-Host '+========================================================+' -ForegroundColor Yellow
    Write-Host '|  WARNING: This will CREATE GPOs and APPLY settings!   |' -ForegroundColor Yellow
    Write-Host '|  Target OU:' "$($config.TargetOU)".PadRight(42) '|' -ForegroundColor Yellow
    Write-Host '+========================================================+' -ForegroundColor Yellow
    Write-Host ''

    $confirm = Read-Host 'Type YES to proceed'
    if ($confirm -ne 'YES') {
        Write-CISLog -Message 'Apply cancelled by user.' -Level Warning
        exit 0
    }
}

# ── Pre-flight connectivity ──
if ($config.HaltOnConnectivityFailure -and -not $SkipPrereqCheck) {
    $preFlight = Test-AWSConnectivity
    if (-not $preFlight.Pass) {
        Write-CISLog -Message 'Pre-flight connectivity check FAILED - aborting apply.' -Level Error
        exit 1
    }
}

# ── Determine modules ──
$modulesToApply = if ($Modules) {
    $Modules
} else {
    $config.Modules.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }
}

# ── Backup current state ──
if (-not $isDryRun) {
    Write-CISLog -Message 'Creating pre-apply state backup...' -Level Info
    $backupPath = Backup-CISState -Modules $modulesToApply
    Write-CISLog -Message "Backup saved: $backupPath" -Level Info
}

# ── Create GPO framework ──
$gpoMap = New-CISGpoFramework -DryRun $isDryRun

# ── Apply each module ──
$applyOrder = @(
    'AdminTemplates'         # Registry-based (largest)
    'Firewall'               # Registry-based
    'AdminTemplatesUser'     # Registry-based (User config)
    'SecurityOptions'        # Registry + secedit
    'UserRightsAssignment'   # secedit GptTmpl.inf
    'AuditPolicy'            # auditpol audit.csv
    'Services'               # Registry-based
    'AccountPolicies'        # Skip (AWS-owned)
)

foreach ($modName in $applyOrder) {
    if ($modName -notin $modulesToApply) { continue }

    $setFunc = "Set-CIS$modName"
    if (-not (Get-Command $setFunc -ErrorAction SilentlyContinue)) {
        Write-CISLog -Message "Apply function not found: $setFunc - skipping" -Level Warning
        continue
    }

    $gpoName = $gpoMap[$modName]
    if (-not $gpoName) {
        Write-CISLog -Message "No GPO mapped for module: $modName - skipping" -Level Warning
        continue
    }

    Write-CISLog -Message "-- Applying: $modName -> $gpoName --" -Level Info

    try {
        & $setFunc -GpoName $gpoName -DryRun $isDryRun
    } catch {
        Write-CISLog -Message "Error applying $modName`: $_" -Level Error
    }
}

# ── Post-flight connectivity ──
if ($config.PostFlightCheck -and -not $isDryRun -and -not $SkipPrereqCheck) {
    Write-CISLog -Message 'Running post-flight connectivity check...' -Level Info
    $postFlight = Test-AWSConnectivity

    if (-not $postFlight.Pass) {
        Write-CISLog -Message '+======================================================+' -Level Error
        Write-CISLog -Message '|  POST-FLIGHT CONNECTIVITY CHECK FAILED!             |' -Level Error
        Write-CISLog -Message '|  Management access may be impaired.                 |' -Level Error
        Write-CISLog -Message "|  Backup location: $backupPath" -Level Error
        Write-CISLog -Message '|  Run Invoke-CISRollback.ps1 to revert changes.      |' -Level Error
        Write-CISLog -Message '+======================================================+' -Level Error
        exit 1
    }
}

# ── Run audit to show compliance delta ──
Write-CISLog -Message '=== Apply complete - running compliance audit ===' -Level Info

$allResults = @()
foreach ($modName in $modulesToApply) {
    $testFunc = "Test-CIS$modName"
    if (Get-Command $testFunc -ErrorAction SilentlyContinue) {
        try {
            $results = & $testFunc
            if ($results) { $allResults += $results }
        } catch {
            Write-CISLog -Message "Post-apply audit error for $modName`: $_" -Level Warning
        }
    }
}

if ($allResults.Count -gt 0) {
    $summary = Export-CISReport -Results $allResults -Formats $config.ReportFormats
    Write-CISLog -Message "Post-apply compliance: $($summary.PassPercent)% ($($summary.Passed)/$($summary.Total - $summary.Skipped))" -Level Info
}

Write-CISLog -Message '=== CIS Benchmark Apply - Complete ===' -Level Info
