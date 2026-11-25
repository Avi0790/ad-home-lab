<#
.SYNOPSIS
    Step 2 (run on DC01 after step 1's restart): install AD DS + DNS and create a new forest.

.DESCRIPTION
    Installs the Active Directory Domain Services role and promotes this server to the
    first domain controller of a new forest. You will be asked for a DSRM (Directory
    Services Restore Mode) password. Write it down; it's used for AD recovery.
    The server restarts automatically when promotion finishes.

.EXAMPLE
    .\02-Install-ADForest.ps1
#>
[CmdletBinding()]
param(
    [string]$DomainName  = 'lab.khadka.local',
    [string]$NetbiosName = 'KHADKALAB'
)

$ErrorActionPreference = 'Stop'

Write-Host 'Installing AD DS role and management tools...' -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

$dsrm = Read-Host 'Enter a DSRM (restore mode) password' -AsSecureString

Write-Host "Creating forest '$DomainName' (NetBIOS: $NetbiosName). The server will restart..." -ForegroundColor Cyan
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -Force
