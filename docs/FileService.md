# File Services — Group-Driven Shares (AGDLP)

Department file shares hosted on the member server `MS01`, with access granted
entirely through group membership using the **AGDLP** model. No user is ever
named on a folder; access is added or removed by moving a single account in or
out of a group. This is the role-based, least-privilege model auditors expect
(SOC 2 CC6.1–6.3, NIST 800-53 AC-2/AC-3/AC-6, CIS Control 6), and it ties
directly into the [offboarding](Offboarding.md) control — revoking a group
membership removes file access everywhere at once.

The shares live on `MS01` rather than the domain controller on purpose: a DC
should hold directory and identity services, not general file data. Separating
the file-server role onto a member server is both a security boundary and the
normal production topology.

---

## AGDLP — what the model is and why

**AGDLP** = **A**ccount → **G**lobal → **D**omain Local → **P**ermission. It is
Microsoft's prescribed chain for granting resource access:

| Link | Object | In this lab |
|---|---|---|
| **A**ccount | the user | `jsmith` and the other 24 provisioned users |
| **G**lobal group | role / department membership | `IT-Users`, `HR-Users`, `Finance-Users`, `Operations-Users` |
| **D**omain Local group | the thing permissioned on a resource | `SH-IT-Modify`, `SH-HR-Modify`, … |
| **P**ermission | the ACL entry on the folder/share | `SH-<Dept>-Modify` granted Modify |

Users go in global groups (who they are); the resource is permissioned to a
domain-local group (what may touch this folder); the global group is nested into
the domain-local group to connect the two. The permission is granted **once**,
to the domain-local group, and never changes again — all future access
management is membership changes on the global group.

The reason for the extra hop in a single-domain lab is that it is the pattern
that **scales**: in a multi-domain forest, global groups can only contain
principals from their own domain, while domain-local groups can be granted
access across domains. Permissioning the global group directly works here but
breaks the moment a second domain appears. Doing it the AGDLP way shows the
model is understood, not just the shortcut.

---

## Build

### 1. File Server role and folder structure (on MS01)

```powershell
Install-WindowsFeature FS-FileServer

New-Item -ItemType Directory -Force -Path C:\Shares\IT, C:\Shares\HR, C:\Shares\Finance, C:\Shares\Operations
Get-ChildItem C:\Shares
```

All four department folders live under a single `C:\Shares` parent, confirmed
with `Get-ChildItem` before any sharing — see the troubleshooting note below on
why that confirmation matters.

### 2. Domain-local groups (on DC01)

A dedicated `Groups` OU holds the resource-access groups, keeping them out of the
department user/computer OUs:

```powershell
New-ADOrganizationalUnit -Name "Groups" -Path "DC=lab,DC=local"

"IT","HR","Finance","Operations" | ForEach-Object {
    New-ADGroup -Name "SH-$_-Modify" -GroupScope DomainLocal -GroupCategory Security -Path "OU=Groups,DC=lab,DC=local"
    Add-ADGroupMember -Identity "SH-$_-Modify" -Members "$_-Users"
}

Get-ADGroup -Filter 'Name -like "SH-*"' | Select-Object Name, GroupScope
```

The naming convention `SH-<Dept>-<Right>` (`SH` = share, plus the access level)
makes the group's purpose readable at a glance and leaves room for a future
`SH-<Dept>-Read` tier without ambiguity.

![Domain-local SH-* groups created](screenshots/fileservices/ad-groups-domainlocal.png)

### 3. Shares and permissions (on MS01)

```powershell
"IT","HR","Finance","Operations" | ForEach-Object {
    $path = "C:\Shares\$_"
    $grp  = "LAB\SH-$_-Modify"
    New-SmbShare -Name $_ -Path $path -ChangeAccess $grp -FullAccess "LAB\Domain Admins"
    Revoke-SmbShareAccess -Name $_ -AccountName "Everyone" -Force -ErrorAction SilentlyContinue
    icacls $path /inheritance:r | Out-Null
    icacls $path /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "${grp}:(OI)(CI)M" | Out-Null
}
```

Windows file access passes through **two independent permission layers**, and the
effective access is the **more restrictive** of the two:

- **Share permissions** (`New-SmbShare -ChangeAccess`) apply only over the network
  (`\\MS01\IT`). The department group gets **Change**; Domain Admins get **Full**.
  `Revoke-SmbShareAccess ... Everyone` strips the default `Everyone = Read` that a
  new share otherwise carries.
- **NTFS permissions** (`icacls`) apply however the folder is reached — network or
  local console. `/inheritance:r` **breaks inheritance** so permissions from the
  drive root don't leak in; then SYSTEM and local Administrators get Full, and the
  department group gets **Modify** (`M`). `(OI)(CI)` = Object Inherit + Container
  Inherit, so the grant flows to files and subfolders.

The production-standard pattern used here is **share = Change for the group,
NTFS = Modify for the group**, with NTFS as the authoritative gatekeeper.

---

## Verification

### Shares and ACLs (on MS01)

```powershell
Get-SmbShare | Where-Object Name -in "IT","HR","Finance","Operations"
Get-SmbShareAccess -Name IT
```

Each share resolves to its folder under `C:\Shares`, and each share ACL shows
exactly two entries — `LAB\SH-<Dept>-Modify` = Change and `LAB\Domain Admins` =
Full — with no `Everyone`.

![Share list and per-share ACL](screenshots/fileservices/smbshare-list.png)

### Live allow / deny test (on CLIENT01, logged in as `jsmith`, IT)

The payoff: prove the boundary holds in both directions from an ordinary user
account.

```powershell
whoami /groups | Select-String "SH-IT-Modify"          # token carries the nested group

Get-ChildItem \\MS01\IT                                 # succeeds
New-Item \\MS01\IT\jsmith-was-here.txt -ItemType File   # succeeds — Modify, not just read

Get-ChildItem \\MS01\HR                                 # fails: Access is denied
```

Confirmed results:

- `whoami /groups` lists **`LAB\SH-IT-Modify`** (shown as an `Alias` / Local
  Group — the form a domain-local group takes in a logon token). Its presence
  proves the full chain resolved: `jsmith` → `IT-Users` (global) → `SH-IT-Modify`
  (domain local).
- `\\MS01\IT` — directory listed **and** a file written. Modify access works.
- `\\MS01\HR` — **Access is denied.** `jsmith` is in no group that grants HR, and
  `Everyone` was removed, so there is no path to access.

![Allow on IT, deny on HR, from jsmith](screenshots/fileservices/access-test-allow-deny.png)

---

## Troubleshooting notes

- **Group membership is evaluated at logon, not in real time.** The `SH-*` groups
  were created after `jsmith` had already logged in, so his existing token
  predated them and access failed until a full **log off / log on** rebuilt the
  token. This is the single most common file-access help-desk ticket — "I was
  added to the group but still can't get in" — and the fix is almost always a new
  logon, not a permissions change. Confirm with `whoami /groups`.

- **"Access is denied" and "does not exist" on the same object is a permissions
  wall, not a missing share.** Hitting `\\MS01\HR` as an unauthorized user throws
  *two* errors: `UnauthorizedAccessException` (the real cause), immediately
  followed by a `PathNotFound` — because once the share denies the session,
  PowerShell can no longer resolve the path to tell you anything about it. The
  share exists; the caller simply can't see it.

- **A dropped path prefix resolves relative to the current directory.** The first
  folder-creation run put three folders in `C:\Shares` but landed `HR` in
  `C:\Users\Administrator\Shares\HR` — one token lost its `C:\Shares\` prefix and
  resolved against the working directory instead. `Get-ChildItem C:\Shares` caught
  it before the shares were built. Always confirm a batch of created paths landed
  where intended rather than assuming the loop did.

- **Singular/plural and `-AD` vs non-`-AD` cmdlet names fail loudly — which is
  good.** Two typos surfaced here: an OU created as `Group` while the groups
  targeted `OU=Groups` (directory-object-not-found), and `Add-ADGroup` (no such
  cmdlet) typed in place of `Add-ADGroupMember`. Both error immediately rather
  than doing the wrong thing silently. Copying object names and cmdlet names from
  prior working output beats retyping them.

- **`Rename-ADObject` reporting "a name that is already in use"** means the target
  name already exists — in this case both a leftover `Group` and the intended
  `Groups` OU were present. The fix was to use the existing `Groups` and delete the
  stray `Group` (clearing its accidental-deletion protection flag first).

---

## Compliance mapping

| Control | Implementation | Framework |
|---|---|---|
| Role-based, least-privilege access | AGDLP — access by group, never per-user | CIS Control 6 · SOC 2 CC6.1–6.3 · NIST 800-53 AC-2/AC-6 |
| Deny-by-default on data | `Everyone` removed; explicit grants only | CIS 3/6 · NIST CSF PR.AC/PR.DS · SOC 2 CC6.1 |
| Data segregation by department | Separate share + domain-local group per department | SOC 2 CC6.1 · NIST AC-5 (separation of duties) |
| Defense in depth on access | Two enforced layers (share + NTFS), inheritance broken | CIS 3 · NIST 800-53 AC-3 |
| Access tied to joiner-mover-leaver | Entitlement follows group membership → [offboarding](Offboarding.md) revokes it | SOC 2 CC6.2–6.3 · NIST AC-2 |

These are *technical controls demonstrated*, not a compliance certification.

---

## Production considerations

- **Access-based enumeration (ABE)** would be enabled in production
  (`Set-SmbShare -FolderEnumerationMode AccessBased`) so users don't even see
  shares and folders they can't open — the HR share simply wouldn't appear for
  `jsmith`, rather than appearing and denying.
- **A read-only tier** (`SH-<Dept>-Read`, granted Read at share and NTFS) would
  usually accompany the Modify tier, so managers or auditors can view without
  changing.
- **DFS Namespaces** would front the shares with stable `\\lab.local\<share>`
  paths, decoupling the UNC users map a drive to from the physical server, and
  enabling replication/failover of the data itself.
- **Quotas and file screening** (FSRM) would cap usage and block disallowed file
  types per share.
- The provisioning/offboarding scripts manage the *global* group memberships; the
  domain-local groups and their permissions are set once and left alone — which is
  the entire point of the model.
