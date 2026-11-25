<#
.SYNOPSIS
    Help-desk password reset: unlock the account, set a temporary password, and force a change at next logon.

.DESCRIPTION
    The most common Level 1 ticket. Shows the account's current state (enabled, locked out,
    last bad password attempt, password last set), then unlocks it and sets a temporary
    password the user must change at next sign-in. Supports -WhatIf.

.EXAMPLE
    .\Reset-LabUserPassword.ps1 -Username jdoe -Ticket INC0010045
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Username,
    [string]$Ticket = ''
)

$ErrorActionPreference = 'Stop'

$user = Get-ADUser -Identity $Username -Properties Enabled, LockedOut, LastBadPasswordAttempt, BadLogonCount, PasswordLastSet
$user | Select-Object SamAccountName, Name, Enabled, LockedOut, BadLogonCount, LastBadPasswordAttempt, PasswordLastSet | Format-List

if (-not $user.Enabled) {
    Write-Warning "$Username is disabled. Check whether the account was offboarded before re-enabling it."
    return
}

$temp = Read-Host "New temporary password for $Username" -AsSecureString

if ($PSCmdlet.ShouldProcess($Username, 'Unlock account and reset password')) {
    if ($user.LockedOut) { Unlock-ADAccount -Identity $Username; Write-Host 'Account unlocked.' -ForegroundColor Green }
    Set-ADAccountPassword -Identity $Username -Reset -NewPassword $temp
    Set-ADUser -Identity $Username -ChangePasswordAtLogon $true
    Write-Host "Password reset for $Username; user must change it at next logon. $Ticket" -ForegroundColor Green
}
