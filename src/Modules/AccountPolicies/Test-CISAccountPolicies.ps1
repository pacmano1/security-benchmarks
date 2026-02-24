function Test-CISAccountPolicies {
    <#
    .SYNOPSIS
        Audits CIS Section 1 - Account Policies.
    .DESCRIPTION
        Uses secedit /export to read domain password and lockout policies.
        NOTE: In AWS Managed AD, these are controlled by AWS and cannot be
        changed via member server GPO. This function reports current state.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'AccountPolicies'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AccountPolicies' -Level Warning -Module $moduleName
        return @()
    }

    $seceditData = Get-SeceditExport

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

        $key      = $ctl.SeceditKey
        $expected = $ctl.ExpectedValue
        $operator = if ($ctl.Operator) { $ctl.Operator } else { 'Equals' }
        $actual   = $seceditData[$key]

        if ($null -eq $actual) {
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Fail'
                Expected = "$expected ($($ctl.Description))"
                Actual   = '(not found)'
                Detail   = "secedit key: $key"
            }
            continue
        }

        $numActual   = [int]$actual
        $numExpected = [int]$expected

        $pass = switch ($operator) {
            'GreaterOrEqual' { $numActual -ge $numExpected }
            'LessOrEqual'    { $numActual -le $numExpected -and $numActual -ne 0 }
            'Equals'         { $actual -eq $expected }
            default          { $actual -eq $expected }
        }

        [PSCustomObject]@{
            Id       = $ctl.Id
            Title    = $ctl.Title
            Module   = $moduleName
            Status   = if ($pass) { 'Pass' } else { 'Fail' }
            Expected = "$expected ($($ctl.Description))"
            Actual   = $actual
            Detail   = "secedit key: $key (AWS Managed AD controls domain policy)"
        }
    }

    Write-Progress -Activity "Auditing $moduleName" -Completed

    return $results
}
