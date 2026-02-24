@{
    RootModule        = 'CISBenchmark.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Security Engineering'
    Description       = 'CIS Benchmark L1 Automation for Windows Server 2025 (AWS Managed AD)'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        # Core
        'Initialize-CISEnvironment'
        'Get-CISConfiguration'
        'Write-CISLog'
        'Export-CISReport'
        'Test-AWSConnectivity'
        'New-CISGpoFramework'
        'Backup-CISState'
        'Restore-CISState'
        'Disable-UnnecessaryFirewallRules'
        # Module: SecurityOptions
        'Test-CISSecurityOptions'
        'Set-CISSecurityOptions'
        # Module: AuditPolicy
        'Test-CISAuditPolicy'
        'Set-CISAuditPolicy'
        # Module: AdminTemplates
        'Test-CISAdminTemplates'
        'Set-CISAdminTemplates'
        # Module: AdminTemplatesUser
        'Test-CISAdminTemplatesUser'
        'Set-CISAdminTemplatesUser'
        # Module: Firewall
        'Test-CISFirewall'
        'Set-CISFirewall'
        # Module: Services
        'Test-CISServices'
        'Set-CISServices'
        # Module: UserRightsAssignment
        'Test-CISUserRightsAssignment'
        'Set-CISUserRightsAssignment'
        # Module: AccountPolicies
        'Test-CISAccountPolicies'
        'Set-CISAccountPolicies'
    )
    PrivateData = @{
        PSData = @{
            Tags       = @('CIS', 'Benchmark', 'Security', 'WindowsServer', 'AWS', 'GPO')
            ProjectUri = ''
        }
    }
}
