**Active Directory User Provisioning and OU Structure**

*Confirmed the starting state of the directory. Only the three built-in accounts existed at this point.*
  ```powershell
  Get-ADUser -Filter * | Select-Object Name, SamAccountName
  ```

*Created a working folder on DC01 to hold lab scripts and input files.*
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

*Created the organizational unit structure. A parent OU holds one child OU per department. Users are placed in OUs rather than the default Users container because Group Policy cannot be linked to a container.*
  ```powershell
  New-ADOrganizationalUnit -Name "LabUsers" -Path "DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "IT" -Path "OU=LabUsers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "HR" -Path "OU=LabUsers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "Finance" -Path "OU=LabUsers,DC=lab,DC=local"
  New-ADOrganizationalUnit -Name "Operations" -Path "OU=LabUsers,DC=lab,DC=local"
  ```

*Verified the OU hierarchy. Distinguished names confirm the departments are nested inside LabUsers rather than sitting flat at the domain root.*
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

*Bulk removal command used to reset the lab between provisioning tests. Scoped to the Users container and excludes built-in accounts. The read-only version was run first to confirm the target set before deleting.*
  ```powershell
  Get-ADUser -Filter * -SearchBase "CN=Users,DC=lab,DC=local" | Where-Object {$_.Name -notin "Administrator","Guest","krbtgt"} | Select-Object Name

  Get-ADUser -Filter * -SearchBase "CN=Users,DC=lab,DC=local" | Where-Object {$_.Name -notin "Administrator","Guest","krbtgt"} | Remove-ADUser -Confirm:$false
  ```

  **Troubleshooting Notes**

**Domain join attempted on the domain controller**

*Add-Computer -DomainName "lab.local" -Restart returned Cannot add computer 'DC01' to domain 'lab.local' because it is already in that domain. A domain controller is inherently a member of the domain it hosts, so the join command has nothing to do there. It belongs on member clients only. The error was a reminder to check which machine the session is actually connected to before running host-level commands.

**Users created outside any OU**

*The first version of the provisioning script omitted -Path, so all accounts landed in the default CN=Users container. That container is not an organizational unit and cannot have Group Policy Objects linked to it, which would have blocked all later GPO work. The fix was to build the target OU path from the department field and pass it to New-ADUser.*
  ```powershell
  $OUPath = "OU=$($User.Department),OU=LabUsers,DC=lab,DC=local"
  ```
**Silent failures from misspelled properties and variables**

Select-Object Name, DistiguishedName returned a column of empty {} values rather than an error. PowerShell does not validate property names against the object, and it creates any variable it sees on first use, so a typo in either produces no error and no output. Misspelled cmdlet names fail loudly; misspelled properties and variables fail quietly. Get-Member was used to confirm exact property names on returned objects.*
  ```powershell
  Get-ADOrganizationalUnit -Filter * | Get-Member
  ```

**Verifying destructive commands before running them**

*Remove-ADUser -Confirm:$false suppresses all prompts, so a mis-scoped -SearchBase would delete accounts silently. Standard practice adopted here: run the Get- and Where-Object portion of the pipeline first, confirm the returned set is exactly what is intended, then append the removal cmdlet.*

**Production Considerations**

*The default password is hardcoded in the script and committed alongside it. In a production environment this would be sourced from a credential store or generated per account, and the script would accept the CSV path and domain as parameters rather than hardcoding them.*
