function Export-CISReport {
    <#
    .SYNOPSIS
        Generates HTML and/or JSON compliance reports from audit results.
    .PARAMETER Results
        Array of audit result objects (from Test-CIS* functions).
    .PARAMETER OutputDir
        Directory to write reports to. Defaults to <ProjectRoot>/reports.
    .PARAMETER Formats
        Which formats to generate: HTML, JSON, or both.
    .PARAMETER ReportTitle
        Title shown in the HTML report header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Results,

        [string]$OutputDir,

        [string[]]$Formats = @('HTML','JSON'),

        [string]$ReportTitle = 'CIS Benchmark L1 - Compliance Report'
    )

    if (-not $OutputDir) {
        $OutputDir = Join-Path $script:CISConfig.ProjectRoot 'reports'
    }
    if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $datePretty = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # -- Summary stats --
    $total   = $Results.Count
    $passed  = ($Results | Where-Object { $_.Status -eq 'Pass' }).Count
    $failed  = ($Results | Where-Object { $_.Status -eq 'Fail' }).Count
    $skipped = ($Results | Where-Object { $_.Status -eq 'Skipped' }).Count
    $errors  = ($Results | Where-Object { $_.Status -eq 'Error' }).Count
    $pct     = if ($total -gt 0) { [math]::Round(($passed / ($total - $skipped)) * 100, 1) } else { 0 }

    # -- JSON --
    if ($Formats -contains 'JSON') {
        $jsonPath = Join-Path $OutputDir "CIS-Report-$timestamp.json"
        $jsonPayload = [ordered]@{
            ReportTitle      = $ReportTitle
            GeneratedAt      = $datePretty
            BenchmarkVersion = $script:CISConfig.BenchmarkVersion
            Profile          = $script:CISConfig.Profile
            Summary          = [ordered]@{
                Total       = $total
                Passed      = $passed
                Failed      = $failed
                Skipped     = $skipped
                Errors      = $errors
                PassPercent = $pct
            }
            Results = $Results
        }
        $jsonPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding utf8
        Write-CISLog -Message "JSON report: $jsonPath" -Level Info
    }

    # -- HTML --
    if ($Formats -contains 'HTML') {
        $htmlPath = Join-Path $OutputDir "CIS-Report-$timestamp.html"

        $rows = foreach ($r in $Results) {
            $statusClass = switch ($r.Status) {
                'Pass'    { 'pass' }
                'Fail'    { 'fail' }
                'Skipped' { 'skip' }
                'Error'   { 'error' }
                default   { '' }
            }
            @"
            <tr class="$statusClass">
                <td>$($r.Id)</td>
                <td>$($r.Title)</td>
                <td>$($r.Module)</td>
                <td class="status">$($r.Status)</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($r.Expected))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($r.Actual))</td>
                <td>$([System.Web.HttpUtility]::HtmlEncode($r.Detail))</td>
            </tr>
"@
        }

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>$ReportTitle</title>
<style>
    body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    h1 { color: #1a1a2e; }
    .summary { display: flex; gap: 15px; margin: 20px 0; }
    .summary .card {
        background: #fff; border-radius: 8px; padding: 15px 25px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; min-width: 100px;
    }
    .card .num { font-size: 2em; font-weight: bold; }
    .card.pass  .num { color: #27ae60; }
    .card.fail  .num { color: #e74c3c; }
    .card.skip  .num { color: #f39c12; }
    .card.error .num { color: #8e44ad; }
    .card.pct   .num { color: #2980b9; }
    table { border-collapse: collapse; width: 100%; background: #fff; margin-top: 20px; }
    th { background: #1a1a2e; color: #fff; padding: 10px 8px; text-align: left; font-size: 0.85em; }
    td { padding: 8px; border-bottom: 1px solid #ddd; font-size: 0.85em; }
    tr.pass td.status { color: #27ae60; font-weight: bold; }
    tr.fail td.status { color: #e74c3c; font-weight: bold; }
    tr.skip td.status { color: #f39c12; font-weight: bold; }
    tr.error td.status { color: #8e44ad; font-weight: bold; }
    tr:hover { background: #f0f0f0; }
    .meta { color: #666; font-size: 0.9em; }
</style>
</head>
<body>
<h1>$ReportTitle</h1>
<p class="meta">Generated: $datePretty &nbsp;|&nbsp; Benchmark: $($script:CISConfig.BenchmarkVersion) &nbsp;|&nbsp; Profile: $($script:CISConfig.Profile)</p>

<div class="summary">
    <div class="card"><div class="num">$total</div><div>Total</div></div>
    <div class="card pass"><div class="num">$passed</div><div>Passed</div></div>
    <div class="card fail"><div class="num">$failed</div><div>Failed</div></div>
    <div class="card skip"><div class="num">$skipped</div><div>Skipped</div></div>
    <div class="card error"><div class="num">$errors</div><div>Errors</div></div>
    <div class="card pct"><div class="num">$pct%</div><div>Compliance</div></div>
</div>

<table>
<thead>
    <tr><th>ID</th><th>Title</th><th>Module</th><th>Status</th><th>Expected</th><th>Actual</th><th>Detail</th></tr>
</thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
</body>
</html>
"@
        $html | Out-File -FilePath $htmlPath -Encoding utf8
        Write-CISLog -Message "HTML report: $htmlPath" -Level Info
    }

    return @{
        Total       = $total
        Passed      = $passed
        Failed      = $failed
        Skipped     = $skipped
        Errors      = $errors
        PassPercent = $pct
    }
}
