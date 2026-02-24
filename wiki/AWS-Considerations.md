# AWS Considerations

This project is specifically designed for Windows Server 2025 instances running in AWS with **AWS Managed Microsoft AD**. This page documents the constraints, exclusions, and safety measures unique to the AWS environment.

---

## AWS Managed Microsoft AD Constraints

### Domain Controllers Are Off-Limits

AWS owns and manages the Domain Controllers for AWS Managed AD. You cannot:

- Log into DCs directly
- Apply GPOs to the Domain Controllers OU
- Modify the Default Domain Policy
- Run scripts or install software on DCs

**Impact:** All GPOs created by this tool are linked to a **delegated OU** that you control, never to the domain root or DC OU.

### Domain Password/Lockout Policy

AWS controls the domain-level password and lockout policies (CIS Section 1). These settings are managed through the **AWS Directory Service console**, not via GPO.

**Impact:**
- The `AccountPolicies` module is **disabled by default**
- `Set-CISAccountPolicies` is a no-op that logs a warning
- You can still audit with `Test-CISAccountPolicies` to see current values

### To Manage Password Policy in AWS

1. AWS Console → Directory Service → select your directory
2. Click **Networking & security** → **Password policy**
3. Create or modify a password policy that meets CIS requirements:
   - Password history: 24+
   - Maximum age: 365 days or fewer
   - Minimum age: 1+ days
   - Minimum length: 14+ characters
   - Complexity: Enabled

---

## Services That Must Stay Running

AWS EC2 management relies on several Windows services. These are excluded from the Services module:

| CIS Control | Service | Why It Must Stay |
|---|---|---|
| 5.20 | SessionEnv | Remote Desktop Configuration — required for RDP |
| 5.21 | TermService | Remote Desktop Services — primary management access |
| 5.22 | UmRdpService | RDP UserMode Port Redirector — required for RDP |
| 5.39 | WinRM | Windows Remote Management — required for SSM Agent, PowerShell remoting |

### What Happens If These Are Disabled

- **RDP disabled:** You lose console access to the instance. Recovery requires stopping the instance, detaching the root volume, mounting it on another instance, and editing the registry.
- **WinRM disabled:** SSM Agent loses its management channel. AWS Systems Manager can no longer run commands, collect inventory, or manage the instance. SSM Session Manager also stops working.

---

## SSM Agent Compatibility

The AWS Systems Manager (SSM) Agent runs as **SYSTEM** (LocalSystem) and requires:

1. **Network access:** SSM Agent makes HTTPS calls to SSM endpoints. CIS controls that deny SYSTEM network access break SSM.
2. **Service logon:** SSM Agent must be able to run as a service.
3. **WinRM:** SSM uses WinRM as a transport for Run Command and other features.

### Modified Controls for SSM

| Control | CIS Recommendation | AWS Modification | Reason |
|---|---|---|---|
| 2.2.17 | Deny network access: Guests, Local account & admin | Deny: Guests only | SYSTEM must retain network access for SSM |
| 2.2.38 | Log on as a service: not defined | LOCAL SERVICE, NETWORK SERVICE | SYSTEM implicitly has this; ensure it's not restricted |

### Verifying SSM Agent After Apply

```powershell
# Check SSM Agent service
Get-Service AmazonSSMAgent

# Verify SSM connectivity (from the instance)
$ssm = Get-CimInstance -ClassName Win32_Service -Filter "Name='AmazonSSMAgent'"
$ssm | Format-List Name, State, StartMode, PathName

# Check in AWS console
# Systems Manager → Fleet Manager → verify instance appears as "Online"
```

---

## RDP Hardening (Applied, Not Disabled)

CIS Section 18.9.35 contains Remote Desktop controls. This project applies the **hardening** settings but never disables RDP:

| Control | Setting | Value | Purpose |
|---|---|---|---|
| 18.9.35.3.9.1 | Always prompt for password | Enabled | Prevent cached credential reuse |
| 18.9.35.3.9.3 | Security layer | SSL/TLS (2) | Encrypt RDP at transport level |
| 18.9.35.3.9.4 | NLA required | Enabled | Network Level Authentication |
| 18.9.35.3.9.5 | Encryption level | High (3) | 128-bit encryption |
| 18.9.35.3.10.1 | Idle session timeout | 15 min (900000 ms) | Disconnect idle sessions |
| 18.9.35.3.10.2 | Disconnected session timeout | 1 min (60000 ms) | Clean up disconnected sessions |
| 18.9.35.3.3.1–4 | Disable COM/drive/LPT/PnP redirection | Enabled | Reduce attack surface |

### What Is NOT Done
- RDP (TermService) is never disabled
- RDP port is not changed (stays 3389)
- The "Deny log on through RDP" right does not include Administrators

---

## WinRM Hardening (Applied, Not Disabled)

CIS Section 18.9.58 contains WinRM controls. Hardening is applied but WinRM stays functional:

| Control | Setting | Value | Purpose |
|---|---|---|---|
| 18.9.58.1 | Client: Allow Basic auth | Disabled | No plaintext credentials |
| 18.9.58.2 | Client: Allow unencrypted traffic | Disabled | Force encryption |
| 18.9.58.3 | Client: Disallow Digest auth | Disabled | Remove weak auth |
| 18.9.58.5 | Service: Allow Basic auth | Disabled | No plaintext credentials |
| 18.9.58.6 | Service: Allow remote management | **Enabled** | **Must stay enabled** |
| 18.9.58.7 | Service: Allow unencrypted traffic | Disabled | Force encryption |
| 18.9.58.8 | Service: Disallow RunAs credentials | Enabled | Don't store RunAs creds |

### What Is NOT Done
- WinRM service is never disabled or stopped
- `AllowAutoConfig` is explicitly set to `1` (enabled)
- WinRM listeners are not removed

---

## Pre/Post-Flight Connectivity Checks

`Test-AWSConnectivity` validates management channels before and after changes:

| Check | Method | Failure = Halt? |
|---|---|---|
| WinRM service | `Get-Service WinRM` | Yes |
| WinRM listener | `Get-WSManInstance` | Warning only |
| SSM Agent | `Get-Service AmazonSSMAgent` | Warning (may not be EC2) |
| RDP service | `Get-Service TermService` | Yes |
| RDP port | Registry check | Warning only |
| Firewall rules | Management allow rules count | Warning only |

### If Post-Flight Fails

The apply script:
1. Logs a prominent error banner
2. Prints the backup path
3. Recommends running `Invoke-CISRollback.ps1`
4. Exits with code 1

**You still have management access at this point** — the GPO settings haven't been applied to the machine yet (they're in the GPO, awaiting `gpupdate`). If you need to prevent application:

```powershell
# Emergency: unlink all CIS GPOs immediately
Get-GPO -All | Where-Object { $_.DisplayName -match '^CIS-L1-' } | ForEach-Object {
    Remove-GPLink -Name $_.DisplayName -Target $TargetOU -ErrorAction SilentlyContinue
}
```

---

## EC2-Specific Notes

### Instance Metadata
The tools don't access EC2 instance metadata (169.254.169.254). No IAM role permissions are required beyond standard AD operations.

### Security Groups
Ensure your EC2 security group allows:
- **Inbound:** RDP (TCP 3389), WinRM (TCP 5985/5986) from management networks
- **Outbound:** HTTPS (TCP 443) to SSM endpoints, DNS/LDAP/Kerberos to AD

### AMI Baseline
AWS Windows Server 2025 AMIs ship with certain CIS controls already compliant. Run an audit first to see your baseline compliance before applying any changes.
