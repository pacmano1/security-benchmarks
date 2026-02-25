# Apply Guide

The apply pipeline enforces CIS-compliant settings. It auto-detects your environment and operates in one of two modes:

| Mode | When | How |
|---|---|---|
| **GPO Mode** | Domain-joined machine | Creates GPOs in AD, links to target OU, runs `gpupdate /force` |
| **Local Policy Mode** | Standalone machine (or `-LocalPolicy` flag) | Writes directly to registry, secedit, and auditpol |

---

## Prerequisites

### Domain Mode (GPO)

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

### Standalone / Local Policy Mode

1. **Run prerequisites installer** (auto-detects standalone):
   ```powershell
   .\scripts\Install-Prerequisites.ps1
   ```

2. **Run an audit first:**
   ```powershell
   .\scripts\Invoke-CISAudit.ps1 -SkipPrereqCheck
   ```

No AD permissions, RSAT modules, or domain connectivity required.

---

## Interactive Mode (Default)

Simply run the script with no flags — it will prompt you for each option:

```powershell
.\scripts\Invoke-CISApply.ps1
```

You'll be asked:

```
  ? Run in DRY RUN (preview only) or LIVE mode? [D/l]:
  ? Does this server run IIS (web server)? [y/N]:
  ? Apply all enabled modules or select specific ones? [A/s]:
  ? Disable unnecessary firewall rules (casting, mDNS, wireless display)? [y/N]:
```

- **Mode:** Press Enter for dry run (default), or `l` for live mode.
- **IIS:** Answer `Y` if this server runs IIS — skips controls 5.6, 5.31, 5.40.
- **Modules:** Press Enter for all, or `s` to pick from a numbered list.
- **Firewall hardening:** Answer `Y` to disable consumer firewall rules (casting, mDNS, etc.).

In live mode, you'll still be asked to type `YES` before any changes are made.

Each prompt is skipped when its corresponding CLI parameter is passed (e.g., `-DryRun $false` skips the mode prompt, `-Modules Firewall` skips the module prompt, etc.).

---

## Dry Run (Default)

With `DryRun = $true` (the default), apply only *logs* what it would do:

```powershell
# Interactive — prompts for options, defaults to dry run
.\scripts\Invoke-CISApply.ps1

# Non-interactive — skip all prompts
.\scripts\Invoke-CISApply.ps1 -Force
```

Output:
```
[Info]  ═══ CIS Benchmark — Apply Mode (DryRun: True) ═══
[Info]  [DRY RUN] Would create GPO: CIS-L1-AdminTemplates and link to OU=Servers,...
[Info]  [DRY RUN] Would set HKLM\SOFTWARE\Policies\...\NoLockScreenCamera = 1
[Info]  [DRY RUN] Would set HKLM\SOFTWARE\Policies\...\NoLockScreenSlideshow = 1
...

  ==================================
  Dry Run Complete
  ---------------------------------
    No changes were made. Run with LIVE mode to apply.
  ==================================
```

Review the dry run output to confirm the changes look correct. The post-apply compliance audit is skipped in dry run mode since no changes were made.

---

## Live Apply

### Step 1: Run Apply

```powershell
# Interactive — will prompt for mode, modules, IIS, firewall
.\scripts\Invoke-CISApply.ps1
```

Or pass the mode directly:
```powershell
.\scripts\Invoke-CISApply.ps1 -DryRun $false
```

You'll be prompted to confirm before changes are made:
```
╔════════════════════════════════════════════════════════╗
║  WARNING: This will CREATE GPOs and APPLY settings!   ║
║  Target OU: OU=Servers,OU=MyOrg,DC=corp,...           ║
╚════════════════════════════════════════════════════════╝

Type YES to proceed:
```

### Step 2: Skip All Prompts (Automation)

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

## IIS Servers (`-SkipIIS`)

CIS Section 5 includes controls that disable IIS services. On servers that **run IIS**, these must be skipped.

In interactive mode, the script asks: `Does this server run IIS (web server)? [y/N]`

For automation, use the `-SkipIIS` flag:

```powershell
# Apply on an IIS server (skip IIS service controls)
.\scripts\Invoke-CISApply.ps1 -DryRun $false -SkipIIS

# Automation — skip all prompts + skip IIS controls
.\scripts\Invoke-CISApply.ps1 -DryRun $false -Force -SkipIIS
```

Controls skipped by `-SkipIIS`:

| Control | Service | Description |
|---|---|---|
| 5.6 | IISADMIN | IIS Admin Service |
| 5.31 | WMSvc | Web Management Service |
| 5.40 | W3SVC | World Wide Web Publishing Service |

These controls appear as **Skipped** in audit reports with reason "IIS server — service must remain enabled".

---

## Firewall Rule Hardening (Optional)

Windows ships with default firewall allow rules for consumer features (casting, wireless display, mDNS, etc.) that are inappropriate on hardened servers. The CIS Firewall module (Section 9) only covers firewall **profile settings** -- it doesn't manage individual rules.

In interactive mode, the script asks: `Disable unnecessary firewall rules (casting, mDNS, wireless display)? [y/N]`

For automation, use the `-HardenFirewallRules` switch:

```powershell
# Preview what would be disabled (dry run)
.\scripts\Invoke-CISApply.ps1 -HardenFirewallRules

# Apply CIS settings + disable unnecessary firewall rules
.\scripts\Invoke-CISApply.ps1 -DryRun $false -HardenFirewallRules

# Standalone machine
.\scripts\Invoke-CISApply.ps1 -DryRun $false -SkipPrereqCheck -HardenFirewallRules
```

### Rule Groups Disabled

| Group | Why |
|---|---|
| Cast to Device functionality | Media casting -- not needed on servers |
| Wireless Display | Miracast -- not needed on servers |
| DIAL protocol server | Discovery and Launch -- consumer feature |
| mDNS | Multicast DNS -- not needed in managed environments |
| AllJoyn Router | IoT protocol -- not needed on servers |
| Connected Devices Platform | Consumer device pairing |
| Connected Devices Platform - Wi-Fi Direct Transport | Wi-Fi Direct -- not needed on servers |
| Wi-Fi Direct Network Discovery | Wi-Fi Direct -- not needed on servers |
| Wi-Fi Direct Scan | Wi-Fi Direct -- not needed on servers |
| Wi-Fi Direct Spooler Use | Wi-Fi Direct -- not needed on servers |
| Proximity Sharing | Near Share -- consumer feature |
| Media Center Extenders | Windows Media Center -- deprecated |
| Wireless Portable Devices | MTP device access -- not needed on servers |
| Microsoft Media Foundation Network Source | Media streaming -- not needed on servers |
| PlayTo Receiver | DLNA receiver -- not needed on servers |

This is **opt-in only** -- these rules are never disabled unless you explicitly pass `-HardenFirewallRules`. The switch respects DryRun mode.

---

## What Happens During Apply

### Step 1: Environment Detection
Auto-detects domain membership via `Win32_ComputerSystem.PartOfDomain`:
- **Domain-joined** -> GPO mode (creates GPOs in AD)
- **Standalone** -> Local policy mode (writes directly to local machine)

You'll see one of:
```
    +  Target: GROUP POLICY (domain-joined machine)
    +  Target: LOCAL POLICY (standalone machine detected)
```

### Step 2: Pre-Flight Connectivity Check (Domain Only)
Validates WinRM, SSM Agent, and RDP are operational. Skipped in local policy mode.

### Step 3: State Backup
Creates a timestamped backup in `backups/CIS-Backup-<timestamp>/`:

| Backup item | Domain mode | Local policy mode |
|---|---|---|
| GPO backups (`Backup-GPO`) | Yes | Skipped |
| secedit policy export | Yes | Yes |
| auditpol export | Yes | Yes |
| Service startup states | Yes | Yes |
| Metadata JSON | Yes | Yes |

### Step 4: GPO Framework / Local Policy Preparation

**Domain mode:** Creates a GPO per module (`<GpoPrefix>-<ModuleName>`) and links each to the target OU.

**Local policy mode:** Prepares direct-write targets (no GPOs created).

### Step 5: Apply Settings (Ordered)

| Order | Module | Domain (GPO) | Local Policy |
|---|---|---|---|
| 1 | AdminTemplates | `Set-GPRegistryValue` | `Set-ItemProperty` |
| 2 | Firewall | `Set-GPRegistryValue` | `Set-ItemProperty` |
| 3 | AdminTemplatesUser | `Set-GPRegistryValue` | `Set-ItemProperty` |
| 4 | SecurityOptions | `Set-GPRegistryValue` + GptTmpl.inf | `Set-ItemProperty` + `secedit /configure` |
| 5 | UserRightsAssignment | GptTmpl.inf | `secedit /configure` |
| 6 | AuditPolicy | audit.csv + CSE GUID | `auditpol /set` per subcategory |
| 7 | Services | `Set-GPRegistryValue` | `Set-ItemProperty` on Start key |
| 8 | AccountPolicies | (skipped) | (skipped) |

### Step 6: Policy Refresh

**Domain mode:** Runs `gpupdate /force /wait:120` to apply GPO settings to the local machine.

**Local policy mode:** No refresh needed — settings were written directly.

### Step 7: Post-Flight Connectivity Check (Domain Only)
Re-validates WinRM, SSM, and RDP. Skipped in local policy mode.

### Step 8: Post-Apply Compliance Report (Live Mode Only)
In live mode, runs a full audit and generates an updated report so you can see the compliance improvement. Skipped in dry run mode (no changes to measure).

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

## Golden AMI Workflow (Local Policy)

The local policy mode is ideal for building hardened AMIs:

```powershell
# 1. Launch a fresh Windows Server 2025 instance
# 2. Run prerequisites and CIS hardening (use -Force to skip prompts)
.\scripts\Install-Prerequisites.ps1 -Force
.\scripts\Invoke-CISApply.ps1 -DryRun $false -Force -SkipPrereqCheck

# For IIS servers, add -SkipIIS:
.\scripts\Invoke-CISApply.ps1 -DryRun $false -Force -SkipPrereqCheck -SkipIIS

# 3. Verify compliance
.\scripts\Invoke-CISAudit.ps1 -Force -SkipPrereqCheck

# 4. Save as AMI
# 5. Launch EC2 instances from AMI and join to AD
```

**What happens when the AMI joins a domain:**
- Local policy settings serve as the hardened baseline (lowest priority)
- Domain/OU GPOs layer on top and override any overlapping settings
- Settings not covered by domain GPOs retain their hardened local values
- Group Policy precedence: Local < Site < Domain < OU

---

## Incremental Rollout Strategy

Recommended approach for production:

### Domain Mode

1. **Test environment first:**
   - Create a test OU with one or two servers
   - Apply all modules -> verify functionality -> run audit

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

### Standalone Mode

1. **Apply all at once** (safe — changes are local only):
   ```powershell
   .\scripts\Invoke-CISApply.ps1 -DryRun $false -SkipPrereqCheck
   ```

2. **Or module-by-module:**
   ```powershell
   .\scripts\Invoke-CISApply.ps1 -Modules Firewall -DryRun $false -SkipPrereqCheck
   .\scripts\Invoke-CISApply.ps1 -Modules AdminTemplates -DryRun $false -SkipPrereqCheck
   ```

3. **Rollback** restores secedit/auditpol baselines and service states from backup
