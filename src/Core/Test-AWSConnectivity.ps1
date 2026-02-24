function Test-AWSConnectivity {
    <#
    .SYNOPSIS
        Validates that AWS management channels (WinRM, SSM Agent, RDP) are operational.
    .DESCRIPTION
        Pre-flight and post-flight check. If any critical service is down, returns $false
        so the caller can halt before or rollback after changes.
    .PARAMETER CheckRDP
        Include RDP listener check. Default $true.
    .OUTPUTS
        [PSCustomObject] with per-service pass/fail and an overall Pass boolean.
    #>
    [CmdletBinding()]
    param(
        [bool]$CheckRDP = $true
    )

    Write-CISLog -Message '-- Connectivity pre/post-flight check --' -Level Info

    $results = [ordered]@{}
    $allPassed = $true

    # ── WinRM service ──
    try {
        $winrm = Get-Service -Name WinRM -ErrorAction Stop
        if ($winrm.Status -eq 'Running') {
            $results['WinRM'] = 'Pass'
            Write-CISLog -Message 'WinRM service: Running' -Level Info
        } else {
            $results['WinRM'] = 'Fail'
            $allPassed = $false
            Write-CISLog -Message "WinRM service: $($winrm.Status)" -Level Error
        }
    } catch {
        $results['WinRM'] = 'Fail'
        $allPassed = $false
        Write-CISLog -Message "WinRM check failed: $_" -Level Error
    }

    # ── WinRM listener ──
    try {
        $listeners = Get-WSManInstance -ResourceURI winrm/config/listener -Enumerate -ErrorAction Stop
        if ($listeners) {
            $results['WinRM_Listener'] = 'Pass'
            Write-CISLog -Message "WinRM listeners: $($listeners.Count) configured" -Level Info
        } else {
            $results['WinRM_Listener'] = 'Fail'
            $allPassed = $false
            Write-CISLog -Message 'No WinRM listeners configured' -Level Error
        }
    } catch {
        $results['WinRM_Listener'] = 'Warning'
        Write-CISLog -Message "WinRM listener check: $_" -Level Warning
    }

    # ── SSM Agent ──
    try {
        $ssm = Get-Service -Name AmazonSSMAgent -ErrorAction Stop
        if ($ssm.Status -eq 'Running') {
            $results['SSMAgent'] = 'Pass'
            Write-CISLog -Message 'SSM Agent: Running' -Level Info
        } else {
            $results['SSMAgent'] = 'Fail'
            $allPassed = $false
            Write-CISLog -Message "SSM Agent: $($ssm.Status)" -Level Error
        }
    } catch {
        $results['SSMAgent'] = 'Warning'
        Write-CISLog -Message 'SSM Agent not found - may not be an EC2 instance' -Level Warning
    }

    # ── RDP ──
    if ($CheckRDP) {
        try {
            $rdp = Get-Service -Name TermService -ErrorAction Stop
            if ($rdp.Status -eq 'Running') {
                $results['RDP'] = 'Pass'
                Write-CISLog -Message 'RDP (TermService): Running' -Level Info
            } else {
                $results['RDP'] = 'Fail'
                $allPassed = $false
                Write-CISLog -Message "RDP (TermService): $($rdp.Status)" -Level Error
            }
        } catch {
            $results['RDP'] = 'Fail'
            $allPassed = $false
            Write-CISLog -Message "RDP check failed: $_" -Level Error
        }

        # RDP listener port
        try {
            $rdpPort = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -ErrorAction Stop).PortNumber
            $results['RDP_Port'] = $rdpPort
            Write-CISLog -Message "RDP listener port: $rdpPort" -Level Info
        } catch {
            $results['RDP_Port'] = 'Unknown'
            Write-CISLog -Message 'Could not determine RDP port' -Level Warning
        }
    }

    # ── Firewall rules for management ──
    try {
        $fwRules = Get-NetFirewallRule -Enabled True -Action Allow -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Remote Desktop|Windows Remote Management|WinRM' }
        $results['FirewallRules'] = "$($fwRules.Count) management rules active"
        Write-CISLog -Message "Firewall: $($fwRules.Count) management allow rules found" -Level Info
    } catch {
        $results['FirewallRules'] = 'Check skipped'
        Write-CISLog -Message 'Firewall rule check skipped' -Level Warning
    }

    $output = [PSCustomObject]@{
        Pass    = $allPassed
        Details = $results
    }

    if ($allPassed) {
        Write-CISLog -Message '-- Connectivity check: ALL PASSED --' -Level Info
    } else {
        Write-CISLog -Message '-- Connectivity check: FAILURES DETECTED --' -Level Error
    }

    return $output
}
