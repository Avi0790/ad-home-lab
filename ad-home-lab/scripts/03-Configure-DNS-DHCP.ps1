<#
.SYNOPSIS
    Step 3 (run on DC01 as a domain admin): configure DNS forwarders and, for local labs, DHCP.

.DESCRIPTION
    - Adds DNS forwarders so domain machines can still resolve internet names.
    - Local lab (VirtualBox/Hyper-V): sets DC01's DNS client to its own IP, then installs DHCP,
      authorizes it in AD, and creates a scope that hands out addresses, gateway, DNS, and domain name.
    - Azure (-Azure): Azure assigns IPs and runs its own DHCP, so the DHCP part is skipped.
      The guest NIC stays on DHCP (Azure hands out the static private IP you set on the NIC),
      and the forwarder is Azure's built-in DNS resolver, 168.63.129.16.

.EXAMPLE
    .\03-Configure-DNS-DHCP.ps1 -Azure      # Azure lab
    .\03-Configure-DNS-DHCP.ps1             # local VirtualBox lab
#>
[CmdletBinding()]
param(
    [switch]  $Azure,
    [string]  $DcIP        = '10.0.50.10',
    [string]  $ScopeId     = '10.0.50.0',
    [string]  $StartRange  = '10.0.50.100',
    [string]  $EndRange    = '10.0.50.200',
    [string]  $SubnetMask  = '255.255.255.0',
    [string]  $Gateway     = '10.0.50.1',
    [string[]]$Forwarders
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$domain = Get-ADDomain
$fqdn   = "$env:COMPUTERNAME.$($domain.DNSRoot)"

if (-not $Forwarders) {
    $Forwarders = if ($Azure) { @('168.63.129.16') } else { @('1.1.1.1', '8.8.8.8') }
}

# --- DNS ---------------------------------------------------------------
Write-Host 'Configuring DNS forwarders...' -ForegroundColor Cyan
$existing = @((Get-DnsServerForwarder).IPAddress | ForEach-Object { $_.IPAddressToString })
foreach ($f in $Forwarders) {
    if ($existing -notcontains $f) { Add-DnsServerForwarder -IPAddress $f }
}
Write-Host "DNS forwarders: $($Forwarders -join ', ')" -ForegroundColor Green

if ($Azure) {
    Write-Host 'Azure mode: skipping DHCP (Azure provides it). Set the virtual network DNS server to the DC IP in the portal.' -ForegroundColor Yellow
    return
}

$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $DcIP

# --- DHCP (local labs only) ---------------------------------------------
Write-Host 'Installing and configuring DHCP...' -ForegroundColor Cyan
Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue
Restart-Service -Name DHCPServer

if (-not (Get-DhcpServerInDC | Where-Object DnsName -eq $fqdn)) {
    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $DcIP
}

if (-not (Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.IPAddressToString -eq $ScopeId })) {
    Add-DhcpServerv4Scope -Name 'LabNet' -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask -State Active
}
Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Gateway -DnsServer $DcIP -DnsDomain $domain.DNSRoot

# Tell Server Manager the DHCP post-install wizard is done (removes the yellow flag)
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

Write-Host "DHCP scope $StartRange - $EndRange is active." -ForegroundColor Green
