**DHCP Installation and Configuratation**

*To install DHCP onto the server via Powershell I used the script bellow.*

```powershell
Install-WindowsFeature DHCP -IncludeManagementTools
```

*Next I added the DHCP server to DC01. This is the primary DC for this lab.*

```powershell
  Add-DhcpServerInDC -DnsName "DC01.lab.local" -IPAddress 192.168.100.10
```

