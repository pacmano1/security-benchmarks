function Test-CISAdminTemplates {
    <#
    .SYNOPSIS
        Audits CIS Section 18 - Administrative Templates (Computer) controls.
    .DESCRIPTION
        All controls are registry-based. Reads current values and compares
        against CIS-required values.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'AdminTemplates'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AdminTemplates' -Level Warning -Module $moduleName
        return @()
    }

    $total = $controls.Count
    $i = 0
    $results = foreach ($ctl in $controls) {
        $i++
        Write-Progress -Activity "Auditing $moduleName" -Status "$i of $total - $($ctl.Id)" -PercentComplete (($i / $total) * 100)

        if ($ctl.Skipped) {
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Skipped'
                Expected = ''
                Actual   = ''
                Detail   = $ctl.SkipReason
            }
            continue
        }

        try {
            Test-RegistryControl -Control $ctl -ModuleName $moduleName
        } catch {
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Error'
                Expected = ''
                Actual   = ''
                Detail   = $_.Exception.Message
            }
        }
    }
    Write-Progress -Activity "Auditing $moduleName" -Completed

    return $results
}
