function Initialize-CISEnvironment {
    <#
    .SYNOPSIS
        Performs prerequisite checks, imports modules, and sets up logging.
    .DESCRIPTION
        Called at the start of every entry-point script. Validates the environment,
        loads configuration, and prepares the logging pipeline.
    .PARAMETER ProjectRoot
        Root directory of the security_benchmarks project.
    .PARAMETER SkipPrereqCheck
        Skip prerequisite validation (useful for audit-only on non-domain machines for testing).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [switch]$SkipPrereqCheck
    )

    # ── Set up log file early so Write-CISLog can write to it ──
    $logDir = Join-Path $ProjectRoot 'reports'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $logDir ("CIS-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-CISLog -Message '=== CIS Benchmark Automation - Initializing ===' -Level Info

    # ── OS check ──
    if (-not $SkipPrereqCheck) {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            Write-CISLog -Message "OS: $($os.Caption) Build $($os.BuildNumber)" -Level Info
            if ($os.Caption -notmatch 'Server') {
                Write-CISLog -Message 'WARNING: This does not appear to be a Windows Server OS.' -Level Warning
            }
        } else {
            Write-CISLog -Message 'Could not query OS information (non-Windows or CIM unavailable).' -Level Warning
        }
    }

    # ── Required PowerShell modules ──
    $requiredModules = @('GroupPolicy', 'ActiveDirectory')
    if (-not $SkipPrereqCheck) {
        foreach ($mod in $requiredModules) {
            if (Get-Module -ListAvailable -Name $mod -ErrorAction SilentlyContinue) {
                Import-Module $mod -ErrorAction SilentlyContinue
                Write-CISLog -Message "Module available: $mod" -Level Debug
            } else {
                Write-CISLog -Message "Required module not installed: $mod - run Install-Prerequisites.ps1" -Level Warning
            }
        }
    }

    # ── Load configuration ──
    $config = Get-CISConfiguration -ProjectRoot $ProjectRoot

    # ── Ensure output directories ──
    $reportsDir = Join-Path $ProjectRoot 'reports'
    $backupsDir = Join-Path $ProjectRoot 'backups'
    foreach ($dir in @($reportsDir, $backupsDir)) {
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    }

    Write-CISLog -Message "DryRun mode: $($config.DryRun)" -Level Info
    Write-CISLog -Message "Target OU: $($config.TargetOU)" -Level Info

    $enabledModules = ($config.Modules.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }) -join ', '
    Write-CISLog -Message "Enabled modules: $enabledModules" -Level Info
    Write-CISLog -Message '=== Initialization complete ===' -Level Info

    return $config
}
