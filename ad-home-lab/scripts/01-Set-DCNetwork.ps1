<#
.SYNOPSIS
    Step 1 (run on the server VM): give the server a static IP and rename it to DC01.

.DESCRIPTION
    A domain controller needs a fixed IP address so clients can always find it for DNS
    and logons. This script sets the static IP, points DNS at a public resolver for now
    (so Windows Update and downloads work before AD DNS exists), then renames the
    computer and restarts.

.EXAMPLE
    .\01-Set-DCNetwork.ps1
#>
[CmdletBinding()]
param(
    [string]$ComputerName = 'DC01',
    [string]$IPAddress    = '10.0.50.10',
    [int]   $PrefixLength = 24,
    [string]$Gateway      = '10.0.50.1',
    [string]$TempDns      = '1.1.1.1'
)

$ErrorActionPreference = 'Stop'

$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $nic) { throw 'No connected network adapter found.' }
Write-Host "Configuring adapter '$($nic.Name)'..." -ForegroundColor Cyan

# Clear any DHCP address and old default route before setting the static IP
Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false

New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $TempDns

Write-Host "Static IP $IPAddress/$PrefixLength set (gateway $Gateway)." -ForegroundColor Green

if ($env:COMPUTERNAME -ne $ComputerName) {
    Write-Host "Renaming computer to $ComputerName and restarting..." -ForegroundColor Cyan
    Rename-Computer -NewName $ComputerName -Restart
} else {
    Write-Host "Computer is already named $ComputerName." -ForegroundColor Green
}
