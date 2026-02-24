function Get-CISConfiguration {
    <#
    .SYNOPSIS
        Loads master config, module configs, and AWS exclusions into a unified object.
    .DESCRIPTION
        Reads config/master-config.psd1, each enabled module's .psd1, and
        config/aws-exclusions.psd1. Merges them into $script:CISConfig used
        throughout the session.
    .PARAMETER ProjectRoot
        Root directory of the security_benchmarks project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    # ── Master config ──
    $masterPath = Join-Path (Join-Path $ProjectRoot 'config') 'master-config.psd1'
    if (-not (Test-Path $masterPath)) {
        throw "Master config not found: $masterPath"
    }
    $config = Import-PowerShellDataFile -Path $masterPath
    $config.ProjectRoot = $ProjectRoot

    Write-CISLog -Message "Loaded master config ($($config.BenchmarkVersion))" -Level Info

    # ── AWS exclusions ──
    $exclPath = Join-Path (Join-Path $ProjectRoot 'config') 'aws-exclusions.psd1'
    if (Test-Path $exclPath) {
        $config.AWSExclusions = Import-PowerShellDataFile -Path $exclPath
        Write-CISLog -Message "Loaded AWS exclusions ($($config.AWSExclusions.Skip.Count) skipped, $($config.AWSExclusions.Modify.Count) modified)" -Level Info
    } else {
        $config.AWSExclusions = @{ Skip = @(); Modify = @{} }
        Write-CISLog -Message 'No AWS exclusions file found - proceeding without exclusions' -Level Warning
    }

    # ── Module configs ──
    $config.ModuleConfigs = @{}
    $modulesDir = Join-Path (Join-Path $ProjectRoot 'config') 'modules'

    foreach ($modName in $config.Modules.Keys) {
        if (-not $config.Modules[$modName]) {
            Write-CISLog -Message "Module '$modName' is disabled - skipping config load" -Level Debug
            continue
        }

        $modFile = Join-Path $modulesDir "$modName.psd1"
        if (Test-Path $modFile) {
            $config.ModuleConfigs[$modName] = Import-PowerShellDataFile -Path $modFile
            $controlCount = $config.ModuleConfigs[$modName].Controls.Count
            Write-CISLog -Message "Loaded module config: $modName ($controlCount controls)" -Level Info
        } else {
            Write-CISLog -Message "Module config not found: $modFile - module will be skipped" -Level Warning
        }
    }

    # ── Apply exclusions ──
    # Mark skipped controls
    $skipIds = $config.AWSExclusions.Skip
    foreach ($modName in $config.ModuleConfigs.Keys) {
        $controls = $config.ModuleConfigs[$modName].Controls
        if (-not $controls) { continue }
        foreach ($ctl in $controls) {
            if ($skipIds -contains $ctl.Id) {
                $ctl.Skipped    = $true
                $ctl.SkipReason = 'AWS exclusion'
            }
        }
    }

    # Store globally
    $script:CISConfig = $config
    return $config
}
