# PowerShell Command Reference

Every PowerShell command used across this lab, broken down piece by piece — what
each one is, what it does, its key parameters, and a real example as used here.
Organized by area so commands can be found and reused quickly.

Convention: `Verb-Noun` is PowerShell's cmdlet naming — the **verb** is the action
(`Get`, `Set`, `New`, `Add`, `Remove`, `Install`…) and the **noun** is what it acts
on. This consistency is why the commands below are predictable once the pattern is
learned.

## Contents

- [1. PowerShell language & pipeline patterns](#1-powershell-language--pipeline-patterns)
- [2. Hyper-V (host)](#2-hyper-v-host)
- [3. Host networking & NAT](#3-host-networking--nat)
- [4. Guest networking](#4-guest-networking)
- [5. Roles & Windows features](#5-roles--windows-features)
- [6. Active Directory Domain Services](#6-active-directory-domain-services)
- [7. DNS Server](#7-dns-server)
- [8. DHCP Server & failover](#8-dhcp-server--failover)
- [9. Group Policy](#9-group-policy)
- [10. Windows Defender Firewall](#10-windows-defender-firewall)
- [11. File services — SMB & NTFS](#11-file-services--smb--ntfs)
- [12. AD Certificate Services & certificates](#12-ad-certificate-services--certificates)
- [13. Remote Desktop & sessions](#13-remote-desktop--sessions)
- [14. Services, registry & system](#14-services-registry--system)
- [15. Data handling (CSV, dates)](#15-data-handling-csv-dates)
- [16. Diagnostics & native tools](#16-diagnostics--native-tools)

---

## 1. PowerShell language & pipeline patterns

The constructs used throughout the rest of this reference.

**The pipeline (`|`)** — passes the objects output by one command as input to the
next. PowerShell pipes *objects*, not text, so properties survive down the chain.

```powershell
Get-ADUser -Filter * | Select-Object Name, DistinguishedName
```

**`Select-Object`** — chooses which properties to show (or limits the count).

```powershell
Get-VMSwitch | Select-Object Name, SwitchType
Get-NetFirewallRule -PolicyStore $store | Select-Object -First 4
```

**`Where-Object`** — filters objects by a condition, keeping only matches.

```powershell
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "*lab-CA01-CA*" }
Get-ADComputer -Filter * | Where-Object Name -like "vEthernet*"
```
`$_` is the current object in the pipeline. Two syntaxes are shown: a full script
block `{ $_.Prop -op value }`, and the simplified `Property -op value`.

**`ForEach-Object`** — runs a block once per piped object. Used for bulk creation.

```powershell
"IT","HR","Finance","Operations" | ForEach-Object {
    New-ADGroup -Name "SH-$_-Modify" -GroupScope DomainLocal -GroupCategory Security -Path "OU=Groups,DC=lab,DC=local"
}
```

**Variables & hashtables** — `$name = value`; a hashtable `@{ Key = Value }` holds
named pairs.

```powershell
$store = "lab.local\DC Firewall Baseline"
$params = @{ Name = "IT-Users"; GroupScope = "Global" }
```

**Splatting (`@params`)** — passes a hashtable's keys as parameters. Preferred over
backtick line-continuation, which silently drops parameters if whitespace sneaks in.

```powershell
$profileSettings = @{
    PolicyStore          = $store
    Profile              = "Domain","Private","Public"
    DefaultInboundAction = "Block"
}
Set-NetFirewallProfile @profileSettings
```

**`Import-Module`** — loads a module so its cmdlets are available (e.g.
`GroupPolicy`, `ActiveDirectory`). Modules usually auto-load, but this forces it.

**`Get-Member`** — lists an object's real properties and methods. The tool for
"what can I actually select here?" — confirms property names before assuming data
is missing.

```powershell
Get-ADUser jsmith | Get-Member
```

**`Out-Null`** — discards a command's output (keeps a bulk loop quiet).
**`Format-Table` / `Format-List`** — control console layout (`-AutoSize` fits columns).
**`Select-String`** — greps text/command output for a pattern.

```powershell
certutil -CATemplates | Select-String "RDPAuthentication"
```

---

## 2. Hyper-V (host)

Run on the physical host; these cmdlets do not exist inside a guest.

**`Get-ComputerInfo`** — reports host details; used to confirm virtualization support.
```powershell
Get-ComputerInfo -Property "HyperV*"
```

**`New-VMSwitch`** — creates a virtual switch. `-SwitchType Internal` = host + VMs only, no physical NIC.
```powershell
New-VMSwitch -SwitchName "lab.local.switch" -SwitchType Internal
```

**`New-VM`** — creates a virtual machine.
```powershell
New-VM -Name "DC01" -Generation 2 -MemoryStartupBytes 4GB -NewVHDPath "C:\VMs\DC01\DC01.vhdx" -NewVHDSizeBytes 60GB -SwitchName "lab.local.switch"
```
- `-Generation 2` — UEFI VM (Secure Boot capable); `-MemoryStartupBytes` — RAM at boot; `-NewVHDPath`/`-NewVHDSizeBytes` — create the disk; `-SwitchName` — which vSwitch to attach.

**`Set-VM`** — changes VM settings after creation (CPU count, dynamic memory).
```powershell
Set-VM -Name "CA01" -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 1GB -MemoryMaximumBytes 4GB
```

**`Add-VMDvdDrive`** — attaches an ISO as a virtual DVD (install media).
```powershell
Add-VMDvdDrive -VMName "DC01" -Path "C:\ISO\WindowsServer2022.iso"
```

**`Set-VMFirmware`** — UEFI/boot settings. Sets Secure Boot and the boot order.
```powershell
Set-VMFirmware -VMName "DC01" -FirstBootDevice $dvd -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
```

**`Set-VMProcessor`** — CPU settings. Compatibility mode lets a VM move between hosts with different CPUs without the saved-state restore error.
```powershell
Set-VMProcessor -VMName "DC01" -CompatibilityForMigrationEnabled $true
```

**`Get-VM` / `Get-VMSwitch` / `Get-VMNetworkAdapter`** — inventory VMs, switches, and VM/host NIC-to-switch mappings.
```powershell
Get-VM
Get-VMNetworkAdapter -VMName * | Select-Object VMName, SwitchName
Get-VMNetworkAdapter -ManagementOS | Select-Object Name, SwitchName   # host vNICs → switch
```

**`Checkpoint-VM`** — takes a snapshot of a VM's current state for rollback.
```powershell
Checkpoint-VM -Name "DC01" -SnapshotName "Pre-DC-firewall-baseline"
```

**`Start-VM` / `Stop-VM` / `Remove-VMSavedState`** — power control; discard a saved state that won't restore on a new CPU.
```powershell
Remove-VMSavedState -VMName "DC01"
Start-VM -Name "DC01"
```

**`Remove-VMSwitch`** — deletes a virtual switch (used for cleanup).
```powershell
Remove-VMSwitch -Name "vSwich-WAN" -Force
```

---

## 3. Host networking & NAT

**`New-NetNat`** — creates a NAT so an internal subnet can route out through the host.
```powershell
New-NetNat -Name "lab-nat" -InternalIPInterfaceAddressPrefix "192.168.100.0/24"
```
- `-InternalIPInterfaceAddressPrefix` — the subnet NAT serves (a host interface in that subnet is the gateway).

**`Get-NetNat`** — lists existing NATs (check for conflicts before creating one).
```powershell
Get-NetNat | Select-Object Name, InternalIPInterfaceAddressPrefix
```

**`Get-NetAdapter`** — lists network adapters (host or guest) with status and description.
```powershell
Get-NetAdapter | Select-Object Name, Status, InterfaceDescription
```

---

## 4. Guest networking

**`New-NetIPAddress`** — assigns a static IP to an interface. (Appends — clear the interface first if re-assigning.)
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.100.10 -PrefixLength 24
```
- `-PrefixLength 24` = `255.255.255.0`.

**`Set-DnsClientServerAddress`** — sets which DNS server(s) an interface uses.
```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.100.10
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses   # back to DHCP-supplied
```

**`Set-NetIPInterface`** — interface-level settings; used to switch an interface to DHCP.
```powershell
Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled
```

**`Remove-NetIPAddress`** — removes a static IP (clears config before switching to DHCP).
```powershell
Remove-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4 -Confirm:$false
```

**`New-NetRoute`** — adds a route; a `0.0.0.0/0` destination is the default gateway. Used to give a static host its route to the NAT gateway.
```powershell
New-NetRoute -InterfaceAlias "Ethernet" -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.100.1"
```

**`Get-NetIPAddress`** — shows configured IP addresses (filter by family or value).
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -like "192.168.100.*" | Select-Object InterfaceAlias, IPAddress
```

**`Get-NetConnectionProfile`** — shows each interface's network category (Domain / Private / Public). Critical for profile-scoped firewall rules.
```powershell
Get-NetConnectionProfile
```

**`Get-NetTCPConnection`** — shows TCP connections/listeners. "Is anything listening on this port?"
```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen | Select-Object LocalAddress, LocalPort, State
```

**`Test-NetConnection`** — tests reachability to a host/port (and ping). The go-to connectivity check.
```powershell
Test-NetConnection 192.168.100.10 -Port 389
```
- `-Port` — tests TCP to that port (`TcpTestSucceeded`); without it, does ICMP ping. A service port (389/445/3389) proves the service answers, not just that the host is up.

**`Resolve-DnsName`** — DNS lookup (optionally against a specific server). Confirms name resolution and forwarding.
```powershell
Resolve-DnsName dc01.lab.local -Server 192.168.100.10
Resolve-DnsName microsoft.com      # external name → tests forwarders
```

---

## 5. Roles & Windows features

**`Install-WindowsFeature`** — installs a server role/feature. `-IncludeManagementTools` adds its consoles/cmdlets.
```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-WindowsFeature DHCP -IncludeManagementTools
Install-WindowsFeature FS-FileServer
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
```

**`Enable-WindowsOptionalFeature`** — enables a client/host optional feature (e.g. Hyper-V on Windows 11 Pro).
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

---

## 6. Active Directory Domain Services

Requires the `ActiveDirectory` module (installed with AD DS / RSAT; lives on the DC).

**`Install-ADDSForest`** — promotes a server to the first DC of a new forest. Installs DNS automatically.
```powershell
Install-ADDSForest -DomainName "lab.local"
```

**`Get-ADDomain`** — returns domain details (name, FSMO roles, DN).
```powershell
Get-ADDomain
```

**`New-ADOrganizationalUnit`** — creates an OU (GPO-linkable container for objects).
```powershell
New-ADOrganizationalUnit -Name "LabUsers" -Path "DC=lab,DC=local"
```
- `-Path` — the parent DN. Build child OUs by pointing `-Path` at the parent OU.

**`Get-ADOrganizationalUnit`** — lists OUs; always include `DistinguishedName` (Name alone is ambiguous across branches).
```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
```

**`New-ADUser`** — creates a user account.
```powershell
New-ADUser -Name "svc-dhcpdns" -SamAccountName "svc-dhcpdns" -UserPrincipalName "svc-dhcpdns@lab.local" -AccountPassword $pw -Enabled $true -Path "OU=ServiceAccounts,DC=lab,DC=local"
```
- `-SamAccountName` — the pre-Windows-2000 logon name; `-AccountPassword` — a `SecureString`; `-Path` — the OU to create it in; `-Enabled` — active on creation.

**`Get-ADUser`** — queries user accounts. `-Properties` pulls attributes beyond the default set.
```powershell
Get-ADUser tnash -Properties Enabled, MemberOf, DistinguishedName | Select-Object Enabled, DistinguishedName, MemberOf
```

**`Remove-ADUser`** — deletes a user. Verify the target set with `Get-`/`Where-Object` first — a mis-scoped `-SearchBase` deletes silently.

**`New-ADGroup`** — creates a security (or distribution) group.
```powershell
New-ADGroup -Name "IT-Users" -GroupScope Global -GroupCategory Security -Path "OU=IT,OU=LabUsers,DC=lab,DC=local"
New-ADGroup -Name "SH-IT-Modify" -GroupScope DomainLocal -GroupCategory Security -Path "OU=Groups,DC=lab,DC=local"
```
- `-GroupScope` — `Global` (holds members, used by role) vs `DomainLocal` (granted on resources) — the two halves of the AGDLP model.

**`Add-ADGroupMember` / `Remove-ADGroupMember`** — add/remove members (users or nested groups). `Add` is idempotent.
```powershell
Add-ADGroupMember -Identity "SH-IT-Modify" -Members "IT-Users"
```

**`Get-ADGroup` / `Get-ADGroupMember`** — query groups and their membership.
```powershell
Get-ADGroup -Filter 'Name -like "SH-*"' | Select-Object Name, GroupScope
Get-ADGroupMember "SH-IT-Modify" | Select-Object Name
```

**`Get-ADPrincipalGroupMembership`** — lists the groups a user/computer belongs to (the reverse view).
```powershell
Get-ADPrincipalGroupMembership tnash | Select-Object Name
```

**`New-ADComputer` / `Get-ADComputer`** — create (pre-stage) and query computer accounts.
```powershell
Get-ADComputer -Filter * -Properties DNSHostName | Select-Object Name, DNSHostName
```

**`Move-ADObject`** — moves an object (e.g. a joined computer) into an OU.
```powershell
Get-ADComputer CLIENT01 | Move-ADObject -TargetPath "OU=IT,OU=LabComputers,DC=lab,DC=local"
```

**`Rename-ADObject`** — renames a directory object (e.g. an OU). Errors if the target name is already in use.
```powershell
Rename-ADObject -Identity "OU=Group,DC=lab,DC=local" -NewName "Groups"
```

**`Disable-ADAccount`** — disables an account so it can't authenticate (offboarding step 1).
```powershell
Disable-ADAccount -Identity tnash
```

**`Get-ADDefaultDomainPasswordPolicy`** — shows the domain password/lockout policy.

**`Add-Computer`** — joins a machine to a domain (optionally renaming and placing it in an OU, in one reboot).
```powershell
Add-Computer -DomainName "lab.local" -NewName "MS01" -OUPath "OU=Servers,DC=lab,DC=local" -Credential (Get-Credential) -Restart
```
- `-NewName` — rename during join; `-OUPath` — drop the new computer object straight into this OU; `-Credential` — a domain account with join rights.

**`Rename-Computer`** — renames a machine. On a domain member, `-DomainCredential` is needed to update the AD object.
```powershell
Rename-Computer -NewName "CA01" -DomainCredential (Get-Credential) -Restart
```

---

## 7. DNS Server

**`Add-DnsServerForwarder` / `Set-DnsServerForwarder`** — configure upstream resolvers for names the DC isn't authoritative for.
```powershell
Add-DnsServerForwarder -IPAddress 8.8.8.8
Set-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1    # set the whole list at once
```

**`Get-DnsServerForwarder`** — shows the configured forwarders.

---

## 8. DHCP Server & failover

**`Add-DhcpServerInDC`** — authorizes a DHCP server in Active Directory (it won't lease until authorized). Needs Enterprise Admin, run in a domain context.
```powershell
Add-DhcpServerInDC -DnsName "DC01.lab.local" -IPAddress 192.168.100.10
```

**`Get-DhcpServerInDC`** — lists authorized DHCP servers.

**`Add-DhcpServerv4Scope`** — creates an address pool.
```powershell
Add-DhcpServerv4Scope -Name "LabScope" -StartRange 192.168.100.100 -EndRange 192.168.100.200 -SubnetMask 255.255.255.0 -State Active
```

**`Set-DhcpServerv4OptionValue`** — sets scope options handed to clients.
```powershell
Set-DhcpServerv4OptionValue -ScopeId 192.168.100.0 -DnsServer 192.168.100.10 -DnsDomain "lab.local" -Router 192.168.100.1
```
- `-DnsServer` (opt 006), `-DnsDomain` (opt 015), `-Router` (opt 003, default gateway).

**`Get-DhcpServerv4Scope` / `Get-DhcpServerv4Lease`** — show the scope and current leases.

**`Add-DhcpServerSecurityGroup`** — creates the DHCP Administrators/Users local groups (post-install step).

**`Export-DhcpServer`** — backs up DHCP config (and optionally leases) to XML.
```powershell
Export-DhcpServer -File "C:\Backup\dhcp-config.xml" -Leases -Force
```

**`Add-DhcpServerv4Failover`** — creates a failover relationship between two DHCP servers.
```powershell
Add-DhcpServerv4Failover -Name "DC01-MS01-Failover" -PartnerServer MS01.lab.local -ScopeId 192.168.100.0 -LoadBalancePercent 50 -SharedSecret "<secret>" -Force
```
- `-PartnerServer` — the second server; `-ScopeId` — the scope to make HA; `-LoadBalancePercent` — split of requests; `-SharedSecret` — authenticates the failover channel (TCP 647).

**`Get-DhcpServerv4Failover`** — shows the relationship state (`Normal` = healthy).
```powershell
Get-DhcpServerv4Failover | Select-Object Name, State, Mode
```

---

## 9. Group Policy

Requires the `GroupPolicy` module.

**`New-GPO`** — creates an (unlinked) Group Policy Object.
```powershell
New-GPO -Name "DC Firewall Baseline" -Comment "Default-deny inbound baseline for DCs."
```

**`New-GPLink`** — links a GPO to a site/domain/OU so it applies to objects there.
```powershell
New-GPLink -Name "DC Firewall Baseline" -Target "OU=Domain Controllers,DC=lab,DC=local" -LinkEnabled Yes
```
- `-Target` — the DN to link to. Linking is separate from creating — a GPO can exist and apply to nothing.

**`Remove-GPO`** — deletes a GPO. (Deleting a GPO's *link* is different from deleting the GPO itself.)

**`gpupdate`** (native) — forces a policy refresh.
```powershell
gpupdate /force
```
Note the forward slash — `gpupdate \force` (backslash) prints help and does nothing.

**`gpresult`** (native) — shows the resultant set of policy on a machine.
```powershell
gpresult /r /scope computer
```
OU-targeted policy only shows on a machine that sits in that OU — not in a DC's own `gpresult`.

---

## 10. Windows Defender Firewall

The `NetSecurity` module. A `-PolicyStore` targets a GPO (e.g. `"lab.local\DC Firewall Baseline"`); `ActiveStore` is the live, merged policy.

**`Set-NetFirewallProfile`** — sets per-profile posture (on/off, default actions, logging, rule-merge).
```powershell
Set-NetFirewallProfile -PolicyStore $store -Profile Domain,Private,Public -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow -AllowLocalFirewallRules False -LogBlocked True -LogAllowed True
```
- `-DefaultInboundAction Block` — deny inbound unless a rule allows; `-AllowLocalFirewallRules False` — ignore locally-defined rules so the GPO is the single source of truth.

**`Get-NetFirewallProfile`** — reads profile settings (from a policy store or the ActiveStore).
```powershell
Get-NetFirewallProfile -PolicyStore ActiveStore -Profile Domain | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
```

**`New-NetFirewallRule`** — creates a firewall rule.
```powershell
New-NetFirewallRule -PolicyStore $store -DisplayName "AD DC - LDAP (TCP 389)" -Group "AD DC Baseline" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 389 -RemoteAddress 192.168.100.0/24 -Profile Domain
```
- `-Direction`/`-Action` — Inbound/Allow; `-Protocol`/`-LocalPort` — what to match; `-RemoteAddress` — source scope; `-Group` — a label to manage rules together; `-Profile` — which profile(s) it applies to.

**`Get-NetFirewallRule`** — queries rules (then pipe to address/port filters for detail).
```powershell
Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object DisplayGroup -eq "AD DC Baseline" | Measure-Object | Select-Object Count
```

**`Set-NetFirewallRule`** — modifies existing rules (e.g. widen the profile scope in bulk).
```powershell
Get-NetFirewallRule -PolicyStore $store | Where-Object DisplayGroup -eq "AD DC Baseline" | Set-NetFirewallRule -Profile Any
```

---

## 11. File services — SMB & NTFS

**`New-SmbShare`** — shares a folder with share-level permissions.
```powershell
New-SmbShare -Name "IT" -Path "C:\Shares\IT" -ChangeAccess "LAB\SH-IT-Modify" -FullAccess "LAB\Domain Admins"
```
- `-ChangeAccess`/`-FullAccess`/`-ReadAccess` — grant that share-level right to a principal.

**`Set-SmbShare`** — changes share settings (e.g. access-based enumeration).

**`Get-SmbShare` / `Get-SmbShareAccess`** — list shares and their share-level ACLs.
```powershell
Get-SmbShare | Where-Object Name -in "IT","HR","Finance","Operations"
Get-SmbShareAccess -Name IT
```

**`Revoke-SmbShareAccess`** — removes a share-level grant (e.g. strip the default `Everyone`).
```powershell
Revoke-SmbShareAccess -Name "IT" -AccountName "Everyone" -Force
```

**`icacls`** (native) — manages NTFS (file-system) permissions, the second, authoritative access layer.
```powershell
icacls "C:\Shares\IT" /inheritance:r
icacls "C:\Shares\IT" /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "LAB\SH-IT-Modify:(OI)(CI)M"
```
- `/inheritance:r` — remove inherited permissions (break inheritance); `/grant` — add an ACE; `(OI)(CI)` — Object + Container Inherit (flows to files and subfolders); `F`/`M` — Full / Modify.

---

## 12. AD Certificate Services & certificates

**`Install-AdcsCertificationAuthority`** — configures the CA role after install.
```powershell
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName "lab-CA01-CA" -KeyLength 4096 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 10 -Force
```
- `-CAType EnterpriseRootCA` — AD-integrated root (auto-publishes trust, supports templates/autoenrollment); `-KeyLength`/`-HashAlgorithmName` — key strength and signing hash; `-ValidityPeriod*` — the CA cert's lifetime.

**The `Cert:` PSDrive** — certificate stores browsable like a filesystem.
```powershell
Get-ChildItem Cert:\LocalMachine\My   | Where-Object { $_.Issuer -like "*lab-CA01-CA*" }   # machine's issued certs
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "*lab-CA01-CA*"           # trusted roots
Get-ChildItem Cert:\LocalMachine\CA                                                          # intermediate/CA certs
```

**`certutil`** (native) — the CA/certificate Swiss-army tool.
```powershell
certutil -cainfo                       # CA type/status
certutil -CATemplates                  # templates the CA will issue
certutil -pulse                        # trigger autoenrollment now
```

---

## 13. Remote Desktop & sessions

**Enable/disable RDP (registry)** — `fDenyTSConnections` 0 = enabled, 1 = disabled.
```powershell
(Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server").fDenyTSConnections
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
```
Better enforced by GPO (RDSH → Connections → *Allow users to connect remotely*) so it can't drift.

**RDP's bound certificate (WMI)** — which cert the RDP listener presents.
```powershell
(Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TSGeneralSetting -Filter "TerminalName='RDP-tcp'").SSLCertificateSHA1Hash
```
Compare this thumbprint to a CA-issued cert's to confirm RDP uses it.

**`Restart-Service TermService`** — restarts Remote Desktop Services (to rebind after a cert change).

**`whoami /groups`** (native) — shows the groups in the current logon token. Proves nested group membership resolved (log off/on after a group change to refresh the token).
```powershell
whoami /groups | Select-String "SH-IT-Modify"
```

**`mstsc`** (native) — the Remote Desktop client.
```powershell
mstsc /v:dc01.lab.local
```

---

## 14. Services, registry & system

**`Get-Service` / `Restart-Service`** — query and restart Windows services.
```powershell
Get-Service NTDS, DNS, DHCPServer | Select-Object Name, Status
Restart-Service DHCPServer
```

**`Set-ItemProperty` / `Get-ItemProperty`** — read/write registry values (and other item properties).
```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name ConfigurationState -Value 2
```

**`New-Item`** — creates a filesystem item (e.g. a folder; parent dirs aren't auto-created by most cmdlets).
```powershell
New-Item -Path "C:\Backup" -ItemType Directory
New-Item -ItemType Directory -Force -Path C:\Shares\IT, C:\Shares\HR
```

**`Get-Content` / `Out-File`** — read a file / write output to a file.
```powershell
Get-Content C:\Scripts\offboarding-log.csv
```

**`Set-ExecutionPolicy`** — controls whether scripts can run.
```powershell
Set-ExecutionPolicy RemoteSigned
```

**`Read-Host` / `Get-Credential`** — prompt for input; `-AsSecureString` / `Get-Credential` capture secrets safely.
```powershell
$pw = Read-Host -AsSecureString "Password for svc-dhcpdns"
Add-Computer -DomainName "lab.local" -Credential (Get-Credential) -Restart
```

---

## 15. Data handling (CSV, dates)

**`Import-Csv`** — reads a CSV into objects (one per row; columns become properties). Used by the provisioning script.
```powershell
Import-Csv C:\Scripts\newusers.csv
```
Reads `.csv`, not `.xlsx` — an Excel file here parses as garbage.

**`Export-Csv`** — writes objects to CSV (the offboarding audit log). `-Append -NoTypeInformation` keeps a clean running log.

**`Get-Date`** — the current date/time; used for timestamps in logs.
```powershell
Get-Date -Format "yyyy-MM-dd HH:mm:ss"
```

---

## 16. Diagnostics & native tools

**`Test-NetConnection`** — connectivity/port test (see §4). First stop for "can A reach B on port X?".

**`Get-Member`** — confirm an object's real property names before concluding data is missing (see §1).

**`Get-NetTCPConnection`** — distinguishes "service listening" from "service running" (see §4).

**`pktmon`** (native) — built-in packet capture/monitor. Localizes where a packet is dropped (e.g. to the Windows Filtering Platform) when inference fails.

**`wfpdiag`** / `netsh wfp` (native) — dumps Windows Filtering Platform state; names the exact filter and provider dropping traffic.
```powershell
netsh wfp capture start
# reproduce the failure, then:
netsh wfp capture stop
```

**`nltest`** (native) — locates a domain controller; a quick "can this client find a DC?" check.
```powershell
nltest /dsgetdc:lab.local
```

**`w32tm`** (native) — Windows Time service; `/resync` forces a time sync (clock skew breaks Kerberos).
```powershell
w32tm /resync
```

**`Get-WinEvent`** — reads event logs (e.g. the Event 1056 DHCP/DNS finding).
```powershell
Get-WinEvent -LogName "Microsoft-Windows-Dhcp-Server/Operational" -MaxEvents 20
```

**`ipconfig`** (native) — quick IP configuration view (`/all`, `/renew`, `/release`).
```powershell
ipconfig /all
ipconfig /renew
```

**`netsh`** (native) — legacy network/firewall/WFP configuration. Used here for WFP capture; note some verbs (e.g. DHCP DNS credentials) misbehave on Server 2022 — fall back to the console.

---

*This reference mirrors the commands in the topic docs; each area's full context,
reasoning, and troubleshooting lives in its own write-up (see the
[repository README](../README.md) documentation index).*
