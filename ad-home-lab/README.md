# Active Directory Home Lab on Azure, with PowerShell Automation

A small Windows domain built in Microsoft Azure to practice Level 1–2 IT support and systems administration: domain controller setup, DNS, Group Policy, file share permissions, and scripted user onboarding, offboarding, and password resets. It's managed from a Mac over Remote Desktop.

> Building on a Windows PC instead? See [docs/virtualbox-setup.md](docs/virtualbox-setup.md) for the local VirtualBox version.

## Lab design

```
   Your Mac ── Windows App (RDP, allowed from your IP only) ──┐
                                                             │
   Azure  ·  Resource group rg-adlab  ·  VNet vnet-adlab (10.0.0.0/16)
             Subnet snet-lab 10.0.50.0/24  ·  VNet DNS → 10.0.50.10
             │                                   │
     DC01  10.0.50.10 (static)            CLIENT01  (dynamic)
     Windows Server 2025                  Windows Server 2025
     AD DS · DNS · File shares            Joined to lab.khadka.local
```

| Item | Value |
|---|---|
| Domain | `lab.khadka.local` (NetBIOS `KHADKALAB`) |
| DC01 | Windows Server 2025 Datacenter, size B2s (2 vCPU, 4 GB), private IP 10.0.50.10 static |
| CLIENT01 | Windows Server 2025 Datacenter, size B2s, acts as the domain "workstation" |
| OUs | `Lab\Users\{IT,HR,Finance,Operations}`, `Lab\Computers`, `Lab\Groups`, `Lab\Disabled Users` |
| Groups | `GG_IT`, `GG_HR`, `GG_Finance`, `GG_Operations` |
| Shares | `\\DC01\IT`, `\\DC01\HR`, `\\DC01\Finance`, `\\DC01\Operations` |

**Why the client runs Windows Server:** Windows 11 images in Azure need a separate eligible license. A Windows Server VM joins the domain, receives Group Policy, maps drives, and enforces lockouts the same way a workstation does, and its license is included in the Azure price.

**How Azure differs from a local lab:** Azure runs DHCP for every virtual network, so you don't install a DHCP server. Instead, you give DC01 a static private IP *in Azure* (not inside Windows) and point the virtual network's DNS setting at it.

## Before you start

- **Azure for Students:** sign up at azure.microsoft.com/free/students with your **A-State email** while you're still enrolled. It gives $100 of credit and needs no credit card. When the credit runs out, the subscription stops rather than billing you.
- **Windows App** (Microsoft's Remote Desktop client) from the Mac App Store.
- **Cost rule:** VMs bill while they're running. Always **Stop** them in the Azure portal when you're done. Shutting down from inside Windows does *not* stop billing. Turning on auto-shutdown (Phase 1) is your safety net.

---

## Phase 1: Build the Azure resources (about 45 minutes)

In the Azure portal (portal.azure.com):

1. **Resource group.** Create `rg-adlab` in a region near you, such as *South Central US* or *Central US*. Put everything below in this resource group and region.
2. **Virtual network.** Create `vnet-adlab` with address space `10.0.0.0/16` and one subnet, `snet-lab` = `10.0.50.0/24`.
3. **DC01 VM.** Go to Virtual machines → Create:
   - Image: **Windows Server 2025 Datacenter – x64 Gen2** (with Desktop Experience, not Core)
   - Size: **B2s**. If it's not offered in your region, pick B2ms or try another region.
   - Administrator username: `labadmin` (Azure doesn't allow "administrator") and a strong password
   - Public inbound ports: allow **RDP (3389)**. You'll lock it to your IP in step 5.
   - Disks: **Standard SSD** (cheaper than Premium)
   - Networking: `vnet-adlab` / `snet-lab`, with a new public IP
   - Management: turn on **Auto-shutdown** (for example 11:00 PM Central)
4. **Static private IP.** Open DC01 → Networking → click the network interface → **IP configurations** → ipconfig1 → set Assignment to **Static**, IP `10.0.50.10` → Save.
5. **Lock down RDP.** In DC01 → Networking, edit the RDP inbound rule: set **Source = My IP address**. Do the same for CLIENT01 after you create it. This keeps the rest of the internet from guessing your passwords.
6. **CLIENT01 VM.** Create it the same way: same image, size, `labadmin` username, vnet/subnet, and auto-shutdown. Leave its IP dynamic.

📸 Screenshots: the resource group's resource list, DC01's IP configuration showing static 10.0.50.10, the locked-down RDP rule.

## Phase 2: Domain controller (about 30 minutes)

1. On your Mac, open **Windows App** → Add PC → DC01's public IP → sign in as `labadmin`.
2. Get the scripts onto DC01. The easiest way is to push this repo to GitHub, open Edge on DC01, download the repo ZIP, and extract it to `C:\ad-home-lab`.
3. Open **PowerShell as Administrator**:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   cd C:\ad-home-lab\scripts
   .\02-Install-ADForest.ps1     # installs AD DS + DNS, creates lab.khadka.local, restarts
   ```
   Skip `01-Set-DCNetwork.ps1`. Azure already named the computer DC01 and set its IP. The restart takes 5–10 minutes.
4. Reconnect and sign in as **`KHADKALAB\labadmin`**. Your local admin is now the domain admin. Then run:
   ```powershell
   cd C:\ad-home-lab\scripts
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\03-Configure-DNS-DHCP.ps1 -Azure   # DNS forwarder to Azure DNS; skips DHCP
   .\04-Build-OUStructure.ps1           # OUs, department groups, department shares
   ```
5. **Point the network at your DC.** In the portal, open `vnet-adlab` → **DNS servers** → Custom → `10.0.50.10` → Save. Then **Restart CLIENT01** from the portal so it picks up the new DNS.

Check it worked (on DC01):
```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName
Get-ADOrganizationalUnit -Filter * | Select-Object DistinguishedName
Resolve-DnsName lab.khadka.local
Resolve-DnsName microsoft.com      # proves the forwarder works
```

📸 Screenshots: Server Manager, the Active Directory Users and Computers OU tree, the VNet DNS setting.

## Phase 3: Join CLIENT01 to the domain (about 15 minutes)

RDP to CLIENT01 as its local `labadmin` and open PowerShell as Administrator:
```powershell
ipconfig /all                        # DNS Servers should show 10.0.50.10
Resolve-DnsName lab.khadka.local     # must succeed before joining
Add-Computer -DomainName lab.khadka.local -Credential KHADKALAB\labadmin -Restart
```
On DC01, confirm CLIENT01 appears in **Lab\Computers**.

**If the join fails with "domain could not be contacted":** DNS is almost always the cause. Check the VNet DNS setting, restart CLIENT01 from the portal, and run `ipconfig /all` again. Write down what happened, because it makes a good interview story.

## Phase 4: Onboard users with PowerShell (about 15 minutes)

On DC01:
```powershell
.\New-LabUser.ps1 -CsvPath ..\data\new-hires.csv -WhatIf   # preview, changes nothing
.\New-LabUser.ps1 -CsvPath ..\data\new-hires.csv           # create the accounts
```
Use a temporary password of at least 12 characters, so it meets the password policy you set in Phase 5.

The sample CSV includes two deliberate test cases:
- **Jordan Lee and Jamie Lee** both map to `jlee`, so the second becomes `jlee2` (duplicate-username handling).
- **Marcus Bell** is in `Marketing`, which isn't a valid department, so the row fails cleanly and is logged (input validation).

Each run writes a CSV log to `logs\`.

## Phase 5: Group Policy (about 1 hour)

Open **Group Policy Management** (`gpmc.msc`) on DC01.

**A. Password and lockout policy.** Edit **Default Domain Policy** → Computer Configuration → Policies → Windows Settings → Security Settings → Account Policies:
- Password Policy: minimum length **12**, complexity **Enabled**, maximum age **90 days**
- Account Lockout Policy: threshold **5** invalid attempts, duration **15 minutes**

**B. Let domain users sign in to CLIENT01 over Remote Desktop.** In Azure, RDP is the only way to "sit at" the workstation. Right-click **Lab\Computers** → create and link `Lab RDP Access`, then edit it:
- Computer Configuration → Preferences → Control Panel Settings → **Local Users and Groups** → New → Local Group: Action **Update**, Group **Remote Desktop Users (built-in)**, Members → Add `KHADKALAB\Domain Users`
- Computer Configuration → Policies → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Session Host → Security → **Require user authentication for remote connections by using Network Level Authentication = Disabled**. This lab-only setting lets new users complete the forced password change at their first RDP sign-in. It's safe here because RDP only accepts connections from your IP.

**C. Department mapped drives.** For each department OU under `Lab\Users`, create and link a GPO like `Map S Drive - HR`. Edit it: User Configuration → Preferences → Windows Settings → **Drive Maps** → New → Mapped Drive:
- Action **Update**, Location `\\DC01\HR`, Reconnect checked, Label `HR Share`, Drive letter **S:**

**D. Workstation security baseline.** On **Lab\Computers**, create and link `Workstation Security Baseline`. Under Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → **Security Options**:
- Interactive logon: Machine inactivity limit = **900** seconds
- Interactive logon: Message title / Message text = an "Authorized use only" logon banner

**Test it.** On CLIENT01 (as labadmin), run `gpupdate /force` and restart it. Then from your Mac, connect to CLIENT01 as `KHADKALAB\ppatel` with the temporary password:
- You should be prompted to change the password.
- The logon banner appears.
- The **S:** drive opens `\\DC01\HR`; opening `\\DC01\Finance` gives **Access denied**.
- `gpresult /r` lists the GPOs that applied.

📸 Screenshots: GPMC with the linked GPOs, the banner, the S: drive, `gpresult /r`, the access-denied message.

## Phase 6: Help-desk scenarios (about 30 minutes)

**Locked-out user.** Try to RDP to CLIENT01 as `KHADKALAB\ebrooks` with a wrong password 5 times. Then on DC01:
```powershell
.\Reset-LabUserPassword.ps1 -Username ebrooks -Ticket INC0010045
```

**Offboarding.** An employee leaves:
```powershell
.\Remove-LabUser.ps1 -Username jlee2 -Ticket RITM0010023 -WhatIf
.\Remove-LabUser.ps1 -Username jlee2 -Ticket RITM0010023
```
Confirm the account is disabled, sits in **Lab\Disabled Users**, has no group memberships, and has the ticket number in its description.

📸 Screenshots: the locked-out account before and after, the disabled account's properties.

## When you're done

- **Stop both VMs** in the portal after every session.
- When the project is finished and your screenshots are saved, **delete the `rg-adlab` resource group**. That removes everything at once, so nothing keeps using credit (public IPs cost a little even when VMs are stopped).

---

## Scripts

| Script | Purpose |
|---|---|
| `01-Set-DCNetwork.ps1` | Local labs only: static IP and rename (skip on Azure) |
| `02-Install-ADForest.ps1` | Install AD DS + DNS and create the forest |
| `03-Configure-DNS-DHCP.ps1` | DNS forwarders; `-Azure` skips DHCP, local mode installs and scopes it |
| `04-Build-OUStructure.ps1` | OUs, department security groups, NTFS/SMB-permissioned shares |
| `New-LabUser.ps1` | Bulk onboarding from CSV with unique usernames, validation, logging, `-WhatIf` |
| `Remove-LabUser.ps1` | Offboarding: strip groups, scramble password, disable, move, ticket stamp |
| `Reset-LabUserPassword.ps1` | Unlock and reset with forced change at next logon |

## What I learned

_Write 3–5 bullets after you finish. For example: a problem you hit (DNS, a GPO not applying, an RDP sign-in error) and how you diagnosed it._

## Screenshots

Put images in `docs/screenshots/` and link them here.
