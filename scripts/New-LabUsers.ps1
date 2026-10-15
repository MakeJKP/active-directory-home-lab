<#
.SYNOPSIS
    Creates Active Directory user accounts in bulk from a CSV file and ensures
    each user's department security-group membership.

.DESCRIPTION
    Reads a CSV containing FirstName, LastName, and Department columns and creates
    one Active Directory user per row.

    Usernames are generated from the first initial plus the last name, lowercased
    (John Smith becomes jsmith). Each user is placed in the organizational unit
    matching their Department value, is required to change their password at first
    logon, and is added to the department security group named "<Department>-Users"
    (for example, IT users are added to IT-Users).

    The script is idempotent in two ways:
      * Account creation checks whether the SamAccountName already exists and skips
        creation if so.
      * Group membership is verified and added on every run, for existing accounts
        as well as newly created ones. Re-running the script therefore repairs
        missing group memberships rather than only handling brand-new users. This
        closes the gap where accounts created before group logic was added would
        otherwise never receive their group membership.

    A summary of created, skipped, group-add, and failed counts is printed at the end.

    The department OUs and the "<Department>-Users" groups must already exist. A
    Department value with no matching OU or group is reported per-user and does not
    stop the run.

.PARAMETER CsvPath
    Path to the input CSV. Defaults to C:\Scripts\newusers.csv.

.PARAMETER ParentOU
    Distinguished name of the OU containing the department OUs and groups.
    Defaults to OU=LabUsers,DC=lab,DC=local.

.PARAMETER UpnSuffix
    Domain suffix used for the UserPrincipalName. Defaults to lab.local.

.EXAMPLE
    .\New-LabUsers.ps1

    Provisions users from the default CSV path into the default OU structure and
    ensures each user's department group membership.

.EXAMPLE
    .\New-LabUsers.ps1 -CsvPath "C:\Scripts\newhires-october.csv"

    Provisions users from an alternate input file.

.NOTES
    Must be run on a domain controller, or on a workstation with the Remote Server
    Administration Tools installed, since it depends on the ActiveDirectory module.

    The default password is defined in this script for lab purposes. In a production
    environment it should be sourced from a credential store or generated per
    account rather than committed to source control.
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

$Created  = 0
$Skipped  = 0
$Grouped  = 0
$Failed   = 0

foreach ($User in $Users) {

    # Guard against blank rows / empty required fields
    if ([string]::IsNullOrWhiteSpace($User.FirstName) -or
        [string]::IsNullOrWhiteSpace($User.LastName)  -or
        [string]::IsNullOrWhiteSpace($User.Department)) {
        Write-Warning "Skipping row with missing FirstName, LastName, or Department."
        $Failed++
        continue
    }

    $Username  = ($User.FirstName.Substring(0,1) + $User.LastName).ToLower()
    $OUPath    = "OU=$($User.Department),$ParentOU"
    $GroupName = "$($User.Department)-Users"

    # --- Create the account if it does not already exist ---
    if (Get-ADUser -Filter "SamAccountName -eq '$Username'") {
        Write-Warning "$Username already exists - skipping creation"
        $Skipped++
    }
    else {
        $params = @{
            Name                  = "$($User.FirstName) $($User.LastName)"
            GivenName             = $User.FirstName
            Surname               = $User.LastName
            SamAccountName        = $Username
            UserPrincipalName     = "$Username@$UpnSuffix"
            Department            = $User.Department
            Path                  = $OUPath
            AccountPassword       = $DefaultPassword
            ChangePasswordAtLogon = $true
            Enabled               = $true
            ErrorAction           = "Stop"
        }

        try {
            New-ADUser @params
            Write-Host "Created user: $Username ($($User.Department))" -ForegroundColor Green
            $Created++
        }
        catch {
            Write-Warning "Failed to create $Username - $($_.Exception.Message)"
            $Failed++
            continue   # no point attempting group membership if creation failed
        }
    }

    # --- Ensure department group membership (idempotent; runs for new and existing) ---
    try {
        $isMember = Get-ADGroupMember -Identity $GroupName -ErrorAction Stop |
                    Where-Object { $_.SamAccountName -eq $Username }

        if (-not $isMember) {
            Add-ADGroupMember -Identity $GroupName -Members $Username -ErrorAction Stop
            Write-Host "  added $Username to $GroupName" -ForegroundColor Cyan
            $Grouped++
        }
    }
    catch {
        Write-Warning "Group membership for $Username ($GroupName) failed - $($_.Exception.Message)"
    }
}

Write-Host "`nDone. Created: $Created  Skipped: $Skipped  GroupAdds: $Grouped  Failed: $Failed"
