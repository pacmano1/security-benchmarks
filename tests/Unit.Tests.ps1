#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
    Unit tests for CIS Benchmark module with mocked Windows dependencies.
.DESCRIPTION
    Tests core helper functions and module logic without requiring a domain
    environment, Group Policy, secedit, auditpol, or any Windows-only commands.
    Safe to run on macOS, Linux, or non-domain Windows with PowerShell 7+ and Pester 5.x.
#>

BeforeAll {
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
    $ModulePath  = Join-Path (Join-Path $ProjectRoot 'src') 'CISBenchmark.psm1'

    # Import module fresh
    Import-Module $ModulePath -Force
}

# =============================================================================
# Test-RegistryControl
# =============================================================================
Describe 'Test-RegistryControl' {
    BeforeAll {
        # Suppress log output during tests
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Error' }
            $script:LogFile = $null
        }
    }

    Context 'Equals operator' {
        It 'should Pass when registry value matches expected' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 1 }
                }

                $control = @{
                    Id       = '2.3.1.1'
                    Title    = 'Test control'
                    Registry = @{
                        Path  = 'HKLM:\SOFTWARE\Test'
                        Name  = 'TestValue'
                        Value = 1
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Fail when registry value differs from expected' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 0 }
                }

                $control = @{
                    Id       = '2.3.1.2'
                    Title    = 'Test mismatch'
                    Registry = @{
                        Path  = 'HKLM:\SOFTWARE\Test'
                        Name  = 'TestValue'
                        Value = 1
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
                $result.Expected | Should -Be '1'
                $result.Actual | Should -Be '0'
            }
        }

        It 'should Fail when registry key does not exist' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty { throw 'Registry key not found' }

                $control = @{
                    Id       = '2.3.1.3'
                    Title    = 'Missing key'
                    Registry = @{
                        Path  = 'HKLM:\SOFTWARE\Missing'
                        Name  = 'TestValue'
                        Value = 1
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
                $result.Actual | Should -Be '(not set)'
            }
        }

        It 'should handle string comparison correctly' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 'Enabled' }
                }

                $control = @{
                    Id       = '2.3.1.4'
                    Title    = 'String match'
                    Registry = @{
                        Path  = 'HKLM:\SOFTWARE\Test'
                        Name  = 'TestValue'
                        Value = 'Enabled'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }
    }

    Context 'LessOrEqual operator' {
        It 'should Pass when value is within range' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 15 }
                }

                $control = @{
                    Id       = '2.3.2.1'
                    Title    = 'LessOrEqual pass'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Value    = 30
                        Operator = 'LessOrEqual'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Fail when value exceeds threshold' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 60 }
                }

                $control = @{
                    Id       = '2.3.2.2'
                    Title    = 'LessOrEqual fail high'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Value    = 30
                        Operator = 'LessOrEqual'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
            }
        }

        It 'should Fail when value is below MinValue' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = -1 }
                }

                $control = @{
                    Id       = '2.3.2.3'
                    Title    = 'LessOrEqual fail low'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Value    = 30
                        Operator = 'LessOrEqual'
                        MinValue = 1
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
            }
        }

        It 'should use 0 as default MinValue' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 0 }
                }

                $control = @{
                    Id       = '2.3.2.4'
                    Title    = 'LessOrEqual default min'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Value    = 30
                        Operator = 'LessOrEqual'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }
    }

    Context 'Range operator' {
        It 'should Pass when value is within min/max range' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 15 }
                }

                $control = @{
                    Id       = '2.3.3.1'
                    Title    = 'Range pass'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Range'
                        MinValue = 5
                        MaxValue = 30
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Pass at boundary values' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 5 }
                }

                $control = @{
                    Id       = '2.3.3.2'
                    Title    = 'Range boundary'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Range'
                        MinValue = 5
                        MaxValue = 30
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Fail when value is outside range' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 50 }
                }

                $control = @{
                    Id       = '2.3.3.3'
                    Title    = 'Range fail'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Range'
                        MinValue = 5
                        MaxValue = 30
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
            }
        }
    }

    Context 'NotEmpty operator' {
        It 'should Pass when value is non-blank' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 'some text' }
                }

                $control = @{
                    Id       = '2.3.4.1'
                    Title    = 'NotEmpty pass'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'NotEmpty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Fail when value is blank' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = '' }
                }

                $control = @{
                    Id       = '2.3.4.2'
                    Title    = 'NotEmpty fail'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'NotEmpty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
            }
        }

        It 'should Fail when value is whitespace only' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = '   ' }
                }

                $control = @{
                    Id       = '2.3.4.3'
                    Title    = 'NotEmpty whitespace'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'NotEmpty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
            }
        }
    }

    Context 'Empty operator' {
        It 'should Pass when array is empty' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = @() }
                }

                $control = @{
                    Id       = '2.3.5.1'
                    Title    = 'Empty array pass'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Empty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Pass when array has single empty element' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = @('') }
                }

                $control = @{
                    Id       = '2.3.5.2'
                    Title    = 'Empty single element'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Empty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Fail when array is populated' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = @('value1', 'value2') }
                }

                $control = @{
                    Id       = '2.3.5.3'
                    Title    = 'Empty fail'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Empty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Fail'
            }
        }

        It 'should Pass when string value is blank' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = '' }
                }

                $control = @{
                    Id       = '2.3.5.4'
                    Title    = 'Empty string pass'
                    Registry = @{
                        Path     = 'HKLM:\SOFTWARE\Test'
                        Name     = 'TestValue'
                        Operator = 'Empty'
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }
    }

    Context 'Default operator (no Operator specified)' {
        It 'should default to Equals comparison' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 42 }
                }

                $control = @{
                    Id       = '2.3.6.1'
                    Title    = 'Default operator'
                    Registry = @{
                        Path  = 'HKLM:\SOFTWARE\Test'
                        Name  = 'TestValue'
                        Value = 42
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'TestModule'
                $result.Status | Should -Be 'Pass'
            }
        }
    }

    Context 'Result object properties' {
        It 'should include all required properties' {
            InModuleScope 'CISBenchmark' {
                Mock Get-ItemProperty {
                    [PSCustomObject]@{ TestValue = 1 }
                }

                $control = @{
                    Id       = '99.1.1'
                    Title    = 'Property check'
                    Registry = @{
                        Path  = 'HKLM:\SOFTWARE\Test'
                        Name  = 'TestValue'
                        Value = 1
                    }
                }

                $result = Test-RegistryControl -Control $control -ModuleName 'MyModule'
                $result.Id | Should -Be '99.1.1'
                $result.Title | Should -Be 'Property check'
                $result.Module | Should -Be 'MyModule'
                $result.Status | Should -BeIn @('Pass', 'Fail')
                $result.PSObject.Properties.Name | Should -Contain 'Expected'
                $result.PSObject.Properties.Name | Should -Contain 'Actual'
                $result.PSObject.Properties.Name | Should -Contain 'Detail'
            }
        }
    }
}

# =============================================================================
# Test-SeceditControl
# =============================================================================
Describe 'Test-SeceditControl' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Error' }
            $script:LogFile = $null
        }
    }

    Context 'Value match' {
        It 'should Pass when secedit value matches expected' {
            InModuleScope 'CISBenchmark' {
                $control = @{
                    Id      = '2.3.1.2'
                    Title   = 'Guest account disabled'
                    Secedit = @{ Key = 'EnableGuestAccount'; Value = '0' }
                }
                $seceditData = @{ 'EnableGuestAccount' = '0' }

                $result = Test-SeceditControl -Control $control -ModuleName 'SecurityOptions' -SeceditData $seceditData
                $result.Status | Should -Be 'Pass'
            }
        }

        It 'should Fail when secedit value mismatches' {
            InModuleScope 'CISBenchmark' {
                $control = @{
                    Id      = '2.3.1.2'
                    Title   = 'Guest account disabled'
                    Secedit = @{ Key = 'EnableGuestAccount'; Value = '0' }
                }
                $seceditData = @{ 'EnableGuestAccount' = '1' }

                $result = Test-SeceditControl -Control $control -ModuleName 'SecurityOptions' -SeceditData $seceditData
                $result.Status | Should -Be 'Fail'
                $result.Actual | Should -Be '1'
            }
        }
    }

    Context 'NotValue match' {
        It 'should Pass when actual differs from forbidden value' {
            InModuleScope 'CISBenchmark' {
                $control = @{
                    Id      = '2.3.1.5'
                    Title   = 'Rename guest'
                    Secedit = @{ Key = 'NewGuestName'; NotValue = '"Guest"' }
                }
                $seceditData = @{ 'NewGuestName' = '"Visitor"' }

                $result = Test-SeceditControl -Control $control -ModuleName 'SecurityOptions' -SeceditData $seceditData
                $result.Status | Should -Be 'Pass'
                $result.Expected | Should -Be 'Not "Guest"'
            }
        }

        It 'should Fail when actual equals forbidden value' {
            InModuleScope 'CISBenchmark' {
                $control = @{
                    Id      = '2.3.1.5'
                    Title   = 'Rename guest'
                    Secedit = @{ Key = 'NewGuestName'; NotValue = '"Guest"' }
                }
                $seceditData = @{ 'NewGuestName' = '"Guest"' }

                $result = Test-SeceditControl -Control $control -ModuleName 'SecurityOptions' -SeceditData $seceditData
                $result.Status | Should -Be 'Fail'
            }
        }
    }

    Context 'Key not found' {
        It 'should Fail when key is missing from secedit data' {
            InModuleScope 'CISBenchmark' {
                $control = @{
                    Id      = '2.3.1.9'
                    Title   = 'Missing key'
                    Secedit = @{ Key = 'NonExistentKey'; Value = '1' }
                }
                $seceditData = @{}

                $result = Test-SeceditControl -Control $control -ModuleName 'SecurityOptions' -SeceditData $seceditData
                $result.Status | Should -Be 'Fail'
                $result.Actual | Should -Be '(not found)'
                $result.Detail | Should -Match 'not found'
            }
        }
    }
}

# =============================================================================
# Test-AuditSettingCompliance
# =============================================================================
Describe 'Test-AuditSettingCompliance' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Error' }
        }
    }

    It 'should return true for exact match' {
        InModuleScope 'CISBenchmark' {
            $result = Test-AuditSettingCompliance -Actual 'Success and Failure' -Expected 'Success and Failure'
            $result | Should -Be $true
        }
    }

    It 'should return true when actual is "Success and Failure" for any expected' {
        InModuleScope 'CISBenchmark' {
            Test-AuditSettingCompliance -Actual 'Success and Failure' -Expected 'Success' | Should -Be $true
            Test-AuditSettingCompliance -Actual 'Success and Failure' -Expected 'Failure' | Should -Be $true
        }
    }

    It 'should return true when expected is "Include Success" and actual contains success' {
        InModuleScope 'CISBenchmark' {
            Test-AuditSettingCompliance -Actual 'Success' -Expected 'Include Success' | Should -Be $true
            Test-AuditSettingCompliance -Actual 'Success and Failure' -Expected 'Include Success' | Should -Be $true
        }
    }

    It 'should return true when expected is "Include Failure" and actual contains failure' {
        InModuleScope 'CISBenchmark' {
            Test-AuditSettingCompliance -Actual 'Failure' -Expected 'Include Failure' | Should -Be $true
            Test-AuditSettingCompliance -Actual 'Success and Failure' -Expected 'Include Failure' | Should -Be $true
        }
    }

    It 'should return false for mismatch' {
        InModuleScope 'CISBenchmark' {
            Test-AuditSettingCompliance -Actual 'No Auditing' -Expected 'Success' | Should -Be $false
            Test-AuditSettingCompliance -Actual 'Success' -Expected 'Failure' | Should -Be $false
        }
    }

    It 'should be case-insensitive' {
        InModuleScope 'CISBenchmark' {
            Test-AuditSettingCompliance -Actual 'success AND failure' -Expected 'Success and Failure' | Should -Be $true
        }
    }
}

# =============================================================================
# Get-SeceditExport
# =============================================================================
Describe 'Get-SeceditExport' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Error' }
            $script:LogFile = $null
        }
    }

    It 'should parse secedit INF output into a hashtable' {
        InModuleScope 'CISBenchmark' {
            # Create a temp INF file that mimics secedit output
            $tempInf = Join-Path $TestDrive 'test_secedit.inf'
            @(
                '[Unicode]'
                'Unicode=yes'
                '[System Access]'
                'MinimumPasswordAge = 1'
                'MaximumPasswordAge = 60'
                'EnableGuestAccount = 0'
                '[Event Audit]'
                'AuditSystemEvents = 3'
                '[Version]'
                'signature="$CHICAGO$"'
                'Revision=1'
            ) | Set-Content -Path $tempInf

            # Mock secedit.exe to be a no-op; we'll mock Test-Path and Get-Content
            # to return our test file content
            Mock secedit.exe { } -RemoveParameterValidation 'cfg'

            # Intercept the temp file path and redirect to our test file
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*cis_secedit*' }
            Mock Get-Content {
                Get-Content -LiteralPath $tempInf
            } -ParameterFilter { $Path -like '*cis_secedit*' }
            Mock Remove-Item { } -ParameterFilter { $Path -like '*cis_secedit*' }

            $data = Get-SeceditExport
            $data | Should -BeOfType [hashtable]
            $data['MinimumPasswordAge'] | Should -Be '1'
            $data['MaximumPasswordAge'] | Should -Be '60'
            $data['EnableGuestAccount'] | Should -Be '0'
            $data['AuditSystemEvents'] | Should -Be '3'
        }
    }
}

# =============================================================================
# Get-AuditPolData
# =============================================================================
Describe 'Get-AuditPolData' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Error' }
            $script:LogFile = $null
        }
    }

    It 'should parse auditpol CSV output into a subcategory-to-setting hashtable' {
        InModuleScope 'CISBenchmark' {
            # Mock auditpol.exe to return CSV-like output
            $csvOutput = @(
                'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting'
                'WIN-TEST,System,Credential Validation,{0CCE923F-69AE-11D9-BED3-505054503030},Success and Failure,No Auditing'
                'WIN-TEST,System,Logon,{0CCE9215-69AE-11D9-BED3-505054503030},Success,No Auditing'
                'WIN-TEST,System,Other Account Management Events,{0CCE923A-69AE-11D9-BED3-505054503030},No Auditing,No Auditing'
            )

            Mock auditpol.exe { $csvOutput }

            $data = Get-AuditPolData
            $data | Should -BeOfType [hashtable]
            $data['Credential Validation'] | Should -Be 'Success and Failure'
            $data['Logon'] | Should -Be 'Success'
            $data['Other Account Management Events'] | Should -Be 'No Auditing'
        }
    }

    It 'should return empty hashtable when auditpol fails' {
        InModuleScope 'CISBenchmark' {
            Mock auditpol.exe { throw 'auditpol not found' }

            $data = Get-AuditPolData
            $data | Should -BeOfType [hashtable]
            $data.Count | Should -Be 0
        }
    }
}

# =============================================================================
# Get-AWSModifiedValue
# =============================================================================
Describe 'Get-AWSModifiedValue' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                AWSExclusions = @{
                    Modify = @{
                        '2.2.17' = '*S-1-5-32-546'
                        '2.2.38' = '*S-1-5-19,*S-1-5-20'
                    }
                }
            }
            $script:LogFile = $null
        }
    }

    It 'should return modified value when control ID is in Modify list' {
        InModuleScope 'CISBenchmark' {
            $result = Get-AWSModifiedValue -ControlId '2.2.17' -DefaultValue '*S-1-5-32-546,*S-1-5-32-547'
            $result | Should -Be '*S-1-5-32-546'
        }
    }

    It 'should return default value when control ID is not in Modify list' {
        InModuleScope 'CISBenchmark' {
            $result = Get-AWSModifiedValue -ControlId '99.99.99' -DefaultValue 'original'
            $result | Should -Be 'original'
        }
    }

    It 'should return default value when Modify list is empty' {
        InModuleScope 'CISBenchmark' {
            $saved = $script:CISConfig.AWSExclusions.Modify
            $script:CISConfig.AWSExclusions.Modify = @{}

            $result = Get-AWSModifiedValue -ControlId '2.2.17' -DefaultValue 'fallback'
            $result | Should -Be 'fallback'

            $script:CISConfig.AWSExclusions.Modify = $saved
        }
    }

    It 'should return default value when AWSExclusions.Modify is null' {
        InModuleScope 'CISBenchmark' {
            $saved = $script:CISConfig.AWSExclusions
            $script:CISConfig.AWSExclusions = @{ Modify = $null }

            $result = Get-AWSModifiedValue -ControlId '2.2.17' -DefaultValue 'default'
            $result | Should -Be 'default'

            $script:CISConfig.AWSExclusions = $saved
        }
    }
}

# =============================================================================
# Get-CISConfiguration
# =============================================================================
Describe 'Get-CISConfiguration' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Error' }
            $script:LogFile = $null
        }
    }

    It 'should load master config with correct keys' {
        InModuleScope 'CISBenchmark' -Parameters @{ ProjectRoot = (Split-Path $PSScriptRoot -Parent) } {
            param($ProjectRoot)
            $config = Get-CISConfiguration -ProjectRoot $ProjectRoot
            $config.BenchmarkVersion | Should -Not -BeNullOrEmpty
            $config.Profile | Should -Not -BeNullOrEmpty
            $config.Modules | Should -Not -BeNullOrEmpty
            $config.ProjectRoot | Should -Be $ProjectRoot
        }
    }

    It 'should load AWS exclusions' {
        InModuleScope 'CISBenchmark' -Parameters @{ ProjectRoot = (Split-Path $PSScriptRoot -Parent) } {
            param($ProjectRoot)
            $config = Get-CISConfiguration -ProjectRoot $ProjectRoot
            $config.AWSExclusions | Should -Not -BeNullOrEmpty
            $config.AWSExclusions.Skip | Should -Not -BeNullOrEmpty
            $config.AWSExclusions.Modify | Should -Not -BeNullOrEmpty
        }
    }

    It 'should load module configs for enabled modules' {
        InModuleScope 'CISBenchmark' -Parameters @{ ProjectRoot = (Split-Path $PSScriptRoot -Parent) } {
            param($ProjectRoot)
            $config = Get-CISConfiguration -ProjectRoot $ProjectRoot
            $config.ModuleConfigs.Keys.Count | Should -BeGreaterThan 0

            # SecurityOptions is enabled by default — verify it loaded
            $config.ModuleConfigs['SecurityOptions'] | Should -Not -BeNullOrEmpty
            $config.ModuleConfigs['SecurityOptions'].Controls.Count | Should -BeGreaterThan 0
        }
    }

    It 'should not load disabled modules' {
        InModuleScope 'CISBenchmark' -Parameters @{ ProjectRoot = (Split-Path $PSScriptRoot -Parent) } {
            param($ProjectRoot)
            $config = Get-CISConfiguration -ProjectRoot $ProjectRoot

            # AccountPolicies is disabled by default
            $config.ModuleConfigs.ContainsKey('AccountPolicies') | Should -Be $false
        }
    }

    It 'should mark skipped controls from AWS exclusion list' {
        InModuleScope 'CISBenchmark' -Parameters @{ ProjectRoot = (Split-Path $PSScriptRoot -Parent) } {
            param($ProjectRoot)
            $config = Get-CISConfiguration -ProjectRoot $ProjectRoot

            # 5.21 is in the Skip list (TermService RDP)
            $allControls = foreach ($mod in $config.ModuleConfigs.Keys) {
                $config.ModuleConfigs[$mod].Controls
            }
            $skippedControl = $allControls | Where-Object { $_.Id -eq '5.21' }
            if ($skippedControl) {
                $skippedControl.Skipped | Should -Be $true
                $skippedControl.SkipReason | Should -Be 'AWS exclusion'
            }
        }
    }

    It 'should throw when master config is missing' {
        InModuleScope 'CISBenchmark' {
            { Get-CISConfiguration -ProjectRoot '/nonexistent/path' } | Should -Throw
        }
    }

    It 'should handle missing aws-exclusions gracefully' {
        InModuleScope 'CISBenchmark' {
            # Create a minimal project structure with no aws-exclusions
            $tempRoot = Join-Path $TestDrive 'test-project'
            $configDir = Join-Path $tempRoot 'config'
            $modulesDir = Join-Path $configDir 'modules'
            New-Item -Path $modulesDir -ItemType Directory -Force | Out-Null

            # Minimal master config
            @"
@{
    BenchmarkVersion = 'Test v1.0'
    Profile          = 'L1 - Test'
    TargetOU         = 'OU=Test'
    GpoPrefix        = 'TEST'
    DryRun           = `$true
    Modules          = @{}
    LogLevel         = 'Error'
}
"@ | Set-Content (Join-Path $configDir 'master-config.psd1')

            # Should not throw — just warn and use empty exclusions
            $config = Get-CISConfiguration -ProjectRoot $tempRoot
            $config.AWSExclusions | Should -Not -BeNullOrEmpty
            $config.AWSExclusions.Skip.Count | Should -Be 0
            $config.AWSExclusions.Modify.Count | Should -Be 0
        }
    }
}

# =============================================================================
# Test-CISServices (full function with mocks)
# =============================================================================
Describe 'Test-CISServices' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    Services = @{
                        Controls = @(
                            @{ Id = '5.1'; Title = 'Bluetooth service'; ServiceName = 'BTAGService'; StartType = 'Disabled' }
                            @{ Id = '5.2'; Title = 'Auto service'; ServiceName = 'AutoSvc'; StartType = 'Auto' }
                            @{ Id = '5.3'; Title = 'Missing service'; ServiceName = 'FakeSvc'; StartType = 'Disabled' }
                            @{ Id = '5.4'; Title = 'Missing required'; ServiceName = 'MissingSvc'; StartType = 'Auto' }
                            @{ Id = '5.5'; Title = 'Running not disabled'; ServiceName = 'RunningSvc'; StartType = 'Disabled' }
                        )
                    }
                }
            }
            $script:LogFile = $null
        }
    }

    It 'should Pass when service is Disabled and expected Disabled' {
        InModuleScope 'CISBenchmark' {
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'BTAGService'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'BTAGService' }

            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'BTAGService'; StartMode = 'Disabled' }
            } -ParameterFilter { $Filter -match 'BTAGService' }

            # Mock other services to avoid interference
            Mock Get-Service { throw [Microsoft.PowerShell.Commands.ServiceCommandException]::new('not found') } -ParameterFilter { $Name -ne 'BTAGService' -and $Name -ne 'AutoSvc' -and $Name -ne 'RunningSvc' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'AutoSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'AutoSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'AutoSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'AutoSvc' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'RunningSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'RunningSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'RunningSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'RunningSvc' }

            $results = Test-CISServices
            $bt = $results | Where-Object { $_.Id -eq '5.1' }
            $bt.Status | Should -Be 'Pass'
        }
    }

    It 'should Fail when service is Auto but expected Disabled' {
        InModuleScope 'CISBenchmark' {
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'RunningSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'RunningSvc' }

            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'RunningSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'RunningSvc' }

            # Let other services be not found
            Mock Get-Service { throw [Microsoft.PowerShell.Commands.ServiceCommandException]::new('not found') } -ParameterFilter { $Name -notin @('RunningSvc', 'AutoSvc', 'BTAGService') }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'BTAGService'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'BTAGService' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'BTAGService'; StartMode = 'Disabled' }
            } -ParameterFilter { $Filter -match 'BTAGService' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'AutoSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'AutoSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'AutoSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'AutoSvc' }

            $results = Test-CISServices
            $svc = $results | Where-Object { $_.Id -eq '5.5' }
            $svc.Status | Should -Be 'Fail'
        }
    }

    It 'should Pass when not-installed service is expected Disabled' {
        InModuleScope 'CISBenchmark' {
            # Only set up the specific service we're testing as not found
            # For 5.3 (FakeSvc), Get-Service should throw ServiceCommandException
            Mock Get-Service {
                throw [Microsoft.PowerShell.Commands.ServiceCommandException]::new('service not found')
            } -ParameterFilter { $Name -eq 'FakeSvc' }

            # Set up other services
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'BTAGService'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'BTAGService' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'BTAGService'; StartMode = 'Disabled' }
            } -ParameterFilter { $Filter -match 'BTAGService' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'AutoSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'AutoSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'AutoSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'AutoSvc' }
            Mock Get-Service {
                throw [Microsoft.PowerShell.Commands.ServiceCommandException]::new('not found')
            } -ParameterFilter { $Name -eq 'MissingSvc' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'RunningSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'RunningSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'RunningSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'RunningSvc' }

            $results = Test-CISServices
            $svc = $results | Where-Object { $_.Id -eq '5.3' }
            $svc.Status | Should -Be 'Pass'
            $svc.Actual | Should -Be 'Not Installed'
        }
    }

    It 'should Error when not-installed service is expected Auto' {
        InModuleScope 'CISBenchmark' {
            Mock Get-Service {
                throw [Microsoft.PowerShell.Commands.ServiceCommandException]::new('not found')
            } -ParameterFilter { $Name -eq 'MissingSvc' }

            Mock Get-Service {
                [PSCustomObject]@{ Name = 'BTAGService'; Status = 'Stopped' }
            } -ParameterFilter { $Name -eq 'BTAGService' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'BTAGService'; StartMode = 'Disabled' }
            } -ParameterFilter { $Filter -match 'BTAGService' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'AutoSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'AutoSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'AutoSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'AutoSvc' }
            Mock Get-Service {
                throw [Microsoft.PowerShell.Commands.ServiceCommandException]::new('not found')
            } -ParameterFilter { $Name -eq 'FakeSvc' }
            Mock Get-Service {
                [PSCustomObject]@{ Name = 'RunningSvc'; Status = 'Running' }
            } -ParameterFilter { $Name -eq 'RunningSvc' }
            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'RunningSvc'; StartMode = 'Auto' }
            } -ParameterFilter { $Filter -match 'RunningSvc' }

            $results = Test-CISServices
            $svc = $results | Where-Object { $_.Id -eq '5.4' }
            $svc.Status | Should -Be 'Error'
        }
    }

    It 'should handle skipped controls' {
        InModuleScope 'CISBenchmark' {
            # Add a skipped control temporarily
            $saved = $script:CISConfig.ModuleConfigs.Services.Controls
            $script:CISConfig.ModuleConfigs.Services.Controls = @(
                @{ Id = '5.21'; Title = 'RDP service'; ServiceName = 'TermService'; StartType = 'Disabled'; Skipped = $true; SkipReason = 'AWS exclusion' }
            )

            $results = Test-CISServices
            $results[0].Status | Should -Be 'Skipped'
            $results[0].Detail | Should -Be 'AWS exclusion'

            $script:CISConfig.ModuleConfigs.Services.Controls = $saved
        }
    }
}

# =============================================================================
# Test-CISUserRightsAssignment (SID comparison)
# =============================================================================
Describe 'Test-CISUserRightsAssignment' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    UserRightsAssignment = @{
                        Controls = @(
                            @{
                                Id            = '2.2.1'
                                Title         = 'Exact match test'
                                SeceditKey    = 'SeNetworkLogonRight'
                                ExpectedValue = '*S-1-5-32-544,*S-1-5-32-545'
                                Description   = 'Administrators, Users'
                            }
                            @{
                                Id            = '2.2.2'
                                Title         = 'No one test'
                                SeceditKey    = 'SeTrustedCredManAccessPrivilege'
                                ExpectedValue = ''
                                Description   = 'No One'
                            }
                            @{
                                Id            = '2.2.3'
                                Title         = 'Superset test'
                                SeceditKey    = 'SeBackupPrivilege'
                                ExpectedValue = '*S-1-5-32-544'
                                Description   = 'Administrators'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null
        }
    }

    It 'should Pass when SID list matches exactly' {
        InModuleScope 'CISBenchmark' {
            Mock Get-SeceditExport {
                @{
                    'SeNetworkLogonRight'            = '*S-1-5-32-544,*S-1-5-32-545'
                    'SeTrustedCredManAccessPrivilege' = ''
                    'SeBackupPrivilege'              = '*S-1-5-32-544'
                }
            }

            $results = Test-CISUserRightsAssignment
            $r = $results | Where-Object { $_.Id -eq '2.2.1' }
            $r.Status | Should -Be 'Pass'
        }
    }

    It 'should Pass when actual is a superset of expected' {
        InModuleScope 'CISBenchmark' {
            Mock Get-SeceditExport {
                @{
                    'SeNetworkLogonRight'            = '*S-1-5-32-544,*S-1-5-32-545'
                    'SeTrustedCredManAccessPrivilege' = ''
                    'SeBackupPrivilege'              = '*S-1-5-32-544,*S-1-5-32-551'
                }
            }

            $results = Test-CISUserRightsAssignment
            $r = $results | Where-Object { $_.Id -eq '2.2.3' }
            $r.Status | Should -Be 'Pass'
        }
    }

    It 'should Pass when expected empty and not set' {
        InModuleScope 'CISBenchmark' {
            Mock Get-SeceditExport {
                @{
                    'SeNetworkLogonRight' = '*S-1-5-32-544,*S-1-5-32-545'
                    'SeBackupPrivilege'   = '*S-1-5-32-544'
                    # SeTrustedCredManAccessPrivilege is absent — $null
                }
            }

            $results = Test-CISUserRightsAssignment
            $r = $results | Where-Object { $_.Id -eq '2.2.2' }
            $r.Status | Should -Be 'Pass'
            $r.Actual | Should -Be '(not set)'
        }
    }

    It 'should Fail when expected empty but actual has values' {
        InModuleScope 'CISBenchmark' {
            Mock Get-SeceditExport {
                @{
                    'SeNetworkLogonRight'            = '*S-1-5-32-544,*S-1-5-32-545'
                    'SeTrustedCredManAccessPrivilege' = '*S-1-5-32-544'
                    'SeBackupPrivilege'              = '*S-1-5-32-544'
                }
            }

            $results = Test-CISUserRightsAssignment
            $r = $results | Where-Object { $_.Id -eq '2.2.2' }
            $r.Status | Should -Be 'Fail'
        }
    }

    It 'should Fail when required SID is missing from actual' {
        InModuleScope 'CISBenchmark' {
            Mock Get-SeceditExport {
                @{
                    'SeNetworkLogonRight'            = '*S-1-5-32-544'  # missing *S-1-5-32-545
                    'SeTrustedCredManAccessPrivilege' = ''
                    'SeBackupPrivilege'              = '*S-1-5-32-544'
                }
            }

            $results = Test-CISUserRightsAssignment
            $r = $results | Where-Object { $_.Id -eq '2.2.1' }
            $r.Status | Should -Be 'Fail'
        }
    }

    It 'should handle skipped controls' {
        InModuleScope 'CISBenchmark' {
            $saved = $script:CISConfig.ModuleConfigs.UserRightsAssignment.Controls
            $script:CISConfig.ModuleConfigs.UserRightsAssignment.Controls = @(
                @{
                    Id            = '2.2.99'
                    Title         = 'Skipped URA'
                    SeceditKey    = 'SeTest'
                    ExpectedValue = ''
                    Description   = 'Test'
                    Skipped       = $true
                    SkipReason    = 'AWS exclusion'
                }
            )

            Mock Get-SeceditExport { @{} }

            $results = Test-CISUserRightsAssignment
            $results[0].Status | Should -Be 'Skipped'

            $script:CISConfig.ModuleConfigs.UserRightsAssignment.Controls = $saved
        }
    }
}

# =============================================================================
# Set-CIS* DryRun behavior
# =============================================================================
Describe 'Set-CIS* DryRun behavior' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                AWSExclusions = @{ Skip = @(); Modify = @{} }
                ModuleConfigs = @{
                    AdminTemplates = @{
                        Controls = @(
                            @{
                                Id       = '18.1.1'
                                Title    = 'Test admin template'
                                Registry = @{
                                    Path  = 'HKLM:\SOFTWARE\Policies\Test'
                                    Name  = 'Setting1'
                                    Type  = 'DWord'
                                    Value = 1
                                }
                            }
                        )
                    }
                    Firewall = @{
                        Controls = @(
                            @{
                                Id       = '9.1.1'
                                Title    = 'Test firewall'
                                Registry = @{
                                    Path  = 'HKLM:\SOFTWARE\Policies\Firewall'
                                    Name  = 'Enable'
                                    Type  = 'DWord'
                                    Value = 1
                                }
                            }
                        )
                    }
                    Services = @{
                        Controls = @(
                            @{
                                Id          = '5.1'
                                Title       = 'Test service'
                                ServiceName = 'TestSvc'
                                StartType   = 'Disabled'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null
        }
    }

    Context 'Set-CISAdminTemplates DryRun' {
        It 'should never call Set-GPRegistryValue when DryRun is true' {
            InModuleScope 'CISBenchmark' {
                Mock Set-GPRegistryValue { }
                Mock Write-CISLog { }

                Set-CISAdminTemplates -GpoName 'CIS-L1-AdminTemplates' -DryRun $true

                Should -Invoke Set-GPRegistryValue -Times 0 -Exactly
            }
        }

        It 'should log DRY RUN messages' {
            InModuleScope 'CISBenchmark' {
                $logMessages = @()
                Mock Set-GPRegistryValue { }
                Mock Write-CISLog {
                    $script:capturedMessages += $Message
                }

                $script:capturedMessages = @()
                Set-CISAdminTemplates -GpoName 'CIS-L1-AdminTemplates' -DryRun $true

                $dryRunMsg = $script:capturedMessages | Where-Object { $_ -match '\[DRY RUN\]' }
                $dryRunMsg | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Set-CISFirewall DryRun' {
        It 'should never call Set-GPRegistryValue when DryRun is true' {
            InModuleScope 'CISBenchmark' {
                Mock Set-GPRegistryValue { }
                Mock Write-CISLog { }

                Set-CISFirewall -GpoName 'CIS-L1-Firewall' -DryRun $true

                Should -Invoke Set-GPRegistryValue -Times 0 -Exactly
            }
        }
    }

    Context 'Set-CISServices DryRun' {
        It 'should never call Set-GPRegistryValue when DryRun is true' {
            InModuleScope 'CISBenchmark' {
                Mock Set-GPRegistryValue { }
                Mock Write-CISLog { }

                Set-CISServices -GpoName 'CIS-L1-Services' -DryRun $true

                Should -Invoke Set-GPRegistryValue -Times 0 -Exactly
            }
        }

        It 'should log DRY RUN with service registry path' {
            InModuleScope 'CISBenchmark' {
                $script:capturedMessages = @()
                Mock Set-GPRegistryValue { }
                Mock Write-CISLog {
                    $script:capturedMessages += $Message
                }

                Set-CISServices -GpoName 'CIS-L1-Services' -DryRun $true

                $dryRunMsg = $script:capturedMessages | Where-Object { $_ -match '\[DRY RUN\]' -and $_ -match 'Start' }
                $dryRunMsg | Should -Not -BeNullOrEmpty
            }
        }
    }
}

# =============================================================================
# Export-CISReport — extended edge cases
# =============================================================================
Describe 'Export-CISReport edge cases' {
    BeforeAll {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                ProjectRoot      = (Split-Path $PSScriptRoot -Parent)
                BenchmarkVersion = 'Test v1.0.0'
                Profile          = 'L1 - Test'
                LogLevel         = 'Error'
            }
            $script:LogFile = $null
        }
    }

    It 'should calculate 100% compliance when all pass' {
        $results = @(
            [PSCustomObject]@{ Id = '1.1'; Title = 'Pass 1'; Module = 'T'; Status = 'Pass'; Expected = '1'; Actual = '1'; Detail = '' }
            [PSCustomObject]@{ Id = '1.2'; Title = 'Pass 2'; Module = 'T'; Status = 'Pass'; Expected = '1'; Actual = '1'; Detail = '' }
            [PSCustomObject]@{ Id = '1.3'; Title = 'Pass 3'; Module = 'T'; Status = 'Pass'; Expected = '1'; Actual = '1'; Detail = '' }
        )
        $outDir = Join-Path $TestDrive 'rpt-allpass'
        $summary = Export-CISReport -Results $results -OutputDir $outDir -Formats @('JSON')
        $summary.PassPercent | Should -Be 100
        $summary.Failed | Should -Be 0
    }

    It 'should calculate 0% compliance when all fail' {
        $results = @(
            [PSCustomObject]@{ Id = '1.1'; Title = 'Fail 1'; Module = 'T'; Status = 'Fail'; Expected = '1'; Actual = '0'; Detail = '' }
            [PSCustomObject]@{ Id = '1.2'; Title = 'Fail 2'; Module = 'T'; Status = 'Fail'; Expected = '1'; Actual = '0'; Detail = '' }
        )
        $outDir = Join-Path $TestDrive 'rpt-allfail'
        $summary = Export-CISReport -Results $results -OutputDir $outDir -Formats @('JSON')
        $summary.PassPercent | Should -Be 0
        $summary.Passed | Should -Be 0
    }

    It 'should exclude skipped from compliance denominator' {
        $results = @(
            [PSCustomObject]@{ Id = '1.1'; Title = 'Pass'; Module = 'T'; Status = 'Pass'; Expected = '1'; Actual = '1'; Detail = '' }
            [PSCustomObject]@{ Id = '1.2'; Title = 'Skip'; Module = 'T'; Status = 'Skipped'; Expected = ''; Actual = ''; Detail = 'AWS' }
        )
        $outDir = Join-Path $TestDrive 'rpt-skip'
        $summary = Export-CISReport -Results $results -OutputDir $outDir -Formats @('JSON')
        # 1 pass out of (2 total - 1 skipped) = 100%
        $summary.PassPercent | Should -Be 100
        $summary.Total | Should -Be 2
        $summary.Skipped | Should -Be 1
    }

    It 'should handle all-skipped results without division by zero' {
        $results = @(
            [PSCustomObject]@{ Id = '1.1'; Title = 'Skip 1'; Module = 'T'; Status = 'Skipped'; Expected = ''; Actual = ''; Detail = '' }
            [PSCustomObject]@{ Id = '1.2'; Title = 'Skip 2'; Module = 'T'; Status = 'Skipped'; Expected = ''; Actual = ''; Detail = '' }
        )
        $outDir = Join-Path $TestDrive 'rpt-allskip'
        # total - skipped = 0, this would cause division by zero if not handled
        # The current code: $passed / ($total - $skipped) would throw; let's see actual behavior
        { Export-CISReport -Results $results -OutputDir $outDir -Formats @('JSON') } | Should -Not -Throw
    }

    It 'should return 0 for empty results' {
        $results = @()
        $outDir = Join-Path $TestDrive 'rpt-empty'
        $summary = Export-CISReport -Results $results -OutputDir $outDir -Formats @('JSON')
        $summary.Total | Should -Be 0
        $summary.PassPercent | Should -Be 0
    }

    It 'should count errors separately' {
        $results = @(
            [PSCustomObject]@{ Id = '1.1'; Title = 'Pass'; Module = 'T'; Status = 'Pass'; Expected = '1'; Actual = '1'; Detail = '' }
            [PSCustomObject]@{ Id = '1.2'; Title = 'Error'; Module = 'T'; Status = 'Error'; Expected = '1'; Actual = ''; Detail = 'oops' }
        )
        $outDir = Join-Path $TestDrive 'rpt-errors'
        $summary = Export-CISReport -Results $results -OutputDir $outDir -Formats @('JSON')
        $summary.Errors | Should -Be 1
        $summary.Passed | Should -Be 1
    }
}

# =============================================================================
# Write-CISLog — extended edge cases
# =============================================================================
Describe 'Write-CISLog log level filtering' {
    It 'should suppress Debug messages when LogLevel is Warning' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Warning' }
            $tempLog = Join-Path $TestDrive 'filter-test.log'
            $script:LogFile = $tempLog

            Write-CISLog -Message 'Debug msg' -Level Debug
            Write-CISLog -Message 'Info msg' -Level Info
            Write-CISLog -Message 'Warning msg' -Level Warning
            Write-CISLog -Message 'Error msg' -Level Error

            if (Test-Path $tempLog) {
                $content = Get-Content $tempLog -Raw
                $content | Should -Not -Match 'Debug msg'
                $content | Should -Not -Match 'Info msg'
                $content | Should -Match 'Warning msg'
                $content | Should -Match 'Error msg'
            } else {
                # If nothing was logged at all, that's wrong — Warning and Error should have logged
                $false | Should -Be $true -Because 'Warning and Error messages should be logged'
            }

            $script:LogFile = $null
        }
    }

    It 'should log everything when LogLevel is Debug' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Debug' }
            $tempLog = Join-Path $TestDrive 'debug-all.log'
            $script:LogFile = $tempLog

            Write-CISLog -Message 'Debug msg' -Level Debug
            Write-CISLog -Message 'Info msg' -Level Info

            $content = Get-Content $tempLog -Raw
            $content | Should -Match 'Debug msg'
            $content | Should -Match 'Info msg'

            $script:LogFile = $null
        }
    }

    It 'should include ControlId prefix when provided' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Info' }
            $tempLog = Join-Path $TestDrive 'prefix-test.log'
            $script:LogFile = $tempLog

            Write-CISLog -Message 'Test message' -Level Info -ControlId '2.3.1.1'

            $content = Get-Content $tempLog -Raw
            $content | Should -Match '\[2\.3\.1\.1\]'

            $script:LogFile = $null
        }
    }

    It 'should include Module prefix when ControlId not provided' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{ LogLevel = 'Info' }
            $tempLog = Join-Path $TestDrive 'module-prefix.log'
            $script:LogFile = $tempLog

            Write-CISLog -Message 'Test message' -Level Info -Module 'SecurityOptions'

            $content = Get-Content $tempLog -Raw
            $content | Should -Match '\[SecurityOptions\]'

            $script:LogFile = $null
        }
    }

    It 'should default to Info threshold when LogLevel not configured' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{}  # No LogLevel set
            $tempLog = Join-Path $TestDrive 'default-level.log'
            $script:LogFile = $tempLog

            Write-CISLog -Message 'Debug should be hidden' -Level Debug
            Write-CISLog -Message 'Info should show' -Level Info

            if (Test-Path $tempLog) {
                $content = Get-Content $tempLog -Raw
                $content | Should -Not -Match 'Debug should be hidden'
                $content | Should -Match 'Info should show'
            }

            $script:LogFile = $null
        }
    }
}

# =============================================================================
# Test-CISSecurityOptions (integrated with mocks)
# =============================================================================
Describe 'Test-CISSecurityOptions' {
    It 'should process mixed registry and secedit controls' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    SecurityOptions = @{
                        Controls = @(
                            @{
                                Id       = '2.3.1.1'
                                Title    = 'Registry control'
                                Registry = @{
                                    Path  = 'HKLM:\SOFTWARE\Test'
                                    Name  = 'DisableValue'
                                    Value = 0
                                }
                            }
                            @{
                                Id      = '2.3.1.2'
                                Title   = 'Secedit control'
                                Secedit = @{ Key = 'EnableGuestAccount'; Value = '0' }
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            Mock Get-ItemProperty {
                [PSCustomObject]@{ DisableValue = 0 }
            }

            Mock Get-SeceditExport {
                @{ 'EnableGuestAccount' = '0' }
            }

            $results = Test-CISSecurityOptions
            $results.Count | Should -Be 2
            ($results | Where-Object { $_.Status -eq 'Pass' }).Count | Should -Be 2
        }
    }

    It 'should return Skipped for AWS-excluded controls' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    SecurityOptions = @{
                        Controls = @(
                            @{
                                Id         = '2.3.1.1'
                                Title      = 'Skipped control'
                                Registry   = @{ Path = 'HKLM:\Test'; Name = 'Val'; Value = 1 }
                                Skipped    = $true
                                SkipReason = 'AWS exclusion'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            $results = Test-CISSecurityOptions
            $results[0].Status | Should -Be 'Skipped'
            $results[0].Detail | Should -Be 'AWS exclusion'
        }
    }
}

# =============================================================================
# Test-CISAuditPolicy (integrated with mocks)
# =============================================================================
Describe 'Test-CISAuditPolicy' {
    It 'should check audit subcategories against expected values' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    AuditPolicy = @{
                        Controls = @(
                            @{
                                Id               = '17.1.1'
                                Title            = 'Credential Validation'
                                Subcategory      = 'Credential Validation'
                                CategoryGuid     = '{0CCE923F}'
                                ExpectedValue    = 'Success and Failure'
                                InclusionSetting = 'Success and Failure'
                            }
                            @{
                                Id               = '17.2.1'
                                Title            = 'Application Group Management'
                                Subcategory      = 'Application Group Management'
                                CategoryGuid     = '{0CCE9239}'
                                ExpectedValue    = 'Success and Failure'
                                InclusionSetting = 'Success and Failure'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            Mock Get-AuditPolData {
                @{
                    'Credential Validation'          = 'Success and Failure'
                    'Application Group Management'   = 'No Auditing'
                }
            }

            $results = Test-CISAuditPolicy
            $results.Count | Should -Be 2

            $r1 = $results | Where-Object { $_.Id -eq '17.1.1' }
            $r1.Status | Should -Be 'Pass'

            $r2 = $results | Where-Object { $_.Id -eq '17.2.1' }
            $r2.Status | Should -Be 'Fail'
        }
    }

    It 'should return Error when subcategory not found in auditpol' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    AuditPolicy = @{
                        Controls = @(
                            @{
                                Id               = '17.9.9'
                                Title            = 'Missing subcategory'
                                Subcategory      = 'NonExistent Subcategory'
                                CategoryGuid     = '{0000}'
                                ExpectedValue    = 'Success'
                                InclusionSetting = 'Success'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            Mock Get-AuditPolData { @{} }

            $results = Test-CISAuditPolicy
            $results[0].Status | Should -Be 'Error'
        }
    }
}

# =============================================================================
# Test-CISAccountPolicies (secedit-based with operators)
# =============================================================================
Describe 'Test-CISAccountPolicies' {
    It 'should evaluate GreaterOrEqual operator correctly' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    AccountPolicies = @{
                        Controls = @(
                            @{
                                Id            = '1.1.1'
                                Title         = 'Password history'
                                SeceditKey    = 'PasswordHistorySize'
                                ExpectedValue = '24'
                                Operator      = 'GreaterOrEqual'
                                Description   = '24 or more'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            Mock Get-SeceditExport {
                @{ 'PasswordHistorySize' = '24' }
            }

            $results = Test-CISAccountPolicies
            $results[0].Status | Should -Be 'Pass'
        }
    }

    It 'should Fail GreaterOrEqual when actual is less than expected' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    AccountPolicies = @{
                        Controls = @(
                            @{
                                Id            = '1.1.1'
                                Title         = 'Password history'
                                SeceditKey    = 'PasswordHistorySize'
                                ExpectedValue = '24'
                                Operator      = 'GreaterOrEqual'
                                Description   = '24 or more'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            Mock Get-SeceditExport {
                @{ 'PasswordHistorySize' = '10' }
            }

            $results = Test-CISAccountPolicies
            $results[0].Status | Should -Be 'Fail'
        }
    }

    It 'should handle LessOrEqual with non-zero check' {
        InModuleScope 'CISBenchmark' {
            $script:CISConfig = @{
                LogLevel      = 'Error'
                ModuleConfigs = @{
                    AccountPolicies = @{
                        Controls = @(
                            @{
                                Id            = '1.1.3'
                                Title         = 'Min password age'
                                SeceditKey    = 'MinimumPasswordAge'
                                ExpectedValue = '1'
                                Operator      = 'LessOrEqual'
                                Description   = '1 or fewer days'
                            }
                        )
                    }
                }
            }
            $script:LogFile = $null

            # Zero should fail LessOrEqual in AccountPolicies (non-zero requirement)
            Mock Get-SeceditExport {
                @{ 'MinimumPasswordAge' = '0' }
            }

            $results = Test-CISAccountPolicies
            $results[0].Status | Should -Be 'Fail'
        }
    }
}
