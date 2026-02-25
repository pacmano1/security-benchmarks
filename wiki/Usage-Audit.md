# Audit Guide

The audit pipeline scans the current machine state against CIS L1 controls and produces compliance reports. **It makes no changes** — safe to run anytime.

---

## Running an Audit

### Interactive Mode (Default)

Simply run the script with no flags — it will prompt you for options:

```powershell
.\scripts\Invoke-CISAudit.ps1
```

You'll be asked:

```
  ? Does this server run IIS (web server)? [y/N]:
  ? Audit all enabled modules or select specific ones? [A/s]:
```

- **IIS prompt:** If you answer `Y`, controls 5.6 (IISADMIN), 5.31 (WMSvc), and 5.40 (W3SVC) are skipped so IIS services are not flagged as non-compliant.
- **Module prompt:** Press Enter to audit all enabled modules, or type `s` to pick from a numbered list.

### Full Audit (All Enabled Modules)

```powershell
.\scripts\Invoke-CISAudit.ps1 -Force
```

The `-Force` flag skips all interactive prompts and uses defaults (all modules, no IIS exclusion).

### Audit Specific Modules

```powershell
# Single module
.\scripts\Invoke-CISAudit.ps1 -Modules SecurityOptions

# Multiple modules
.\scripts\Invoke-CISAudit.ps1 -Modules SecurityOptions, AuditPolicy, Firewall
```

When `-Modules` is passed, the module selection prompt is skipped.

### IIS Servers

On servers running IIS, use `-SkipIIS` to exclude IIS service controls without being prompted:

```powershell
.\scripts\Invoke-CISAudit.ps1 -SkipIIS
```

This skips controls 5.6 (IIS Admin Service), 5.31 (Web Management Service), and 5.40 (World Wide Web Publishing Service).

### Skip Prerequisite Checks

Useful on standalone (non-domain) machines or when RSAT isn't installed:

```powershell
.\scripts\Invoke-CISAudit.ps1 -SkipPrereqCheck
```

> **Note:** On standalone machines, the audit auto-detects that you're not domain-joined and skips AD/GPO-related checks automatically. The `-SkipPrereqCheck` flag is still useful to suppress module-availability warnings.

### Audit a Disabled Module

Even disabled modules can be audited explicitly:

```powershell
# AccountPolicies is disabled by default, but you can still audit it
.\scripts\Invoke-CISAudit.ps1 -Modules AccountPolicies -SkipPrereqCheck
```

---

## Reading the Output

### Console Output

During the audit, the console shows progress:

```
2025-01-15 14:30:01 [Info]  ═══ CIS Benchmark Automation — Initializing ═══
2025-01-15 14:30:01 [Info]  Loaded master config (CIS Microsoft Windows Server 2025 Benchmark v1.0.0)
2025-01-15 14:30:02 [Info]  ── Auditing: SecurityOptions ──
2025-01-15 14:30:03 [Info]  SecurityOptions: 45 passed, 15 failed (of 60 controls)
2025-01-15 14:30:03 [Info]  ── Auditing: Firewall ──
2025-01-15 14:30:04 [Info]  Firewall: 20 passed, 6 failed (of 26 controls)
...
2025-01-15 14:30:15 [Info]  ═══════════════════════════════════════════
2025-01-15 14:30:15 [Info]  AUDIT COMPLETE — 339 controls evaluated
2025-01-15 14:30:15 [Info]  Passed: 250 | Failed: 70 | Skipped: 16 | Errors: 3
2025-01-15 14:30:15 [Info]  Compliance: 78.1%
2025-01-15 14:30:15 [Info]  ═══════════════════════════════════════════
```

### HTML Report

Located at `reports/CIS-Report-<timestamp>.html`. Open in any browser.

**Features:**
- Summary cards: Total, Passed, Failed, Skipped, Errors, Compliance %
- Sortable table with columns: ID, Title, Module, Status, Expected, Actual, Detail
- Color-coded rows: green (Pass), red (Fail), yellow (Skipped), purple (Error)
- Hover highlighting for easy row tracking

### JSON Report

Located at `reports/CIS-Report-<timestamp>.json`. Machine-readable for integration with dashboards, SIEM, or CI/CD.

**Structure:**
```json
{
    "ReportTitle": "CIS Benchmark L1 — Compliance Report",
    "GeneratedAt": "2025-01-15 14:30:15",
    "BenchmarkVersion": "CIS Microsoft Windows Server 2025 Benchmark v1.0.0",
    "Profile": "L1 - Member Server",
    "Summary": {
        "Total": 339,
        "Passed": 250,
        "Failed": 70,
        "Skipped": 16,
        "Errors": 3,
        "PassPercent": 78.1
    },
    "Results": [
        {
            "Id": "2.3.1.1",
            "Title": "Accounts: Block Microsoft accounts",
            "Module": "SecurityOptions",
            "Status": "Pass",
            "Expected": "3",
            "Actual": "3",
            "Detail": "HKLM:\\SOFTWARE\\...\\NoConnectedUser"
        }
    ]
}
```

### Log File

Detailed log at `reports/CIS-<timestamp>.log` — includes Debug-level messages if `LogLevel = 'Debug'` is set.

---

## Control Statuses

| Status | Meaning |
|---|---|
| **Pass** | Current value matches CIS requirement |
| **Fail** | Current value does not match CIS requirement |
| **Skipped** | Control excluded (AWS exclusion or module disabled) |
| **Error** | Could not read the setting (registry key missing, access denied, command failed) |

### Notes on "Error" Status
- A registry key not existing often means the setting was never configured — most of these are effectively "Fail"
- `secedit` keys may not appear if the security policy area was never configured
- On non-Windows machines, all checks will return Error (expected)

---

## Pre-Flight Connectivity Check

On **domain-joined** machines, `Test-AWSConnectivity` verifies management channels before auditing:

| Service | Check | Impact of Failure |
|---|---|---|
| WinRM | Service running + listeners configured | Audit halts (configurable) |
| SSM Agent | AmazonSSMAgent service running | Warning only |
| RDP | TermService running + port detected | Audit halts |
| Firewall | Management allow rules exist | Warning only |

On **standalone** machines, this check is automatically skipped (no AWS services to validate).

To skip manually: use `-SkipPrereqCheck` or set `HaltOnConnectivityFailure = $false` in master-config.

---

## Programmatic Usage

You can also import the module directly and call audit functions individually:

```powershell
Import-Module .\src\CISBenchmark.psm1 -Force

# Initialize (loads all config)
$config = Initialize-CISEnvironment -ProjectRoot $PWD -SkipPrereqCheck

# Audit a single module
$results = Test-CISSecurityOptions

# Filter failures
$failures = $results | Where-Object { $_.Status -eq 'Fail' }
$failures | Format-Table Id, Title, Expected, Actual -AutoSize

# Generate report from results
$summary = Export-CISReport -Results $results -Formats @('JSON')
```

---

## Scheduling Audits

To run audits on a schedule (e.g., daily compliance check), use `-Force` to skip all prompts:

```powershell
# Example: Windows Task Scheduler action
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\security_benchmarks\scripts\Invoke-CISAudit.ps1" -Force -SkipPrereqCheck

# IIS server — also skip IIS controls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\security_benchmarks\scripts\Invoke-CISAudit.ps1" -Force -SkipIIS -SkipPrereqCheck
```

Reports accumulate in `reports/` with timestamps — track compliance over time by comparing JSON reports.
