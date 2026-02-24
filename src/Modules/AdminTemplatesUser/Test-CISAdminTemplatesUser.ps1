function Test-CISAdminTemplatesUser {
    <#
    .SYNOPSIS
        Audits CIS Section 19 - Administrative Templates (User Configuration).
    .DESCRIPTION
        Reads HKCU registry values. Note: these values reflect the currently
        logged-on user's applied policy. For accurate GPO-level auditing, run
        as a user in the target OU or inspect the GPO directly.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'AdminTemplatesUser'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AdminTemplatesUser' -Level Warning -Module $moduleName
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
