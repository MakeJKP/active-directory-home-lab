<#
.SYNOPSIS
    Audits whether each lab user is a member of their department security group,
    reporting any drift.

.DESCRIPTION
    For every user under the LabUsers OU branch, the script determines the expected
    department group ("<Department>-Users") from the user's Department attribute and
    checks whether the user is actually a member of it. It emits one object per user
    with an IsMember / MissingFromGroup result, so the output can be filtered,
    formatted as a table, or exported to CSV as audit evidence.

    This is a drift-detection companion to New-LabUsers.ps1: provisioning ensures
    membership at creation time, and this script confirms it has not drifted since.

.PARAMETER ParentOU
    Distinguished name of the OU containing the department user OUs.
    Defaults to OU=LabUsers,DC=lab,DC=local.

.PARAMETER CsvPath
    Optional path. If supplied, the full report is also written to this CSV.

.EXAMPLE
    .\Test-LabGroupMembership.ps1 | Format-Table -AutoSize

    Shows every user's expected group and whether they are a member.

.EXAMPLE
    .\Test-LabGroupMembership.ps1 | Where-Object MissingFromGroup

    Shows only the users that are missing from their department group.

.EXAMPLE
    .\Test-LabGroupMembership.ps1 -CsvPath C:\Scripts\group-audit.csv

    Runs the audit and also writes the full report to a CSV.

.NOTES
    Must be run on a domain controller, or on a workstation with the Remote Server
    Administration Tools installed, since it depends on the ActiveDirectory module.
#>

[CmdletBinding()]
param(
    [string]$ParentOU = "OU=LabUsers,DC=lab,DC=local",
    [string]$CsvPath
)

Import-Module ActiveDirectory

$Users = Get-ADUser -Filter * -SearchBase $ParentOU -Properties Department, MemberOf

$Report = foreach ($User in $Users) {

    $Dept = $User.Department

    if ([string]::IsNullOrWhiteSpace($Dept)) {
        [PSCustomObject]@{
            Name             = $User.Name
            SamAccountName   = $User.SamAccountName
            Department       = "(none)"
            ExpectedGroup    = "(unknown)"
            IsMember         = $false
            MissingFromGroup = $true
        }
        continue
    }

    $ExpectedGroup = "$Dept-Users"

    # Resolve the expected group's DN, then test membership against MemberOf
    $GroupDN = (Get-ADGroup -Filter "Name -eq '$ExpectedGroup'" -ErrorAction SilentlyContinue).DistinguishedName
    $IsMember = $false
    if ($GroupDN) {
        $IsMember = $User.MemberOf -contains $GroupDN
    }

    [PSCustomObject]@{
        Name             = $User.Name
        SamAccountName   = $User.SamAccountName
        Department       = $Dept
        ExpectedGroup    = $ExpectedGroup
        IsMember         = $IsMember
        MissingFromGroup = (-not $IsMember)
    }
}

if ($CsvPath) {
    $Report | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "Report written to $CsvPath" -ForegroundColor Cyan
}

$Report

