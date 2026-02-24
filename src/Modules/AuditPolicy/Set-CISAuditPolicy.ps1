function Set-CISAuditPolicy {
    <#
    .SYNOPSIS
        Applies CIS Section 17 - Advanced Audit Policy via GPO audit.csv.
    .PARAMETER GpoName
        Name of the GPO to configure.
    .PARAMETER DryRun
        If $true, logs what would be changed without modifying anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GpoName,

        [bool]$DryRun = $true
    )

    $moduleName = 'AuditPolicy'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for AuditPolicy' -Level Warning -Module $moduleName
        return
    }

    $activeControls = $controls | Where-Object { -not $_.Skipped }

    if ($DryRun) {
        foreach ($ctl in $activeControls) {
            Write-CISLog -Message "[DRY RUN] Would set audit: $($ctl.Subcategory) = $($ctl.InclusionSetting)" -Level Info -ControlId $ctl.Id
        }
        return
    }

    # -- Build audit.csv and write to GPO SYSVOL --
    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
    } catch {
        Write-CISLog -Message "Cannot find GPO '$GpoName': $_" -Level Error
        return
    }

    $domain  = (Get-ADDomain).DNSRoot
    $gpoId   = $gpo.Id.ToString('B').ToUpper()
    $csvDir  = "\\$domain\SYSVOL\$domain\Policies\$gpoId\Machine\Microsoft\Windows NT\Audit"
    $csvPath = Join-Path $csvDir 'audit.csv'

    # Ensure directory exists
    if (-not (Test-Path $csvDir)) {
        New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
    }

    # Build CSV content
    $csvLines = @('Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting')

    foreach ($ctl in $activeControls) {
        # Map InclusionSetting to the numeric value
        $settingValue = switch ($ctl.InclusionSetting) {
            'Success'             { 'Success' }
            'Failure'             { 'Failure' }
            'Success and Failure' { 'Success and Failure' }
            'No Auditing'         { 'No Auditing' }
            default               { $ctl.InclusionSetting }
        }

        $csvLines += ",$($ctl.Subcategory),$($ctl.CategoryGuid),$settingValue,"
        Write-CISLog -Message "Audit CSV: $($ctl.Subcategory) = $settingValue" -Level Info -ControlId $ctl.Id
    }

    $csvLines | Set-Content -Path $csvPath -Encoding UTF8
    Write-CISLog -Message "Wrote audit.csv to $csvPath ($($activeControls.Count) subcategories)" -Level Info -Module $moduleName

    # Update gPCMachineExtensionNames to include audit policy CSE
    $auditCSE = '[{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]'
    Update-GpoExtensionAttribute -GpoName $GpoName -CSE $auditCSE
}

# -----------------------------------------------------------------------------
# Helper: update gPCMachineExtensionNames to include a CSE GUID pair
# -----------------------------------------------------------------------------
function Update-GpoExtensionAttribute {
    param(
        [string]$GpoName,
        [string]$CSE
    )

    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
        $dn  = "CN={$($gpo.Id)},CN=Policies,CN=System,$((Get-ADDomain).DistinguishedName)"
        $obj = Get-ADObject -Identity $dn -Properties gPCMachineExtensionNames -ErrorAction Stop
        $current = $obj.gPCMachineExtensionNames

        if ($current -notmatch [regex]::Escape($CSE)) {
            $new = "$current$CSE"
            Set-ADObject -Identity $dn -Replace @{ gPCMachineExtensionNames = $new }
            Write-CISLog -Message "Updated gPCMachineExtensionNames with audit CSE" -Level Info -Module 'AuditPolicy'
        }
    } catch {
        Write-CISLog -Message "Warning: could not update GPO extension attribute: $_" -Level Warning -Module 'AuditPolicy'
    }
}
