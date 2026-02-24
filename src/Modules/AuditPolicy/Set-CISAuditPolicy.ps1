function Set-CISAuditPolicy {
    <#
    .SYNOPSIS
        Applies CIS Section 17 - Advanced Audit Policy.
    .DESCRIPTION
        In GPO mode writes audit.csv to SYSVOL. In local mode uses
        auditpol /set to configure each subcategory directly.
    .PARAMETER GpoName
        Name of the GPO to configure (ignored in local mode).
    .PARAMETER DryRun
        If $true, logs what would be changed without modifying anything.
    .PARAMETER LocalPolicy
        Apply directly via auditpol instead of GPO audit.csv.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GpoName,

        [bool]$DryRun = $true,

        [switch]$LocalPolicy
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

    if ($LocalPolicy) {
        # -- Apply directly via auditpol /set --
        $applied = 0
        $errors  = 0

        foreach ($ctl in $activeControls) {
            $subcategory = $ctl.Subcategory
            $setting     = $ctl.InclusionSetting

            # Map setting to success/failure flags
            $successFlag = 'disable'
            $failureFlag = 'disable'
            switch ($setting) {
                'Success'             { $successFlag = 'enable' }
                'Failure'             { $failureFlag = 'enable' }
                'Success and Failure' { $successFlag = 'enable'; $failureFlag = 'enable' }
            }

            try {
                $result = auditpol.exe /set /subcategory:"$subcategory" /success:$successFlag /failure:$failureFlag 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-CISLog -Message "[LOCAL] auditpol: $subcategory = $setting" -Level Info -ControlId $ctl.Id
                    $applied++
                } else {
                    Write-CISLog -Message "[LOCAL] auditpol failed for $subcategory`: $result" -Level Error -ControlId $ctl.Id
                    $errors++
                }
            } catch {
                Write-CISLog -Message "[LOCAL] auditpol error for $subcategory`: $_" -Level Error -ControlId $ctl.Id
                $errors++
            }
        }

        Write-CISLog -Message "AuditPolicy: $applied settings applied, $errors errors (local)" -Level Info -Module $moduleName
        return
    }

    # -- GPO mode: Build audit.csv and write to GPO SYSVOL --
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
