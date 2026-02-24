# Configuration

All configuration lives in `.psd1` (PowerShell Data) files under `config/`. These files are loaded via `Import-PowerShellDataFile`, which is safe — it cannot execute arbitrary code.

---

## Master Config (`config/master-config.psd1`)

The central configuration file. Edit this before running anything.

### Required Settings

| Key | Type | Description |
|---|---|---|
| `TargetOU` | String | Distinguished Name of the OU where GPOs will be linked. Must be a delegated OU — not the domain root, not the Domain Controllers OU. |
| `GpoPrefix` | String | Prefix for all GPO names (default: `CIS-L1`). GPOs are named `<prefix>-<module>`. |

### Safety Settings

| Key | Type | Default | Description |
|---|---|---|---|
| `DryRun` | Boolean | `$true` | **Most important setting.** When `$true`, all Set-CIS* functions only log — no GPOs are created or modified. |
| `HaltOnConnectivityFailure` | Boolean | `$true` | Abort if pre-flight check (WinRM, SSM, RDP) fails. |
| `PostFlightCheck` | Boolean | `$true` | Run connectivity check after applying changes. |

### Module Toggles

```powershell
Modules = @{
    AccountPolicies      = $false   # Section 1 — DISABLED: AWS owns domain policy
    UserRightsAssignment = $true    # Section 2.2
    SecurityOptions      = $true    # Section 2.3
    AuditPolicy          = $true    # Section 17
    Services             = $true    # Section 5
    Firewall             = $true    # Section 9
    AdminTemplates       = $true    # Section 18
    AdminTemplatesUser   = $true    # Section 19
}
```

Set any module to `$false` to skip it during both audit and apply. AccountPolicies is disabled by default because AWS Managed AD controls domain password/lockout policy.

### Logging & Reports

| Key | Type | Default | Description |
|---|---|---|---|
| `LogLevel` | String | `Info` | Minimum severity to log: `Debug`, `Info`, `Warning`, `Error` |
| `LogPath` | String | `reports` | Directory for log files (relative to project root) |
| `ReportFormats` | Array | `@('HTML', 'JSON')` | Output formats for compliance reports |

### Example: Minimal Production Config

```powershell
@{
    BenchmarkVersion = 'CIS Microsoft Windows Server 2025 Benchmark v1.0.0'
    Profile          = 'L1 - Member Server'
    TargetOU         = 'OU=Servers,OU=Production,DC=corp,DC=mycompany,DC=com'
    GpoPrefix        = 'CIS-L1'
    DryRun           = $false        # LIVE MODE
    HaltOnConnectivityFailure = $true
    PostFlightCheck  = $true
    Modules = @{
        AccountPolicies      = $false
        UserRightsAssignment = $true
        SecurityOptions      = $true
        AuditPolicy          = $true
        Services             = $true
        Firewall             = $true
        AdminTemplates       = $true
        AdminTemplatesUser   = $true
    }
    LogLevel      = 'Info'
    LogPath       = 'reports'
    ReportFormats = @('HTML', 'JSON')
}
```

---

## Module Config Files (`config/modules/<ModuleName>.psd1`)

Each module has its own config file defining every CIS control it manages. The structure varies slightly by mechanism type.

### Common Fields

Every control hashtable has:

| Field | Required | Description |
|---|---|---|
| `Id` | Yes | CIS control ID (e.g., `2.3.1.1`) |
| `Title` | Yes | Human-readable control title |
| `Description` | No | Additional context or CIS recommendation text |

### Registry-Based Controls

Used by: SecurityOptions, AdminTemplates, Firewall, AdminTemplatesUser

```powershell
@{
    Id       = '2.3.17.6'
    Title    = 'UAC: Run all administrators in Admin Approval Mode'
    Registry = @{
        Path     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        Name     = 'EnableLUA'
        Type     = 'DWord'          # DWord, String, MultiString, ExpandString, QWord, Binary
        Value    = 1
        Operator = 'Equals'         # Optional: Equals (default), LessOrEqual, GreaterOrEqual, Range, NotEmpty, Empty
        MinValue = 0                # For Range/LessOrEqual operators
        MaxValue = 100              # For Range operator
    }
}
```

**Operators:**

| Operator | Comparison | Example Use |
|---|---|---|
| `Equals` | `actual == expected` (default) | Most boolean/enum settings |
| `LessOrEqual` | `actual <= expected && actual >= MinValue` | Timeouts, max ages |
| `GreaterOrEqual` | `actual >= expected` | Log sizes, minimum lengths |
| `Range` | `MinValue <= actual <= MaxValue` | Password warning days (5–14) |
| `NotEmpty` | Value is not null/blank | Legal notice text |
| `Empty` | Value is null/blank or empty array | Named pipes (must be none) |

### Secedit-Based Controls

Used by: SecurityOptions (some), AccountPolicies, UserRightsAssignment

```powershell
# Security policy value (exact match)
@{
    Id          = '2.3.1.2'
    Title       = 'Accounts: Guest account status'
    Secedit     = @{
        Key   = 'EnableGuestAccount'
        Value = '0'
    }
}

# Security policy value (not-equal check)
@{
    Id          = '2.3.1.4'
    Title       = 'Accounts: Rename administrator account'
    Secedit     = @{
        Key      = 'NewAdministratorName'
        NotValue = '"Administrator"'     # Must NOT be the default
    }
}

# User rights assignment (SID list)
@{
    Id            = '2.2.6'
    Title         = 'Allow log on locally'
    SeceditKey    = 'SeInteractiveLogonRight'
    ExpectedValue = '*S-1-5-32-544'       # Comma-separated SIDs
    Description   = 'Administrators'
}
```

### Audit Policy Controls

Used by: AuditPolicy

```powershell
@{
    Id               = '17.5.4'
    Title            = 'Audit Logon'
    Subcategory      = 'Logon'                                        # auditpol subcategory name
    CategoryGuid     = '{0CCE9215-69AE-11D9-BED3-505054503030}'       # Subcategory GUID
    ExpectedValue    = 'Success and Failure'                          # What we check during audit
    InclusionSetting = 'Success and Failure'                          # What we write to audit.csv
}
```

### Service Controls

Used by: Services

```powershell
@{
    Id          = '5.17'
    Title       = 'Print Spooler (Spooler)'
    ServiceName = 'Spooler'
    StartType   = 'Disabled'              # Disabled, Manual, or Auto
}
```

---

## AWS Exclusions (`config/aws-exclusions.psd1`)

Defines controls that must be skipped or modified for AWS Managed AD compatibility.

### Skip List

Controls in the `Skip` array are marked `Status = Skipped` during audit and ignored during apply:

```powershell
Skip = @(
    '1.1.1', '1.1.2', ...    # Domain password policy — AWS owns these
    '5.20', '5.21', '5.22'   # RDP services — must stay enabled
    '5.39'                    # WinRM — must stay for SSM/management
)
```

### Modify List

Controls in the `Modify` hashtable use a different value than the CIS recommendation:

```powershell
Modify = @{
    '2.2.17' = '*S-1-5-32-546'     # Don't deny SYSTEM network access (SSM Agent)
    '2.2.38' = '*S-1-5-19,*S-1-5-20'  # Ensure SYSTEM keeps service logon
}
```

When `Set-CIS*` applies a control listed in `Modify`, it uses the modified value instead of the config default.

### Notes (Informational)

The `Notes` section documents the reasoning but is not parsed by code:

```powershell
Notes = @{
    RDP      = 'RDP hardening controls are applied but RDP itself is never disabled.'
    WinRM    = 'WinRM hardening applied (no Basic auth) but service stays enabled.'
    SSMAgent = 'Amazon SSM Agent runs as SYSTEM — controls are modified to preserve it.'
}
```

---

## Configuration Loading Order

When `Get-CISConfiguration` runs:

1. Load `config/master-config.psd1` → `$script:CISConfig`
2. Load `config/aws-exclusions.psd1` → `$script:CISConfig.AWSExclusions`
3. For each enabled module, load `config/modules/<Module>.psd1` → `$script:CISConfig.ModuleConfigs.<Module>`
4. Walk all loaded controls — if a control's ID is in the Skip list, set `$ctl.Skipped = $true`

The merged config object is then available to all functions via `$script:CISConfig`.
