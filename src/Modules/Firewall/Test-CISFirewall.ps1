function Test-CISFirewall {
    <#
    .SYNOPSIS
        Audits CIS Section 9 - Windows Defender Firewall controls.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'Firewall'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for Firewall' -Level Warning -Module $moduleName
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
