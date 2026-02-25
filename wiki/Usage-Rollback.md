# Rollback Guide

The rollback pipeline reverts CIS Benchmark changes. On domain-joined machines, it restores GPOs from backup or removes them. On standalone machines, it restores local secedit, auditpol, and service baselines.

---

## When to Rollback

- **Post-flight failure:** After apply, connectivity checks fail (WinRM, SSM, RDP impaired)
- **Application issues:** Services or applications break after policy enforcement
- **Testing:** Reverting a test apply before production rollout
- **Module-specific:** Disable just one CIS section that caused issues

---

## Interactive Rollback (Default)

Run with no flags — the script will guide you through the options:

```powershell
.\scripts\Invoke-CISRollback.ps1
```

If multiple backups exist, you'll be shown a list:

```
  Available backups:
    1. CIS-Backup-20250120-091500 (most recent)
    2. CIS-Backup-20250115-143015
    3. CIS-Backup-20250110-080000

  ? Select a backup [1] (default: most recent):
```

Then you'll be asked about module scope:

```
  ? Rollback all modules or a specific one? [A/s]:
```

Type `s` to see a numbered list of modules in the backup and pick one, or press Enter to rollback all.

Finally, you'll confirm with `YES` before any changes are made.

---

## Quick Rollback (Most Recent Backup)

```powershell
.\scripts\Invoke-CISRollback.ps1 -Force
```

The `-Force` flag skips all prompts: uses the most recent backup, rolls back all modules, and skips the `YES` confirmation.

---

## Rollback Options

### Restore from a Specific Backup

```powershell
.\scripts\Invoke-CISRollback.ps1 -BackupPath .\backups\CIS-Backup-20250115-143015
```

When `-BackupPath` is passed, the backup selection prompt is skipped.

### Rollback a Single Module

```powershell
.\scripts\Invoke-CISRollback.ps1 -Module SecurityOptions
```

Only the `CIS-L1-SecurityOptions` GPO is restored; other GPOs are untouched. When `-Module` is passed, the module scope prompt is skipped.

### Remove GPOs Entirely (Instead of Restoring)

```powershell
.\scripts\Invoke-CISRollback.ps1 -RemoveGPOs
```

This unlinks and **deletes** all CIS GPOs. Use when you want a clean slate rather than restoring prior settings.

> **Note:** `-RemoveGPOs` is CLI-only — it is never offered as an interactive prompt due to its destructive nature.

### Remove a Single Module's GPO

```powershell
.\scripts\Invoke-CISRollback.ps1 -Module Firewall -RemoveGPOs
```

### Skip All Prompts

```powershell
.\scripts\Invoke-CISRollback.ps1 -Force
```

---

## What Happens During Rollback

### On Standalone Machines (Local Policy)

1. Loads backup metadata from `backup-metadata.json`
2. Restores secedit baseline via `secedit /configure`
3. Restores audit policy via `auditpol /restore`
4. Restores service startup states via registry writes
5. GPO operations are skipped

### On Domain-Joined Machines

#### Restore Mode (Default)

1. Loads backup metadata from `backup-metadata.json`
2. Restores local baselines (secedit, auditpol, services)
3. For each module:
   - Finds the GPO backup in `GPOs/` subfolder
   - Runs `Import-GPO` to restore the GPO to its pre-apply state
4. Runs `gpupdate /force` to apply restored settings immediately
5. Runs post-rollback connectivity check

#### Remove Mode (`-RemoveGPOs`)

1. Restores local baselines (secedit, auditpol, services)
2. For each module:
   - Unlinks the GPO from the target OU (`Remove-GPLink`)
   - Deletes the GPO (`Remove-GPO`)
3. Runs `gpupdate /force`
4. Runs post-rollback connectivity check

---

## Backup Contents

Each backup in `backups/CIS-Backup-<timestamp>/` contains:

| File/Folder | Description |
|---|---|
| `backup-metadata.json` | Timestamp, modules, GPO prefix, OU, computer name |
| `GPOs/` | Full GPO backups (from `Backup-GPO`) |
| `secedit-baseline.inf` | Security policy snapshot at time of backup |
| `auditpol-baseline.csv` | Audit policy snapshot |
| `services-baseline.json` | All service names, start modes, and states |

### Listing Available Backups

```powershell
Get-ChildItem .\backups\ -Directory | Sort-Object Name -Descending | Format-Table Name, LastWriteTime
```

### Inspecting a Backup

```powershell
Get-Content .\backups\CIS-Backup-20250115-143015\backup-metadata.json | ConvertFrom-Json | Format-List
```

---

## Manual Rollback (If Script Fails)

If the rollback script itself fails (e.g., AD connectivity lost), you can manually revert:

### Option A: GPMC

1. Open Group Policy Management Console
2. Navigate to your OU
3. Right-click each `CIS-L1-*` GPO link → **Delete Link** (unlinks but doesn't delete)
4. Or right-click the GPO → **Delete** (removes entirely)
5. Run `gpupdate /force` on affected machines

### Option B: PowerShell

```powershell
# Unlink and delete a specific GPO
Remove-GPLink -Name 'CIS-L1-SecurityOptions' -Target 'OU=Servers,DC=corp,DC=example,DC=com'
Remove-GPO -Name 'CIS-L1-SecurityOptions'

# Force update
gpupdate /force
```

### Option C: Restore Secedit Baseline

If `GptTmpl.inf`-based settings need manual revert:

```powershell
# Restore from backup
secedit /configure /db secedit.sdb /cfg .\backups\CIS-Backup-20250115-143015\secedit-baseline.inf /overwrite
```

### Option D: Restore Audit Policy

```powershell
auditpol /restore /file:.\backups\CIS-Backup-20250115-143015\auditpol-baseline.csv
```

---

## Post-Rollback Verification

After rollback, always verify:

1. **Connectivity:**
   ```powershell
   # Check management services
   Get-Service WinRM, TermService, AmazonSSMAgent | Format-Table Name, Status
   ```

2. **GPO removal:**
   ```powershell
   # Should return nothing for removed GPOs
   Get-GPO -Name 'CIS-L1-*' -ErrorAction SilentlyContinue
   ```

3. **Policy refresh:**
   ```powershell
   gpresult /r    # Check which GPOs are applied
   ```

4. **Run audit to confirm revert:**
   ```powershell
   .\scripts\Invoke-CISAudit.ps1
   ```
