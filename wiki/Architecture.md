# Architecture

## Project Structure

```
security_benchmarks/
├── config/                         # All configuration — no code here
│   ├── master-config.psd1          # Global settings: OU, prefix, toggles, safety flags
│   ├── aws-exclusions.psd1         # Controls to skip/modify for AWS compatibility
│   └── modules/                    # One .psd1 per CIS section
│       ├── AccountPolicies.psd1    #   Section 1  (11 controls)
│       ├── UserRightsAssignment.psd1 # Section 2.2 (37 controls)
│       ├── SecurityOptions.psd1    #   Section 2.3 (60 controls)
│       ├── AuditPolicy.psd1        #   Section 17  (30 controls)
│       ├── Services.psd1           #   Section 5   (38 controls)
│       ├── Firewall.psd1           #   Section 9   (26 controls)
│       ├── AdminTemplates.psd1     #   Section 18  (128 controls)
│       └── AdminTemplatesUser.psd1 #   Section 19  (9 controls)
├── src/
│   ├── CISBenchmark.psm1          # Root module — dot-sources everything
│   ├── CISBenchmark.psd1          # Module manifest
│   ├── Core/                       # Infrastructure functions
│   │   ├── Initialize-CISEnvironment.ps1
│   │   ├── Get-CISConfiguration.ps1
│   │   ├── Write-CISLog.ps1
│   │   ├── Export-CISReport.ps1
│   │   ├── Test-AWSConnectivity.ps1
│   │   ├── New-CISGpoFramework.ps1
│   │   ├── Backup-CISState.ps1
│   │   └── Restore-CISState.ps1
│   └── Modules/                    # Each module: Test-*.ps1 + Set-*.ps1
│       ├── AccountPolicies/
│       ├── UserRightsAssignment/
│       ├── SecurityOptions/
│       ├── AuditPolicy/
│       ├── Services/
│       ├── Firewall/
│       ├── AdminTemplates/
│       └── AdminTemplatesUser/
├── scripts/                        # Entry points (what operators run)
│   ├── Invoke-CISAudit.ps1
│   ├── Invoke-CISApply.ps1
│   ├── Invoke-CISRollback.ps1
│   └── Install-Prerequisites.ps1
├── tests/                          # Pester 5.x tests
├── reports/                        # .gitignore'd — generated output
└── backups/                        # .gitignore'd — state snapshots
```

## Design Decisions

### 1. One GPO Per Module

Each CIS section gets its own GPO (e.g., `CIS-L1-SecurityOptions`, `CIS-L1-Firewall`). This provides:

- **Granular control** — unlink one GPO to disable an entire category without touching others
- **Easy troubleshooting** — `gpresult` shows exactly which GPO applied a setting
- **Incremental rollout** — enable modules one at a time in production
- **Clean rollback** — delete one GPO to fully revert a category

### 2. PowerShell Data Files (.psd1) for Configuration

All control definitions live in `.psd1` files rather than JSON, YAML, or CSV:

- **Native to PowerShell** — `Import-PowerShellDataFile` is built-in
- **Safe by design** — `.psd1` files cannot execute code (unlike `.ps1`)
- **Supports comments** — each control can be documented inline
- **Supports PowerShell types** — `$true`, `$false`, `@()` arrays, nested hashtables

### 3. DryRun = $true by Default

The master config ships with `DryRun = $true`. Every Set-CIS* function accepts a `-DryRun` parameter that defaults to the config value. This means:

- First-time users can safely run `Invoke-CISApply.ps1` and only see logs of what *would* change
- Switching to live mode requires an intentional config edit
- The `-DryRun` parameter can also be overridden per-invocation

### 4. Audit-First Pipeline

The system is designed so that auditing works independently of applying:

- `Test-CIS*` functions read the current machine state directly (registry, secedit, auditpol, Get-Service)
- `Set-CIS*` functions write to GPOs, which then propagate via Group Policy
- You can audit without ever creating a GPO
- Post-apply, the audit re-runs to show the compliance delta

### 5. Separation: Config vs. Code

Control definitions (what to check) are entirely in config files. The PowerShell code (how to check) is generic. To add a new registry-based control, you add a hashtable to a `.psd1` file — no code changes needed.

## Data Flow

### Audit Flow

```
Invoke-CISAudit.ps1
  ├─ Import-Module CISBenchmark
  ├─ Initialize-CISEnvironment
  │    ├─ Write-CISLog (set up logging)
  │    └─ Get-CISConfiguration
  │         ├─ Load master-config.psd1
  │         ├─ Load aws-exclusions.psd1
  │         └─ Load each enabled module's .psd1
  ├─ Test-AWSConnectivity (pre-flight)
  ├─ For each enabled module:
  │    └─ Test-CIS<Module>
  │         ├─ Read current state (registry / secedit / auditpol / service)
  │         └─ Compare against config → Pass / Fail / Skipped / Error
  └─ Export-CISReport (HTML + JSON)
```

### Apply Flow

```
Invoke-CISApply.ps1
  ├─ Initialize-CISEnvironment
  ├─ Safety confirmation prompt (if not DryRun)
  ├─ Test-AWSConnectivity (pre-flight)
  ├─ Backup-CISState (snapshot current GPOs + local policy)
  ├─ New-CISGpoFramework (create/link one GPO per module)
  ├─ For each enabled module (ordered):
  │    └─ Set-CIS<Module> -GpoName <prefix>-<module> -DryRun <bool>
  │         ├─ Registry controls → Set-GPRegistryValue
  │         ├─ Secedit controls → Write GptTmpl.inf to SYSVOL
  │         ├─ Audit controls → Write audit.csv to SYSVOL
  │         └─ Service controls → Set-GPRegistryValue on Start key
  ├─ Test-AWSConnectivity (post-flight)
  └─ Test-CIS* + Export-CISReport (post-apply compliance)
```

### Rollback Flow

```
Invoke-CISRollback.ps1
  ├─ Initialize-CISEnvironment
  ├─ Find backup (latest or specified)
  ├─ Restore-CISState
  │    ├─ Import-GPO from backup  —OR—  Remove-GPO entirely
  │    └─ gpupdate /force
  └─ Test-AWSConnectivity (post-rollback)
```

## Apply Mechanisms by Type

| Setting Type | Where It Lives | Audit Reads | Apply Writes |
|---|---|---|---|
| Registry-based | HKLM registry | `Get-ItemProperty` | `Set-GPRegistryValue` on GPO |
| User Rights Assignment | Security policy | `secedit /export` → parse .inf | Write `GptTmpl.inf` to `{GPO}\Machine\...\SecEdit\` |
| Advanced Audit Policy | Audit subcategories | `auditpol /get /category:*` | Write `audit.csv` to `{GPO}\Machine\...\Audit\` |
| Security Options (secedit) | Security policy | `secedit /export` → parse .inf | Write `GptTmpl.inf` to `{GPO}\Machine\...\SecEdit\` |
| Services | Service startup type | `Get-Service` + `Win32_Service` | `Set-GPRegistryValue` on `HKLM\...\Services\<name>\Start` |

## Module Loading Order

`CISBenchmark.psm1` dot-sources scripts in this order:

1. **Core (order matters):**
   - `Write-CISLog.ps1` — must be first (all other functions call it)
   - `Get-CISConfiguration.ps1` — depends on Write-CISLog
   - `Initialize-CISEnvironment.ps1` — depends on both above
   - Remaining core functions (order-independent)

2. **Modules (order-independent):**
   - Each folder under `src/Modules/` is scanned for `*.ps1` files
   - `Test-CIS*.ps1` and `Set-CIS*.ps1` are loaded for all 8 modules

## Script-Scope Variables

The module uses PowerShell's `$script:` scope for shared state:

| Variable | Set By | Used By |
|---|---|---|
| `$script:CISConfig` | `Get-CISConfiguration` | All Test/Set functions, Export-CISReport |
| `$script:LogFile` | `Initialize-CISEnvironment` | `Write-CISLog` |
