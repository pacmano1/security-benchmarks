# CIS Modules

Each CIS benchmark section is implemented as an independent module with its own configuration, audit function (`Test-CIS*`), and apply function (`Set-CIS*`).

---

## Module Summary

| Module | CIS Section | Controls | Mechanism | Default |
|---|---|---|---|---|
| [AccountPolicies](#accountpolicies) | 1 | 11 | secedit | **Disabled** |
| [UserRightsAssignment](#userrightsassignment) | 2.2 | 37 | secedit / GptTmpl.inf | Enabled |
| [SecurityOptions](#securityoptions) | 2.3 | 60 | Registry + secedit | Enabled |
| [Services](#services) | 5 | 38 | Service startup type | Enabled |
| [Firewall](#firewall) | 9 | 26 | Registry | Enabled |
| [AuditPolicy](#auditpolicy) | 17 | 30 | auditpol / audit.csv | Enabled |
| [AdminTemplates](#admintemplates) | 18 | 128 | Registry | Enabled |
| [AdminTemplatesUser](#admintemplatesuser) | 19 | 9 | Registry (HKCU) | Enabled |

---

## AccountPolicies

**CIS Section 1 — Password Policy & Account Lockout Policy**

> **Disabled by default.** AWS Managed Microsoft AD controls the domain-level password and lockout policies. These cannot be overridden by member server GPO. Use the AWS Directory Service console to manage these settings.

### What It Covers
- 1.1.x — Password history, max/min age, length, complexity, reversible encryption
- 1.2.x — Lockout duration, threshold, counter reset, administrator lockout

### Audit Behavior
Even when disabled in master-config, you can audit this module explicitly to see current domain policy values:

```powershell
.\scripts\Invoke-CISAudit.ps1 -Modules AccountPolicies
```

### Apply Behavior
`Set-CISAccountPolicies` is a no-op — it logs a warning directing you to the AWS console.

### Files
- Config: `config/modules/AccountPolicies.psd1`
- Audit: `src/Modules/AccountPolicies/Test-CISAccountPolicies.ps1`
- Apply: `src/Modules/AccountPolicies/Set-CISAccountPolicies.ps1`

---

## UserRightsAssignment

**CIS Section 2.2 — Local Policies: User Rights Assignment**

Defines which accounts/groups are granted specific privileges (e.g., "Allow log on locally", "Debug programs", "Shut down the system").

### What It Covers
- 37 privilege assignments including:
  - Network access, local/remote logon, service logon
  - Deny rights (network, batch, service, interactive, RDP)
  - Administrative privileges (backup, restore, take ownership, debug)

### Mechanism
- **Audit:** Exports security policy via `secedit /export /cfg`, parses the `[Privilege Rights]` section
- **Apply:** Writes privilege entries into `GptTmpl.inf` on the GPO's SYSVOL path

### AWS Considerations
- **2.2.17** (Deny network access): Modified to not deny SYSTEM/NETWORK SERVICE — SSM Agent runs as SYSTEM
- **2.2.38** (Replace process level token): Ensures SYSTEM retains this right

### Files
- Config: `config/modules/UserRightsAssignment.psd1`
- Audit: `src/Modules/UserRightsAssignment/Test-CISUserRightsAssignment.ps1`
- Apply: `src/Modules/UserRightsAssignment/Set-CISUserRightsAssignment.ps1`

---

## SecurityOptions

**CIS Section 2.3 — Local Policies: Security Options**

The broadest security-options section covering accounts, audit, devices, domain membership, interactive logon, network clients/servers, UAC, and more.

### What It Covers (60 controls)
- **2.3.1** Accounts — Block Microsoft accounts, disable guest, rename admin/guest, blank password policy
- **2.3.2** Audit — Force subcategory overrides, audit failure behavior
- **2.3.4** Devices — Removable media formatting
- **2.3.6** Domain member — Secure channel encryption/signing, machine password age
- **2.3.7** Interactive logon — CTRL+ALT+DEL, inactivity timeout, legal notice, smart card removal
- **2.3.8–9** Network client/server — SMB signing, unencrypted passwords, idle timeout
- **2.3.10** Network access — Anonymous enumeration, named pipes, SAM restrictions
- **2.3.11** Network security — NTLM settings, Kerberos encryption, LAN Manager level
- **2.3.13** Shutdown — Require logon before shutdown
- **2.3.15** System objects — Case insensitivity, default permissions
- **2.3.17** UAC — Admin Approval Mode, elevation prompts, secure desktop

### Mechanism
- **Registry-based controls** (majority): `Get-ItemProperty` for audit, `Set-GPRegistryValue` for apply
- **Secedit-based controls** (5 controls): `secedit /export` for audit, `GptTmpl.inf` for apply

### Files
- Config: `config/modules/SecurityOptions.psd1`
- Audit: `src/Modules/SecurityOptions/Test-CISSecurityOptions.ps1`
- Apply: `src/Modules/SecurityOptions/Set-CISSecurityOptions.ps1`

---

## Services

**CIS Section 5 — System Services**

Ensures unnecessary services are disabled to reduce attack surface.

### What It Covers (38 controls)
Services that should be disabled on a hardened member server:
- Bluetooth, geolocation, infrared, mobile hotspot
- IIS, FTP, Web Management, OpenSSH Server
- Print Spooler, Remote Registry, SNMP
- Xbox services, Windows Media Player networking
- Peer networking, UPnP, SSDP Discovery
- And more

### AWS-Excluded Services
These services are **never disabled** (excluded in `aws-exclusions.psd1`):
- **5.20–5.22:** Remote Desktop services (SessionEnv, TermService, UmRdpService)
- **5.39:** Windows Remote Management (WinRM)

### Mechanism
- **Audit:** `Get-Service` to check existence + `Win32_Service` WMI to check StartMode
- **Apply:** `Set-GPRegistryValue` on `HKLM\SYSTEM\CurrentControlSet\Services\<name>\Start`
- If a service is not installed, it counts as compliant for "Disabled" requirements

### Files
- Config: `config/modules/Services.psd1`
- Audit: `src/Modules/Services/Test-CISServices.ps1`
- Apply: `src/Modules/Services/Set-CISServices.ps1`

---

## Firewall

**CIS Section 9 — Windows Defender Firewall with Advanced Security**

Configures firewall profiles (Domain, Private, Public) for proper security posture.

### What It Covers (26 controls)
For each of the three profiles (Domain, Private, Public):
- Firewall state (on)
- Default inbound action (block)
- Default outbound action (allow)
- Notification settings
- Logging: file path, size limit, log dropped packets, log successful connections

Public profile additionally:
- Disable local firewall rule merge
- Disable local IPsec rule merge

### Mechanism
All registry-based under `HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\`:
- **Audit:** `Get-ItemProperty`
- **Apply:** `Set-GPRegistryValue`

### Files
- Config: `config/modules/Firewall.psd1`
- Audit: `src/Modules/Firewall/Test-CISFirewall.ps1`
- Apply: `src/Modules/Firewall/Set-CISFirewall.ps1`

---

## AuditPolicy

**CIS Section 17 — Advanced Audit Policy Configuration**

Configures Windows audit subcategories to ensure proper event logging.

### What It Covers (30 controls)
- **17.1** Account Logon — Credential Validation
- **17.2** Account Management — Application/Computer/Distribution/Security Group, User Account
- **17.3** Detailed Tracking — PNP Activity, Process Creation
- **17.5** Logon/Logoff — Account Lockout, Group Membership, Logon/Logoff, Special Logon
- **17.6** Object Access — File Share, Removable Storage, Other
- **17.7** Policy Change — Audit/Authentication/Authorization Policy, MPSSVC Rule-Level
- **17.8** Privilege Use — Sensitive Privilege Use
- **17.9** System — IPsec Driver, Security State/System Extension/Integrity, Other System

### Mechanism
- **Audit:** `auditpol.exe /get /category:* /r` → CSV output → parsed by subcategory name
- **Apply:** Writes `audit.csv` to `{GPO}\Machine\Microsoft\Windows NT\Audit\`
- Updates `gPCMachineExtensionNames` AD attribute with the audit policy CSE GUID

### Compliance Logic
- "Success and Failure" in actual satisfies any requirement
- "Include Success" passes if actual contains "Success"
- "Include Failure" passes if actual contains "Failure"

### Files
- Config: `config/modules/AuditPolicy.psd1`
- Audit: `src/Modules/AuditPolicy/Test-CISAuditPolicy.ps1`
- Apply: `src/Modules/AuditPolicy/Set-CISAuditPolicy.ps1`

---

## AdminTemplates

**CIS Section 18 — Administrative Templates (Computer Configuration)**

The largest module — 128 controls covering Windows component policies applied via registry.

### What It Covers
- **18.1** Control Panel — Lock screen camera/slideshow, speech recognition
- **18.3** MS Security Guide — UAC on network, SMBv1 disable, SEHOP, WDigest
- **18.4** MSS (Legacy) — Auto logon, IP source routing, ICMP redirects, Safe DLL search
- **18.5** Network — DNS DoH, LLMNR, insecure guest logons, hardened UNC, network bridge
- **18.6** Printers — Redirection guard, RPC settings, driver installation restrictions
- **18.8** System — Process command line auditing, credential delegation, Device Guard/VBS, Early Launch AM, Group Policy processing, logon UI settings, RPC restrictions
- **18.9** Windows Components:
  - App runtime, AutoPlay, BitLocker
  - Cloud Content, Connect, Credential UI
  - Data Collection/Telemetry, Event Log sizes
  - File Explorer, Remote Desktop hardening
  - RSS Feeds, Search/Cortana
  - WinRM Client/Service hardening, Remote Shell
  - Windows Defender/Antivirus, PowerShell logging
  - Windows Update configuration

### AWS Considerations
- **RDP controls (18.9.35.x):** Hardening is applied (NLA, encryption, session timeouts) but RDP is never disabled
- **WinRM controls (18.9.58.x):** Basic auth disabled, unencrypted traffic blocked, but WinRM service stays enabled with `AllowAutoConfig = 1`

### Mechanism
All registry-based:
- **Audit:** `Get-ItemProperty` for each control's registry path
- **Apply:** `Set-GPRegistryValue` to write each setting into the GPO

### Files
- Config: `config/modules/AdminTemplates.psd1`
- Audit: `src/Modules/AdminTemplates/Test-CISAdminTemplates.ps1`
- Apply: `src/Modules/AdminTemplates/Set-CISAdminTemplates.ps1`

---

## AdminTemplatesUser

**CIS Section 19 — Administrative Templates (User Configuration)**

User-level policies applied via the GPO's User Configuration section.

### What It Covers (9 controls)
- **19.1.3** Screen saver — Enable, password protect, timeout (900s)
- **19.5.1** Notifications — Disable toast on lock screen
- **19.6.6** Internet Communication — Disable Help Experience Improvement
- **19.7.4** Attachment Manager — Preserve zone info, antivirus scan
- **19.7.8** Cloud Content — Windows Spotlight, third-party suggestions

### Mechanism
- **Audit:** `Get-ItemProperty` on HKCU paths (reflects current user's applied policy)
- **Apply:** `Set-GPRegistryValue` with HKCU paths (written to GPO's User Configuration)

### Note
HKCU-based auditing reflects the currently logged-on user's policy. For GPO-level verification, inspect the GPO directly via GPMC or use `Get-GPRegistryValue`.

### Files
- Config: `config/modules/AdminTemplatesUser.psd1`
- Audit: `src/Modules/AdminTemplatesUser/Test-CISAdminTemplatesUser.ps1`
- Apply: `src/Modules/AdminTemplatesUser/Set-CISAdminTemplatesUser.ps1`
