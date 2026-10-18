# Architecture & Design Decisions

The system-level view of the lab: how it is designed, why each major choice was
made, what the production alternative would be, and how the whole thing fits
together. The topic documents cover *how* each piece was built; this document
covers *why it was built that way* — the reasoning a design review (or an
interview) asks for.

---

## Design intent

Three principles drove every decision:

1. **Production-faithful, not just functional.** Choices follow how a real
   environment is built (role separation, least privilege, policy-enforced
   baselines), and where the lab deliberately simplifies, the simplification is
   documented alongside the production approach.
2. **Security mapped to recognized frameworks.** Controls are named (CIS, NIST,
   SOC 2), not ad-hoc, so the work reads as deliberate rather than incidental.
3. **Reproducible and self-documenting.** The lab can be rebuilt from its own
   docs ([Lab Rebuild](Lab_Rebuild.md)), and every command is explained
   ([PowerShell Reference](PowerShell_Reference.md)).

---

## Logical architecture

```
                       Host (Windows 11 Pro, Hyper-V)
                       Wi-Fi uplink ── WinNAT ── 192.168.100.1 (gateway)
                                                  │
        ┌─────────────────────────────────────────┴──────────────────────────┐
        │                  lab.local.switch  (Internal, 192.168.100.0/24)     │
        └───┬───────────────┬───────────────┬──────────────┬─────────────────┘
            │               │               │              │
      ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴────────────┐
      │   DC01    │   │   MS01    │   │   CA01    │   │ CLIENT01/02      │
      │ .10 static│   │ .11 static│   │ .12 static│   │ DHCP .100–.200   │
      ├───────────┤   ├───────────┤   ├───────────┤   ├──────────────────┤
      │ AD DS     │   │ File (SMB)│   │ Enterprise│   │ Win11, domain-   │
      │ DNS       │   │ DHCP      │   │ Root CA   │   │ joined, in dept  │
      │ DHCP(pri) │   │ failover  │   │ (AD CS)   │   │ computer OUs     │
      │ all FSMO  │   │ partner   │   │           │   │                  │
      └───────────┘   └───────────┘   └───────────┘   └──────────────────┘

  Trust & services flow:
    clients ──Kerberos/LDAP──▶ DC01 (auth, policy)      DC01 ⇄ MS01  DHCP failover (TCP 647)
    clients ──DNS──▶ DC01 ──forwarders──▶ 8.8.8.8/1.1.1.1 (via NAT)
    all hosts ◀──root cert (auto, via AD)── CA01         clients ──SMB/AGDLP──▶ MS01 shares
```

Forest `lab.local` — single forest, single domain, with the OU tree:

```
lab.local
├── OU=LabUsers        → IT · HR · Finance · Operations   (user accounts)
├── OU=LabComputers    → IT · HR · Finance · Operations   (workstation accounts)
├── OU=Servers         → MS01, CA01
├── OU=Groups          → SH-<Dept>-Modify (domain-local resource groups)
├── OU=ServiceAccounts → svc-dhcpdns
├── OU=Disabled Users  → deprovisioned accounts
└── CN=Domain Controllers (built-in) → DC01
```

---

## Naming & addressing conventions

Consistent conventions make the environment predictable and self-documenting — a
reviewer can infer an object's purpose from its name.

| Convention | Pattern | Example |
|---|---|---|
| Hostnames | role + number | `DC01`, `MS01`, `CA01` |
| Usernames | first initial + surname, lowercase | `jsmith` (John Smith) |
| Department global groups | `<Dept>-Users` | `IT-Users` |
| Resource (domain-local) groups | `SH-<Dept>-<Right>` | `SH-IT-Modify` |
| Service accounts | `svc-<purpose>` | `svc-dhcpdns` |
| Static addresses | `.1`–`.99` reserved | DC `.10`, MS01 `.11`, CA01 `.12`, gateway `.1` |
| DHCP pool | `.100`–`.200` | clients |

Static servers sit in a range deliberately kept **outside** the DHCP scope so a
static assignment can never collide with a lease.

---

## Key design decisions

Each row: the decision, the choice made, why, and what a production environment
would do differently. These are the points a design review probes.

| Area | Decision | Rationale | Production alternative |
|---|---|---|---|
| **Namespace** | `lab.local` | Simple, unambiguous for a lab; isolated from any public zone | A **routable subdomain of an owned domain** (e.g. `ad.example.com`). `.local` is now discouraged — it collides with mDNS/Bonjour and complicates split-brain DNS and public TLS |
| **Forest/domain** | Single forest, single domain | Smallest unit that demonstrates AD; no multi-domain complexity needed | Multiple domains/forests only when org/political/security boundaries require; otherwise one domain is Microsoft's own guidance |
| **Functional level** | Windows Server 2016 | Unlocks modern features; all hosts are current | Set to the lowest DC OS in the forest; raise only when all DCs support it (irreversible downward) |
| **FSMO roles** | All five on DC01 | Only one DC in the lab | Keep the five roles consolidated but on **redundant DCs**; seize/transfer plan documented for DR |
| **Redundancy** | Single DC | Lab resource limit | **At least two DCs** per domain — a single DC is a single point of failure for all authentication |
| **DNS** | AD-integrated on DC01, forwarders upstream | Zone data replicates with AD; clients use one resolver | Same pattern; add a second DNS/DC, consider conditional forwarders and DNSSEC |
| **OU design** | Users and computers split, each by department | A GPO has both User and Computer sections; separating lets each apply where it belongs, and objects must be in OUs (not `CN=Users`) for GPO linking | Same; often add tier/function OUs and a dedicated admin OU structure |
| **Access model** | AGDLP, group-driven | Entitlement by group membership, not per-user; scales to multi-domain | Identical — AGDLP is the standard; often automated via IGA tooling |
| **Server roles** | DC / file+DHCP-partner / CA on separate hosts | A DC shouldn't hold general data or a CA; a CA is never renamed/demoted | Same separation; a CA on dedicated (often offline) hardware |
| **PKI** | Single online Enterprise Root CA | One tier is enough to issue and auto-enroll in a lab | **Two-tier**: offline root + online issuing subordinate, so the root key is never network-exposed; HSM-protected keys |
| **DHCP HA** | Failover, Load Balance 50/50 | Both servers active; simple for a single site | Load Balance within a site; **Hot Standby** across sites; tuned MCLT |
| **Host firewall** | Default-deny inbound, GPO-authored, separate workstation vs DC baselines | Single source of truth; DCs need a role-aware allow-list workstations don't | Same model; often centralized via a management platform and log-forwarded to a SIEM |
| **Remote access** | RDP with NLA, High encryption, source-scoped, CA-issued cert | Authenticated, encrypted, least-exposure remote admin | Same, **plus MFA** and a jump/bastion host; RDP never exposed broadly |
| **Internet** | Isolated internal switch + host NAT | Internet without multihoming the DC (which breaks DNS registration) | Egress through a **firewall/router with filtering and logging**, not a host NAT |
| **Password policy** | NIST 800-63B: length-first, **no forced expiration**, lockout | Forced rotation drives weak, predictable passwords; length + breach-checking is current guidance | Same, plus breached-password screening and MFA; PSOs for differentiated account tiers |

---

## Security model

The lab layers controls so no single failure is total — defense in depth:

| Layer | Control | Where |
|---|---|---|
| **Network** | Isolated switch; NAT egress only (no inbound from outside) | [NAT](NAT_Internet.md) |
| **Host firewall** | Default-deny inbound on workstations and the DC, allow-by-exception | [GPO](GroupPolicy.md) · [DC baseline](DC_Firewall_Baseline.md) |
| **Authentication** | Kerberos; RDP with NLA + High encryption | [RDP remediation](RDP_Firewall_Remediation.md) |
| **Authorization** | AGDLP least-privilege, group-driven file access | [File services](FileService.md) |
| **Identity assurance** | Internal PKI — CA-issued host certificates | [AD CS](AD_CS_PKI.md) |
| **Account lifecycle** | Scripted, logged provisioning and offboarding | [DC01/AD](Active_Directory.md) · [Offboarding](Offboarding.md) |
| **Detection** | Firewall logging (dropped + allowed) | [GPO](GroupPolicy.md) · [DC baseline](DC_Firewall_Baseline.md) |
| **Configuration integrity** | GPO-enforced baselines (single source of truth, no local drift) | all GPO docs |

**Least privilege** runs through all of it: access by group not user, a
dedicated least-privilege service account for DHCP dynamic DNS, RDP scoped to a
management source, and the domain-local half of AGDLP holding the only permission
on each share.

*Known gap vs production:* the lab does not implement Microsoft's **administrative
tier model** (separate Tier 0/1/2 admin accounts and PAWs). Administration is done
by logging into servers directly — acceptable for a lab, called out as the first
hardening step a real environment would take.

---

## Security & Compliance crosswalk

Every implemented control, mapped to frameworks and to where it is demonstrated.
These are *technical controls shown in a lab*, not a compliance certification.

| Control | Implementation | CIS | NIST | SOC 2 | Doc |
|---|---|---|---|---|---|
| Default-deny inbound firewall | Workstation + DC baselines, allow-by-exception | 4, 13 | CSF PR.PS | CC6.6 | GPO, DC baseline |
| Least-privilege / RBAC | AGDLP group-driven access | 6 | 800-53 AC-2/AC-6 | CC6.1–6.3 | File services |
| Scoped remote administration | RDP source-scoped to management | 12 | CSF PR.AA | CC6.1 | GPO, RDP |
| Encrypted remote sessions | RDP NLA + High encryption | 3, 6 | 800-53 SC-8 | CC6.7 | RDP |
| Trusted host identity (PKI) | Enterprise Root CA, CA-issued RDP certs | — | 800-53 SC-12/SC-17 | CC6.7 | AD CS |
| Strong authentication policy | NIST 800-63B password policy, lockout | 5 | 800-63B | CC6.1 | GPO |
| Timely, auditable deprovisioning | Scripted offboarding + audit log | 6 | 800-53 AC-2 | CC6.2–6.3, CC7.2 | Offboarding |
| Least-privilege service accounts | `svc-dhcpdns` for dynamic DNS | 5 | 800-53 AC-6 | CC6.1 | DHCP |
| Service availability | DHCP failover | — | CSF PR.PT/RC | A1 | DHCP |
| Attack-surface reduction | Role-aware DC firewall, least functionality | 4 | 800-53 CM-7 | CC8.1 | DC baseline |
| Detection / audit trail | Firewall logging (dropped + allowed) | 8 | CSF DE.CM | CC7.2 | GPO, DC baseline |
| Managed baselines (no drift) | GPO-authored, local rules disabled | 4 | — | CC8.1 | GPO docs |

Secondary mappings to NIST 800-171, PCI DSS, and HIPAA for the firewall/remote-access
controls are in the [RDP remediation crosswalk](RDP_Firewall_Remediation.md).

---

## Intentional simplifications (lab vs production)

Consolidated so a reviewer sees them acknowledged in one place, each with its
production fix:

- **Single DC** → two+ DCs for authentication redundancy.
- **`.local` namespace** → a routable subdomain of an owned domain.
- **Single-tier online Root CA** → two-tier with an offline root; HSM keys.
- **Host NAT for egress** → a filtering/logging firewall or router.
- **Direct server logon for admin** → RSAT from a workstation, and the AD tier model with PAWs.
- **Hardcoded script password** → a credential store / per-account generation.
- **No MFA** → MFA on administrative and remote access (requires Entra/third-party — a planned extension).
- **DC firewall rules scoped to all profiles** → Domain-profile-scoped on a routed network where the NIC classifies as DomainAuthenticated.

Each is also noted in the relevant topic document alongside its production approach.

---

## Where to go deeper

| For… | See |
|---|---|
| The full build, step by step | the topic docs in the [documentation index](../README.md) |
| Rebuilding from nothing | [Lab Rebuild Runbook](Lab_Rebuild.md) |
| Any command explained | [PowerShell Reference](PowerShell_Reference.md) |
| Cross-cutting lessons learned | [Troubleshooting Notes](Troubleshooting_Notes.md) |
