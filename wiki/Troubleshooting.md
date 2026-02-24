# Troubleshooting

Common issues and solutions when running the CIS Benchmark automation.

---

## Installation & Prerequisites

### "Required module not installed: GroupPolicy"

**Cause:** RSAT tools are not installed.

**Fix:**
```powershell
# Run as Administrator
.\scripts\Install-Prerequisites.ps1

# Or manually:
Install-WindowsFeature -Name GPMC -IncludeManagementTools
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

### "secedit.exe not found"

**Cause:** Running on a system without the Security Configuration tool.

**Fix:** `secedit.exe` should be present on all Windows Server editions. Verify:
```powershell
Get-Command secedit.exe
# Expected: C:\Windows\System32\secedit.exe
```

### "auditpol.exe not found"

**Cause:** Same as above — should exist on all Windows Server editions.

**Fix:**
```powershell
Get-Command auditpol.exe
# Expected: C:\Windows\System32\auditpol.exe
```

---

## Configuration Loading

### "Master config not found"

**Cause:** Running from the wrong directory or `$ProjectRoot` is incorrect.

**Fix:**
```powershell
# Ensure you're in the project root
cd C:\security_benchmarks
.\scripts\Invoke-CISAudit.ps1

# Or specify the root explicitly
.\scripts\Invoke-CISAudit.ps1 -ProjectRoot C:\security_benchmarks
```

### "Module config not found: config/modules/X.psd1"

**Cause:** A module is enabled in master-config but its `.psd1` file doesn't exist.

**Fix:** Either create the config file (see [Adding Controls](Adding-Controls.md)) or disable the module in master-config.

### "Error importing PowerShell data file"

**Cause:** Syntax error in a `.psd1` file (usually a missing comma, bracket, or quote).

**Fix:**
```powershell
# Test the file
Import-PowerShellDataFile -Path .\config\modules\SecurityOptions.psd1
```

Common `.psd1` syntax issues:
- Missing comma between hashtable entries in an array
- Unmatched `@{` and `}` braces
- Single quotes inside a single-quoted string (use `''` to escape)
- Trailing comma after the last item in an array

---

## Audit Issues

### All Controls Show "Error" / "(not set)"

**Cause:** Running on a non-Windows machine (macOS/Linux), or running without Administrator privileges.

**Fix:**
- Run PowerShell as Administrator on a Windows Server 2025 machine
- Use `-SkipPrereqCheck` for testing on non-domain machines

### Audit Policy Controls Show "(not found)"

**Cause:** The subcategory name in the config doesn't match `auditpol` output exactly.

**Fix:**
```powershell
# List all subcategories with exact names
auditpol.exe /get /category:* /r | ConvertFrom-Csv | Select-Object Subcategory | Sort-Object Subcategory
```

Compare against the `Subcategory` field in `AuditPolicy.psd1`.

### Service Controls Show "Error" for Missing Services

**Cause:** The service isn't installed on this system (e.g., IIS-related services on a machine without IIS).

**Note:** This is expected and handled — services that are not installed count as **Pass** if the expected state is Disabled. If it shows as Error, check the service name spelling.

### User Rights Assignment Shows SIDs Instead of Names

**Cause:** Normal behavior — `secedit` exports SIDs, not friendly names. The audit function compares SIDs directly.

**Tip:** To translate SIDs to names:
```powershell
$sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$sid.Translate([System.Security.Principal.NTAccount]).Value
# Output: BUILTIN\Administrators
```

---

## Apply Issues

### "Cannot find GPO 'CIS-L1-X'"

**Cause:** GPO creation failed (permissions, AD connectivity, or naming conflict).

**Fix:**
```powershell
# Check if GPOs exist
Get-GPO -All | Where-Object { $_.DisplayName -match 'CIS-L1' }

# Check permissions — you need to create GPOs in the domain
# Try creating one manually:
New-GPO -Name 'CIS-L1-Test' -Comment 'test'
```

### "Access denied" When Writing to SYSVOL

**Cause:** Insufficient permissions on the SYSVOL share for the GPO path.

**Fix:**
- Ensure your account has **Edit Settings** permission on the GPO (not just Read)
- Check SYSVOL replication health:
  ```powershell
  dcdiag /test:sysvolcheck
  ```

### GPO Settings Don't Apply After `gpupdate`

**Causes and fixes:**

1. **WMI filter or security filtering:** Check GPO scope in GPMC
2. **GPO link disabled:** Verify the link is enabled in GPMC
3. **OU targeting wrong:** Verify the computer account is in the target OU
4. **Replication delay:** Wait a few minutes and try again
5. **CSE not triggered:** For audit policy, verify `gPCMachineExtensionNames` contains the audit CSE GUID

```powershell
# Detailed GPO application report
gpresult /h gpresult.html
start gpresult.html
```

### "GptTmpl.inf" Changes Not Taking Effect

**Cause:** The `gPCMachineExtensionNames` attribute on the GPO AD object may not include the Security CSE.

**Fix:**
```powershell
# The Security Settings CSE GUID pair:
# [{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]
# Verify it's in the GPO's extension list in AD
```

---

## Rollback Issues

### "No backups found"

**Cause:** No apply has been run yet, or backups were deleted.

**Fix:**
```powershell
# Check backup directory
Get-ChildItem .\backups\ -Directory

# If empty — you need to create a backup first or manually revert via GPMC
```

### "Invalid backup: metadata not found"

**Cause:** The backup folder is corrupted or was manually modified.

**Fix:** Use a different backup, or manually rollback via GPMC (see [Rollback Guide](Usage-Rollback.md#manual-rollback-if-script-fails)).

---

## Connectivity Issues

### WinRM Fails After Apply

**Emergency fix:**
```powershell
# If you still have RDP access:
Enable-PSRemoting -Force
Set-Service WinRM -StartupType Automatic
Start-Service WinRM

# Remove the WinRM GPO
Remove-GPLink -Name 'CIS-L1-AdminTemplates' -Target $TargetOU
gpupdate /force
```

### SSM Agent Stops Working

**Cause:** A policy is blocking SYSTEM from network access.

**Fix:**
```powershell
# Check deny network logon right
secedit /export /cfg C:\temp\secpol.inf
Select-String 'SeDenyNetworkLogonRight' C:\temp\secpol.inf

# If SYSTEM (*S-1-5-18) or NETWORK SERVICE (*S-1-5-20) appears, remove them
# Quickest fix: unlink the UserRightsAssignment GPO
Remove-GPLink -Name 'CIS-L1-UserRightsAssignment' -Target $TargetOU
gpupdate /force
```

### RDP Stops Working

**Cause:** Unlikely with AWS exclusions in place, but possible if exclusions were modified.

**Fix (via SSM Session Manager if RDP is down):**
```powershell
# Check TermService
Get-Service TermService
Start-Service TermService

# Check firewall
Get-NetFirewallRule -DisplayName 'Remote Desktop*' | Select-Object DisplayName, Enabled, Action

# Remove all CIS GPO links as emergency measure
Get-GPO -All | Where-Object { $_.DisplayName -match '^CIS-L1-' } | ForEach-Object {
    Remove-GPLink -Name $_.DisplayName -Target $TargetOU -ErrorAction SilentlyContinue
}
gpupdate /force
```

---

## Pester Test Failures

### "Should have a Controls array" Fails

**Cause:** Empty or malformed `.psd1` file.

**Fix:** Run `Import-PowerShellDataFile` on the file to see the parse error.

### "Should have unique control IDs" Fails

**Cause:** Duplicate `Id` values in a module config.

**Fix:** Search for duplicates:
```powershell
$cfg = Import-PowerShellDataFile .\config\modules\AdminTemplates.psd1
$cfg.Controls | Group-Object Id | Where-Object { $_.Count -gt 1 } | Select-Object Name, Count
```

---

## General Tips

### Enable Debug Logging

In `master-config.psd1`:
```powershell
LogLevel = 'Debug'
```

This shows detailed output for every control check, including registry paths, secedit keys, and comparison results.

### Test a Single Module in Isolation

```powershell
Import-Module .\src\CISBenchmark.psm1 -Force
$config = Initialize-CISEnvironment -ProjectRoot $PWD -SkipPrereqCheck

# Run just one module
$results = Test-CISFirewall
$results | Where-Object { $_.Status -eq 'Fail' } | Format-Table Id, Title, Expected, Actual
```

### Check What a GPO Contains

```powershell
# List all registry values in a GPO
Get-GPRegistryValue -Name 'CIS-L1-AdminTemplates' -Key 'HKLM\SOFTWARE\Policies' -ErrorAction SilentlyContinue

# Full GPO report
Get-GPOReport -Name 'CIS-L1-AdminTemplates' -ReportType HTML -Path .\gpo-report.html
```
