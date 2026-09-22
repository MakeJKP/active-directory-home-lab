Group Policy is where this lab moves from "a domain exists" to "the domain is
managed." Two Group Policy Objects are in place: one grants remote-access rights
by group membership, and one applies a Windows Defender Firewall baseline to
every workstation. Both are scoped to computer OUs and verified from the client
side, because a domain controller's own `gpresult` never shows policy targeted at
an OU it does not sit in.

A note on where GPOs are linked: a GPO applies to the objects beneath the OU it
is linked to. Firewall and remote-access settings are Computer Configuration, so
these GPOs link to the `LabComputers` branch, not `LabUsers`.

---

## GPO 1 — IT - Local Remote Access

*Linked to `OU=IT,OU=LabComputers`. Its job is to let members of the
`IT-RemoteAccess` group sign in over RDP to IT workstations, delivered centrally
so no machine is touched by hand.*

Two settings:

- **Local Users and Groups preference** (Computer Configuration → Preferences →
  Control Panel Settings → Local Users and Groups): add `LAB\IT-RemoteAccess` to
  the built-in **Remote Desktop Users** group. Action **Update** (not Replace),
  both "Delete all member users / groups" boxes left unchecked so existing
  membership is preserved, and the **Rename to** field left blank.
- **Administrative template** (Computer Configuration → Policies → Administrative
  Templates → Windows Components → Remote Desktop Services → Remote Desktop
  Session Host → Connections): **Allow users to connect remotely by using Remote
  Desktop Services** = **Enabled**.

*Group membership drives access. Granting a person RDP rights to IT machines is
then a matter of adding them to one group, rather than editing each computer —
the role-based, least-privilege model.*

*Verified from the client, which is the only place OU-targeted policy shows up.*
```powershell
  gpupdate /force
  gpresult /r /scope computer
  # confirm "IT - Local Remote Access" under Applied Group Policy Objects
  net localgroup "Remote Desktop Users"
  # confirm LAB\IT-RemoteAccess is listed
```

---

## GPO 2 — Workstation Firewall Baseline

*Linked to the `OU=LabComputers` parent so it reaches every department. This is
the deny-by-default host firewall baseline, plus the hardening for the one
inbound service the lab exposes: RDP.*

**Profile posture** (Windows Defender Firewall with Advanced Security → Properties):

| Profile | Firewall state | Inbound | Outbound |
|---|---|---|---|
| Domain | On | Block (default) | Allow (default) |
| Private | On | Block (default) | Allow (default) |
| Public | On | **Block all connections** | Allow (default) |

*Domain and Private block inbound by default but honor allow rules — the standard
enterprise posture. Public is deliberately left at "Block all connections"
(shields-up), so an IT workstation taken onto an untrusted network refuses all
inbound regardless of rules. Differentiating trust by profile, rather than one
blanket setting, is the point.*

**Inbound allow rules** (all scoped to the Domain profile):

- Remote Desktop — User Mode (TCP-In) and (UDP-In)
- File and Printer Sharing group (includes ICMPv4 Echo Request and SMB)

**RDP source scoping.** The Remote Desktop rules are restricted on the **Scope**
tab → Remote IP address → `192.168.100.10` (the management/administration host).
RDP is no longer accepted from anywhere on the subnet — only from the management
source. Widening later (an admin jump host, a management subnet) is a matter of
adding addresses to this same list.

**Remote-access hardening** (Remote Desktop Session Host → Security):

- Require user authentication for remote connections by using **Network Level
  Authentication** = Enabled
- Set client connection encryption level = **High Level**

**Session limits** (Remote Desktop Session Host → Session Time Limits): idle
session limit and disconnected session limit both **15 minutes** — the automatic
logoff control.

**Logging** (WDFAS → Properties → each profile → Logging → Customize): log
dropped packets and successful connections, 16 MB, default path
`%systemroot%\system32\logfiles\firewall\pfirewall.log`. Without this, a silent
drop is invisible — see the remediation write-up for what that cost.

*Verified from the client, in the effective (ActiveStore) firewall configuration.*
```powershell
  gpupdate /force
  Get-NetFirewallProfile -PolicyStore ActiveStore |
    Format-Table Name, Enabled, DefaultInboundAction, AllowInboundRules -AutoSize
  # Domain/Private AllowInboundRules True, Public False
```

**Connectivity proof — positive and negative.** The pair together show the
control works *and* restricts:
```powershell
  # From DC01 (192.168.100.10, in scope) — succeeds
  Test-NetConnection 192.168.100.100 -Port 3389   # TcpTestSucceeded : True
  # From CLIENT02 (192.168.100.101, out of scope) — refused, but host still pings
  Test-NetConnection 192.168.100.100 -Port 3389   # PingSucceeded True, TcpTestSucceeded False
```

*The full diagnostic and remediation of the RDP connectivity failure that
surfaced during this work — a shields-up filter overriding the allow rules,
identified by name from a WFP state dump — is documented separately in*
[RDP connectivity remediation & firewall hardening](RDP_Firewall_Remediation.md).

Screenshots:

![Firewall profile — Public (shields-up retained)](screenshots/gpo/firewall-profile-public.png)
![RDP inbound rule scoped to the management source](screenshots/gpo/rdp-scope-tcp.png)
![NLA required for remote connections](screenshots/gpo/rdp-nla.png)
![Client connection encryption set to High](screenshots/gpo/rdp-encryption.png)
![Firewall logging enabled (Domain profile)](screenshots/gpo/firewall-logging-domain.png)

Additional captures in `screenshots/gpo/`: `firewall-profile-domain.png`, `firewall-profile-private.png`, `rdp-scope-udp.png`, `rdp-session-idle.png`, `rdp-session-disconnected.png`, `firewall-logging-private.png`, `firewall-logging-public.png`. Still to capture: `it-remote-access-gpresult.png` (a `gpresult /r /scope computer` on CLIENT01 showing GPO 1 applied).

---

## Troubleshooting Notes

### GPP "Rename to" field silently renamed the target group

*The Local Users and Groups preference in GPO 1 applied before its configuration
was cleaned up, and the "Rename to" field — which is an action, not a label —
renamed the built-in Remote Desktop Users group to "IT - RemoteAccess" on the
client. Subsequent logons failed with error 1376 ("the specified local group
does not exist"). Diagnosed by well-known SID: the Remote Desktop Users group is
`S-1-5-32-555` regardless of its display name, so the group still existed under a
wrong name. Renamed back on the client with `Rename-LocalGroup`.*
```powershell
  Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-555" }
  Rename-LocalGroup -Name "IT - RemoteAccess" -NewName "Remote Desktop Users"
```

### Group Policy preferences do not self-heal in reverse

*Correcting the GPO did not undo the damage already applied to the client — the
renamed group stayed renamed until fixed directly. A preference pushes a state; it
does not roll back a previous state when the policy changes. The lesson: after
fixing a misapplied preference, remediate the affected clients too, not just the
policy.*

### DC-side gpresult never shows OU-targeted GPOs

*Running `gpresult /r` on DC01 to confirm the firewall baseline showed nothing —
DC01 lives in the Domain Controllers OU, so a GPO linked to `LabComputers` does
not apply to it and does not appear in its resultant set. OU-targeted policy must
be verified on a machine that actually sits in the target OU.*

### gpupdate silently did nothing on a bad switch

*`gpupdate \force` (backslash) is not a valid switch — the tool printed its help
text and never refreshed policy, which looked exactly like "the GPO isn't
applying." Native executables parse their own flags and want forward slashes.
Always confirm "Computer Policy update has completed successfully" rather than
assuming the refresh ran.*

### "Block (default)" vs "Block all connections"

*These read similarly in the firewall profile dropdown but behave very
differently. "Block (default)" blocks inbound that matches no rule but honors
allow rules; "Block all connections" (shields-up) ignores allow rules entirely.
Setting the latter by mistake produces a firewall that drops traffic every allow
rule says to permit — see the remediation write-up.*

---

## Production Considerations

*Remote-access allow rules should be scoped by source address (a management
subnet or jump host), not merely by profile. A flat "RDP allowed on the Domain
profile" is acceptable in a lab; production restricts who may originate the
connection.*

*Domain controllers warrant their own firewall baseline GPO, separate from
workstations and linked to the Domain Controllers OU. Firewall configuration does
not belong in the Default Domain Controllers Policy, which is reserved for the DC
account and security settings.*

*RDP currently trusts a self-signed host certificate (the certificate warning on
first connect). A production environment issues RDP host certificates from an
internal CA (AD Certificate Services) via auto-enrollment, so host identity is
verified automatically and the warning disappears.*

*Multi-factor authentication for administrative and remote access is a
requirement under most frameworks (e.g. PCI DSS) and modern best practice; it is
not achievable with on-premises AD alone and is a candidate for the Entra ID
phase.*

---

## Planned

- **GPO 3 — Password policy**, linked at the domain root (account policies are
  domain-wide; fine-grained password policies / PSOs are the OU-scoped
  alternative).
- **GPO 4 — Department-differentiated setting** between IT and HR, to demonstrate
  and verify OU-scoped policy producing different `gpresult` output on CLIENT01
  vs CLIENT02.

