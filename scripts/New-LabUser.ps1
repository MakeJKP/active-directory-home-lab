<#
.SYNOPSIS
    Creates Active Directory user accounts in bulk from a CSV file.

.DESCRIPTION
    Reads a CSV containing FirstName, LastName, and Department columns and creates
    one Active Directory user per row.

    Usernames are generated from the first initial plus the last name, lowercased
    (John Smith becomes jsmith). Each user is placed in the organizational unit
    matching their Department value, and is required to change their password at
    first logon.

    The script is idempotent. Before creating an account it checks whether the
    SamAccountName already exists, and skips it if so, reporting a count of
    created and skipped accounts at the end. This makes the script safe to
    re-run against a partially provisioned directory.

    The department OUs must already exist. A Department value with no matching
    OU will cause that user's creation to fail, since the target path will not
    resolve.

.PARAMETER CsvPath
    Path to the input CSV. Defaults to C:\Scripts\newusers.csv.

.PARAMETER ParentOU
    Distinguished name of the OU containing the department OUs.
    Defaults to OU=LabUsers,DC=lab,DC=local.

.PARAMETER UpnSuffix
    Domain suffix used for the UserPrincipalName. Defaults to lab.local.

.EXAMPLE
    .\New-LabUsers.ps1

    Provisions users from the default CSV path into the default OU structure.

.EXAMPLE
    .\New-LabUsers.ps1 -CsvPath "C:\Scripts\newhires-october.csv"

    Provisions users from an alternate input file.

.NOTES
    Must be run on a domain controller, or on a workstation with the Remote
    Server Administration Tools installed, since it depends on the
    ActiveDirectory module.

    The default password is defined in this script for lab purposes. In a
    production environment it should be sourced from a credential store or
    generated per account rather than committed to source control.
#>

[CmdletBinding()]
param(
    [string]$CsvPath   = "C:\Scripts\newusers.csv",
    [string]$ParentOU  = "OU=LabUsers,DC=lab,DC=local",
    [string]$UpnSuffix = "lab.local"
)

Import-Module ActiveDirectory

$DefaultPassword = ConvertTo-SecureString "Welcome2Lab!" -AsPlainText -Force

if (-not (Test-Path $CsvPath)) {
    Write-Error "Input file not found: $CsvPath"
    return
}

$Users = Import-Csv -Path $CsvPath

$Created = 0
$Skipped = 0
$Failed  = 0

foreach ($User in $Users) {

    $Username = ($User.FirstName.Substring(0,1) + $User.LastName).ToLower()

    $OUPath = "OU=$($User.Department),$ParentOU"

    if (Get-ADUser -Filter "SamAccountName -eq '$Username'") {
        Write-Warning "$Username already exists - skipping"
        $Skipped++
        continue
    }

    try {
        New-ADUser `
            -Name "$($User.FirstName) $($User.LastName)" `
            -GivenName $User.FirstName `
            -Surname $User.LastName `
            -SamAccountName $Username `
            -UserPrincipalName "$Username@$UpnSuffix" `
            -Department $User.Department `
            -Path $OUPath `
            -AccountPassword $DefaultPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -ErrorAction Stop

        Write-Host "Created user: $Username ($($User.Department))" -ForegroundColor Green
        $Created++
    }
    catch {
        Write-Warning "Failed to create $Username - $($_.Exception.Message)"
        $Failed++
    }
}

Write-Host "`nDone. Created: $Created  Skipped: $Skipped  Failed: $Failed"
