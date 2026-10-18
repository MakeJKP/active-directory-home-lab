## Active Directory User Provisioning and OU Structure

*Confirmed the starting state of the directory. Only the three built-in accounts existed at this point.*
```powershell
  Get-ADUser -Filter * | Select-Object Name, SamAccountName
```

*Created a working folder on DC01 to hold lab scripts and input files.*
```powershell
  New-Item -Path "C:\Scripts" -ItemType Directory
```

*Built the CSV that drives bulk provisioning. Each row represents one new hire.*
```powershell
  @"
  FirstName,LastName,Department
  John,Smith,IT
  Maria,Garcia,HR
  David,Chen,Finance
  Sarah,Johnson,IT
  Michael,Brown,Operations
  "@ | Out-File -FilePath "C:\Scripts\newusers.csv" -Encoding UTF8
```

*Verified the CSV parsed correctly before running anything against the directory.*
```powershell
  Import-Csv C:\Scripts\newusers.csv
```

*Created the organizational unit structure. Users and computers are kept in separate branches, each subdivided by department. Objects are placed in OUs rather than the default CN=Users and CN=Computers containers because Group Policy cannot be linked to a container. The two branches are separated because every GPO contains both a User Configuration and a Computer Configuration section — user settings follow the person to whatever machine they log into, while computer settings stay with the machine regardless of who uses it.*
```powershell
  New-ADOrganizationalUnit -Name "LabUsers" -Path "DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "IT" -Path "OU=LabUsers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "HR" -Path "OU=LabUsers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "Finance" -Path "OU=LabUsers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "Operations" -Path "OU=LabUsers,DC=lab,DC=local"

  New-ADOrganizationalUnit -Name "LabComputers" -Path "DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "IT" -Path "OU=LabComputers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "HR" -Path "OU=LabComputers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "Finance" -Path "OU=LabComputers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "Operations" -Path "OU=LabComputers,DC=lab,DC=local"
```

*Verified the OU hierarchy. Distinguished names confirm the departments are nested inside their parent OU rather than sitting flat at the domain root.*
```powershell
  Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
```

*Allowed locally written scripts to run while still blocking unsigned scripts from the internet.*
```powershell
  Set-ExecutionPolicy RemoteSigned
```

*The provisioning script. It reads the CSV, generates usernames from first initial plus last name, skips accounts that already exist, and places each user in the OU matching their department.*
```powershell
  # New-LabUsers.ps1
  # Creates AD users in bulk from a CSV file

  Import-Module ActiveDirectory

  $DefaultPassword = ConvertTo-SecureString "Welcome2Lab!" -AsPlainText -Force

  $Users = Import-Csv -Path "C:\Scripts\newusers.csv"

  $Created = 0
  $Skipped = 0

  foreach ($User in $Users) {

    $Username = ($User.FirstName.Substring(0,1) + $User.LastName).ToLower()

    $OUPath = "OU=$($User.Department),OU=LabUsers,DC=lab,DC=local"

    if (Get-ADUser -Filter "SamAccountName -eq '$Username'") {
        Write-Warning "$Username Already Exists - Skipping"
        $Skipped++
        continue
    }

    New-ADUser `
        -Name "$($User.FirstName) $($User.LastName)" `
        -GivenName $User.FirstName `
        -Surname $User.LastName `
        -SamAccountName $Username `
        -UserPrincipalName "$Username@lab.local" `
        -Department $User.Department `
        -Path $OUPath `
        -AccountPassword $DefaultPassword `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    Write-Host "Created user: $Username ($($User.Department))" -ForegroundColor Green
    $Created++
  }

  Write-Host "`nDone. Created: $Created  Skipped: $Skipped"
```

*Ran the script from the scripts directory.*
```powershell
  cd C:\Scripts
  .\New-LabUsers.ps1
```

*Verified placement. Each distinguished name shows the user inside the correct department OU.*
```powershell
  Get-ADUser -Filter * | Select-Object Name, DistinguishedName
```

*Ran the script a second time to confirm it is safe to re-run. The existing-account check causes all five users to be skipped rather than erroring or creating duplicates.*
```powershell
  .\New-LabUsers.ps1
```

---

## Domain Join and Client Placement

*Before joining, each client was verified from its own console: DHCP-assigned address within the scope, DNS pointing at the domain controller, LDAP reachable, and the domain name resolving. Port 389 is tested rather than ICMP because it confirms the directory service itself is answering, not merely that the host is up.*
```powershell
  ipconfig /all
  Test-NetConnection 192.168.100.10 -Port 389
  Resolve-DnsName lab.local
```

*Joined each client to the domain. The second client was renamed during the join, since it still carried its default factory hostname and that name would otherwise persist as the computer object name in Active Directory.*
```powershell
  Add-Computer -DomainName "lab.local" -Restart

  Add-Computer -DomainName "lab.local" -NewName "CLIENT02" -Restart
```

*Computer objects land in the default CN=Computers container on join. Both clients were moved into department OUs so that computer-side Group Policy can be targeted, and placed in different OUs so that policy scoping can be demonstrated across separate targets.*
```powershell
  Get-ADComputer CLIENT01 | Move-ADObject -TargetPath "OU=IT,OU=LabComputers,DC=lab,DC=local"
  Get-ADComputer CLIENT02 | Move-ADObject -TargetPath "OU=HR,OU=LabComputers,DC=lab,DC=local"

  Get-ADComputer -Filter * | Select-Object Name, DistinguishedName
```

*Verified the provisioning pipeline end to end by logging into a domain-joined client with one of the scripted accounts. The forced password change prompted on first logon, confirming that the account, its OU placement, and the password policy all took effect as configured.*

---

## Troubleshooting Notes

### Domain join attempted on the domain controller

*`Add-Computer -DomainName "lab.local" -Restart` returned `Cannot add computer 'DC01' to domain 'lab.local' because it is already in that domain.` A domain controller is inherently a member of the domain it hosts, so the join command has nothing to do there. It belongs on member clients only. The error was a reminder to confirm which machine the session is connected to before running a command.*

### Rename refused when the new name matched the current name

*`Add-Computer -DomainName "lab.local" -NewName "Client01" -Restart` failed with `the new name is the same as the current name`, because the machine had already been renamed in an earlier session. The cmdlet aborts the entire operation rather than skipping just the rename, so the domain join did not proceed either. Resolved by running the join without `-NewName`.*

### Host-level and guest-level cmdlets are not interchangeable

*Two errors in the same session came from the same boundary in opposite directions: `Get-ADComputer` run on a client failed because the ActiveDirectory module installs with the AD DS role and does not exist on member workstations, and `Checkpoint-VM` run inside the domain controller failed because Hyper-V cmdlets exist only on the physical host. A guest has no awareness that it is virtualized. Running `hostname` before issuing a command is a reliable way to confirm which machine the session belongs to.*

### Move-ADObject reported the parent as uninstantiated or deleted

*A move failed with `the object's parent is either uninstantiated or deleted`. The target OU existed, but the distinguished name had been typed as `DC=lab=local` rather than `DC=lab,DC=local`. Active Directory cannot distinguish a malformed path from a nonexistent one, so both produce the same not-found error. The error message does identify the source object's current DN, which is useful for determining whether the problem lies with the object being moved or with the destination. Copying distinguished names directly from `Get-ADOrganizationalUnit` output avoids the issue entirely.*

### Users created outside any OU

*The first version of the provisioning script omitted `-Path`, so all accounts landed in the default `CN=Users` container. That container is not an organizational unit and cannot have Group Policy Objects linked to it, which would have blocked all later GPO work. The fix was to build the target OU path from the department field and pass it to `New-ADUser`.*
```powershell
  $OUPath = "OU=$($User.Department),OU=LabUsers,DC=lab,DC=local"
```

### Silent failures from misspelled properties and variables

*`Select-Object Name, DistiguishedName` returned a column of empty `{}` values rather than an error. PowerShell does not validate property names against the object, and it creates any variable it sees on first use, so a typo in either produces no error and no output. Misspelled cmdlet names fail loudly; misspelled properties and variables fail quietly. Cmdlets that write to the directory do validate their targets, which is why a bad `-Path` errors immediately while a bad property name does not. `Get-Member` was used to confirm exact property names on returned objects.*
```powershell
  Get-ADOrganizationalUnit -Filter * | Get-Member
```

### Verifying destructive commands before running them

*`Remove-ADUser -Confirm:$false` suppresses all prompts, so a mis-scoped `-SearchBase` would delete accounts silently. Standard practice adopted here: run the `Get-` and `Where-Object` portion of the pipeline first, confirm the returned set is exactly what is intended, then append the removal cmdlet.*
```powershell
  Get-ADUser -Filter * -SearchBase "CN=Users,DC=lab,DC=local" | Where-Object {$_.Name -notin "Administrator","Guest","krbtgt"} | Select-Object Name

  Get-ADUser -Filter * -SearchBase "CN=Users,DC=lab,DC=local" | Where-Object {$_.Name -notin "Administrator","Guest","krbtgt"} | Remove-ADUser -Confirm:$false
```

---

## Production Considerations

*The default password is hardcoded in the script and committed alongside it. In a production environment this would be sourced from a credential store or generated per account, and the script would accept the CSV path and domain as parameters rather than hardcoding them.*

*Routine administration would be performed from a workstation using the Remote Server Administration Tools rather than by logging into the domain controller directly, since interactive logon to a DC exposes privileged credentials on a system that should have minimal exposure.*
