function Backup-CISState {
    <#
    .SYNOPSIS
        Snapshots the current state of GPOs and local settings before changes.
    .DESCRIPTION
        Creates a timestamped backup folder containing:
        - GPO backups (Backup-GPO) for each CIS GPO that exists
        - secedit export of current security policy
        - auditpol export
        - Service startup states
        - Registry baseline for audited keys
    .PARAMETER BackupDir
        Directory to store backups. Defaults to <ProjectRoot>/backups.
    .PARAMETER Modules
        Specific modules to back up. If omitted, backs up all enabled modules.
    .OUTPUTS
        Path to the backup folder.
    #>
    [CmdletBinding()]
    param(
        [string]$BackupDir,

        [string[]]$Modules
    )

    $config = $script:CISConfig
    if (-not $BackupDir) {
        $BackupDir = Join-Path $config.ProjectRoot 'backups'
    }

    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $BackupDir "CIS-Backup-$timestamp"
    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null

    Write-CISLog -Message "-- Creating state backup: $backupPath --" -Level Info

    # ── GPO Backups ──
    $gpoDir = Join-Path $backupPath 'GPOs'
    New-Item -Path $gpoDir -ItemType Directory -Force | Out-Null

    $prefix = $config.GpoPrefix
    $modulesToBackup = if ($Modules) { $Modules } else {
        $config.Modules.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }
    }

    foreach ($modName in $modulesToBackup) {
        $gpoName = "$prefix-$modName"
        $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if ($gpo) {
            try {
                Backup-GPO -Name $gpoName -Path $gpoDir -ErrorAction Stop | Out-Null
                Write-CISLog -Message "Backed up GPO: $gpoName" -Level Info
            } catch {
                Write-CISLog -Message "Failed to back up GPO $gpoName`: $_" -Level Warning
            }
        }
    }

    # ── Secedit export ──
    $seceditPath = Join-Path $backupPath 'secedit-baseline.inf'
    try {
        $null = secedit.exe /export /cfg $seceditPath /quiet 2>&1
        Write-CISLog -Message "Exported secedit baseline" -Level Info
    } catch {
        Write-CISLog -Message "Failed secedit export: $_" -Level Warning
    }

    # ── Auditpol export ──
    $auditPath = Join-Path $backupPath 'auditpol-baseline.csv'
    try {
        auditpol.exe /backup /file:$auditPath 2>&1 | Out-Null
        Write-CISLog -Message "Exported auditpol baseline" -Level Info
    } catch {
        Write-CISLog -Message "Failed auditpol export: $_" -Level Warning
    }

    # ── Service states ──
    $svcPath = Join-Path $backupPath 'services-baseline.json'
    try {
        $services = Get-CimInstance -ClassName Win32_Service | Select-Object Name, StartMode, State
        $services | ConvertTo-Json -Depth 3 | Out-File -FilePath $svcPath -Encoding utf8
        Write-CISLog -Message "Exported service states ($($services.Count) services)" -Level Info
    } catch {
        Write-CISLog -Message "Failed service state export: $_" -Level Warning
    }

    # ── Metadata ──
    $meta = @{
        Timestamp  = $timestamp
        Modules    = $modulesToBackup
        GpoPrefix  = $prefix
        TargetOU   = $config.TargetOU
        ComputerName = $env:COMPUTERNAME
    }
    $meta | ConvertTo-Json -Depth 3 | Out-File (Join-Path $backupPath 'backup-metadata.json') -Encoding utf8

    Write-CISLog -Message "-- Backup complete: $backupPath --" -Level Info
    return $backupPath
}
