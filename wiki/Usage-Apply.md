# Apply Guide

The apply pipeline creates Group Policy Objects and populates them with CIS-compliant settings. This **modifies Active Directory** — use with care.

---

## Prerequisites

Before applying:

1. **Run prerequisites installer:**
   ```powershell
   .\scripts\Install-Prerequisites.ps1
   ```

2. **Edit master config:**
   - Set `TargetOU` to your delegated OU's Distinguished Name
   - Set `GpoPrefix` (default: `CIS-L1`)
   - Enable/disable modules as needed
   - Leave `DryRun = $true` for your first run

3. **Verify permissions:** The account running the script needs:
   - Create GPO objects in the domain
   - Link GPOs to the target OU
   - Write to SYSVOL (for GptTmpl.inf and audit.csv)

4. **Run an audit first:**
   ```powershell
   .\scripts\Invoke-CISAudit.ps1
   ```
   Review the report to understand your current compliance posture.

---

## Dry Run (Default)

With `DryRun = $true` (the default), apply only *logs* what it would do:

```powershell
.\scripts\Invoke-CISApply.ps1
```

Output:
```
[Info]  ═══ CIS Benchmark — Apply Mode (DryRun: True) ═══
[Info]  [DRY RUN] Would create GPO: CIS-L1-AdminTemplates and link to OU=Servers,...
[Info]  [DRY RUN] Would set HKLM\SOFTWARE\Policies\...\NoLockScreenCamera = 1
[Info]  [DRY RUN] Would set HKLM\SOFTWARE\Policies\...\NoLockScreenSlideshow = 1
...
```

Review the dry run output to confirm the changes look correct.

---

## Live Apply

### Step 1: Set DryRun to False

Edit `config/master-config.psd1`:
```powershell
DryRun = $false
```

Or pass it on the command line:
```powershell
.\scripts\Invoke-CISApply.ps1 -DryRun $false
```

### Step 2: Run Apply

```powershell
.\scripts\Invoke-CISApply.ps1
```

You'll be prompted to confirm:
```
╔════════════════════════════════════════════════════════╗
║  WARNING: This will CREATE GPOs and APPLY settings!   ║
║  Target OU: OU=Servers,OU=MyOrg,DC=corp,...           ║
╚════════════════════════════════════════════════════════╝

Type YES to proceed:
```

### Step 3: Skip Confirmation (Automation)

```powershell
.\scripts\Invoke-CISApply.ps1 -DryRun $false -Force
```

---

## Apply-Specific Modules

```powershell
# Apply only firewall and audit policy
.\scripts\Invoke-CISApply.ps1 -Modules Firewall, AuditPolicy -DryRun $false
```

---

## What Happens During Apply

### 1. Pre-Flight Connectivity Check
Validates WinRM, SSM Agent, and RDP are operational. Aborts if any critical check fails.

### 2. State Backup
Creates a timestamped backup in `backups/CIS-Backup-<timestamp>/`:
- GPO backups (via `Backup-GPO`)
- Current secedit policy export
- Current auditpol export
- All service startup states
- Metadata (timestamp, modules, OU, computer name)

### 3. GPO Framework Creation
For each enabled module, creates a GPO named `<GpoPrefix>-<ModuleName>`:

```
CIS-L1-AdminTemplates
CIS-L1-AuditPolicy
CIS-L1-Firewall
CIS-L1-SecurityOptions
CIS-L1-Services
CIS-L1-UserRightsAssignment
CIS-L1-AdminTemplatesUser
```

Each GPO is linked to the target OU. If a GPO already exists, it's reused.

### 4. Apply Settings (Ordered)

Settings are applied in this order:

| Order | Module | Mechanism | Why This Order |
|---|---|---|---|
| 1 | AdminTemplates | `Set-GPRegistryValue` | Largest module, registry-based (fast) |
| 2 | Firewall | `Set-GPRegistryValue` | Registry-based |
| 3 | AdminTemplatesUser | `Set-GPRegistryValue` | Registry-based (User config) |
| 4 | SecurityOptions | `Set-GPRegistryValue` + GptTmpl.inf | Mixed mechanism |
| 5 | UserRightsAssignment | GptTmpl.inf | Secedit-based |
| 6 | AuditPolicy | audit.csv | Requires CSE GUID update |
| 7 | Services | `Set-GPRegistryValue` | Registry-based |
| 8 | AccountPolicies | (skipped) | AWS-owned |

### 5. Post-Flight Connectivity Check
Re-validates WinRM, SSM, and RDP. If any check fails:
- Logs a prominent error with the backup path
- Suggests running rollback
- Exits with error code 1

### 6. Post-Apply Compliance Report
Runs a full audit and generates an updated report so you can see the compliance improvement.

---

## GPO Management After Apply

### View GPOs in GPMC
Open Group Policy Management Console → navigate to your OU → you'll see the linked CIS GPOs.

### Apply Settings to Clients
Settings propagate via normal Group Policy:
```powershell
# Force immediate update on a target machine
gpupdate /force
```

Or wait for the default refresh interval (90 minutes ± 30 minutes).

### Disable a Module
To stop applying a CIS section without deleting the GPO:
1. In GPMC, right-click the GPO link → **Link Enabled = No**
2. Or update `master-config.psd1` and re-run apply (it won't remove existing GPOs)

### Re-Run Apply (Idempotent)
Running apply again is safe:
- GPOs that already exist are reused
- Settings are overwritten with the same values
- No errors, no duplicates

---

## Incremental Rollout Strategy

Recommended approach for production:

1. **Test environment first:**
   - Create a test OU with one or two servers
   - Apply all modules → verify functionality → run audit

2. **Production — one module at a time:**
   ```powershell
   # Week 1: Firewall only
   .\scripts\Invoke-CISApply.ps1 -Modules Firewall -DryRun $false

   # Week 2: Add Audit Policy
   .\scripts\Invoke-CISApply.ps1 -Modules AuditPolicy -DryRun $false

   # Week 3: Add AdminTemplates
   .\scripts\Invoke-CISApply.ps1 -Modules AdminTemplates -DryRun $false
   ```

3. **Monitor after each module:**
   - Run `Invoke-CISAudit.ps1` to verify compliance
   - Check application functionality
   - Monitor event logs for authentication/access issues
   - Verify SSM Agent connectivity in AWS Systems Manager

4. **Full rollout:**
   - Once all modules are validated, move the target OU scope to include all servers
