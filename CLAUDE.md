# CLAUDE.md

## Project Overview
CIS Benchmark L1 automation for Windows Server 2025. PowerShell-based, modular architecture with 339 controls across 8 modules. Supports domain-joined (GPO) and standalone (local policy) modes.

## Repository Structure
```
config/                    # .psd1 data files (no code execution)
  master-config.psd1       # Main settings: TargetOU, DryRun, module enable/disable
  aws-exclusions.psd1      # Controls skipped/modified for AWS compatibility
  modules/                 # Per-module control definitions
scripts/                   # Entry points (user-facing)
  Install-Prerequisites.ps1
  Invoke-CISAudit.ps1
  Invoke-CISApply.ps1
  Invoke-CISRollback.ps1
src/
  CISBenchmark.psm1        # Module manifest
  Core/                    # Shared: Get-CISConfiguration, logging, backup, connectivity
  Modules/<Name>/          # Test-CIS<Name>.ps1 (audit) + Set-CIS<Name>.ps1 (apply)
tests/                     # Pester tests
wiki/                      # Documentation (synced to GitHub wiki separately)
```

## Key Conventions

### Interactive Prompts
- All entry-point scripts prompt interactively by default (Read-Host)
- `-Force` skips ALL prompts; CLI params skip their corresponding prompt
- Prompt format: `  ? Question text? [D/l]:` — uppercase letter is the default
- IIS exclusion (`-SkipIIS`) is dynamic/opt-in, not in aws-exclusions.psd1

### Config Files
- `.psd1` format (PowerShell data files) — safe, no code execution
- Loaded via `Import-PowerShellDataFile`
- Controls defined as arrays of hashtables with Id, Title, and type-specific fields

### Exclusion Mechanism
- `aws-exclusions.psd1` → `Skip` array + `Modify` hashtable
- `Get-CISConfiguration` sets `$ctl.Skipped = $true` / `$ctl.SkipReason` at load time
- All Test-/Set- functions check `$ctl.Skipped` before processing

### Apply Modes
- **DryRun** (default): logs what would change, no modifications
- **Live**: creates backups first, then applies via GPO (domain) or local policy (standalone)
- Post-apply audit only runs in live mode

### Module Pattern
Each CIS section follows the same pattern:
- Config: `config/modules/<Name>.psd1` — control definitions
- Audit: `src/Modules/<Name>/Test-CIS<Name>.ps1` — returns PSCustomObject array (Id, Title, Status, Expected, Actual, Detail)
- Apply: `src/Modules/<Name>/Set-CIS<Name>.ps1` — accepts `-GpoName`, `-DryRun`, optionally `-LocalPolicy`

## Testing
```powershell
Invoke-Pester ./tests/
```

## Wiki Sync
The `wiki/` folder is the source of truth. To sync to GitHub wiki:
```bash
git clone https://github.com/pacmano1/security-benchmarks.wiki.git /tmp/wiki
cp wiki/*.md /tmp/wiki/
cd /tmp/wiki && git add -A && git commit -m "sync" && git push
```
