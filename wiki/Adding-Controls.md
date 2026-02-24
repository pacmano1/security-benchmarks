# Adding Controls

This guide explains how to add new CIS controls to existing modules and how to create entirely new modules.

---

## Adding a Control to an Existing Module

Most CIS controls can be added by editing a `.psd1` config file — **no code changes required** for registry-based, secedit-based, audit policy, or service controls.

### Step 1: Identify the Mechanism

| If the CIS control is... | Add to | Mechanism |
|---|---|---|
| A registry value | The appropriate module's `.psd1` | Registry |
| A security policy setting | `SecurityOptions.psd1` or `UserRightsAssignment.psd1` | Secedit |
| An audit subcategory | `AuditPolicy.psd1` | AuditPol |
| A service startup type | `Services.psd1` | Service |
| A user-level (HKCU) registry value | `AdminTemplatesUser.psd1` | Registry |

### Step 2: Add the Control Definition

#### Registry-Based Control

Open the module's `.psd1` file and add a new hashtable to the `Controls` array:

```powershell
@{
    Id          = '18.9.99.1'                    # CIS control ID
    Title       = 'My New Control Title'          # From the CIS benchmark document
    Description = 'Optional detailed description'
    Registry    = @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\MyFeature'
        Name  = 'MySettingName'
        Type  = 'DWord'                           # DWord, String, MultiString, etc.
        Value = 1                                  # Expected compliant value
    }
}
```

**With a comparison operator:**

```powershell
@{
    Id       = '18.9.99.2'
    Title    = 'My Timeout Setting'
    Description = '300 seconds or fewer'
    Registry = @{
        Path     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\MyFeature'
        Name     = 'TimeoutSeconds'
        Type     = 'DWord'
        Value    = 300
        Operator = 'LessOrEqual'
        MinValue = 1                  # Actual must be >= 1 (not 0)
    }
}
```

#### Secedit-Based Control (Security Options)

```powershell
@{
    Id      = '2.3.99.1'
    Title   = 'My Security Option'
    Secedit = @{
        Key   = 'MySecurityPolicyKey'
        Value = '1'
    }
}
```

#### Secedit-Based Control (User Rights Assignment)

```powershell
@{
    Id            = '2.2.99'
    Title         = 'My Privilege Assignment'
    SeceditKey    = 'SeMyPrivilege'
    ExpectedValue = '*S-1-5-32-544'           # Comma-separated SIDs
    Description   = 'Administrators'
}
```

#### Audit Policy Control

```powershell
@{
    Id               = '17.99.1'
    Title            = 'Audit My Subcategory'
    Subcategory      = 'My Subcategory'                             # Exact name from auditpol
    CategoryGuid     = '{00000000-0000-0000-0000-000000000000}'     # GUID from auditpol /list /subcategory:*
    ExpectedValue    = 'Success and Failure'
    InclusionSetting = 'Success and Failure'
}
```

To find the GUID:
```powershell
auditpol /list /subcategory:* /v
```

#### Service Control

```powershell
@{
    Id          = '5.99'
    Title       = 'My Unnecessary Service (MyServiceName)'
    ServiceName = 'MyServiceName'     # Actual Windows service name
    StartType   = 'Disabled'          # Disabled, Manual, or Auto
}
```

### Step 3: Test

```powershell
# Verify the config file still parses
Import-PowerShellDataFile -Path .\config\modules\AdminTemplates.psd1

# Run audit for that module
.\scripts\Invoke-CISAudit.ps1 -Modules AdminTemplates

# Check the new control appears in the report
```

### Step 4: Add AWS Exclusions (If Needed)

If the new control must be skipped or modified in AWS:

Edit `config/aws-exclusions.psd1`:

```powershell
# To skip entirely
Skip = @(
    ...existing...
    '18.9.99.1'    # My control — must be skipped because...
)

# To apply with a different value
Modify = @{
    ...existing...
    '18.9.99.2' = 600    # Use 600 instead of 300 because...
}
```

---

## Creating a New Module

To add an entirely new CIS section:

### Step 1: Create the Config File

Create `config/modules/MyNewModule.psd1`:

```powershell
@{
    ModuleName = 'MyNewModule'
    CISSection = '99'
    Mechanism  = 'Registry'     # Registry, Secedit, AuditPol, Service

    Controls = @(
        @{
            Id       = '99.1'
            Title    = 'First Control'
            Registry = @{
                Path  = 'HKLM:\SOFTWARE\...'
                Name  = 'SettingName'
                Type  = 'DWord'
                Value = 1
            }
        }
    )
}
```

### Step 2: Create the Module Directory

```
src/Modules/MyNewModule/
    Test-CISMyNewModule.ps1
    Set-CISMyNewModule.ps1
```

### Step 3: Create the Audit Function

`src/Modules/MyNewModule/Test-CISMyNewModule.ps1`:

```powershell
function Test-CISMyNewModule {
    [CmdletBinding()]
    param()

    $moduleName = 'MyNewModule'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) {
        Write-CISLog -Message 'No controls loaded for MyNewModule' -Level Warning -Module $moduleName
        return @()
    }

    $results = foreach ($ctl in $controls) {
        if ($ctl.Skipped) {
            [PSCustomObject]@{
                Id = $ctl.Id; Title = $ctl.Title; Module = $moduleName
                Status = 'Skipped'; Expected = ''; Actual = ''; Detail = $ctl.SkipReason
            }
            continue
        }

        try {
            # Use existing helpers for standard mechanisms:
            Test-RegistryControl -Control $ctl -ModuleName $moduleName
        } catch {
            [PSCustomObject]@{
                Id = $ctl.Id; Title = $ctl.Title; Module = $moduleName
                Status = 'Error'; Expected = ''; Actual = ''; Detail = $_.Exception.Message
            }
        }
    }

    return $results
}
```

### Step 4: Create the Apply Function

`src/Modules/MyNewModule/Set-CISMyNewModule.ps1`:

```powershell
function Set-CISMyNewModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GpoName,
        [bool]$DryRun = $true
    )

    $moduleName = 'MyNewModule'
    $controls   = $script:CISConfig.ModuleConfigs[$moduleName].Controls
    if (-not $controls) { return }

    foreach ($ctl in ($controls | Where-Object { -not $_.Skipped -and $_.Registry })) {
        $reg   = $ctl.Registry
        $value = Get-AWSModifiedValue -ControlId $ctl.Id -DefaultValue $reg.Value
        $gpRegPath = $reg.Path -replace '^HKLM:\\', 'HKLM\'

        if ($DryRun) {
            Write-CISLog -Message "[DRY RUN] Would set $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
        } else {
            Set-GPRegistryValue -Name $GpoName -Key $gpRegPath -ValueName $reg.Name -Type $reg.Type -Value $value
            Write-CISLog -Message "Set $gpRegPath\$($reg.Name) = $value" -Level Info -ControlId $ctl.Id
        }
    }
}
```

### Step 5: Register the Module

1. **Add to master-config.psd1:**
   ```powershell
   Modules = @{
       ...existing...
       MyNewModule = $true
   }
   ```

2. **Add to CISBenchmark.psd1 FunctionsToExport:**
   ```powershell
   'Test-CISMyNewModule'
   'Set-CISMyNewModule'
   ```

3. **Add to CISBenchmark.psm1 moduleNames array:**
   ```powershell
   $moduleNames = @(
       ...existing...
       'MyNewModule'
   )
   ```

4. **Add to Invoke-CISApply.ps1 $applyOrder array** (choose appropriate position).

### Step 6: Add Tests

Add to `tests/CISBenchmark.Tests.ps1`:
- Add `'MyNewModule'` to the `$expectedModules` array in the config tests
- Add `'MyNewModule'` to the function export tests

### Step 7: Verify

```powershell
# Reimport module
Import-Module .\src\CISBenchmark.psm1 -Force

# Check functions exist
Get-Command Test-CISMyNewModule, Set-CISMyNewModule

# Run audit
.\scripts\Invoke-CISAudit.ps1 -Modules MyNewModule

# Run Pester
Invoke-Pester .\tests\CISBenchmark.Tests.ps1
```

---

## Tips

- **Look up registry paths** in the CIS benchmark PDF — they're documented for every control
- **Use `gpedit.msc`** to find the exact registry path for Administrative Template settings
- **Check `auditpol /list /subcategory:* /v`** for audit subcategory names and GUIDs
- **Test one control at a time** — add it, audit, verify, then add more
- **Keep IDs unique** across the module — the Pester tests validate this
