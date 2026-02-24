function Set-CISSecurityOptions {
    <#
    .SYNOPSIS
        Applies CIS Section 2.3 - Security Options via GPO.
    .DESCRIPTION
        For registry-based controls: uses Set-GPRegistryValue.
        For secedit-based controls: writes GptTmpl.inf to the GPO SYSVOL path.
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

    $moduleName = 'SecurityOptions'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for SecurityOptions' -Level Warning -Module $moduleName
        return
    }

    # Separate controls by mechanism
    $registryControls = $controls | Where-Object { $_.Registry -and -not $_.Skipped }
    $seceditControls  = $controls | Where-Object { $_.Secedit -and -not $_.Skipped }

    # -- Registry-based controls -> Set-GPRegistryValue --
    foreach ($ctl in $registryControls) {
        $reg = $ctl.Registry
        # Check AWS exclusion modifications
        $value = Get-AWSModifiedValue -ControlId $ctl.Id -DefaultValue $reg.Value
        $gpRegPath = $reg.Path -replace '^HKLM:\\', 'HKLM\'

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would set $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
        } else {
            try {
                Set-GPRegistryValue -Name $GpoName -Key $gpRegPath -ValueName $reg.Name -Type $reg.Type -Value $value -ErrorAction Stop
                Write-CISLog -Message "Set $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
            } catch {
                Write-CISLog -Message "Failed to set $($ctl.Id): $_" -Level Error -ControlId $ctl.Id
            }
        }
    }

    # -- Secedit-based controls -> GptTmpl.inf --
    if ($seceditControls) {
        if ($DryRun) {
            foreach ($ctl in $seceditControls) {
                Write-CISLog -Message "[DRY RUN] Would write secedit key $($ctl.Secedit.Key)" -Level Info -ControlId $ctl.Id
            }
        } else {
            Write-GptTmplEntries -GpoName $GpoName -Controls $seceditControls -Section 'System Access'
        }
    }
}

# -----------------------------------------------------------------------------
# Helper: check if AWS exclusions modify a control value
# -----------------------------------------------------------------------------
function Get-AWSModifiedValue {
    param(
        [string]$ControlId,
        $DefaultValue
    )

    $mods = $script:CISConfig.AWSExclusions.Modify
    if ($mods -and $mods[$ControlId]) {
        $modified = $mods[$ControlId]
        Write-CISLog -Message "AWS modification applied for $ControlId" -Level Warning -ControlId $ControlId
        return $modified
    }
    return $DefaultValue
}

# -----------------------------------------------------------------------------
# Helper: write secedit entries into GptTmpl.inf on SYSVOL
# -----------------------------------------------------------------------------
function Write-GptTmplEntries {
    param(
        [string]$GpoName,
        [array]$Controls,
        [string]$Section = 'System Access'
    )

    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction Stop
    } catch {
        Write-CISLog -Message "Cannot find GPO '$GpoName': $_" -Level Error
        return
    }

    $domain  = (Get-ADDomain).DNSRoot
    $gpoId   = $gpo.Id.ToString('B').ToUpper()
    $infPath = "\\$domain\SYSVOL\$domain\Policies\$gpoId\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"

    # Read existing or create new
    $content = @{}
    if (Test-Path $infPath) {
        $currentSection = ''
        Get-Content $infPath | ForEach-Object {
            if ($_ -match '^\[(.+)\]$') {
                $currentSection = $Matches[1]
                if (-not $content[$currentSection]) { $content[$currentSection] = @{} }
            } elseif ($_ -match '^(.+?)\s*=\s*(.+)$' -and $currentSection) {
                $content[$currentSection][$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }

    # Ensure section exists
    if (-not $content[$Section]) { $content[$Section] = @{} }

    # Add our settings
    foreach ($ctl in $Controls) {
        if ($ctl.Secedit.Value) {
            $val = Get-AWSModifiedValue -ControlId $ctl.Id -DefaultValue $ctl.Secedit.Value
            $content[$Section][$ctl.Secedit.Key] = $val
            Write-CISLog -Message "GptTmpl: [$Section] $($ctl.Secedit.Key) = $val" -Level Info -ControlId $ctl.Id
        }
    }

    # Ensure parent directory exists
    $infDir = Split-Path $infPath -Parent
    if (-not (Test-Path $infDir)) {
        New-Item -Path $infDir -ItemType Directory -Force | Out-Null
    }

    # Write out
    $lines = @('[Unicode]', 'Unicode=yes')
    foreach ($sec in $content.Keys) {
        $lines += "[$sec]"
        foreach ($kv in $content[$sec].GetEnumerator()) {
            $lines += "$($kv.Key) = $($kv.Value)"
        }
    }
    $lines += '[Version]'
    $lines += 'signature="$CHICAGO$"'
    $lines += 'Revision=1'

    $lines | Set-Content -Path $infPath -Encoding Unicode
    Write-CISLog -Message "Wrote GptTmpl.inf to $infPath" -Level Info -Module 'SecurityOptions'

    # Bump GPO version to trigger client refresh
    $gpo.MakeAclConsistent()
}
