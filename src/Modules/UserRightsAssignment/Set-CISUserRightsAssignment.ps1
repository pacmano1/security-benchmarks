function Set-CISUserRightsAssignment {
    <#
    .SYNOPSIS
        Applies CIS Section 2.2 - User Rights Assignment via GPO GptTmpl.inf.
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

    $moduleName = 'UserRightsAssignment'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for UserRightsAssignment' -Level Warning -Module $moduleName
        return
    }

    $activeControls = $controls | Where-Object { -not $_.Skipped }

    if ($DryRun) {
        foreach ($ctl in $activeControls) {
            $value = Get-AWSModifiedValue -ControlId $ctl.Id -DefaultValue $ctl.ExpectedValue
            Write-CISLog -Message "[DRY RUN] Would set privilege $($ctl.SeceditKey) = $value" -Level Info -ControlId $ctl.Id
        }
        return
    }

    # Write to GptTmpl.inf under [Privilege Rights]
    Write-GptTmplEntries -GpoName $GpoName -Controls $activeControls -Section 'Privilege Rights'
}
