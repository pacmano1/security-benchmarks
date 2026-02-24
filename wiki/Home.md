# CIS Benchmark L1 Automation — Windows Server 2025

Automated audit, enforcement, and rollback of **CIS Microsoft Windows Server 2025 Benchmark v1.0.0** (Level 1, Member Server profile) for machines joined to **AWS Managed Microsoft AD**.

---

## What This Does

| Capability | Description |
|---|---|
| **Audit** | Scans a Windows Server 2025 machine against 339 CIS L1 controls and generates HTML + JSON compliance reports |
| **Apply** | Creates one Group Policy Object per CIS section, links them to your delegated OU, and populates settings |
| **Rollback** | Restores GPOs to pre-apply state or removes them entirely |

## Key Safety Features

- **DryRun = $true by default** — nothing changes until you explicitly opt in
- **Pre/post-flight connectivity checks** — validates WinRM, SSM Agent, and RDP before and after changes
- **AWS exclusions** — never disables RDP, WinRM, or SSM; never touches domain password policy
- **One GPO per module** — unlink a single GPO to disable an entire category instantly
- **Full state backup** before every apply operation

## Quick Start

```powershell
# 1. Install prerequisites (run as Administrator on the target server)
.\scripts\Install-Prerequisites.ps1

# 2. Edit config to match your environment
notepad .\config\master-config.psd1    # Set TargetOU, GpoPrefix, enable/disable modules

# 3. Audit current compliance (safe — read-only)
.\scripts\Invoke-CISAudit.ps1

# 4. Review the HTML report in reports/

# 5. When ready to apply (set DryRun = $false in master-config.psd1 first)
.\scripts\Invoke-CISApply.ps1

# 6. If something goes wrong
.\scripts\Invoke-CISRollback.ps1
```

## Wiki Pages

| Page | Description |
|---|---|
| [Architecture](Architecture.md) | Project structure, design decisions, data flow |
| [Configuration](Configuration.md) | Master config, module configs, AWS exclusions |
| [Modules](Modules.md) | Detailed breakdown of all 8 CIS modules and their controls |
| [Audit Guide](Usage-Audit.md) | Running audits, reading reports, filtering by module |
| [Apply Guide](Usage-Apply.md) | Creating GPOs, applying settings, apply order |
| [Rollback Guide](Usage-Rollback.md) | Restoring from backup, removing GPOs |
| [AWS Considerations](AWS-Considerations.md) | AWS Managed AD constraints, excluded controls, SSM safety |
| [Adding Controls](Adding-Controls.md) | How to add new CIS controls or create new modules |
| [Troubleshooting](Troubleshooting.md) | Common issues and solutions |

## Requirements

- Windows Server 2025 (EC2 instance)
- PowerShell 5.1+
- RSAT: Active Directory + Group Policy (installed via `Install-Prerequisites.ps1`)
- Domain-joined to AWS Managed Microsoft AD
- Delegated OU with GPO creation/link permissions
- Pester 5.x (for tests)

## Control Coverage

| Module | CIS Section | Controls | Mechanism |
|---|---|---|---|
| AccountPolicies | 1 | 11 | secedit (audit-only) |
| UserRightsAssignment | 2.2 | 37 | secedit / GptTmpl.inf |
| SecurityOptions | 2.3 | 60 | Registry + secedit |
| Services | 5 | 38 | Service startup type |
| Firewall | 9 | 26 | Registry |
| AuditPolicy | 17 | 30 | auditpol / audit.csv |
| AdminTemplates | 18 | 128 | Registry |
| AdminTemplatesUser | 19 | 9 | Registry (HKCU) |
| **Total** | | **339** | |
