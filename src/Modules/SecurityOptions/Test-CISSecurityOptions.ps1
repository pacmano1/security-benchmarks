function Test-CISSecurityOptions {
    <#
    .SYNOPSIS
        Audits CIS Section 2.3 - Security Options controls.
    .DESCRIPTION
        Reads registry values and secedit output to determine compliance.
        Returns an array of result objects for the report.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'SecurityOptions'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for SecurityOptions' -Level Warning -Module $moduleName
        return @()
    }

    # -- Export secedit once for all secedit-based controls --
    $seceditData = @{}
    $hasSecedit  = $controls | Where-Object { $_.Secedit }
    if ($hasSecedit) {
        $seceditData = Get-SeceditExport
    }

    $total = $controls.Count
    $i = 0
    $results = foreach ($ctl in $controls) {
        $i++
        Write-Progress -Activity "Auditing $moduleName" -Status "$i of $total - $($ctl.Id)" -PercentComplete (($i / $total) * 100)

        # Skip AWS-excluded controls
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
            if ($ctl.Registry) {
                Test-RegistryControl -Control $ctl -ModuleName $moduleName
            } elseif ($ctl.Secedit) {
                Test-SeceditControl -Control $ctl -ModuleName $moduleName -SeceditData $seceditData
            } else {
                [PSCustomObject]@{
                    Id       = $ctl.Id
                    Title    = $ctl.Title
                    Module   = $moduleName
                    Status   = 'Error'
                    Expected = ''
                    Actual   = ''
                    Detail   = 'No audit mechanism defined for this control'
                }
            }
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

# -----------------------------------------------------------------------------
# Helper: audit a single registry-based control
# -----------------------------------------------------------------------------
function Test-RegistryControl {
    param(
        [hashtable]$Control,
        [string]$ModuleName
    )

    $reg      = $Control.Registry
    $regPath  = $reg.Path
    $regName  = $reg.Name
    $expected = $reg.Value
    $operator = if ($reg.Operator) { $reg.Operator } else { 'Equals' }

    # Read current value
    $actual = $null
    try {
        $item = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop
        $actual = $item.$regName
    } catch {
        return [PSCustomObject]@{
            Id       = $Control.Id
            Title    = $Control.Title
            Module   = $ModuleName
            Status   = 'Fail'
            Expected = "$expected"
            Actual   = '(not set)'
            Detail   = "Registry value not found: $regPath\$regName"
        }
    }

    # Compare
    $pass = switch ($operator) {
        'Equals'       { "$actual" -eq "$expected" }
        'LessOrEqual'  {
            $minVal = if ($reg.MinValue) { $reg.MinValue } else { 0 }
            ($actual -le $expected) -and ($actual -ge $minVal)
        }
        'Range'        { ($actual -ge $reg.MinValue) -and ($actual -le $reg.MaxValue) }
        'NotEmpty'     { -not [string]::IsNullOrWhiteSpace($actual) }
        'Empty'        {
            if ($actual -is [array]) { $actual.Count -eq 0 -or ($actual.Count -eq 1 -and [string]::IsNullOrEmpty($actual[0])) }
            else { [string]::IsNullOrWhiteSpace($actual) }
        }
        default        { "$actual" -eq "$expected" }
    }

    [PSCustomObject]@{
        Id       = $Control.Id
        Title    = $Control.Title
        Module   = $ModuleName
        Status   = if ($pass) { 'Pass' } else { 'Fail' }
        Expected = "$expected"
        Actual   = "$actual"
        Detail   = "$regPath\$regName"
    }
}

# -----------------------------------------------------------------------------
# Helper: export secedit security policy to a hashtable
# -----------------------------------------------------------------------------
function Get-SeceditExport {
    $tempFile = Join-Path $env:TEMP "cis_secedit_$(Get-Random).inf"
    try {
        $null = secedit.exe /export /cfg $tempFile /quiet 2>&1
        $data = @{}
        if (Test-Path $tempFile) {
            Get-Content $tempFile | ForEach-Object {
                if ($_ -match '^(.+?)\s*=\s*(.+)$') {
                    $data[$Matches[1].Trim()] = $Matches[2].Trim()
                }
            }
        }
        return $data
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# -----------------------------------------------------------------------------
# Helper: audit a single secedit-based control
# -----------------------------------------------------------------------------
function Test-SeceditControl {
    param(
        [hashtable]$Control,
        [string]$ModuleName,
        [hashtable]$SeceditData
    )

    $sec      = $Control.Secedit
    $key      = $sec.Key
    $actual   = $SeceditData[$key]

    if ($null -eq $actual) {
        return [PSCustomObject]@{
            Id       = $Control.Id
            Title    = $Control.Title
            Module   = $ModuleName
            Status   = 'Fail'
            Expected = if ($sec.Value) { $sec.Value } else { "Not $($sec.NotValue)" }
            Actual   = '(not found)'
            Detail   = "secedit key not found: $key"
        }
    }

    if ($sec.NotValue) {
        $pass = $actual -ne $sec.NotValue
        $expectedStr = "Not $($sec.NotValue)"
    } else {
        $pass = $actual -eq $sec.Value
        $expectedStr = $sec.Value
    }

    [PSCustomObject]@{
        Id       = $Control.Id
        Title    = $Control.Title
        Module   = $ModuleName
        Status   = if ($pass) { 'Pass' } else { 'Fail' }
        Expected = $expectedStr
        Actual   = $actual
        Detail   = "secedit: $key"
    }
}
