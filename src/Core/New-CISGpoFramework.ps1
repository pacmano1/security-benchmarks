function New-CISGpoFramework {
    <#
    .SYNOPSIS
        Creates one GPO per enabled CIS module and links each to the target OU.
    .DESCRIPTION
        GPO naming: <GpoPrefix>-<ModuleName> (e.g., CIS-L1-SecurityOptions).
        Each GPO is created if it doesn't already exist, then linked to the
        delegated OU specified in master config.
    .PARAMETER DryRun
        If $true, logs what would be created without modifying AD.
    .OUTPUTS
        Hashtable mapping module name -> GPO name.
    #>
    [CmdletBinding()]
    param(
        [bool]$DryRun = $true
    )

    $config   = $script:CISConfig
    $prefix   = $config.GpoPrefix
    $targetOU = $config.TargetOU

    Write-CISLog -Message '-- Creating GPO Framework --' -Level Info

    $gpoMap = @{}

    foreach ($modName in $config.Modules.Keys) {
        if (-not $config.Modules[$modName]) {
            Write-CISLog -Message "Skipping GPO for disabled module: $modName" -Level Debug
            continue
        }

        $gpoName = "$prefix-$modName"

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would create GPO: $gpoName and link to $targetOU" -Level Info
            $gpoMap[$modName] = $gpoName
            continue
        }

        # Create GPO if it doesn't exist
        $existing = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-CISLog -Message "GPO already exists: $gpoName (ID: $($existing.Id))" -Level Info
        } else {
            try {
                $newGpo = New-GPO -Name $gpoName -Comment "CIS Benchmark L1 - $modName (auto-generated)" -ErrorAction Stop
                Write-CISLog -Message "Created GPO: $gpoName (ID: $($newGpo.Id))" -Level Info
            } catch {
                Write-CISLog -Message "Failed to create GPO $gpoName`: $_" -Level Error
                continue
            }
        }

        # Link to OU if not already linked
        try {
            $links = (Get-GPInheritance -Target $targetOU -ErrorAction Stop).GpoLinks
            $alreadyLinked = $links | Where-Object { $_.DisplayName -eq $gpoName }

            if ($alreadyLinked) {
                Write-CISLog -Message "GPO already linked: $gpoName -> $targetOU" -Level Info
            } else {
                New-GPLink -Name $gpoName -Target $targetOU -LinkEnabled Yes -ErrorAction Stop
                Write-CISLog -Message "Linked GPO: $gpoName -> $targetOU" -Level Info
            }
        } catch {
            Write-CISLog -Message "Failed to link GPO $gpoName to $targetOU`: $_" -Level Error
        }

        $gpoMap[$modName] = $gpoName
    }

    Write-CISLog -Message "GPO framework: $($gpoMap.Count) GPOs ready" -Level Info
    return $gpoMap
}
