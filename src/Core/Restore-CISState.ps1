function Restore-CISState {
    <#
    .SYNOPSIS
        Restores a previous state backup, reverting GPO and policy changes.
    .DESCRIPTION
        Reads a backup created by Backup-CISState and:
        1. Restores GPOs from backup
        2. Optionally removes GPOs that were created after the backup
        3. Forces a gpupdate to apply restored settings
    .PARAMETER BackupPath
        Path to the backup folder (e.g., backups/CIS-Backup-20250101-120000).
    .PARAMETER Module
        Restore only a specific module's GPO. If omitted, restores all.
    .PARAMETER RemoveGPOs
        If $true, removes CIS GPOs entirely instead of restoring them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,

        [string]$Module,

        [switch]$RemoveGPOs
    )

    if (-not (Test-Path $BackupPath)) {
        Write-CISLog -Message "Backup path not found: $BackupPath" -Level Error
        throw "Backup path not found: $BackupPath"
    }

    # Load metadata
    $metaPath = Join-Path $BackupPath 'backup-metadata.json'
    if (-not (Test-Path $metaPath)) {
        Write-CISLog -Message "Backup metadata not found: $metaPath" -Level Error
        throw "Invalid backup: metadata not found"
    }
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json

    Write-CISLog -Message "-- Restoring from backup: $($meta.Timestamp) --" -Level Info
    Write-CISLog -Message "Backup computer: $($meta.ComputerName)" -Level Info

    $prefix = $meta.GpoPrefix
    $targetOU = $meta.TargetOU

    $modulesToRestore = if ($Module) {
        @($Module)
    } else {
        $meta.Modules
    }

    $gpoDir = Join-Path $BackupPath 'GPOs'

    foreach ($modName in $modulesToRestore) {
        $gpoName = "$prefix-$modName"

        if ($RemoveGPOs) {
            # Unlink and delete the GPO entirely
            try {
                # Remove link first
                Remove-GPLink -Name $gpoName -Target $targetOU -ErrorAction SilentlyContinue
                Write-CISLog -Message "Unlinked GPO: $gpoName from $targetOU" -Level Info

                # Delete GPO
                Remove-GPO -Name $gpoName -ErrorAction Stop
                Write-CISLog -Message "Deleted GPO: $gpoName" -Level Info
            } catch {
                Write-CISLog -Message "Failed to remove GPO $gpoName`: $_" -Level Warning
            }
        } else {
            # Restore from backup
            $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
            if ($gpo) {
                try {
                    # Find the backup for this GPO
                    $backupGpo = Get-ChildItem -Path $gpoDir -Directory | ForEach-Object {
                        $bkManifest = Join-Path $_.FullName 'bkupInfo.xml'
                        if (Test-Path $bkManifest) {
                            [xml]$xml = Get-Content $bkManifest
                            if ($xml.BackupInst.GPODisplayName.'#cdata-section' -eq $gpoName) {
                                $_
                            }
                        }
                    } | Select-Object -First 1

                    if ($backupGpo) {
                        Import-GPO -BackupId $backupGpo.Name -Path $gpoDir -TargetName $gpoName -ErrorAction Stop
                        Write-CISLog -Message "Restored GPO from backup: $gpoName" -Level Info
                    } else {
                        Write-CISLog -Message "No backup found for GPO: $gpoName - skipping restore" -Level Warning
                    }
                } catch {
                    Write-CISLog -Message "Failed to restore GPO $gpoName`: $_" -Level Error
                }
            } else {
                Write-CISLog -Message "GPO not found (may have been deleted): $gpoName" -Level Warning
            }
        }
    }

    # ── Force group policy update ──
    Write-CISLog -Message 'Forcing Group Policy update...' -Level Info
    try {
        $null = gpupdate.exe /force /wait:30 2>&1
        Write-CISLog -Message 'Group Policy update completed' -Level Info
    } catch {
        Write-CISLog -Message "gpupdate failed: $_" -Level Warning
    }

    Write-CISLog -Message "-- Restore complete --" -Level Info
}
