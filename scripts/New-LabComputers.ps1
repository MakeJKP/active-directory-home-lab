<#
.SYNOPSIS
    Pre-stages Active Directory computer accounts per department for Group Policy
    targeting and OU-structure demonstration.

.DESCRIPTION
    Creates placeholder computer objects in each department's computer OU, so that
    computer-side Group Policy targeting and reporting can be demonstrated at a
    realistic scale without building a virtual machine for every object.

    Names are built from a short per-department prefix plus a zero-padded number
    (IT-PC01, HR-PC01, Fin-PC01, Ops-PC01, ...). Short prefixes keep names within
    the 15-character NetBIOS limit.

    These objects are pre-staged only: they intentionally have no DNSHostName set.
    A populated DNSHostName is the tell that distinguishes a real, domain-joined
    machine (such as CLIENT01) from a placeholder created here.

    The script is idempotent — a computer account that already exists is skipped
    rather than recreated.

.PARAMETER CountPerDept
    Number of computer objects to create per department. Defaults to 5.

.PARAMETER ParentOU
    Distinguished name of the OU containing the department computer OUs.
    Defaults to OU=LabComputers,DC=lab,DC=local.

.EXAMPLE
    .\New-LabComputers.ps1

    Creates 5 placeholder computers in each department computer OU.

.EXAMPLE
    .\New-LabComputers.ps1 -CountPerDept 3

    Creates 3 placeholder computers per department.

.NOTES
    Must be run on a domain controller, or on a workstation with the Remote Server
    Administration Tools installed, since it depends on the ActiveDirectory module.

    Real machines are joined to the domain normally and moved into their department
    OU; this script does not replace domain join. It only fills out the directory so
    policy scoping and reporting have realistic targets to act on.
#>

[CmdletBinding()]
param(
    [int]$CountPerDept = 5,
    [string]$ParentOU  = "OU=LabComputers,DC=lab,DC=local"
)

Import-Module ActiveDirectory

# Department -> short NetBIOS-safe prefix
$Departments = @{
    "IT"         = "IT"
    "HR"         = "HR"
    "Finance"    = "Fin"
    "Operations" = "Ops"
}

$Created = 0
$Skipped = 0
$Failed  = 0

foreach ($Dept in $Departments.Keys) {

    $Prefix = $Departments[$Dept]
    $OUPath = "OU=$Dept,$ParentOU"

    foreach ($n in 1..$CountPerDept) {

        $Name = "{0}-PC{1:D2}" -f $Prefix, $n   # e.g. IT-PC01

        if (Get-ADComputer -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue) {
            Write-Warning "$Name already exists - skipping"
            $Skipped++
            continue
        }

        try {
            New-ADComputer -Name $Name -SAMAccountName $Name -Path $OUPath -Enabled $true -ErrorAction Stop
            Write-Host "Created computer: $Name ($Dept)" -ForegroundColor Green
            $Created++
        }
        catch {
            Write-Warning "Failed to create $Name - $($_.Exception.Message)"
            $Failed++
        }
    }
}

Write-Host "`nDone. Created: $Created  Skipped: $Skipped  Failed: $Failed"

