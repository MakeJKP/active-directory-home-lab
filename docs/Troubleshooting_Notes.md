# Troubleshooting Notes

A consolidated index of the recurring lessons from building this lab — the
mistakes that cost real time and the habits adopted to avoid repeating them.
Per-incident detail lives in the topic docs ([DC01/AD](DC01_Powershell.md),
[DHCP](DHCP_Powershell.md), [Group Policy](GroupPolicy.md),
[RDP remediation](RDP_Firewall_Remediation.md)); this file is the cross-cutting
summary.

The single most useful meta-lesson: **when something fails silently, stop
inferring and get a definitive signal** — `Get-Member`, a packet capture, a
provider name, the actual resultant policy. Most of the time lost below was spent
guessing where a direct check would have answered it.

---

## Know which machine you're on

- **`hostname` first, every time.** VM consoles are visually identical, and
  commands staged on the wrong guest were the single most frequent error across
  every session — nearly assigning a client the DC's `.10` address, running
  host-only `Get-VM*` cmdlets inside a guest, running WFP filter queries on the DC
  when only the client mattered. Mitigation: retitle or color-code each console so
  the distinction is mechanical, not remembered.
- **Host-level and guest-level cmdlets are not interchangeable.** Hyper-V cmdlets
  (`Checkpoint-VM`, `Get-VMNetworkAdapter`) exist only on the physical host; the
  `ActiveDirectory` module exists only where AD DS or RSAT is installed. A guest
  has no awareness that it is virtualized.
- **`Get-ADComputer`/GPO edits belong on the DC; firewall/RDP checks belong on the
  client.** OU-targeted policy never appears in the DC's own `gpresult` — the DC
  isn't in the target OU. Verify OU-scoped policy on a machine that sits in the OU.

## Loud failures vs. silent failures

- **Misspelled cmdlets fail loudly; misspelled properties and variables fail
  silently.** `Get-ADCompter` throws; `Select-Object DistiguishedName` just prints
  an empty column, and PowerShell auto-creates any variable on first use. A blank
  column is a typo, not "no data." Confirm property names with `Get-Member` before
  concluding anything is missing.
- **Confirm the command actually ran.** Several dead ends were commands typed but
  never executed (un-pressed Enter), or a native tool that printed help instead of
  running. Verify output exists before drawing a conclusion.

## Native tools parse their own flags

- **Forward slashes for native exes.** `gpupdate \force` (backslash) is an invalid
  switch — the tool printed its usage and never refreshed policy, which looked
  exactly like "the GPO won't apply." Use `/force`, and confirm *"Computer Policy
  update has completed successfully."*
- **PowerShell's case-insensitivity does not extend to native exes.** `tar -c`
  (create) vs `-C` (change dir) collide; use `expand file.cab -F:* dest` for cabs.
- **A documented command isn't guaranteed to work.** `netsh dhcp server set
  dnscredentials` did not behave correctly on Server 2022 (it returned output from
  an unrelated netsh context). The DHCP console wrote the same setting
  successfully. When a CLI verb silently misbehaves, fall back to the GUI rather
  than assuming a quoting error.

## Files and extensions

- **Turn on "File name extensions" in Explorer.** Rounds of time were lost to
  `.cvs`/`.csv`/no-extension/`.txt` saves from Notepad. Create `.ps1` files with
  `notepad C:\path\file.ps1` (extension locked) or a single-quoted here-string.
- **`Import-Csv` reads CSV, not XLSX.** A `.xlsx` sitting where the script expects a
  `.csv` parses as garbage rows. Keep the sample input as real `.csv`.

## Active Directory

- **Objects go in OUs, not `CN=Users`/`CN=Computers`.** A container cannot have a
  GPO linked to it. The first provisioning run omitted `-Path` and dropped users in
  `CN=Users`, which would have blocked all later GPO work.
- **"Parent is uninstantiated or deleted" on a move means the target DN is wrong or
  missing.** AD cannot distinguish a malformed DN from a nonexistent one. Copy DNs
  from `Get-AD*` output rather than retyping (`DC=lab=local` vs `DC=lab,DC=local`).
- **Idempotency has to cover every step, not just creation.** Group membership was
  added to provisioning after the first five accounts existed; because the script
  skipped existing accounts wholesale, those five never got grouped. Fix: the
  existence check short-circuits *only* creation, while membership is verified on
  every run. `Add-ADGroupMember` is naturally idempotent.
- **Verify destructive commands before running them.** `Remove-ADUser -Confirm:$false`
  with a mis-scoped `-SearchBase` deletes silently. Run the `Get-`/`Where-Object`
  half first, confirm the set, then append the removal.

## Group Policy

- **GPP "Rename to" is an action, not a label.** It silently renamed the built-in
  Remote Desktop Users group, causing error 1376 on logon. Diagnosed by well-known
  SID (`S-1-5-32-555`) and fixed with `Rename-LocalGroup`.
- **GPP preferences don't self-heal in reverse.** Correcting the GPO does not undo
  damage already applied to a client — remediate the client directly too.
- **"Block (default)" ≠ "Block all connections."** The former blocks unmatched
  inbound but honors allow rules; the latter (shields-up) ignores allow rules
  entirely. Setting the latter by mistake drops traffic every allow rule permits.

## Network diagnosis

- **Self-tests are unreliable for reachability.** A machine testing its own port
  can mislead; test across the network from the other host.
- **An elimination is only valid if the rest of the path is known-good at the
  time.** The firewall was "ruled out" against a broken sender, so the result had
  to be discarded and the theory reopened hours later. Re-run eliminations after
  fixing anything upstream.
- **Bisect earlier.** With checkpoints available, "did this ever work?" should come
  before "what's blocking it?" — but make sure the checkpoint state isn't itself
  confounded (a pre-GPO checkpoint has the default firewall, which blocks inbound
  by default — failure there is expected, not evidence of a fault).
- **Packet capture ends guessing.** Ten layers were eliminated by inference over
  two sessions; `pktmon` named the failing component in one run, and the `wfpdiag`
  state dump named the exact filter *and its provider*. Reach for capture far
  sooner when a path fails silently. `pktmon` is built into Win11/Server 2022.
- **Read the provider before theorizing.** The RDP drops were blamed on NIC
  binding, a third-party driver, and stale filters across two sessions; the WFP
  dump showed provider `MpsSvc` on every one — the plain built-in firewall in
  shields-up. The evidence named the cause; the theories had not.
- **Interface byte counters are a fast liveness proof.** Sent/Received in the
  millions means the NIC and switch port work — stop suspecting hardware.
- **Removing and re-adding a Hyper-V NIC renames the interface** (`Ethernet` →
  `Ethernet 2` → `Ethernet 3`) and can leave a hidden ghost NIC. Never assume the
  alias survived; check `Get-NetAdapter` first.
- **`New-NetIPAddress` appends rather than replaces.** Re-running it stacked
  multiple addresses on one adapter, including a duplicate of the DC's `.10`. Clear
  the interface before assigning.
- **A multihomed domain controller registers all its addresses in DNS**, so clients
  may try to reach it on an unroutable one. Keep a DC on a single adapter.
- **Bad-destination typos have a tell.** A mistyped ping/`Test-NetConnection`
  target (`193.` for `192.`, `.100` for `.10`) returns blank `InterfaceAlias` and
  `SourceAddress` with no `TimedOut`, whereas a real failure populates both.

## Configuration management

- **Local changes that policy can reassert are config drift, not fixes.** A
  firewall setting fixed locally reverts on the next `gpupdate` if a GPO owns it.
  Make the change at the policy layer so there's a single source of truth.
- **Checkpoint reverts silently undo host- and guest-side work** — IP config,
  adapter rebuilds, DNS settings. Re-verify state after every revert (MAC address
  is a quick tell).
- **Secure Boot / TPM / vTPM cannot cause network drops.** They gate boot and
  credential storage, not packet flow — don't chase them for a connectivity fault.

## Expected behavior mistaken for faults

- **"The session was disconnected" on VM restart is normal.** VMConnect's enhanced
  session is RDP-based and is torn down when the guest reboots; the VM stays
  Running. Reconnect after boot.
- **Server Manager can show stale role inventory after an update** — verify against
  `Get-Service`/role cmdlets, which also work over remoting, rather than the
  dashboard.
- **A self-signed RDP certificate warning is expected without an internal CA.** It's
  the host's TLS identity, separate from NLA (which authenticates you). The fix is
  AD Certificate Services, not clicking through forever.

