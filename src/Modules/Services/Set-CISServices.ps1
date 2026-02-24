function Set-CISServices {
    <#
    .SYNOPSIS
        Applies CIS Section 5 - System Services via GPO registry.
    .DESCRIPTION
        Sets service startup type via the registry key for the service
        under HKLM\SYSTEM\CurrentControlSet\Services\<name>\Start.
    .PARAMETER GpoName
        Name of the GPO to configure.
    .PARAMETER DryRun
        If $true, logs what would be changed without modifying anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GpoName,

        [bool]$DryRun = $true
    )

    $moduleName = 'Services'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for Services' -Level Warning -Module $moduleName
        return
    }

    $startTypeMap = @{
        'Disabled' = 4
        'Manual'   = 3
        'Auto'     = 2
        'Boot'     = 0
        'System'   = 1
    }

    $activeControls = $controls | Where-Object { -not $_.Skipped }
    $applied = 0
    $errors  = 0

    foreach ($ctl in $activeControls) {
        $serviceName = $ctl.ServiceName
        $regValue    = $startTypeMap[$ctl.StartType]
        $gpRegPath   = "HKLM\SYSTEM\CurrentControlSet\Services\$serviceName"

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would set $gpRegPath\Start = $regValue ($($ctl.StartType))" -Level Info -ControlId $ctl.Id
            $applied++
        } else {
            try {
                Set-GPRegistryValue -Name $GpoName -Key $gpRegPath -ValueName 'Start' -Type DWord -Value $regValue -ErrorAction Stop
                Write-CISLog -Message "Set $serviceName startup = $($ctl.StartType)" -Level Info -ControlId $ctl.Id
                $applied++
            } catch {
                Write-CISLog -Message "Failed to set service $serviceName`: $_" -Level Error -ControlId $ctl.Id
                $errors++
            }
        }
    }

    Write-CISLog -Message "Services: $applied settings applied, $errors errors" -Level Info -Module $moduleName
}
