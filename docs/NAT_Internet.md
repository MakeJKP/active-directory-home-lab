# Internet Access via Hyper-V NAT

The lab runs on an isolated internal switch with no route off the subnet. This
adds controlled internet access to that subnet using a **host-based NAT**, so the
lab can reach the internet (Windows Update, DNS resolution, and — next — cloud
identity services) **without multihoming the domain controller**.

Every VM stays single-homed on `lab.local.switch`. The Hyper-V host holds the
gateway address on its virtual adapter for that switch and NATs the lab's traffic
out through its own internet connection (here, the host's Wi-Fi). This is the
clean alternative to giving the DC a second NIC — the multihomed-DC problem that
was deliberately removed earlier (a DC with adapters on two networks registers
both addresses in DNS and causes clients to try unroutable ones).

## Topology

```
Lab VMs (DC01/MS01/CA01/clients)  ──  lab.local.switch (Internal)
   192.168.100.0/24                        │
                                   host vNIC = 192.168.100.1  ← gateway
                                           │
                                   WinNAT (192.168.100.0/24)
                                           │
                                   Host Wi-Fi (10.0.0.x)  ──→  Internet
```

- **Gateway:** `192.168.100.1`, on the host's virtual adapter for the lab switch.
- **NAT object:** `hyperV-NAT`, bound to `192.168.100.0/24`.
- **Clients** receive `.1` as their default gateway via DHCP (scope option 003).
- **DC01** (static) was given a default route to `.1`.
- **Name resolution:** clients query DC01; DC01 forwards external names to public
  resolvers (`8.8.8.8`, `1.1.1.1`) — now reachable because the subnet has a route out.

## Configuration

The NAT itself is two steps on the host — assign the gateway IP to the host's
adapter for the internal switch, then create the NAT:

```powershell
# On the host
New-NetIPAddress -IPAddress 192.168.100.1 -PrefixLength 24 -InterfaceAlias "<host vNIC for lab switch>"
New-NetNat -Name "hyperV-NAT" -InternalIPInterfaceAddressPrefix "192.168.100.0/24"
```

The static domain controller needs a default route to the new gateway (DHCP
clients get theirs automatically):

```powershell
# On DC01 — find the real adapter alias, then add the default route
$alias = (Get-NetIPAddress -IPAddress 192.168.100.10 -AddressFamily IPv4).InterfaceAlias
New-NetRoute -InterfaceAlias $alias -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.100.1"
```

And the DC's DNS forwarders, previously routeless, now resolve:

```powershell
# On DC01
Set-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1
```

## Verification

```powershell
# DC01 — routes and resolves
ping 8.8.8.8
Resolve-DnsName microsoft.com

# CLIENT01 — full chain (gateway via DHCP, DNS via the DC)
ping 8.8.8.8
Resolve-DnsName microsoft.com
```

Confirmed: DC01 and clients both reach `8.8.8.8` and resolve external names, with
no client-side changes — clients route through `.1 → NAT → host uplink` and
resolve through `DC01 → forwarders`.

## Troubleshooting notes

- **Renaming a Hyper-V switch does not rename its host adapter.** The lab switch
  had been renamed to `lab.local.switch`, but its host virtual adapter kept the
  original name (`vEthernet (Windows11Pro_internal_lab)`). That mismatch made it
  look like the NAT gateway and the VMs were on different switches. They weren't —
  `Get-VMNetworkAdapter -ManagementOS` confirmed the oddly-named adapter *is* the
  host vNIC for `lab.local.switch`. The lesson: map adapters to switches by the
  management-OS binding, not by name, and never delete a "stray" vEthernet without
  checking what switch it serves — this one held the live gateway.

- **A static host with no default gateway fails with "General failure."** DC01
  (static `.10`, no gateway by original isolated design) returned *"PING: transmit
  failed. General failure."* — the signature of no default route, not a NAT fault.
  DHCP clients already had `.1` and worked; only the static DC needed the route.

- **Re-added Hyper-V NICs get renamed.** `New-NetRoute -InterfaceAlias "Ethernet"`
  failed with *"Element not found"* (error 1168) because DC01's adapter had been
  renamed to `Ethernet 3` by earlier NIC rebuilds. Deriving the alias from the IP
  (`Get-NetIPAddress -IPAddress …`) avoids hard-coding a name that may have drifted.

## Compliance / design notes

- **Single-homed DC preserved** — internet is provided by host NAT, not a second
  DC NIC, keeping the DC's DNS registration clean (NIST CSF PR.PT; avoids the
  multihomed-DC anti-pattern).
- **Egress is NAT-only** — the lab subnet is not directly routable from outside;
  only outbound-initiated traffic returns.

## Production considerations

- In production, egress would go through a **firewall/router with egress
  filtering and logging**, not a workstation's NAT — this host NAT is a lab
  convenience.
- A dedicated **perimeter DNS/forwarder** or conditional forwarding would replace
  pointing the DC straight at public resolvers.
- NAT depends on the host's own uplink; it is not highly available and is specific
  to this host (the gateway adapter name is host-specific, as the rename gotcha
  above showed).
