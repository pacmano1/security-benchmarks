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
.PARAMETER Force
    Skip interactive prompts (use defaults for all options).
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),

    [string[]]$Modules,

    [switch]$SkipPrereqCheck,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Clear-Host
Write-Host ''
Write-Host '  CIS Benchmark L1 - Compliance Audit' -ForegroundColor White
Write-Host '  ====================================' -ForegroundColor DarkGray
Write-Host ''

# -- Import module --
$modulePath = Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psm1'
Import-Module $modulePath -Force

# -- Initialize --
Write-Host '  [1/4] Initializing...' -ForegroundColor Cyan
$config = Initialize-CISEnvironment -ProjectRoot $ProjectRoot -SkipPrereqCheck:$SkipPrereqCheck

# -- Detect domain membership --
$isDomainJoined = $false
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $isDomainJoined = [bool]$cs.PartOfDomain
} catch { }

# -- Pre-flight connectivity (domain-joined only) --
if ($isDomainJoined -and $config.HaltOnConnectivityFailure -and -not $SkipPrereqCheck) {
    Write-Host '  [2/4] Pre-flight connectivity check...' -ForegroundColor Cyan
    $connectivity = Test-AWSConnectivity
    if (-not $connectivity.Pass) {
        Write-Host '    x  Pre-flight FAILED - aborting audit' -ForegroundColor Red
        Write-CISLog -Message 'Pre-flight connectivity check FAILED - aborting audit.' -Level Error
        exit 1
    }
    Write-Host '    +  Connectivity OK' -ForegroundColor Green
} else {
    Write-Host '  [2/4] Pre-flight check skipped' -ForegroundColor DarkGray
}

# -- Determine which modules to audit --
$enabledModules = @($config.Modules.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key })
if ($Modules) {
    $modulesToAudit = $Modules
} elseif (-not $Force) {
    Write-Host ''
    $modChoice = Read-Host '  ? Audit all enabled modules or select specific ones? [A/s]'
    if ($modChoice -match '^[Ss]') {
        Write-Host ''
        Write-Host '  Enabled modules:' -ForegroundColor White
        for ($i = 0; $i -lt $enabledModules.Count; $i++) {
            Write-Host "    $($i + 1). $($enabledModules[$i])" -ForegroundColor Cyan
        }
        Write-Host ''
        $picks = Read-Host '  Enter module numbers separated by commas (e.g. 1,3,5)'
        $selectedIndices = $picks -split ',' | ForEach-Object { ($_.Trim()) -as [int] } | Where-Object { $_ -ge 1 -and $_ -le $enabledModules.Count }
        if ($selectedIndices.Count -gt 0) {
            $modulesToAudit = @($selectedIndices | ForEach-Object { $enabledModules[$_ - 1] })
        } else {
            Write-Host '    !  No valid selection — using all enabled modules' -ForegroundColor Yellow
            $modulesToAudit = $enabledModules
        }
    } else {
        $modulesToAudit = $enabledModules
    }
} else {
    $modulesToAudit = $enabledModules
}

# -- Run each module's Test function --
Write-Host "  [3/4] Auditing $($modulesToAudit.Count) modules..." -ForegroundColor Cyan
Write-Host ''

$allResults = @()
$modIndex = 0

foreach ($modName in $modulesToAudit) {
    $modIndex++
    $testFunc = "Test-CIS$modName"

    if (-not (Get-Command $testFunc -ErrorAction SilentlyContinue)) {
        Write-Host "    -  $modName (function not found, skipped)" -ForegroundColor Yellow
        continue
    }

    Write-Host "    ~  $modName ..." -ForegroundColor DarkGray -NoNewline

    try {
        $moduleResults = & $testFunc
        if ($moduleResults) {
            $allResults += $moduleResults
            $modPass = ($moduleResults | Where-Object { $_.Status -eq 'Pass' }).Count
            $modFail = ($moduleResults | Where-Object { $_.Status -eq 'Fail' }).Count
            $modSkip = ($moduleResults | Where-Object { $_.Status -eq 'Skipped' }).Count
            Write-Host "`r    +  $modName" -ForegroundColor Green -NoNewline
            Write-Host "  $modPass passed" -ForegroundColor Green -NoNewline
            Write-Host " / $modFail failed" -ForegroundColor $(if ($modFail -gt 0) { 'Red' } else { 'Green' }) -NoNewline
            if ($modSkip -gt 0) {
                Write-Host " / $modSkip skipped" -ForegroundColor Yellow -NoNewline
            }
            Write-Host ''
        } else {
            Write-Host "`r    -  $modName (no results)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "`r    x  $modName - $($_.Exception.Message)" -ForegroundColor Red
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

Write-Host ''

# -- Generate report --
Write-Host '  [4/4] Generating report...' -ForegroundColor Cyan

if ($allResults.Count -gt 0) {
    $summary = Export-CISReport -Results $allResults -Formats $config.ReportFormats

    Write-Host ''
    Write-Host '  ====================================' -ForegroundColor DarkGray
    Write-Host '  Audit Complete' -ForegroundColor White
    Write-Host '  -----------------------------------' -ForegroundColor DarkGray
    Write-Host "    Total:      $($summary.Total)" -ForegroundColor White
    Write-Host "    Passed:     $($summary.Passed)" -ForegroundColor Green
    Write-Host "    Failed:     $($summary.Failed)" -ForegroundColor $(if ($summary.Failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host "    Skipped:    $($summary.Skipped)" -ForegroundColor Yellow
    Write-Host "    Errors:     $($summary.Errors)" -ForegroundColor $(if ($summary.Errors -gt 0) { 'Red' } else { 'White' })
    Write-Host '  -----------------------------------' -ForegroundColor DarkGray
    Write-Host "    Compliance: $($summary.PassPercent)%" -ForegroundColor $(
        if ($summary.PassPercent -ge 90) { 'Green' }
        elseif ($summary.PassPercent -ge 70) { 'Yellow' }
        else { 'Red' }
    )
    Write-Host '  ====================================' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  Report: $(Join-Path $config.ProjectRoot 'reports')" -ForegroundColor DarkGray
} else {
    Write-Host ''
    Write-Host '    !  No audit results' -ForegroundColor Yellow
    Write-Host '       Check that modules are enabled and config files exist.' -ForegroundColor DarkGray
}
Write-Host ''
