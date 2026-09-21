<#
.SYNOPSIS
    Offboards an Active Directory user: disables the account, strips group
    memberships, moves it to a Disabled Users OU, and logs the action.

.DESCRIPTION
    Performs the standard technical steps of user offboarding as a single,
    logged, repeatable operation:

      1. Disables the account so it can no longer authenticate.
      2. Records and removes all group memberships except the primary group
         (Domain Users), which cannot be removed with Remove-ADGroupMember.
      3. Moves the object into a Disabled Users OU, out of the department OUs, so
         disabled accounts are visibly segregated and no longer inherit department
         policy.
      4. Appends a timestamped record (user, removed groups, original DN) to a log
         file, so the action is auditable.

    Timely deprovisioning and revocation of access is a control auditors test
    directly (for example SOC 2 Common Criteria CC6). Doing it by script makes the
    steps consistent and the outcome evidenced.

    The function supports -WhatIf, so the full set of changes can be previewed
    before anything is modified.

.PARAMETER Identity
    SamAccountName of the user to offboard.

.PARAMETER DisabledOU
    Distinguished name of the target OU for disabled accounts.
    Defaults to OU=Disabled Users,DC=lab,DC=local.

.PARAMETER LogPath
    Path to the append-only action log (CSV). Defaults to
    C:\Scripts\offboarding-log.csv.

.EXAMPLE
    .\Disable-LabUser.ps1 -Identity jsmith

    Offboards jsmith: disables, strips groups, moves to Disabled Users, and logs.

.EXAMPLE
    .\Disable-LabUser.ps1 -Identity jsmith -WhatIf

    Shows exactly what would be disabled, removed, and moved without making changes.

.NOTES
    Must be run on a domain controller, or on a workstation with the Remote Server
    Administration Tools installed, since it depends on the ActiveDirectory module.

    The Disabled Users OU must already exist.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    [string]$DisabledOU = "OU=Disabled Users,DC=lab,DC=local",

    [string]$LogPath    = "C:\Scripts\offboarding-log.csv"
)

Import-Module ActiveDirectory

# --- Resolve the user ---
try {
    $User = Get-ADUser -Identity $Identity -Properties MemberOf, DistinguishedName -ErrorAction Stop
}
catch {
    Write-Error "User '$Identity' not found: $($_.Exception.Message)"
    return
}

$OriginalDN = $User.DistinguishedName

# --- 1. Disable the account ---
if ($PSCmdlet.ShouldProcess($Identity, "Disable account")) {
    Disable-ADAccount -Identity $User
    Write-Host "Disabled account: $Identity" -ForegroundColor Yellow
}

# --- 2. Remove group memberships (except the primary group, Domain Users) ---
$Groups = Get-ADPrincipalGroupMembership -Identity $User |
          Where-Object { $_.Name -ne "Domain Users" }

$RemovedGroups = @()
foreach ($Group in $Groups) {
    if ($PSCmdlet.ShouldProcess("$Identity", "Remove from group $($Group.Name)")) {
        try {
            Remove-ADGroupMember -Identity $Group -Members $User -Confirm:$false -ErrorAction Stop
            Write-Host "  removed from $($Group.Name)" -ForegroundColor Cyan
            $RemovedGroups += $Group.Name
        }
        catch {
            Write-Warning "  could not remove from $($Group.Name) - $($_.Exception.Message)"
        }
    }
}

# --- 3. Move to the Disabled Users OU ---
if ($PSCmdlet.ShouldProcess($Identity, "Move to $DisabledOU")) {
    try {
        Move-ADObject -Identity $OriginalDN -TargetPath $DisabledOU -ErrorAction Stop
        Write-Host "  moved to $DisabledOU" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "  move failed - $($_.Exception.Message)"
    }
}

# --- 4. Log the action ---
if ($PSCmdlet.ShouldProcess($LogPath, "Append offboarding record")) {
    $record = [PSCustomObject]@{
        Timestamp     = (Get-Date).ToString("s")
        SamAccountName = $Identity
        RemovedGroups = ($RemovedGroups -join ";")
        OriginalDN    = $OriginalDN
        DisabledOU    = $DisabledOU
    }
    $record | Export-Csv -Path $LogPath -Append -NoTypeInformation
    Write-Host "  logged to $LogPath" -ForegroundColor Cyan
}

Write-Host "`nOffboarding complete for $Identity."

