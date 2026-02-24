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

Clear-Host
Write-Host ''
Write-Host '  CIS Benchmark L1 - Apply Settings' -ForegroundColor White
Write-Host '  ==================================' -ForegroundColor DarkGray
Write-Host ''

# -- Import module --
$modulePath = Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# -- Initialize --
Write-Host '  [1/6] Initializing...' -ForegroundColor Cyan
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck:$SkipPrereqCheck

# Override DryRun if explicitly passed
$isDryRun = if ($null -ne $DryRun) { $DryRun } else { $config.DryRun }

if ($isDryRun) {
    Write-Host '    ~  Mode: DRY RUN (no changes will be made)' -ForegroundColor Yellow
} else {
    Write-Host '    !  Mode: LIVE (changes will be applied)' -ForegroundColor Red
}

# -- Safety confirmation --
if (-not $isDryRun -and -not $Force) {
    Write-Host ''
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  |  WARNING: This will CREATE GPOs and APPLY settings!      |' -ForegroundColor Yellow
    Write-Host "  |  Target OU: $($config.TargetOU)".PadRight(59) + '|' -ForegroundColor Yellow
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host ''

    $confirm = Read-Host '  Type YES to proceed'
    if ($confirm -ne 'YES') {
        Write-Host ''
        Write-Host '    -  Apply cancelled by user.' -ForegroundColor Yellow
        Write-Host ''
        exit 0
    }
    Write-Host ''
}

# -- Pre-flight connectivity --
if ($config.HaltOnConnectivityFailure -and -not $SkipPrereqCheck) {
    Write-Host '  [2/6] Pre-flight connectivity check...' -ForegroundColor Cyan
    $preFlight = Test-AWSConnectivity
    if (-not $preFlight.Pass) {
        Write-Host '    x  Pre-flight FAILED - aborting apply' -ForegroundColor Red
        Write-CISLog -Message 'Pre-flight connectivity check FAILED - aborting apply.' -Level Error
        exit 1
    }
    Write-Host '    +  Connectivity OK' -ForegroundColor Green
} else {
    Write-Host '  [2/6] Pre-flight check skipped' -ForegroundColor DarkGray
}

# -- Determine modules --
$modulesToApply = if ($Modules) {
    $Modules
} else {
    $config.Modules.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }
}

# -- Backup current state --
if (-not $isDryRun) {
    Write-Host '  [3/6] Creating state backup...' -ForegroundColor Cyan
    $backupPath = Backup-CISState -Modules $modulesToApply
    Write-Host "    +  Backup saved: $backupPath" -ForegroundColor Green
} else {
    Write-Host '  [3/6] Backup skipped (dry run)' -ForegroundColor DarkGray
}

# -- Create GPO framework --
Write-Host '  [4/6] Creating GPO framework...' -ForegroundColor Cyan
$gpoMap = New-CISGpoFramework -DryRun $isDryRun
Write-Host "    +  $($gpoMap.Count) GPOs configured" -ForegroundColor Green

# -- Apply each module --
Write-Host "  [5/6] Applying $($modulesToApply.Count) modules..." -ForegroundColor Cyan
Write-Host ''

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
        Write-Host "    -  $modName (function not found, skipped)" -ForegroundColor Yellow
        continue
    }

    $gpoName = $gpoMap[$modName]
    if (-not $gpoName) {
        Write-Host "    -  $modName (no GPO mapped, skipped)" -ForegroundColor Yellow
        continue
    }

    Write-Host "    ~  $modName -> $gpoName ..." -ForegroundColor DarkGray -NoNewline

    try {
        & $setFunc -GpoName $gpoName -DryRun $isDryRun
        Write-Host "`r    +  $modName -> $gpoName" -ForegroundColor Green
    } catch {
        Write-Host "`r    x  $modName - $($_.Exception.Message)" -ForegroundColor Red
        Write-CISLog -Message "Error applying $modName`: $_" -Level Error
    }
}

Write-Host ''

# -- Post-flight connectivity --
if ($config.PostFlightCheck -and -not $isDryRun -and -not $SkipPrereqCheck) {
    Write-Host '  [6/6] Post-flight connectivity check...' -ForegroundColor Cyan
    $postFlight = Test-AWSConnectivity

    if (-not $postFlight.Pass) {
        Write-Host ''
        Write-Host '  +----------------------------------------------------------+' -ForegroundColor Red
        Write-Host '  |  POST-FLIGHT CONNECTIVITY CHECK FAILED!                  |' -ForegroundColor Red
        Write-Host '  |  Management access may be impaired.                      |' -ForegroundColor Red
        Write-Host "  |  Backup: $backupPath" -ForegroundColor Red
        Write-Host '  |  Run Invoke-CISRollback.ps1 to revert changes.           |' -ForegroundColor Red
        Write-Host '  +----------------------------------------------------------+' -ForegroundColor Red
        Write-Host ''
        exit 1
    }
    Write-Host '    +  Connectivity OK' -ForegroundColor Green
} else {
    Write-Host '  [6/6] Post-flight check skipped' -ForegroundColor DarkGray
}

# -- Run audit to show compliance delta --
Write-Host ''
Write-Host '  Running post-apply compliance audit...' -ForegroundColor Cyan

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

    Write-Host ''
    Write-Host '  ==================================' -ForegroundColor DarkGray
    Write-Host '  Apply Complete' -ForegroundColor White
    Write-Host '  ---------------------------------' -ForegroundColor DarkGray
    Write-Host "    Mode:       $(if ($isDryRun) { 'DRY RUN' } else { 'LIVE' })" -ForegroundColor $(if ($isDryRun) { 'Yellow' } else { 'Green' })
    Write-Host "    Compliance: $($summary.PassPercent)% ($($summary.Passed)/$($summary.Total - $summary.Skipped))" -ForegroundColor $(
        if ($summary.PassPercent -ge 90) { 'Green' }
        elseif ($summary.PassPercent -ge 70) { 'Yellow' }
        else { 'Red' }
    )
    Write-Host '  ==================================' -ForegroundColor DarkGray
}
Write-Host ''
