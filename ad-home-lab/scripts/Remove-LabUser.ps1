<#
.SYNOPSIS
    Offboard users: disable the account, scramble the password, strip group memberships, and move it to Disabled Users.

.DESCRIPTION
    Follows a typical help-desk offboarding checklist. For each username:
      1. Records the user's current groups (so access can be restored if HR reverses the change).
      2. Removes the user from every group except their primary group (Domain Users).
      3. Resets the password to a long random value so any saved credentials stop working.
      4. Disables the account and stamps the description with the date, who did it, and the ticket number.
      5. Moves the account to Lab\Disabled Users.
    Accounts are disabled, not deleted, so they can be reviewed or restored later.
    Writes a CSV log including the removed groups. Supports -WhatIf.

.PARAMETER Username
    One or more sAMAccountNames to offboard.

.PARAMETER Ticket
    Ticket or request number (e.g. a ServiceNow RITM/INC number) recorded on the account.

.EXAMPLE
    .\Remove-LabUser.ps1 -Username jdoe -Ticket RITM0010023 -WhatIf
    .\Remove-LabUser.ps1 -Username jdoe, asmith -Ticket RITM0010023
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string[]]$Username,
    [Parameter(Mandatory)][string]  $Ticket,
    [string]$LogDir = (Join-Path $PSScriptRoot '..\logs')
)

$ErrorActionPreference = 'Stop'
$domain     = Get-ADDomain
$disabledOU = "OU=Disabled Users,OU=Lab,$($domain.DistinguishedName)"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function New-RandomPassword {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    # Base64 of 24 random bytes + a fixed suffix guarantees upper, lower, digit, and symbol
    ConvertTo-SecureString -String ([Convert]::ToBase64String($bytes) + 'aA1!') -AsPlainText -Force
}

$results = foreach ($sam in $Username) {
    $groupNames = ''
    try {
        $user   = Get-ADUser -Identity $sam -Properties MemberOf
        $groups = @($user.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name })
        $groupNames = $groups -join '; '

        if ($PSCmdlet.ShouldProcess("$sam ($($user.Name))", 'Disable, reset password, remove groups, move to Disabled Users')) {
            foreach ($g in $user.MemberOf) {
                Remove-ADGroupMember -Identity $g -Members $user.ObjectGUID -Confirm:$false
            }
            Set-ADAccountPassword -Identity $user.ObjectGUID -Reset -NewPassword (New-RandomPassword)
            Disable-ADAccount -Identity $user.ObjectGUID
            Set-ADUser -Identity $user.ObjectGUID -Description ("Disabled {0:yyyy-MM-dd} by {1} - {2}" -f (Get-Date), $env:USERNAME, $Ticket)
            Move-ADObject -Identity $user.ObjectGUID -TargetPath $disabledOU
            $status = 'Offboarded'
            Write-Host "Offboarded $sam (removed from: $(if ($groupNames) { $groupNames } else { 'no extra groups' }))" -ForegroundColor Green
        } else {
            $status = 'WhatIf'
        }

        [pscustomobject]@{ Time = Get-Date -Format s; Username = $sam; Ticket = $Ticket; Status = $status; RemovedGroups = $groupNames; Message = '' }
    }
    catch {
        Write-Warning "${sam}: $($_.Exception.Message)"
        [pscustomobject]@{ Time = Get-Date -Format s; Username = $sam; Ticket = $Ticket; Status = 'Failed'; RemovedGroups = $groupNames; Message = $_.Exception.Message }
    }
}

$logFile = Join-Path $LogDir ("offboard-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$results | Export-Csv -Path $logFile -NoTypeInformation
$results | Format-Table Username, Ticket, Status, RemovedGroups, Message -AutoSize
Write-Host "Log written to $logFile" -ForegroundColor Cyan
