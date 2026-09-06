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
*Clear post install flags and restart service*
  ```powershell
  Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name ConfigurationState -Value 2
  Restart-Service DHCPServer
  ```
*Verify*
  ```powershell
  Get-DhcpServerv4Scope
  Get-DhcpServerInDC
```
