# Day 1: Tenant, Licensing and the Lab VM

*Getting a Microsoft 365 tenant with Intune rights, and a Windows 11 virtual machine that Intune will accept.*

Monday 17 August 2026 · MD-102 study track · Tenant `labtenant.onmicrosoft.com`

**What existed at the end of the day**

- A Microsoft 365 tenant, `labtenant.onmicrosoft.com`, global admin `admin@labtenant.onmicrosoft.com`
- Microsoft Intune Suite trial: 250 licences, expiring 15 November 2026, recurring billing switched off
- Microsoft Entra ID P2 trial: 100 licences
- Licences *assigned* to the admin account, not merely purchased
- Hyper-V enabled on the laptop
- A Generation 2 virtual machine `W11-CORP-01` with a virtual TPM and Secure Boot, ready for an operating system

## 1. Why a tenant at all, and why this one

Intune is not software you install. It is a service that lives inside a Microsoft 365 tenant. Nothing in the MD-102 syllabus can be practised without one, so the tenant is step zero.

> **Why**
>
> **"Tenant"** means a single organisation's dedicated instance of Microsoft's cloud. Every user account, group, device record, policy and licence belongs to exactly one tenant. When you enrol a device, you are enrolling it *into a tenant*. Two tenants never see each other's data.

### The three routes to a free tenant, and why two of them failed

| Route | Result | Reason |
|---|---|---|
| **Microsoft 365 Developer Program**  (the classic free E5 sandbox) | Not available | Microsoft closed open enrolment. It now requires an active Visual Studio Enterprise or Professional subscription. There is no free path in. |
| **Microsoft 365 E5 self-service trial** | Not offered in Switzerland | The Swiss storefront prices E5 at CHF 54.33 per user per month and routes the trial button to "contact sales". No self-service 30-day trial exists on this storefront. |
| **Microsoft Intune Suite trial** | **Worked** | Self-service, instant, 250 licences, no card charge if recurring billing is turned off. Everything MD-102 tests lives here. |

> **Microsoft's rule, trials and billing**
>
> A self-service trial converts to a paid subscription automatically at the end of the trial period unless recurring billing is disabled. Turning recurring billing off does *not* shorten the trial. The subscription still runs to its full expiry date, it simply does not renew.
>
> This is why the trial was switched off on day one rather than the day before it expires. It costs nothing and removes the risk of a surprise charge.

### Turning recurring billing off

**[Laptop]** admin.microsoft.com→ Billing→ Your products→ Microsoft Intune Suite Trial→ Recurring billing: Off

## 2. The licensing trap: purchased is not assigned

This is the single most useful thing learned on Day 1, and it comes back on the exam.

- **Buy / activate** The tenant now owns 250 Intune licences. They sit in a pool.
- **Assign** A licence is attached to a specific user account.
- **Rights active** That user can now enrol devices and use the service.

Skip the middle box and every symptom looks like a broken tenant. Enrolment fails, blades are missing, the portal shows features greyed out. Nothing is broken. The account simply has no licence.

**[Laptop]** admin.microsoft.com→ Users→ Active users→ GocePetrov→ Licenses and apps→ tick Microsoft Intune Suite and Microsoft Entra ID P2→ Save changes

> **Microsoft's rule, licence changes need a fresh sign-in**
>
> Licence assignment is written into the access token issued at sign-in. An already-signed-in session keeps its old token and its old rights until that token is refreshed. Sign out and sign back in, or the portal will keep telling you that you do not have the licence you just assigned.

### The Intune Suite is an add-on, not a base plan

This did not surface until Day 3, but it belongs here because it is a licensing fact.

> **Microsoft's rule, Intune Suite requires a base plan**
>
> **Microsoft Intune Suite** is an *add-on*. It layers advanced features (Remote Help, Endpoint Privilege Management, Advanced Analytics, Microsoft Tunnel) on top of a base plan. It does not itself carry the right to enrol a device.
>
> **Microsoft Intune Plan 1** is the base plan. Plan 1 carries MDM enrolment rights.
>
> Intune Suite without Plan 1 underneath is a car with no engine. This was resolved by buying a single Intune Plan 1 seat at CHF 6.50 per month.

## 3. Why the lab needs a virtual machine, not the laptop

Everything in MD-102 is about doing things *to* a managed device: enrolling it, encrypting it, wiping it, reimaging it, locking it down. None of that is survivable on the machine you work on every day.

> **Why**
>
> **"VM"**, virtual machine. A complete computer running as software inside another computer. It has its own disk, its own memory, its own operating system, and its own identity as far as Intune is concerned. When you break it, you delete it and build another one. When you wipe it, nothing real is lost.
>
> **"Hyper-V"** is Microsoft's built-in virtualisation platform, included in Windows 11 Pro. No third-party software needed.

### Enabling Hyper-V

**[Laptop]** Start→ type Turn Windows features on or off→ tick Hyper-V (parent box, both children)→ OK→ restart

## 4. Building the VM, and why each setting is what it is

These commands ran in **PowerShell as administrator on the laptop**. Every one of the Hyper-V `Get-VM*` and `Set-VM*` cmdlets requires elevation. A non-elevated shell returns access-denied errors that look like the VM does not exist.

#### Create the machine

```
New-VM -Name "W11-CORP-01" -Generation 2 -MemoryStartupBytes 4GB `
  -Path "D:\VMs" -NewVHDPath "D:\VMs\W11-CORP-01\W11-CORP-01.vhdx" `
  -NewVHDSizeBytes 64GB -SwitchName "Default Switch"
```

| Setting | Why this value |
|---|---|
| `-Generation 2` | Generation 2 gives a UEFI firmware, which is what enables Secure Boot and a virtual TPM. Generation 1 is legacy BIOS and cannot run Windows 11 at all. **Generation cannot be changed after creation.** Get it wrong and you rebuild. |
| `-MemoryStartupBytes 4GB` | Windows 11 minimum is 4 GB. On a 15.46 GB laptop this is as much as can be spared. |
| `-NewVHDSizeBytes 64GB` | Windows 11 minimum is 64 GB. The disk is dynamically expanding, so it only consumes what is actually written. |
| `-SwitchName "Default Switch"` | Hyper-V's built-in NAT switch. The VM shares the laptop's internet connection with no extra networking setup. Internet access is not optional here, a cloud-managed device that cannot reach the cloud is not a device Intune can manage. |

#### Turn off the things that quietly consume disk

```
Set-VM -Name "W11-CORP-01" -AutomaticCheckpointsEnabled $false
Set-VMMemory -VMName "W11-CORP-01" -DynamicMemoryEnabled $false
Set-VMProcessor -VMName "W11-CORP-01" -Count 2
```

> **Why automatic checkpoints are off**
>
> A **checkpoint** is a saved point in time. Hyper-V implements it by freezing the main disk and writing every subsequent change to a separate **differencing disk** (a `.avhdx` file). Automatic checkpoints create one every time the VM starts.
>
> Two costs. Disk: the differencing disk grows without limit and is invisible in Explorer unless you look for it. Speed: every write now touches two files instead of one. Later in the lab a single 12.1 GB differencing disk was the reason BitLocker encryption crawled. Manual checkpoints are useful. Automatic ones are a tax.

#### The virtual TPM: order matters

```
Set-VMKeyProtector -VMName "W11-CORP-01" -NewLocalKeyProtector
Enable-VMTPM -VMName "W11-CORP-01"
```

> **Why**
>
> **"TPM"**, Trusted Platform Module. A dedicated chip (here, a software emulation of one) that stores cryptographic keys where the operating system cannot read them out. It is what makes BitLocker able to unlock a disk automatically at boot without asking for a password, and it is what proves a device's identity to Entra ID.
>
> Windows 11 refuses to install without TPM 2.0. Intune device identity and BitLocker both depend on it. No TPM, no lab.
>
> **Order matters.** `Set-VMKeyProtector` creates the key that protects the virtual TPM's own storage. `Enable-VMTPM` then switches it on. Reverse the two and the second command fails.

#### Secure Boot

```
Set-VMFirmware -VMName "W11-CORP-01" -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
```

> **Why**
>
> **Secure Boot** checks the digital signature of every piece of code that runs before Windows starts. Unsigned or tampered bootloaders are refused. It is a Windows 11 requirement, and it is one of the settings a compliance policy will later check.

> **What broke, Secure Boot template locked**
>
> `Set-VMFirmware : Cannot modify the secure boot template ID property after the virtual TPM is initialized.`
>
> **Cause:** once `Enable-VMTPM` has run, the Secure Boot *template* is fixed. The template says which certificate authority to trust. `MicrosoftWindows` is already the default for a Generation 2 VM, so setting it explicitly changes nothing.
>
> **Fix:** drop `-SecureBootTemplate` and set only the state.
>
> ```
> Set-VMFirmware -VMName "W11-CORP-01" -EnableSecureBoot On
> ```

## 5. The memory problem, three times over

> **What broke, 0x800705AA**
>
> `'W11-CORP-01' could not initialize memory: Insufficient system resources exist to complete the requested service. (0x800705AA)`
>
> Hit three separate times across the week.
>
> **Cause:** Hyper-V reserves the *entire* startup memory allocation before the VM executes a single instruction. It does not borrow gradually. Ask for 4 GB and 4 GB must be free, contiguous and available at that moment. The laptop has 15.46 GB total, and Chrome was repeatedly holding between 2,249 MB and 5,236 MB across dozens of background processes.
>
> **Fix:** close Chrome entirely before starting the VM, or lower startup memory. Later in the week this led to a full audit of what was eating RAM: browser extensions, Adobe background services, Figma Agent, Grammarly, Slack. Several gigabytes were recovered.

> **Carry this forward**
>
> Before starting the VM, close the browser. It is faster than diagnosing 0x800705AA for the fourth time.

## 6. What to remember for the exam

- Generation 2 is a creation-time decision and cannot be changed. Generation 2 = UEFI = Secure Boot and vTPM available.
- A purchased licence does nothing. It must be assigned to a user, and the user must sign in again.
- Intune Suite is an add-on. Intune Plan 1 is the base plan that carries enrolment rights.
- Recurring billing off does not end a trial early. The trial runs its full term.
- Hyper-V reserves startup memory in full, up front.
- `Set-VMKeyProtector` before `Enable-VMTPM`. The Secure Boot template locks once the vTPM initialises.

*Day 1 of 5, MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production.*
