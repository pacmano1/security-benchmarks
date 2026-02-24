function Test-CISAuditPolicy {
    <#
    .SYNOPSIS
        Audits CIS Section 17 - Advanced Audit Policy Configuration.
    .DESCRIPTION
        Uses auditpol.exe /get to read current audit subcategory settings
        and compares against CIS-required values.
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'AuditPolicy'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AuditPolicy' -Level Warning -Module $moduleName
        return @()
    }

    # -- Get all audit policy settings at once --
    $auditData = Get-AuditPolData

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

        $subcategory = $ctl.Subcategory
        $actual      = $auditData[$subcategory]
        $expected    = $ctl.ExpectedValue

        if ($null -eq $actual) {
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Error'
                Expected = $expected
                Actual   = '(not found)'
                Detail   = "Subcategory not found in auditpol output: $subcategory"
            }
            continue
        }

        # Normalize comparison
        $pass = Test-AuditSettingCompliance -Actual $actual -Expected $expected

        [PSCustomObject]@{
            Id       = $ctl.Id
            Title    = $ctl.Title
            Module   = $moduleName
            Status   = if ($pass) { 'Pass' } else { 'Fail' }
            Expected = $expected
            Actual   = $actual
            Detail   = "Subcategory: $subcategory"
        }
    }

    Write-Progress -Activity "Auditing $moduleName" -Completed

    return $results
}

# -----------------------------------------------------------------------------
# Helper: parse auditpol output into a hashtable
# -----------------------------------------------------------------------------
function Get-AuditPolData {
    $data = @{}

    try {
        $output = auditpol.exe /get /category:* /r 2>&1
        # CSV format: Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting
        $csv = $output | ConvertFrom-Csv -ErrorAction SilentlyContinue

        foreach ($row in $csv) {
            if ($row.Subcategory) {
                $data[$row.Subcategory.Trim()] = $row.'Inclusion Setting'.Trim()
            }
        }
    } catch {
        Write-CISLog -Message "Failed to query auditpol: $_" -Level Error -Module 'AuditPolicy'
    }

    return $data
}

# -----------------------------------------------------------------------------
# Helper: check if actual audit setting meets the CIS requirement
# -----------------------------------------------------------------------------
function Test-AuditSettingCompliance {
    param(
        [string]$Actual,
        [string]$Expected
    )

    # Normalize
    $a = $Actual.Trim().ToLower()
    $e = $Expected.Trim().ToLower()

    # Exact match
    if ($a -eq $e) { return $true }

    # "Success and Failure" satisfies any requirement
    if ($a -eq 'success and failure') { return $true }

    # "Include Success" - actual must contain success
    if ($e -match 'include success' -and $a -match 'success') { return $true }

    # "Include Failure" - actual must contain failure
    if ($e -match 'include failure' -and $a -match 'failure') { return $true }

    return $false
}
