#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
    Pester tests for CIS Benchmark automation module.
.DESCRIPTION
    Tests configuration loading, module structure, control definitions,
    and helper function behavior. Does NOT require a domain environment —
    tests run against config files and mocked commands.
#>

BeforeAll {
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
    $ModulePath  = Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psm1'

    # Import the module
    Import-Module $ModulePath -Force

    # Set up minimal script-scope config for functions that depend on it
    $script:CISConfig = @{
        LogLevel = 'Warning'  # Suppress Info logs during tests
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration file tests
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Configuration Files' {
    Context 'master-config.psd1' {
        BeforeAll {
            $configPath = Join-Path (Join-Path $ProjectRoot 'config') 'master-config.psd1'
        }

        It 'should exist' {
            $configPath | Should -Exist
        }

        It 'should be a valid PowerShell data file' {
            { Import-PowerShellDataFile -Path $configPath } | Should -Not -Throw
        }

        It 'should have DryRun set to $true by default' {
            $cfg = Import-PowerShellDataFile -Path $configPath
            $cfg.DryRun | Should -Be $true
        }

        It 'should have a Modules hashtable' {
            $cfg = Import-PowerShellDataFile -Path $configPath
            $cfg.Modules | Should -Not -BeNullOrEmpty
            $cfg.Modules | Should -BeOfType [hashtable]
        }

        It 'should have AccountPolicies disabled by default' {
            $cfg = Import-PowerShellDataFile -Path $configPath
            $cfg.Modules.AccountPolicies | Should -Be $false
        }

        It 'should have BenchmarkVersion defined' {
            $cfg = Import-PowerShellDataFile -Path $configPath
            $cfg.BenchmarkVersion | Should -Match 'CIS.*Benchmark'
        }
    }

    Context 'aws-exclusions.psd1' {
        BeforeAll {
            $exclPath = Join-Path (Join-Path $ProjectRoot 'config') 'aws-exclusions.psd1'
        }

        It 'should exist' {
            $exclPath | Should -Exist
        }

        It 'should be a valid PowerShell data file' {
            { Import-PowerShellDataFile -Path $exclPath } | Should -Not -Throw
        }

        It 'should have Skip array with RDP and WinRM service exclusions' {
            $excl = Import-PowerShellDataFile -Path $exclPath
            $excl.Skip | Should -Contain '5.21'
            $excl.Skip | Should -Contain '5.39'
        }

        It 'should have Modify hashtable' {
            $excl = Import-PowerShellDataFile -Path $exclPath
            $excl.Modify | Should -BeOfType [hashtable]
        }
    }

    Context 'Module config files' {
        BeforeAll {
            $moduleDir = Join-Path (Join-Path $ProjectRoot 'config') 'modules'
            $expectedModules = @(
                'AccountPolicies'
                'UserRightsAssignment'
                'SecurityOptions'
                'AuditPolicy'
                'Services'
                'Firewall'
                'AdminTemplates'
                'AdminTemplatesUser'
            )
        }

        It 'should have a config file for <_>' -ForEach $expectedModules {
            $path = Join-Path $moduleDir "$_.psd1"
            $path | Should -Exist
        }

        It 'should parse <_>.psd1 as a valid data file' -ForEach $expectedModules {
            $path = Join-Path $moduleDir "$_.psd1"
            { Import-PowerShellDataFile -Path $path } | Should -Not -Throw
        }

        It 'should have a Controls array in <_>.psd1' -ForEach $expectedModules {
            $path = Join-Path $moduleDir "$_.psd1"
            $cfg = Import-PowerShellDataFile -Path $path
            $cfg.Controls | Should -Not -BeNullOrEmpty
            $cfg.Controls.Count | Should -BeGreaterThan 0
        }

        It 'should have unique control IDs in <_>.psd1' -ForEach $expectedModules {
            $path = Join-Path $moduleDir "$_.psd1"
            $cfg = Import-PowerShellDataFile -Path $path
            $ids = $cfg.Controls | ForEach-Object { $_.Id }
            $ids.Count | Should -Be ($ids | Select-Object -Unique).Count
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Module structure tests
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Module Structure' {
    Context 'PowerShell module files' {
        It 'should have CISBenchmark.psm1' {
            Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psm1' | Should -Exist
        }

        It 'should have CISBenchmark.psd1 manifest' {
            Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psd1' | Should -Exist
        }
    }

    Context 'Core functions' {
        BeforeAll {
            $coreFunctions = @(
                'Write-CISLog'
                'Get-CISConfiguration'
                'Initialize-CISEnvironment'
                'Test-AWSConnectivity'
                'Export-CISReport'
                'New-CISGpoFramework'
                'Backup-CISState'
                'Restore-CISState'
            )
        }

        It 'should export function <_>' -ForEach @(
            'Write-CISLog', 'Get-CISConfiguration', 'Initialize-CISEnvironment',
            'Test-AWSConnectivity', 'Export-CISReport', 'New-CISGpoFramework',
            'Backup-CISState', 'Restore-CISState'
        ) {
            Get-Command $_ -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'CIS Module functions' {
        BeforeAll {
            $moduleNames = @(
                'SecurityOptions', 'AuditPolicy', 'AdminTemplates',
                'Firewall', 'Services', 'UserRightsAssignment',
                'AccountPolicies', 'AdminTemplatesUser'
            )
        }

        It 'should export Test-CIS<_>' -ForEach @(
            'SecurityOptions', 'AuditPolicy', 'AdminTemplates',
            'Firewall', 'Services', 'UserRightsAssignment',
            'AccountPolicies', 'AdminTemplatesUser'
        ) {
            Get-Command "Test-CIS$_" -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'should export Set-CIS<_>' -ForEach @(
            'SecurityOptions', 'AuditPolicy', 'AdminTemplates',
            'Firewall', 'Services', 'UserRightsAssignment',
            'AccountPolicies', 'AdminTemplatesUser'
        ) {
            Get-Command "Set-CIS$_" -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Entry point scripts' {
        It 'should have <_>' -ForEach @(
            'Invoke-CISAudit.ps1', 'Invoke-CISApply.ps1',
            'Invoke-CISRollback.ps1', 'Install-Prerequisites.ps1'
        ) {
            Join-Path (Join-Path $ProjectRoot 'scripts') $_ | Should -Exist
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Write-CISLog tests
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Write-CISLog' {
    BeforeAll {
        $script:CISConfig = @{ LogLevel = 'Debug' }
        $script:LogFile = $null
    }

    It 'should not throw on valid input' {
        { Write-CISLog -Message 'Test message' -Level Info } | Should -Not -Throw
    }

    It 'should accept all valid log levels' {
        { Write-CISLog -Message 'Test' -Level Debug } | Should -Not -Throw
        { Write-CISLog -Message 'Test' -Level Info } | Should -Not -Throw
        { Write-CISLog -Message 'Test' -Level Warning } | Should -Not -Throw
        { Write-CISLog -Message 'Test' -Level Error } | Should -Not -Throw
    }

    It 'should write to log file when configured' {
        $tempLog = Join-Path $TestDrive 'test.log'
        $script:LogFile = $tempLog
        $script:CISConfig = @{ LogLevel = 'Info' }

        Write-CISLog -Message 'Log file test' -Level Info

        $tempLog | Should -Exist
        Get-Content $tempLog | Should -Match 'Log file test'

        $script:LogFile = $null
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Control definition quality tests
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Control Definition Quality' {
    BeforeAll {
        $moduleDir = Join-Path (Join-Path $ProjectRoot 'config') 'modules'
    }

    Context 'Registry-based controls' {
        BeforeAll {
            $regModules = @('SecurityOptions', 'AdminTemplates', 'Firewall', 'AdminTemplatesUser')
            $allRegControls = foreach ($mod in $regModules) {
                $cfg = Import-PowerShellDataFile -Path (Join-Path $moduleDir "$mod.psd1")
                $cfg.Controls | Where-Object { $_.Registry } | ForEach-Object {
                    [PSCustomObject]@{
                        Module = $mod
                        Id     = $_.Id
                        Title  = $_.Title
                        Path   = $_.Registry.Path
                        Name   = $_.Registry.Name
                        Type   = $_.Registry.Type
                    }
                }
            }
        }

        It 'should have valid registry path format for all controls' {
            $badPaths = $allRegControls | Where-Object { $_.Path -notmatch '^HK(LM|CU):\\' }
            $badPaths | Should -BeNullOrEmpty -Because "All registry paths must start with HKLM:\ or HKCU:\"
        }

        It 'should have a registry value name for all controls' {
            $noName = $allRegControls | Where-Object { [string]::IsNullOrEmpty($_.Name) }
            $noName | Should -BeNullOrEmpty -Because "All registry controls must specify a value name"
        }

        It 'should have a valid Type for all controls' {
            $validTypes = @('DWord', 'String', 'MultiString', 'ExpandString', 'QWord', 'Binary')
            $badTypes = $allRegControls | Where-Object { $_.Type -notin $validTypes }
            $badTypes | Should -BeNullOrEmpty -Because "Registry type must be one of: $($validTypes -join ', ')"
        }
    }

    Context 'Service controls' {
        BeforeAll {
            $svcCfg = Import-PowerShellDataFile -Path (Join-Path $moduleDir 'Services.psd1')
        }

        It 'should have ServiceName for every control' {
            $noSvc = $svcCfg.Controls | Where-Object { [string]::IsNullOrEmpty($_.ServiceName) }
            $noSvc | Should -BeNullOrEmpty
        }

        It 'should have valid StartType for every control' {
            $validTypes = @('Disabled', 'Manual', 'Auto')
            $badTypes = $svcCfg.Controls | Where-Object { $_.StartType -notin $validTypes }
            $badTypes | Should -BeNullOrEmpty
        }
    }

    Context 'Audit policy controls' {
        BeforeAll {
            $auditCfg = Import-PowerShellDataFile -Path (Join-Path $moduleDir 'AuditPolicy.psd1')
        }

        It 'should have Subcategory for every control' {
            $noSub = $auditCfg.Controls | Where-Object { [string]::IsNullOrEmpty($_.Subcategory) }
            $noSub | Should -BeNullOrEmpty
        }

        It 'should have CategoryGuid for every control' {
            $noGuid = $auditCfg.Controls | Where-Object { [string]::IsNullOrEmpty($_.CategoryGuid) }
            $noGuid | Should -BeNullOrEmpty
        }

        It 'should have valid InclusionSetting' {
            $validSettings = @('Success', 'Failure', 'Success and Failure', 'No Auditing')
            $badSettings = $auditCfg.Controls | Where-Object { $_.InclusionSetting -notin $validSettings }
            $badSettings | Should -BeNullOrEmpty
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Export-CISReport tests
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Export-CISReport' {
    BeforeAll {
        $script:CISConfig = @{
            ProjectRoot      = $ProjectRoot
            BenchmarkVersion = 'Test v1.0.0'
            Profile          = 'L1 - Test'
            ReportFormats    = @('HTML', 'JSON')
        }

        $mockResults = @(
            [PSCustomObject]@{ Id = '1.1'; Title = 'Test Pass'; Module = 'Test'; Status = 'Pass'; Expected = '1'; Actual = '1'; Detail = '' }
            [PSCustomObject]@{ Id = '1.2'; Title = 'Test Fail'; Module = 'Test'; Status = 'Fail'; Expected = '1'; Actual = '0'; Detail = '' }
            [PSCustomObject]@{ Id = '1.3'; Title = 'Test Skip'; Module = 'Test'; Status = 'Skipped'; Expected = ''; Actual = ''; Detail = 'AWS' }
        )
    }

    It 'should generate an HTML report' {
        $outDir = Join-Path $TestDrive 'reports'
        $summary = Export-CISReport -Results $mockResults -OutputDir $outDir -Formats @('HTML')

        $htmlFiles = Get-ChildItem -Path $outDir -Filter '*.html'
        $htmlFiles.Count | Should -BeGreaterOrEqual 1
    }

    It 'should generate a JSON report' {
        $outDir = Join-Path $TestDrive 'reports-json'
        $summary = Export-CISReport -Results $mockResults -OutputDir $outDir -Formats @('JSON')

        $jsonFiles = Get-ChildItem -Path $outDir -Filter '*.json'
        $jsonFiles.Count | Should -BeGreaterOrEqual 1
    }

    It 'should return correct summary statistics' {
        $outDir = Join-Path $TestDrive 'reports-summary'
        $summary = Export-CISReport -Results $mockResults -OutputDir $outDir -Formats @('JSON')

        $summary.Total | Should -Be 3
        $summary.Passed | Should -Be 1
        $summary.Failed | Should -Be 1
        $summary.Skipped | Should -Be 1
    }

    It 'should produce valid JSON' {
        $outDir = Join-Path $TestDrive 'reports-valid'
        Export-CISReport -Results $mockResults -OutputDir $outDir -Formats @('JSON')

        $jsonFile = Get-ChildItem -Path $outDir -Filter '*.json' | Select-Object -First 1
        { Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Total control count
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Control Coverage Summary' {
    It 'should have a meaningful number of controls defined across all modules' {
        $moduleDir = Join-Path (Join-Path $ProjectRoot 'config') 'modules'
        $totalControls = 0

        Get-ChildItem -Path $moduleDir -Filter '*.psd1' | ForEach-Object {
            $cfg = Import-PowerShellDataFile -Path $_.FullName
            $totalControls += $cfg.Controls.Count
        }

        # We expect a substantial number of controls
        $totalControls | Should -BeGreaterThan 100 -Because "CIS L1 benchmark has ~347 controls, we should have significant coverage"

        Write-Host "Total controls defined: $totalControls" -ForegroundColor Cyan
    }
}
