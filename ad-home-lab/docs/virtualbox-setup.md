# Active Directory Home Lab with PowerShell Automation

A small Windows domain built in VirtualBox to practice Level 1–2 IT support and systems administration tasks: domain controller setup, DNS/DHCP, Group Policy, file share permissions, and scripted user onboarding, offboarding, and password resets.

## Lab design

```
                Internet
                    │
         VirtualBox NAT Network "LabNet"  10.0.50.0/24  (gateway 10.0.50.1)
                    │
      ┌─────────────┴──────────────┐
      │                            │
  DC01  10.0.50.10 (static)     CLIENT01  (DHCP: 10.0.50.100–200)
  Windows Server 2025           Windows 11 Enterprise
  AD DS · DNS · DHCP · Files    Joined to lab.khadka.local
```

| Item | Value |
|---|---|
| Domain | `lab.khadka.local` (NetBIOS `KHADKALAB`) |
| Domain controller | `DC01`, 10.0.50.10, 2 vCPU, 4 GB RAM, 60 GB disk |
| Client | `CLIENT01`, DHCP, 2 vCPU, 4 GB RAM, 64 GB disk |
| DHCP scope | 10.0.50.100 – 10.0.50.200, DNS → 10.0.50.10 |
| OUs | `Lab\Users\{IT,HR,Finance,Operations}`, `Lab\Computers`, `Lab\Groups`, `Lab\Disabled Users` |
| Groups | `GG_IT`, `GG_HR`, `GG_Finance`, `GG_Operations` |
| Shares | `\\DC01\IT`, `\\DC01\HR`, `\\DC01\Finance`, `\\DC01\Operations` |

## What you need

- A Windows or Intel Mac host with **16 GB RAM** (8 GB works if you give each VM 3 GB and keep only these two running). An Apple Silicon (M1–M4) Mac can't run these x64 Windows images well in VirtualBox. Use a Windows PC instead, or build the same two VMs in Azure with the free Azure for Students credit.
- **VirtualBox 7.x** (free).
- **Windows Server 2025 evaluation** ISO (180-day trial) and **Windows 11 Enterprise evaluation** ISO (90-day trial), both free from the Microsoft Evaluation Center. Use Enterprise, not Home: Home edition can't join a domain.

---

## Phase 1: Build the VMs (about 1 hour)

1. In VirtualBox, open **File → Tools → Network Manager → NAT Networks** and create a network named `LabNet` with prefix `10.0.50.0/24`. **Uncheck "Enable DHCP"**, because DC01 will be the DHCP server.
2. Create **DC01**: Windows Server 2025, 2 CPUs, 4 GB RAM, 60 GB disk, attach the Server ISO, and set **Network → Attached to: NAT Network → LabNet**.
3. Install Windows Server and choose **Windows Server 2025 Standard Evaluation (Desktop Experience)** so you get the GUI. Set the local Administrator password.
4. Create **CLIENT01** the same way with the Windows 11 ISO. VirtualBox 7 enables TPM 2.0 and Secure Boot for Windows 11 automatically. Install it with a local account for now.
5. On both VMs, install **Guest Additions** (Devices menu) for clipboard sharing and screen resizing.
6. Copy this repo onto DC01, for example by sharing a host folder or cloning from GitHub. Open **PowerShell as Administrator** and allow scripts for this session:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   cd C:\ad-home-lab\scripts
   ```

📸 Screenshot: VirtualBox showing both VMs and the LabNet settings.

## Phase 2: Domain controller (about 30 minutes)

```powershell
.\01-Set-DCNetwork.ps1       # static IP 10.0.50.10, rename to DC01, restarts
.\02-Install-ADForest.ps1    # installs AD DS + DNS, creates lab.khadka.local, restarts
```
After the second restart, sign in as **KHADKALAB\Administrator** and run:
```powershell
.\03-Configure-DNS-DHCP.ps1  # DNS forwarders, DHCP role + scope
.\04-Build-OUStructure.ps1   # OUs, department groups, department shares
```

Check it worked:
```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName
Get-ADOrganizationalUnit -Filter * | Select-Object DistinguishedName
Get-DhcpServerv4Scope
Resolve-DnsName lab.khadka.local
```

📸 Screenshots: Server Manager dashboard, Active Directory Users and Computers showing the OU tree, the DHCP console scope.

## Phase 3: Join the client to the domain (about 15 minutes)

On **CLIENT01**:
1. Confirm it got an address from DC01: `ipconfig /all` should show an IP in 10.0.50.100–200 and DNS server 10.0.50.10.
2. Join the domain from an admin PowerShell:
   ```powershell
   Add-Computer -DomainName lab.khadka.local -Credential KHADKALAB\Administrator -Restart
   ```
3. On DC01, confirm CLIENT01 appears in **Lab\Computers**. This works because script 04 ran `redircmp`.

📸 Screenshot: System Properties on CLIENT01 showing the domain, and CLIENT01 in ADUC.

## Phase 4: Onboard users with PowerShell (about 15 minutes)

On DC01:
```powershell
.\New-LabUser.ps1 -CsvPath ..\data\new-hires.csv -WhatIf   # preview, changes nothing
.\New-LabUser.ps1 -CsvPath ..\data\new-hires.csv           # create the accounts
```
The sample CSV includes two deliberate test cases:
- **Jordan Lee and Jamie Lee** both map to `jlee`, so the second becomes `jlee2` (duplicate-username handling).
- **Marcus Bell** is in `Marketing`, which isn't a valid department, so the row fails cleanly and is logged without stopping the run (input validation).

Each run writes a CSV log to `logs\`. Pick a temporary password of at least 12 characters so it still meets the password policy you set in Phase 5.

📸 Screenshot: the script's output table and the users in ADUC.

## Phase 5: Group Policy (about 45 minutes)

Open **Group Policy Management** (`gpmc.msc`) on DC01.

**A. Password and lockout policy.** Edit **Default Domain Policy** → Computer Configuration → Policies → Windows Settings → Security Settings → Account Policies:
- Password Policy: minimum length **12**, complexity **Enabled**, maximum age **90 days**
- Account Lockout Policy: threshold **5** invalid attempts, duration **15 minutes**

**B. Department mapped drives.** For each department OU under `Lab\Users`, right-click it → **Create a GPO in this domain, and link it here**, and name it like `Map S Drive - HR`. Edit it: User Configuration → Preferences → Windows Settings → **Drive Maps** → New → Mapped Drive:
- Action **Update**, Location `\\DC01\HR`, Reconnect checked, Label `HR Share`, Drive letter **S:**

**C. Workstation security baseline.** Right-click **Lab\Computers** → create and link `Workstation Security Baseline`. Under Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → **Security Options**:
- Interactive logon: Machine inactivity limit = **900** seconds (auto-lock after 15 minutes)
- Interactive logon: Message title / Message text = an "Authorized use only" logon banner

**Test it.** On CLIENT01, sign in as one of the new users (for example `KHADKALAB\ppatel`) with the temporary password. You should be forced to change it. Then:
```powershell
gpupdate /force
gpresult /r      # shows which GPOs applied to the user and computer
```
Check that the S: drive opens the right department share. Then try to open another department's share by UNC path; it should be **access denied**.

📸 Screenshots: GPMC with the linked GPOs, the logon banner, the S: drive in File Explorer, `gpresult /r` output, the access-denied message.

## Phase 6: Help-desk scenarios (about 30 minutes)

**Locked-out user.** On CLIENT01, enter a wrong password for `ebrooks` 5 times to trigger the lockout policy. Then on DC01:
```powershell
.\Reset-LabUserPassword.ps1 -Username ebrooks -Ticket INC0010045
```

**Offboarding.** An employee leaves:
```powershell
.\Remove-LabUser.ps1 -Username jlee2 -Ticket RITM0010023 -WhatIf
.\Remove-LabUser.ps1 -Username jlee2 -Ticket RITM0010023
```
Confirm the account is disabled, sits in **Lab\Disabled Users**, has no group memberships, and has the ticket number in its description. The log in `logs\` lists the groups that were removed.

📸 Screenshots: the locked-out account before and after, the disabled account's properties.

---

## Scripts

| Script | Purpose |
|---|---|
| `01-Set-DCNetwork.ps1` | Static IP and rename for the domain controller |
| `02-Install-ADForest.ps1` | Install AD DS + DNS and create the forest |
| `03-Configure-DNS-DHCP.ps1` | DNS forwarders; install, authorize, and scope DHCP |
| `04-Build-OUStructure.ps1` | OUs, department security groups, NTFS/SMB-permissioned shares |
| `New-LabUser.ps1` | Bulk onboarding from CSV with unique usernames, validation, logging, `-WhatIf` |
| `Remove-LabUser.ps1` | Offboarding: strip groups, scramble password, disable, move, ticket stamp |
| `Reset-LabUserPassword.ps1` | Unlock and reset with forced change at next logon |

## What I learned

_Write 3–5 bullets here after you finish. For example: a problem you hit (DNS pointing at the wrong server, a GPO not applying) and how you diagnosed it. Interviewers like these troubleshooting stories._

## Screenshots

Put images in `docs/screenshots/` and link them here.
