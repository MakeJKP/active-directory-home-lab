**DHCP Installation and Configuratation**

*To install DHCP onto the server via Powershell I used the script bellow.*
  ```powershell
  Install-WindowsFeature DHCP -IncludeManagementTools
  ```

*Next I added the DHCP server to DC01. This is the primary DC for this lab.*
  ```powershell
  Add-DhcpServerInDC -DnsName "DC01.lab.local" -IPAddress 192.168.100.10
  ```

*Next, add a DHCP Rannge.*
  ```powershell
  Add-DhcpServerv4Scope -Name "LabScope" -StartRange 192.168.100.100 -EndRange 192.168.100.200 -SubnetMask 255.255.255.0 -State Active
  ```

*Set DNS option in order to ensure cleants automatically learn to use DC01 for DNS.
  ```powershell
  Set-DhcpServerv4OptionValue -ScopeId 192.168.100.0 -DnsServer 192.168.100.10 -DnsDomain "lab.local"
  ```

*Clear post install flags and restart service.*
  ```powershell
  Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name ConfigurationState -Value 2
  Restart-Service DHCPServer
  ```

*Verify.*
  ```powershell
  Get-DhcpServerv4Scope
  Get-DhcpServerInDC
  ```

*Remove static IP address and enable DHCP for client computers.*
  ```powershell
  Remove-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4 -Confirm:$false
  Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
  ipconfig /renew
  ```

*Create DNS forwarding Functionality.*
  ```powershell
  Add-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1
  Get-DnsServerForwarder
  ```

*Create DHCP backup.*
  ```powershell
  Export-DhcpServer -File "C:\Backup\dhcp-config.xml" -Leases -Force
  ```

*Verify.*
  ```powershell
  Get-ChildItem C:\Backup
  ```

**Troubleshooting Notes**

**Client adapter accumulated multiple IPv4 addresses**

*A client showed three IPv4 addresses on a single adapter: 192.168.100.10, .20, and .21. New-NetIPAddress adds an address to an interface rather than replacing the existing one, so re-running it during configuration attempts stacked all three. One of them was .10, the address belonging to the domain controller, which would have produced an IP conflict and broken name resolution for that client. Fixed by clearing all IPv4 addresses from the interface and assigning a single correct address.*
  ```powershell
  Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4

  Remove-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4 -Confirm:$false

  New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.100.20 -PrefixLength 24
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.100.10
  ```

**Server Manager reported roles missing after a Windows Update**

*Following an update and reboot, the Server Manager dashboard listed only File and Storage Services, with no AD DS, DNS, or DHCP entries. PowerShell confirmed the roles were intact and running; Server Manager had simply not refreshed its cached role inventory after the restart. No repair was needed. The takeaway is to verify against the service and role cmdlets rather than the dashboard, since those also work over remoting when no GUI is available.*
  ```powershell
  Get-ADDomain
  Get-Service NTDS, DNS, DHCPServer
  ```

**Export-DhcpServer failed with DirectoryNotFoundException**

*The backup export failed because the target folder did not exist. Most PowerShell cmdlets that write files will not create parent directories, by design, so that a mistyped path does not silently produce an unexpected folder. Fixed by creating the directory first.*
  ```powershell
  New-Item -Path "C:\Backup" -ItemType Directory
  Export-DhcpServer -File "C:\Backup\dhcp-config.xml" -Leases -Force
  ```

**DHCP Event ID 1056 warning**

*The System log recorded a warning that the DHCP service is running on a domain controller with no dedicated credentials configured for dynamic DNS registration. In that state DHCP registers client DNS records using the machine account, which carries more privilege than the task requires. Left as-is in the lab, but noted as a real finding. In production the fix is a dedicated low-privilege service account configured for dynamic DNS updates.*

**Stray APIPA address on the domain controller**

*Server Manager reported DC01 with two addresses: 192.168.100.10 and 169.254.23.45. The 169.254.x.x address is APIPA, self-assigned by an adapter set to DHCP that cannot reach a DHCP server, indicating a second virtual network adapter attached to nothing. Harmless in isolation but capable of causing incorrect DNS registration for the DC. Identified and resolved by removing the unused adapter.*
  ```powershell
  Get-NetAdapter
  Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, IPAddress
  ```

**Virtual machine connection dropped on restart**

*Restarting the server produced a "The session was disconnected" dialog in the Virtual Machine Connection window. This is expected behavior rather than a fault: VMConnect uses an RDP-based session for enhanced session mode, and that session is torn down when the guest restarts. The VM status remained Running throughout. Reconnecting after the guest finished booting restored the session.*

**Production Considerations**

*DHCP dynamic DNS registration should run under a dedicated service account rather than the domain controller machine account. Scope options in this lab omit a default gateway because the internal virtual switch provides no route off the subnet; a production scope would include option 003.*
