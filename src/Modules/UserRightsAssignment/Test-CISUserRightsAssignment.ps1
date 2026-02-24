function Test-CISUserRightsAssignment {
    <#
    .SYNOPSIS
        Audits CIS Section 2.2 - User Rights Assignment.
    .DESCRIPTION
        Exports security policy via secedit and compares privilege
        assignments against CIS-required values.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'UserRightsAssignment'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for UserRightsAssignment' -Level Warning -Module $moduleName
        return @()
    }

    # Export secedit once
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
        $actual   = $seceditData[$key]

        if ($null -eq $actual -and [string]::IsNullOrEmpty($expected)) {
            # Not set and expected empty - pass
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Pass'
                Expected = '(No One)'
                Actual   = '(not set)'
                Detail   = "Privilege: $key"
            }
            continue
        }

        if ($null -eq $actual) {
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Fail'
                Expected = $expected
                Actual   = '(not found)'
                Detail   = "Privilege not found in secedit: $key"
            }
            continue
        }

        # Normalize: sort SID lists for comparison
        $expectedSorted = ($expected -split ',' | ForEach-Object { $_.Trim() } | Sort-Object) -join ','
        $actualSorted   = ($actual -split ',' | ForEach-Object { $_.Trim() } | Sort-Object) -join ','

        # For "No One" - expected is empty, actual must be empty
        if ([string]::IsNullOrEmpty($expected)) {
            $pass = [string]::IsNullOrWhiteSpace($actual)
        } else {
            # Check that actual contains at least the expected SIDs
            $expectedSet = $expected -split ',' | ForEach-Object { $_.Trim() }
            $actualSet   = $actual -split ',' | ForEach-Object { $_.Trim() }
            $pass = ($expectedSet | Where-Object { $_ -notin $actualSet }).Count -eq 0
        }

        [PSCustomObject]@{
            Id       = $ctl.Id
            Title    = $ctl.Title
            Module   = $moduleName
            Status   = if ($pass) { 'Pass' } else { 'Fail' }
            Expected = if ($expected) { "$expected ($($ctl.Description))" } else { '(No One)' }
            Actual   = $actual
            Detail   = "Privilege: $key"
        }
    }

    Write-Progress -Activity "Auditing $moduleName" -Completed

    return $results
}
