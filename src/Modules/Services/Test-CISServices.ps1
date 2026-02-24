function Test-CISServices {
    <#
    .SYNOPSIS
        Audits CIS Section 5 - System Services.
    .DESCRIPTION
        Checks that specified services are disabled (or not installed).
    #>
    [CmdletBinding()]
    param()

    $moduleName = 'Services'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for Services' -Level Warning -Module $moduleName
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

        $serviceName  = $ctl.ServiceName
        $expectedType = $ctl.StartType

        try {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            $startType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop).StartMode

            $pass = switch ($expectedType) {
                'Disabled' { $startType -eq 'Disabled' }
                'Manual'   { $startType -eq 'Manual' -or $startType -eq 'Disabled' }
                'Auto'     { $startType -eq 'Auto' }
                default    { $startType -eq $expectedType }
            }

            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = if ($pass) { 'Pass' } else { 'Fail' }
                Expected = $expectedType
                Actual   = "$startType (Status: $($svc.Status))"
                Detail   = "Service: $serviceName"
            }
        } catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            # Service not installed - that's compliant for "Disabled" requirement
            if ($expectedType -eq 'Disabled') {
                [PSCustomObject]@{
                    Id       = $ctl.Id
                    Title    = $ctl.Title
                    Module   = $moduleName
                    Status   = 'Pass'
                    Expected = $expectedType
                    Actual   = 'Not Installed'
                    Detail   = "Service $serviceName not found (compliant)"
                }
            } else {
                [PSCustomObject]@{
                    Id       = $ctl.Id
                    Title    = $ctl.Title
                    Module   = $moduleName
                    Status   = 'Error'
                    Expected = $expectedType
                    Actual   = 'Not Installed'
                    Detail   = "Service $serviceName not found"
                }
            }
        } catch {
            [PSCustomObject]@{
                Id       = $ctl.Id
                Title    = $ctl.Title
                Module   = $moduleName
                Status   = 'Error'
                Expected = $expectedType
                Actual   = ''
                Detail   = $_.Exception.Message
            }
        }
    }

    Write-Progress -Activity "Auditing $moduleName" -Completed

    return $results
}
