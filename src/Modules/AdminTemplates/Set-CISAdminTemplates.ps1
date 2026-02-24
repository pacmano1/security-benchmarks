function Set-CISAdminTemplates {
    <#
    .SYNOPSIS
        Applies CIS Section 18 - Administrative Templates (Computer) via GPO.
    .DESCRIPTION
        All controls are registry-based. Uses Set-GPRegistryValue to write
        settings into the specified GPO.
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

    $moduleName = 'AdminTemplates'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AdminTemplates' -Level Warning -Module $moduleName
        return
    }

    $activeControls = $controls | Where-Object { -not $_.Skipped -and $_.Registry }
    $applied = 0
    $errors  = 0

    foreach ($ctl in $activeControls) {
        $reg   = $ctl.Registry
        $value = Get-AWSModifiedValue -ControlId $ctl.Id -DefaultValue $reg.Value
        $gpRegPath = $reg.Path -replace '^HKLM:\\', 'HKLM\'

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would set $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
            $applied++
        } else {
            try {
                Set-GPRegistryValue -Name $GpoName -Key $gpRegPath -ValueName $reg.Name -Type $reg.Type -Value $value -ErrorAction Stop
                Write-CISLog -Message "Set $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
                $applied++
            } catch {
                Write-CISLog -Message "Failed to set $($ctl.Id): $_" -Level Error -ControlId $ctl.Id
                $errors++
            }
        }
    }

    Write-CISLog -Message "AdminTemplates: $applied settings applied, $errors errors" -Level Info -Module $moduleName
}
