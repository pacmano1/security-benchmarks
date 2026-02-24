function Set-CISAdminTemplatesUser {
    <#
    .SYNOPSIS
        Applies CIS Section 19 - Administrative Templates (User) via GPO.
    .DESCRIPTION
        Uses Set-GPRegistryValue targeting the User Configuration portion
        of the GPO (HKCU paths).
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

    $moduleName = 'AdminTemplatesUser'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AdminTemplatesUser' -Level Warning -Module $moduleName
        return
    }

    $activeControls = $controls | Where-Object { -not $_.Skipped -and $_.Registry }
    $applied = 0
    $errors  = 0

    foreach ($ctl in $activeControls) {
        $reg   = $ctl.Registry
        $value = Get-AWSModifiedValue -ControlId $ctl.Id -DefaultValue $reg.Value
        # Convert HKCU path to the GPO registry format
        $gpRegPath = $reg.Path -replace '^HKCU:\\', 'HKCU\'

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would set (User) $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
            $applied++
        } else {
            try {
                Set-GPRegistryValue -Name $GpoName -Key $gpRegPath -ValueName $reg.Name -Type $reg.Type -Value $value -ErrorAction Stop
                Write-CISLog -Message "Set (User) $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
                $applied++
            } catch {
                Write-CISLog -Message "Failed to set $($ctl.Id): $_" -Level Error -ControlId $ctl.Id
                $errors++
            }
        }
    }

    Write-CISLog -Message "AdminTemplatesUser: $applied settings applied, $errors errors" -Level Info -Module $moduleName
}
