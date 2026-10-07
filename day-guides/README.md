# Intune and Entra ID Lab

*Index, environment reference, and the things worth knowing before opening any single day.*

MD-102 study track · Days 1 to 8, 17 to 27 August 2026. Days 9 onward are in the [lab log](../LAB-LOG.md).

## The day guides

| Day | Subject | The thing that cost the most time |
|---|---|---|
| [**1**](day-01-tenant-licensing-and-the-lab-vm.md)  17 Aug | **Tenant, Licensing and the Lab VM**  Getting a tenant with Intune rights and a VM that Windows 11 will run on. | Hyper-V reserving full startup memory. Hit three times. |
| [**2**](day-02-users-groups-and-tenant-device-settings.md)  19 Aug | **Users, Groups and Tenant Device Settings**  Directory, assigned versus dynamic membership, roles, and the gates above Intune. | Intune Administrator cannot edit Entra Device settings. That is Cloud Device Administrator. |
| [**3**](day-03-windows-install-entra-join-and-intune-enrolment.md)  19–20 Aug | **Windows Install, Entra Join and Intune Enrolment**  The long one. DISM deployment, join versus register, MDM authority. | Three days on a VM that would not boot. Then a full day on error 80180003. |
| [**4**](day-04-compliance-configuration-and-bitlocker.md)  21 Aug | **Compliance, Configuration and BitLocker**  Judging a device versus changing one, and what BitLocker needs. | A verifiably healthy device reporting non-compliant, because attestation is not live state. |
| [**5**](day-05-windows-autopilot.md)  24 Aug | **Windows Autopilot**  Hardware hash, deployment profile, ZTDid group rule, ESP. | Profile stuck at "Not assigned" because the group rule matched enrolled devices, not registered ones. |
| [**6**](day-06-autopilot-end-to-end-deployment.md)  24 Aug | **Autopilot End-to-End Deployment**  Remote wipe, then letting Autopilot rebuild the device from OOBE. | Error 801c03ed at Entra join, caused by our own Day 2 hardening. ESP account setup unresolved. |
| [**7**](day-07-orphaned-devices-policy-stores-and-admx.md) 24 to 25 Aug | **Orphaned Devices, Policy Stores and Administrative Templates** Recovering a device Intune could no longer reach. | Three hours proving a policy worked when it had worked all along. |
| [**8**](day-08-assignment-filters-and-android-enrolment.md) 26 to 27 Aug | **Assignment Filters and Android Enrolment** Targeting without touching groups, and a second platform on real hardware. | Android setup needed a mailbox on the Entra account, mentioned nowhere in the blade. |

## Environment

| Item | Value |
|---|---|
| Tenant | `labtenant.onmicrosoft.com` |
| Global administrator | `admin@labtenant.onmicrosoft.com` |
| Licensing | Microsoft Intune Suite trial, 250 licences, expires 15 November 2026, recurring billing off. Entra ID P2 trial, 100 licences. One paid Intune Plan 1 seat, CHF 6.50/month, as the required base plan. |
| Host | Dell XPS, Windows 11 Pro, 15.46 GB RAM. VMs on `D:\VMs`. |
| Lab VM | Hyper-V name `W11-CORP-01`, Windows hostname `LABVMGOCE`. Generation 2, 4 GB startup, 2 vCPU, 64 GB dynamic disk, vTPM, Secure Boot on, Default Switch. |
| Autopilot serial | `<serial-redacted>` |
| Answer file | `D:\VMs\unattend.xml`, Swiss French keyboard, fr-CH locale, en-GB UI, W. Europe timezone, local admin account |

## Direct URLs worth keeping

| Purpose | URL |
|---|---|
| Intune admin centre | `intune.microsoft.com` |
| Entra admin centre | `entra.microsoft.com` |
| Microsoft 365 admin centre (licensing, billing) | `admin.microsoft.com` |
| **Enrolment diagnostic**, run this first when enrolment fails | `https://aka.ms/IntuneWindowsEnrollment` |
| **MDM authority**, no menu path exists, direct URL only | `intune.microsoft.com/#view/Microsoft_Intune_Enrollment/ChooseMDMAuthorityBlade` |

## The distinctions that everything else hangs off

### Entra ID owns identity. Intune owns management.

Two separate services, two separate portals, two separate sets of admin roles. A device's *identity*, is it joined, who owns it, how many devices may a user have, is Entra. What is *done* to that device, policy, compliance, apps, wipe, is Intune. Nearly every "why can't I edit this" moment traces back to being in the wrong service.

### Joined versus registered

**Joined**: the device belongs to the organisation, the user signs in to Windows with the work account. **Registered**: a work account added to a device the organisation does not own. `dsregcmd /status` is the only reliable way to tell which one you have.

### Compliance versus configuration

**Compliance** evaluates and returns a verdict. It changes nothing. Its output is what Conditional Access consumes. **Configuration** changes the device, silently, with no user prompt.

### Purchased versus assigned

A licence in the tenant's pool grants nothing. It must be assigned to a user, and that user must sign in again before the new rights are in their token.

### Attestation versus local evaluation

Some settings read a boot-time report signed by the TPM. Others read the live device. The boot-time ones only change after a restart. Self-deploying Autopilot and pre-provisioning are a different matter: they need TPM attestation to the Autopilot service, and Microsoft does not support them on virtual machines.

This section first said a virtual TPM could not satisfy the boot-time compliance settings at all. The rebuild disproved that: all three passed on a Hyper-V virtual TPM 2.0.

## Diagnostic commands, by what you need to know

| Question | Command | Machine |
|---|---|---|
| Is this device joined, and how? | `dsregcmd /status` | VM |
| Am I even on the right machine? | `dsregcmd /status` → read `Device Name` first | Either |
| Is it genuinely enrolled in Intune? | `(Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*").Count`  Non-zero means yes. | VM |
| Is BitLocker actually on? | `Get-BitLockerVolume -MountPoint C:` | VM |
| Is Secure Boot actually on? | `Confirm-SecureBootUEFI` | VM |
| What editions are in this install.wim? | `Get-WindowsImage -ImagePath "E:\sources\install.wim"` | Laptop |
| Get the Autopilot hardware hash | `Get-WindowsAutopilotInfo -OutputFile C:\HWID.csv` | VM |

## Failure patterns seen more than once

| Pattern | Where it appeared | What it means |
|---|---|---|
| **NordVPN silently breaks portal blades** | Twice in one week, most visibly on the Autopilot import blade, `Failed to fetch; error code 0` | It runs as a desktop app, so incognito mode does not rule it out. Check the VPN before the browser. |
| **Compliance reads the last boot** | Day 4 compliance, and the rebuild | Device Health settings read a report written at boot, so a change after boot only counts after a restart and Intune's next evaluation. Day 4 blamed the virtual TPM; the rebuild passed all three on a virtual TPM 2.0. Self-deploying and pre-provisioning still need a physical TPM. |
| **Hyper-V reserves memory up front** | Three times, error `0x800705AA` | Close the browser before starting the VM. |
| **Portal saves happily with nothing selected** | Group member picker (Day 2), Included versus Excluded groups (Day 4) | A policy assigned to nobody is valid and silent. Always read the assignment back. |
| **Our own hardening blocks us later** | Day 6, error 801c03ed at Entra join | Day 2's join restriction and five-device limit stopped Day 6's deployment. The failure is rarely a broken product, it is a setting somebody chose, for a good reason, on a different day. |
| **Two identical PowerShell windows** | Day 3, `dsregcmd` on the host | Every instruction in these documents is tagged **[Laptop]** or **[VM]** because of this. |

## The two most expensive lessons of the week

> **1. Change the approach, do not keep debugging the path**
>
> Three days went into making a VM boot from an ISO. Every test was reasonable. The question that ended it was not *why won't this boot* but *do I need to boot from an ISO at all*. Applying the image with DISM took under an hour and never failed again.

> **2. Run the vendor's diagnostic before reasoning from first principles**
>
> A full day of manual elimination on error 80180003, user scope, restrictions, device limits, stale objects, licensing. Microsoft publishes a diagnostic at `aka.ms/IntuneWindowsEnrollment` that reads the tenant and names the fault. It found it in seconds: MDM authority was not set.

## What is not in these documents

Passwords, recovery keys and hardware hashes are deliberately excluded. The lab's local account credentials live in the answer file on disk and nowhere else.

*Index to the MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production.*
