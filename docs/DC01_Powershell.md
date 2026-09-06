*Add Directory to AD.*
  ```powershell
  New-Item -Path "C:\Scripts" -ItemType Directory
  @"
  FirstName,LastName,Department
  John,Smith,IT
  Maria,Garcia,HR
  David,Chen,Finance
  Sarah,Johnson,IT
  Michael,Brown,Operations
  "@ | Out-File -FilePath "C:\Scripts\newusers.csv" -Encoding UTF8
  ```
*Add Lab Users*
  ```powershell
  ise C:\Scripts\New-LabUsers.ps1
  ```
