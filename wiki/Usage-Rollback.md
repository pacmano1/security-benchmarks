# Rollback Guide

The rollback pipeline reverts CIS Benchmark changes by restoring GPOs from backup or removing them entirely.

---

## When to Rollback

- **Post-flight failure:** After apply, connectivity checks fail (WinRM, SSM, RDP impaired)
- **Application issues:** Services or applications break after policy enforcement
- **Testing:** Reverting a test apply before production rollout
- **Module-specific:** Disable just one CIS section that caused issues

---

## Quick Rollback (Most Recent Backup)

```powershell
.\scripts\Invoke-CISRollback.ps1
```

This automatically finds the latest backup in `backups/` and restores all GPOs.

You'll be prompted:
```
╔════════════════════════════════════════════════════════╗
║  ROLLBACK: This will revert CIS Benchmark changes!   ║
║  Backup: CIS-Backup-20250115-143015                  ║
║  Mode: Restore GPOs to pre-apply state               ║
╚════════════════════════════════════════════════════════╝

Type YES to proceed with rollback:
```

---

## Rollback Options

### Restore from a Specific Backup

```powershell
.\scripts\Invoke-CISRollback.ps1 -BackupPath .\backups\CIS-Backup-20250115-143015
```

### Rollback a Single Module

```powershell
.\scripts\Invoke-CISRollback.ps1 -Module SecurityOptions
```

Only the `CIS-L1-SecurityOptions` GPO is restored; other GPOs are untouched.

### Remove GPOs Entirely (Instead of Restoring)

```powershell
.\scripts\Invoke-CISRollback.ps1 -RemoveGPOs
```

This unlinks and **deletes** all CIS GPOs. Use when you want a clean slate rather than restoring prior settings.

### Remove a Single Module's GPO

```powershell
.\scripts\Invoke-CISRollback.ps1 -Module Firewall -RemoveGPOs
```

### Skip Confirmation

```powershell
.\scripts\Invoke-CISRollback.ps1 -Force
```

---

## What Happens During Rollback

### Restore Mode (Default)

1. Loads backup metadata from `backup-metadata.json`
2. For each module:
   - Finds the GPO backup in `GPOs/` subfolder
   - Runs `Import-GPO` to restore the GPO to its pre-apply state
3. Runs `gpupdate /force` to apply restored settings immediately
4. Runs post-rollback connectivity check

### Remove Mode (`-RemoveGPOs`)

1. For each module:
   - Unlinks the GPO from the target OU (`Remove-GPLink`)
   - Deletes the GPO (`Remove-GPO`)
2. Runs `gpupdate /force`
3. Runs post-rollback connectivity check

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
