PowerShell scripts used to build and administer the lab domain. Each script has
comment-based help, so `Get-Help .\ScriptName.ps1 -Full` describes its parameters
and behavior.

| Script | Purpose |
|---|---|
| `New-LabUsers.ps1` | Bulk-creates AD users from a CSV, places each in the OU matching their department, and adds each to the `<Department>-Users` security group |
| `New-LabComputers.ps1` | Pre-stages placeholder computer objects per department for Group Policy targeting and OU-structure demonstration |
| `Disable-LabUser.ps1` | Offboards a user: disables the account, strips group memberships, moves it to a Disabled Users OU, and logs the action (supports `-WhatIf`) |
| `Test-LabGroupMembership.ps1` | Audits whether each user is a member of their department group and reports any drift |
| `newusers.csv` | Sample input file for `New-LabUsers.ps1` (FirstName, LastName, Department) |

## Requirements

- Windows Server with the AD DS role installed, or a workstation with the Remote
  Server Administration Tools
- The `ActiveDirectory` PowerShell module
- The department OUs and the `<Department>-Users` security groups must exist before
  provisioning; a department with no matching OU or group is reported per-user
- Execution policy set to allow local scripts:

```powershell
Set-ExecutionPolicy RemoteSigned
```

## Usage

Provision users and ensure group membership:

```powershell
.\New-LabUsers.ps1
```

Runs against the default CSV path and OU structure. Point it at a different input
file or domain with parameters:

```powershell
.\New-LabUsers.ps1 -CsvPath "C:\Scripts\newhires-october.csv"
```

Pre-stage computer objects (5 per department by default):

```powershell
.\New-LabComputers.ps1
```

Audit group-membership drift, showing only users missing from their group:

```powershell
.\Test-LabGroupMembership.ps1 | Where-Object MissingFromGroup
```

Offboard a user — preview first with `-WhatIf`, then run for real:

```powershell
.\Disable-LabUser.ps1 -Identity jsmith -WhatIf
.\Disable-LabUser.ps1 -Identity jsmith
```

## Notes

These scripts target the lab domain `lab.local` by default. Distinguished names and
the domain suffix are exposed as parameters, so they can be pointed at a different
domain without editing the script body.

`New-LabUsers.ps1` is idempotent for both account creation and group membership:
re-running it skips existing accounts and adds any missing department-group
memberships, so it repairs drift rather than only handling new users. This pairs
with `Test-LabGroupMembership.ps1`, which reports that drift.

The provisioning script sets a known default password for lab purposes. This is
appropriate for a disposable test environment and is not how credentials should be
handled in production, where the password would come from a credential store or be
generated per account. See the Production Considerations section of the
[Active Directory documentation](docs/DC01_Powershell.md) for details.
