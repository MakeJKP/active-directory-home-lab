# Scripts

PowerShell scripts used to build and administer the lab domain. Each script has comment-based help, so `Get-Help .\ScriptName.ps1 -Full` describes its parameters and behavior.

| Script | Purpose |
|---|---|
| `New-LabUsers.ps1` | Bulk-creates Active Directory users from a CSV, placing each in the OU matching their department |
| `newusers.csv` | Sample input file for the provisioning script |

## Requirements

- Windows Server with the AD DS role installed, or a workstation with the Remote Server Administration Tools
- The `ActiveDirectory` PowerShell module
- Department OUs must exist before provisioning; a department with no matching OU will fail to resolve as a target path
- Execution policy set to allow local scripts:

```powershell
Set-ExecutionPolicy RemoteSigned
```

## Usage

```powershell
.\New-LabUsers.ps1
```

Runs against the default CSV path and OU structure. To point it at a different input file or domain:

```powershell
.\New-LabUsers.ps1 -CsvPath "C:\Scripts\newhires-october.csv"
```

## Notes

These scripts target the lab domain `lab.local` by default. The distinguished names and domain suffix are exposed as parameters, so they can be pointed at a different domain without editing the script body.

The provisioning script sets a known default password for lab purposes. This is appropriate for a disposable test environment and is not how credentials should be handled in production, where the password would come from a credential store or be generated per account. See the Production Considerations section of the [Active Directory documentation](../docs/DC01_Powershell.md) for details.
