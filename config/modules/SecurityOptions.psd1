@{
    # ─────────────────────────────────────────────────────────────────────────────
    # CIS Section 2.3 — Security Options
    # Mechanism: Registry-based + secedit for some policies
    # ─────────────────────────────────────────────────────────────────────────────

    ModuleName  = 'SecurityOptions'
    CISSection  = '2.3'
    Mechanism   = 'Registry'

    Controls = @(
        # ── 2.3.1 Accounts ──
        @{
            Id          = '2.3.1.1'
            Title       = 'Accounts: Block Microsoft accounts'
            Description = 'Users cant add or log on with Microsoft accounts'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'NoConnectedUser'
                Type  = 'DWord'
                Value = 3
            }
        }
        @{
            Id          = '2.3.1.2'
            Title       = 'Accounts: Guest account status'
            Description = 'Guest account is disabled'
            Secedit     = @{
                Key   = 'EnableGuestAccount'
                Value = '0'
            }
        }
        @{
            Id          = '2.3.1.3'
            Title       = 'Accounts: Limit local account use of blank passwords to console logon only'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'LimitBlankPasswordUse'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.1.4'
            Title       = 'Accounts: Rename administrator account'
            Description = 'The built-in Administrator account should be renamed'
            Secedit     = @{
                Key       = 'NewAdministratorName'
                NotValue  = '"Administrator"'
            }
        }
        @{
            Id          = '2.3.1.5'
            Title       = 'Accounts: Rename guest account'
            Secedit     = @{
                Key       = 'NewGuestName'
                NotValue  = '"Guest"'
            }
        }

        # ── 2.3.2 Audit ──
        @{
            Id          = '2.3.2.1'
            Title       = 'Audit: Force audit policy subcategory settings to override audit policy category settings'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'SCENoApplyLegacyAuditPolicy'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.2.2'
            Title       = 'Audit: Shut down system immediately if unable to log security audits'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'CrashOnAuditFail'
                Type  = 'DWord'
                Value = 0
            }
        }

        # ── 2.3.4 Devices ──
        @{
            Id          = '2.3.4.1'
            Title       = 'Devices: Allowed to format and eject removable media'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                Name  = 'AllocateDASD'
                Type  = 'String'
                Value = '0'
            }
        }

        # ── 2.3.6 Domain member ──
        @{
            Id          = '2.3.6.1'
            Title       = 'Domain member: Digitally encrypt or sign secure channel data (always)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                Name  = 'RequireSignOrSeal'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.6.2'
            Title       = 'Domain member: Digitally encrypt secure channel data (when possible)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                Name  = 'SealSecureChannel'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.6.3'
            Title       = 'Domain member: Digitally sign secure channel data (when possible)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                Name  = 'SignSecureChannel'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.6.4'
            Title       = 'Domain member: Disable machine account password changes'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                Name  = 'DisablePasswordChange'
                Type  = 'DWord'
                Value = 0
            }
        }
        @{
            Id          = '2.3.6.5'
            Title       = 'Domain member: Maximum machine account password age'
            Description = 'Set to 30 days or fewer'
            Registry    = @{
                Path      = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                Name      = 'MaximumPasswordAge'
                Type      = 'DWord'
                Value     = 30
                Operator  = 'LessOrEqual'
            }
        }
        @{
            Id          = '2.3.6.6'
            Title       = 'Domain member: Require strong (Windows 2000 or later) session key'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                Name  = 'RequireStrongKey'
                Type  = 'DWord'
                Value = 1
            }
        }

        # ── 2.3.7 Interactive logon ──
        @{
            Id          = '2.3.7.1'
            Title       = 'Interactive logon: Do not require CTRL+ALT+DEL'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'DisableCAD'
                Type  = 'DWord'
                Value = 0
            }
        }
        @{
            Id          = '2.3.7.2'
            Title       = 'Interactive logon: Do not display last signed-in'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'DontDisplayLastUserName'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.7.3'
            Title       = 'Interactive logon: Machine inactivity limit'
            Description = 'Set to 900 seconds or fewer, but not 0'
            Registry    = @{
                Path     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name     = 'InactivityTimeoutSecs'
                Type     = 'DWord'
                Value    = 900
                Operator = 'LessOrEqual'
                MinValue = 1
            }
        }
        @{
            Id          = '2.3.7.4'
            Title       = 'Interactive logon: Message text for users attempting to log on'
            Description = 'Configure a logon banner message'
            Registry    = @{
                Path     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name     = 'LegalNoticeText'
                Value    = 'This system is for authorized use only. By using this system, you consent to monitoring and agree to comply with all applicable policies. Unauthorized access is prohibited and may result in disciplinary action or prosecution.'
                Type     = 'String'
                Operator = 'NotEmpty'
            }
        }
        @{
            Id          = '2.3.7.5'
            Title       = 'Interactive logon: Message title for users attempting to log on'
            Registry    = @{
                Path     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name     = 'LegalNoticeCaption'
                Value    = 'NOTICE: Authorized Use Only'
                Type     = 'String'
                Operator = 'NotEmpty'
            }
        }
        @{
            Id          = '2.3.7.7'
            Title       = 'Interactive logon: Prompt user to change password before expiration'
            Description = 'Set to 5 to 14 days'
            Registry    = @{
                Path     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                Name     = 'PasswordExpiryWarning'
                Type     = 'DWord'
                Value    = 14
                Operator = 'Range'
                MinValue = 5
                MaxValue = 14
            }
        }
        @{
            Id          = '2.3.7.8'
            Title       = 'Interactive logon: Smart card removal behavior'
            Description = 'Set to Lock Workstation or higher'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                Name  = 'ScRemoveOption'
                Type  = 'String'
                Value = '1'
            }
        }

        # ── 2.3.8 Microsoft network client ──
        @{
            Id          = '2.3.8.1'
            Title       = 'Microsoft network client: Digitally sign communications (always)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
                Name  = 'RequireSecuritySignature'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.8.2'
            Title       = 'Microsoft network client: Digitally sign communications (if server agrees)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
                Name  = 'EnableSecuritySignature'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.8.3'
            Title       = 'Microsoft network client: Send unencrypted password to third-party SMB servers'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
                Name  = 'EnablePlainTextPassword'
                Type  = 'DWord'
                Value = 0
            }
        }

        # ── 2.3.9 Microsoft network server ──
        @{
            Id          = '2.3.9.1'
            Title       = 'Microsoft network server: Amount of idle time required before suspending session'
            Description = '15 minutes or fewer'
            Registry    = @{
                Path     = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name     = 'AutoDisconnect'
                Type     = 'DWord'
                Value    = 15
                Operator = 'LessOrEqual'
            }
        }
        @{
            Id          = '2.3.9.2'
            Title       = 'Microsoft network server: Digitally sign communications (always)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name  = 'RequireSecuritySignature'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.9.3'
            Title       = 'Microsoft network server: Digitally sign communications (if client agrees)'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name  = 'EnableSecuritySignature'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.9.4'
            Title       = 'Microsoft network server: Disconnect clients when logon hours expire'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name  = 'EnableForcedLogOff'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.9.5'
            Title       = 'Microsoft network server: Server SPN target name validation level'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name  = 'SMBServerNameHardeningLevel'
                Type  = 'DWord'
                Value = 1
            }
        }

        # ── 2.3.10 Network access ──
        @{
            Id          = '2.3.10.1'
            Title       = 'Network access: Allow anonymous SID/Name translation'
            Secedit     = @{
                Key   = 'LSAAnonymousNameLookup'
                Value = '0'
            }
        }
        @{
            Id          = '2.3.10.2'
            Title       = 'Network access: Do not allow anonymous enumeration of SAM accounts'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'RestrictAnonymousSAM'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.10.3'
            Title       = 'Network access: Do not allow anonymous enumeration of SAM accounts and shares'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'RestrictAnonymous'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.10.4'
            Title       = 'Network access: Do not allow storage of passwords and credentials for network authentication'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'DisableDomainCreds'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.10.5'
            Title       = 'Network access: Let Everyone permissions apply to anonymous users'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'EveryoneIncludesAnonymous'
                Type  = 'DWord'
                Value = 0
            }
        }
        @{
            Id          = '2.3.10.7'
            Title       = 'Network access: Named Pipes that can be accessed anonymously'
            Description = 'Set to None (empty)'
            Registry    = @{
                Path     = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name     = 'NullSessionPipes'
                Type     = 'MultiString'
                Value    = @()
                Operator = 'Empty'
            }
        }
        @{
            Id          = '2.3.10.8'
            Title       = 'Network access: Remotely accessible registry paths'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedExactPaths'
                Name  = 'Machine'
                Type  = 'MultiString'
                Value = @(
                    'System\CurrentControlSet\Control\ProductOptions'
                    'System\CurrentControlSet\Control\Server Applications'
                    'Software\Microsoft\Windows NT\CurrentVersion'
                )
            }
        }
        @{
            Id          = '2.3.10.10'
            Title       = 'Network access: Restrict anonymous access to Named Pipes and Shares'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name  = 'RestrictNullSessAccess'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.10.11'
            Title       = 'Network access: Restrict clients allowed to make remote calls to SAM'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'RestrictRemoteSAM'
                Type  = 'String'
                Value = 'O:BAG:BAD:(A;;RC;;;BA)'
            }
        }
        @{
            Id          = '2.3.10.12'
            Title       = 'Network access: Shares that can be accessed anonymously'
            Description = 'Set to None (empty)'
            Registry    = @{
                Path     = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters'
                Name     = 'NullSessionShares'
                Type     = 'MultiString'
                Value    = @()
                Operator = 'Empty'
            }
        }
        @{
            Id          = '2.3.10.13'
            Title       = 'Network access: Sharing and security model for local accounts'
            Description = 'Classic - local users authenticate as themselves'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'ForceGuest'
                Type  = 'DWord'
                Value = 0
            }
        }

        # ── 2.3.11 Network security ──
        @{
            Id          = '2.3.11.1'
            Title       = 'Network security: Allow Local System to use computer identity for NTLM'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'UseMachineId'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.11.2'
            Title       = 'Network security: Allow LocalSystem NULL session fallback'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
                Name  = 'AllowNullSessionFallback'
                Type  = 'DWord'
                Value = 0
            }
        }
        @{
            Id          = '2.3.11.3'
            Title       = 'Network security: Allow PKU2U authentication requests to use online identities'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\pku2u'
                Name  = 'AllowOnlineID'
                Type  = 'DWord'
                Value = 0
            }
        }
        @{
            Id          = '2.3.11.4'
            Title       = 'Network security: Configure encryption types allowed for Kerberos'
            Description = 'AES128_HMAC_SHA1 + AES256_HMAC_SHA1 + Future types = 2147483640'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters'
                Name  = 'SupportedEncryptionTypes'
                Type  = 'DWord'
                Value = 2147483640
            }
        }
        @{
            Id          = '2.3.11.5'
            Title       = 'Network security: Do not store LAN Manager hash value on next password change'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'NoLMHash'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.11.7'
            Title       = 'Network security: LAN Manager authentication level'
            Description = 'Send NTLMv2 response only. Refuse LM & NTLM'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'LmCompatibilityLevel'
                Type  = 'DWord'
                Value = 5
            }
        }
        @{
            Id          = '2.3.11.8'
            Title       = 'Network security: LDAP client signing requirements'
            Description = 'Negotiate signing'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                Name  = 'LDAPClientIntegrity'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.11.9'
            Title       = 'Network security: Minimum session security for NTLM SSP based clients'
            Description = 'Require NTLMv2 session security, Require 128-bit encryption = 537395200'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
                Name  = 'NTLMMinClientSec'
                Type  = 'DWord'
                Value = 537395200
            }
        }
        @{
            Id          = '2.3.11.10'
            Title       = 'Network security: Minimum session security for NTLM SSP based servers'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
                Name  = 'NTLMMinServerSec'
                Type  = 'DWord'
                Value = 537395200
            }
        }

        # ── 2.3.13 Shutdown ──
        @{
            Id          = '2.3.13.1'
            Title       = 'Shutdown: Allow system to be shut down without having to log on'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'ShutdownWithoutLogon'
                Type  = 'DWord'
                Value = 0
            }
        }

        # ── 2.3.15 System objects ──
        @{
            Id          = '2.3.15.1'
            Title       = 'System objects: Require case insensitivity for non-Windows subsystems'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel'
                Name  = 'ObCaseInsensitive'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.15.2'
            Title       = 'System objects: Strengthen default permissions of internal system objects'
            Registry    = @{
                Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
                Name  = 'ProtectionMode'
                Type  = 'DWord'
                Value = 1
            }
        }

        # ── 2.3.17 User Account Control ──
        @{
            Id          = '2.3.17.1'
            Title       = 'UAC: Admin Approval Mode for the Built-in Administrator account'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'FilterAdministratorToken'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.17.2'
            Title       = 'UAC: Behavior of the elevation prompt for administrators in Admin Approval Mode'
            Description = 'Prompt for consent on the secure desktop (2)'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'ConsentPromptBehaviorAdmin'
                Type  = 'DWord'
                Value = 2
            }
        }
        @{
            Id          = '2.3.17.3'
            Title       = 'UAC: Behavior of the elevation prompt for standard users'
            Description = 'Automatically deny elevation requests (0)'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'ConsentPromptBehaviorUser'
                Type  = 'DWord'
                Value = 0
            }
        }
        @{
            Id          = '2.3.17.4'
            Title       = 'UAC: Detect application installations and prompt for elevation'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'EnableInstallerDetection'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.17.5'
            Title       = 'UAC: Only elevate UIAccess applications that are installed in secure locations'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'EnableSecureUIAPaths'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.17.6'
            Title       = 'UAC: Run all administrators in Admin Approval Mode'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'EnableLUA'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.17.7'
            Title       = 'UAC: Switch to the secure desktop when prompting for elevation'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'PromptOnSecureDesktop'
                Type  = 'DWord'
                Value = 1
            }
        }
        @{
            Id          = '2.3.17.8'
            Title       = 'UAC: Virtualize file and registry write failures to per-user locations'
            Registry    = @{
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Name  = 'EnableVirtualization'
                Type  = 'DWord'
                Value = 1
            }
        }
    )
}
