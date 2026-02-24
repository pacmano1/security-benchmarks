# -----------------------------------------------------------------------------
# CISBenchmark.psm1 - Root module
# Dot-sources all Core and Module scripts.
# -----------------------------------------------------------------------------

$ModuleRoot = $PSScriptRoot

# -- Core functions (order matters: Write-CISLog first, then config, then rest) --
$coreScripts = @(
    'Core\Write-CISLog.ps1'
    'Core\Get-CISConfiguration.ps1'
    'Core\Initialize-CISEnvironment.ps1'
    'Core\Test-AWSConnectivity.ps1'
    'Core\Export-CISReport.ps1'
    'Core\New-CISGpoFramework.ps1'
    'Core\Backup-CISState.ps1'
    'Core\Restore-CISState.ps1'
)

foreach ($script in $coreScripts) {
    $path = Join-Path $ModuleRoot $script
    if (Test-Path $path) {
        . $path
    } else {
        Write-Warning "CISBenchmark: Core script not found - $script"
    }
}

# -- CIS Modules (each folder has Test-*.ps1 and Set-*.ps1) --
$moduleNames = @(
    'AccountPolicies'
    'UserRightsAssignment'
    'SecurityOptions'
    'AuditPolicy'
    'Services'
    'Firewall'
    'AdminTemplates'
    'AdminTemplatesUser'
)

foreach ($modName in $moduleNames) {
    $modDir = Join-Path (Join-Path $ModuleRoot 'Modules') $modName
    if (Test-Path $modDir) {
        Get-ChildItem -Path $modDir -Filter '*.ps1' -File | ForEach-Object {
            . $_.FullName
        }
    }
}
