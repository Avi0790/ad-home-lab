<#
.SYNOPSIS
    Step 4 (run on DC01): create the OU structure, department security groups, and department file shares.

.DESCRIPTION
    Builds this layout (safe to run more than once):

        Lab
        ├── Users
        │   ├── IT
        │   ├── HR
        │   ├── Finance
        │   └── Operations
        ├── Computers        <- new domain-joined PCs land here (via redircmp)
        ├── Groups           <- GG_IT, GG_HR, GG_Finance, GG_Operations
        └── Disabled Users   <- offboarded accounts are moved here

    It also creates C:\Shares\<Dept> folders shared as \\DC01\<Dept>, where only that
    department's group (plus admins) can read and write. These shares are what the
    drive-mapping GPO connects users to.

.EXAMPLE
    .\04-Build-OUStructure.ps1
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('IT', 'HR', 'Finance', 'Operations'),
    [string]  $ShareRoot   = 'C:\Shares'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$domain   = Get-ADDomain
$domainDN = $domain.DistinguishedName
$netbios  = $domain.NetBIOSName

function New-OUIfMissing {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "  Created OU $dn" -ForegroundColor Green
    } else {
        Write-Host "  OU exists: $dn"
    }
    return $dn
}

Write-Host 'Creating OUs...' -ForegroundColor Cyan
$labOU = New-OUIfMissing -Name 'Lab' -Path $domainDN
$usersOU = New-OUIfMissing -Name 'Users' -Path $labOU
$computersOU = New-OUIfMissing -Name 'Computers' -Path $labOU
$groupsOU = New-OUIfMissing -Name 'Groups' -Path $labOU
New-OUIfMissing -Name 'Disabled Users' -Path $labOU | Out-Null
foreach ($d in $Departments) { New-OUIfMissing -Name $d -Path $usersOU | Out-Null }

# Newly joined computers go to Lab\Computers instead of the default CN=Computers container,
# so GPOs linked to that OU apply to them automatically.
redircmp $computersOU | Out-Null
Write-Host "Default computer location redirected to $computersOU" -ForegroundColor Green

Write-Host 'Creating department groups and shares...' -ForegroundColor Cyan
foreach ($d in $Departments) {
    $group = "GG_$d"
    if (-not (Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $group -GroupScope Global -GroupCategory Security -Path $groupsOU `
            -Description "Members of the $d department"
        Write-Host "  Created group $group" -ForegroundColor Green
    }

    $folder = Join-Path $ShareRoot $d
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    # NTFS: remove inherited permissions, then grant only admins, SYSTEM, and the department group
    icacls $folder /inheritance:r /grant:r 'Administrators:(OI)(CI)F' 'SYSTEM:(OI)(CI)F' "${netbios}\${group}:(OI)(CI)M" | Out-Null

    if (-not (Get-SmbShare -Name $d -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $d -Path $folder -FullAccess 'Administrators' -ChangeAccess "$netbios\$group" | Out-Null
        Write-Host "  Shared $folder as \\$env:COMPUTERNAME\$d" -ForegroundColor Green
    }
}

Write-Host 'OU structure, groups, and shares are ready.' -ForegroundColor Green
