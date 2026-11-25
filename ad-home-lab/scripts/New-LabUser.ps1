<#
.SYNOPSIS
    Onboard new hires from a CSV: create AD accounts, place them in the right OU, and add them to their department group.

.DESCRIPTION
    For each row in the CSV (FirstName, LastName, Department, Title, Manager):
      - Builds a username as first initial + last name (e.g. Jane Doe -> jdoe), adding a
        number if that name is taken (jdoe2, jdoe3, ...).
      - Creates the account in Lab\Users\<Department>, enabled, with a temporary password
        the user must change at first logon.
      - Adds the user to GG_<Department>, which gives them their department share and mapped drive.
      - Writes a timestamped CSV log of every row (Created / Failed / WhatIf) to the logs folder.

    Supports -WhatIf so you can preview exactly what would happen without changing anything.

.PARAMETER CsvPath
    Path to the new-hire CSV. See data\new-hires.csv for the format.

.EXAMPLE
    .\New-LabUser.ps1 -CsvPath ..\data\new-hires.csv -WhatIf
    .\New-LabUser.ps1 -CsvPath ..\data\new-hires.csv
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]  $LogDir      = (Join-Path $PSScriptRoot '..\logs'),
    [string[]]$Departments = @('IT', 'HR', 'Finance', 'Operations')
)

$ErrorActionPreference = 'Stop'
$domain = Get-ADDomain
$labOU  = "OU=Lab,$($domain.DistinguishedName)"

$tempPassword = Read-Host 'Temporary password for the new accounts (users must change it at first logon)' -AsSecureString
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$results = foreach ($row in Import-Csv -Path $CsvPath) {
    $first = "$($row.FirstName)".Trim()
    $last  = "$($row.LastName)".Trim()
    $dept  = "$($row.Department)".Trim()
    $sam   = ''

    try {
        if (-not $first -or -not $last) { throw 'FirstName and LastName are required.' }
        if ($dept -notin $Departments)   { throw "Unknown department '$dept'. Valid: $($Departments -join ', ')" }

        # Username: first initial + last name, letters/digits only, max 20 chars with room for a suffix
        $base = (($first.Substring(0, 1) + $last) -replace '[^a-zA-Z0-9]', '').ToLower()
        if ($base.Length -gt 18) { $base = $base.Substring(0, 18) }
        $sam = $base
        $n = 1
        while (Get-ADUser -Filter "SamAccountName -eq '$sam'") { $n++; $sam = "$base$n" }

        $displayName = "$first $last"
        $cn = if ($n -gt 1) { "$displayName $n" } else { $displayName }   # CN must be unique within the OU

        $params = @{
            Name                  = $cn
            GivenName             = $first
            Surname               = $last
            DisplayName           = $displayName
            SamAccountName        = $sam
            UserPrincipalName     = "$sam@$($domain.DNSRoot)"
            Department            = $dept
            Path                  = "OU=$dept,OU=Users,$labOU"
            AccountPassword       = $tempPassword
            Enabled               = $true
            ChangePasswordAtLogon = $true
        }
        if ($row.Title)   { $params.Title   = $row.Title.Trim() }
        if ($row.Manager) { $params.Manager = (Get-ADUser -Identity $row.Manager.Trim()).DistinguishedName }

        if ($PSCmdlet.ShouldProcess("$displayName ($sam) in $dept", 'Create AD user and add to GG_' + $dept)) {
            New-ADUser @params
            Add-ADGroupMember -Identity "GG_$dept" -Members $sam
            $status = 'Created'
            Write-Host "Created $sam ($displayName) in $dept" -ForegroundColor Green
        } else {
            $status = 'WhatIf'
        }

        [pscustomobject]@{ Time = Get-Date -Format s; Username = $sam; Name = $displayName; Department = $dept; Status = $status; Message = '' }
    }
    catch {
        Write-Warning "Row '$first $last': $($_.Exception.Message)"
        [pscustomobject]@{ Time = Get-Date -Format s; Username = $sam; Name = "$first $last"; Department = $dept; Status = 'Failed'; Message = $_.Exception.Message }
    }
}

$logFile = Join-Path $LogDir ("onboard-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$results | Export-Csv -Path $logFile -NoTypeInformation
$results | Format-Table Username, Name, Department, Status, Message -AutoSize
Write-Host "Log written to $logFile" -ForegroundColor Cyan
