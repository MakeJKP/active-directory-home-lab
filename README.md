# Active Directory Home Lab

A Windows Server domain built from scratch in Hyper-V to practice and document core system administration work: Active Directory, DNS, DHCP, and PowerShell automation.

Every configuration step in this lab was performed and documented in PowerShell rather than through GUI wizards, so the build is repeatable and the reasoning behind each step is recorded.

---

## Environment

| Role | Hostname | Address | Notes |
|---|---|---|---|
| Domain controller | DC01 | 192.168.100.10 (static) | AD DS, DNS, DHCP |
| Windows 11 client | winpro_lab2 | DHCP assigned | Domain member |

- **Hypervisor:** Hyper-V on Windows 11 Pro
- **Virtual switch:** Internal, isolated from the physical home network
- **Domain:** lab.local
- **Subnet:** 192.168.100.0/24
- **DHCP scope:** 192.168.100.100 – 192.168.100.200
- **Static range:** 192.168.100.1 – .99 reserved outside the scope

---

## What Is Built

**Active Directory Domain Services**
Forest and domain promoted on DC01. Integrated DNS installed automatically with the role. All FSMO roles held by DC01.

**DNS**
Authoritative for lab.local. Forwarders configured to 8.8.8.8 and 1.1.1.1 so clients resolve external names through the domain controller rather than being pointed at public DNS directly.

**DHCP**
Role installed and authorized in Active Directory. Scope configured with option 006 (DNS server) and option 015 (DNS domain name), so clients receive the correct DNS server automatically and can join the domain without per-machine configuration. Configuration exported to XML as a backup.

**Organizational units**
A parent `LabUsers` OU with child OUs for IT, HR, Finance, and Operations. Users are placed in OUs rather than the default `CN=Users` container, because Group Policy Objects cannot be linked to a container.

**Bulk user provisioning**
`New-LabUsers.ps1` reads a CSV, generates usernames from first initial plus last name, checks for existing accounts before creating, places each user in the OU matching their department, and forces a password change at first logon. The script is idempotent — re-running it skips existing accounts rather than erroring or creating duplicates.

---

## Documentation

| Document | Contents |
|---|---|
| [DHCP installation and configuration](docs/dhcp-configuration.md) | Command log for the DHCP role, scope, options, forwarders, and backup |
| [Active Directory users and OUs](docs/active-directory-users-and-ous.md) | Command log for the OU structure and the bulk provisioning script |

Each document records the commands actually used, the reasoning behind them, and a troubleshooting section covering problems encountered during the build and how they were diagnosed.

---

## Skills Demonstrated

- Active Directory Domain Services installation, forest promotion, and OU design
- DNS zone hosting and conditional forwarding
- DHCP scope configuration, AD authorization, and scope options
- PowerShell scripting: CSV input, loops, conditional logic, error handling, idempotent operations
- Hyper-V virtual machine and virtual switch configuration
- Static and dynamic IP addressing, subnetting, and client-side network troubleshooting
- Documenting infrastructure work in a form another administrator could follow

---

## In Progress

- Security groups and automated group membership during provisioning
- Group Policy Objects linked to department OUs
- Automated offboarding script (disable account, remove group memberships, move to a disabled OU)
- Internet routing for lab clients via NAT switch

---

## Notes on Scope

This is a lab environment and some configurations are deliberately simplified. The provisioning script uses a hardcoded default password rather than a credential store, DHCP dynamic DNS registration runs under the domain controller machine account rather than a dedicated service account, and the DHCP scope omits a default gateway because the internal virtual switch provides no route off the subnet. Each of these is noted in the relevant document alongside what the production approach would be.
## About

Built and maintained by James Andrew Kearse — U.S. Marine Corps veteran and IT support professional.
CompTIA A+ and Network+ certified. B.S. in Information Technology.

