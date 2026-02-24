function Disable-UnnecessaryFirewallRules {
    <#
    .SYNOPSIS
        Disables Windows Firewall rules for services inappropriate on hardened servers.
    .DESCRIPTION
        Windows ships with default allow rules for consumer features (casting,
        wireless display, mDNS, etc.) that have no place on a server. This
        function disables those rule groups.
    .PARAMETER DryRun
        If $true, logs what would be disabled without making changes.
    .OUTPUTS
        Array of PSCustomObjects showing what was disabled.
    #>
    [CmdletBinding()]
    param(
        [bool]$DryRun = $true
    )

    # Rule groups to disable on hardened servers
    $unnecessaryGroups = @(
        'Cast to Device functionality'
        'Connected Devices Platform'
        'Connected Devices Platform - Wi-Fi Direct Transport'
        'DIAL protocol server'
        'Media Center Extenders'
        'Proximity Sharing'
        'Wireless Display'
        'Wi-Fi Direct Network Discovery'
        'Wi-Fi Direct Scan'
        'Wi-Fi Direct Spooler Use'
        'AllJoyn Router'
        'mDNS'
        'Wireless Portable Devices'
        'Microsoft Media Foundation Network Source'
        'PlayTo Receiver'
    )

    $results = @()

    foreach ($group in $unnecessaryGroups) {
        $rules = Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        if (-not $rules) { continue }

        $enabledRules = $rules | Where-Object { $_.Enabled -eq 'True' }
        if (-not $enabledRules) { continue }

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would disable $($enabledRules.Count) rules in group: $group" -Level Info
            $results += [PSCustomObject]@{
                Group   = $group
                Count   = $enabledRules.Count
                Action  = 'Would disable'
            }
        } else {
            try {
                Disable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
                Write-CISLog -Message "[LOCAL] Disabled $($enabledRules.Count) firewall rules in group: $group" -Level Info
                $results += [PSCustomObject]@{
                    Group   = $group
                    Count   = $enabledRules.Count
                    Action  = 'Disabled'
                }
            } catch {
                Write-CISLog -Message "Failed to disable firewall group $group`: $_" -Level Warning
                $results += [PSCustomObject]@{
                    Group   = $group
                    Count   = $enabledRules.Count
                    Action  = "Error: $_"
                }
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-CISLog -Message 'No unnecessary firewall rule groups found enabled' -Level Info
    }

    return $results
}
