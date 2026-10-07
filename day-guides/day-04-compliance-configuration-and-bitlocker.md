# Day 4: Compliance, Configuration and BitLocker

*The difference between a policy that judges a device and a policy that changes it, why a healthy device kept reporting non-compliant, and what BitLocker actually needs to run.*

Friday 21 August 2026 · MD-102 study track · VM `LABVMGOCE`

**What existed at the end of the day**

- A compliance policy evaluating the VM, reporting **Compliant** on both settings
- BitLocker on, encryption complete, recovery key escrowed to Intune
- A configuration profile applying a logon banner, confirmed visible on the VM
- Roughly 24 GB of host disk recovered and several GB of RAM freed

## 1. Compliance versus configuration. The core distinction of the day.

- **Compliance policy** Looks at the device. Returns a verdict: compliant or not.
- **Configuration profile** Changes the device. Silently. No verdict, no prompt, no notification.

> **Why the split exists**
>
> They answer different questions and feed different systems.
>
> A **compliance policy** produces a signal. That signal is what Conditional Access consumes: "only let compliant devices reach company email". It is a gate, not a fix. A device failing compliance is still exactly as it was, it has simply been marked.
>
> A **configuration profile** is the fix. It pushes a setting and the device applies it. The user is not asked and is not told. When the profile is later removed, the setting reverts.
>
> You need both. Configuration makes the device correct. Compliance proves it, and lets access control act on the proof.

## 2. Building the compliance policy

**[Browser]** intune.microsoft.com→ Devices→ Compliance→ Create policy→ Platform Windows 10 and later

### The settings that failed, and why

The first attempt used the **Device Health** settings, BitLocker, Secure Boot, Code integrity. The device reported non-compliant on BitLocker and Secure Boot despite both being verifiably on.

Verified directly on the VM:

```
Get-BitLockerVolume -MountPoint C:     # ProtectionStatus : On
Confirm-SecureBootUEFI                 # True
```

> **What broke, a healthy device reporting non-compliant**
>
> **Cause:** the Device Health settings do not read the device's live state. They read a **Device Health Attestation** report generated at boot time and signed by the TPM.
>
> **Corrected later:** my first conclusion here was that a Hyper-V virtual TPM cannot produce an attestation the service accepts, so these settings could never pass on any VM. The rebuild proved that wrong. On a Hyper-V virtual TPM 2.0, BitLocker, Secure Boot and Code Integrity all evaluated **Compliant**, see [rebuild, Compliance](../rebuild/README.md#compliance).
>
> What actually failed on this day was never pinned down, because it was not re-tested. Two things the rebuild showed would fit: the report is written only at boot, so a change made after boot is not seen until a restart, and Intune evaluates the report on its own schedule, about half an hour after the restart in the rebuild.

> **Microsoft's rule, attestation is boot-time, not live**
>
> Device Health Attestation settings evaluate a signed report produced during boot. They do not query the running system. The consequence that appears on the exam: a change made after boot is not reflected until the device restarts.
>
> An earlier version listed a second consequence, that virtual machines cannot satisfy these settings. The rebuild disproved it.

### The settings that worked

Swapped to settings that Intune evaluates locally on the device rather than through attestation:

**[Browser]** Compliance settings→ System Security→ Encryption→ Require encryption of data storage on device: Require

**[Browser]** Compliance settings→ Device Security→ Trusted Platform Module (TPM): Require

Both returned **Compliant**.

> **Carry this forward**
>
> Two settings can look like they check the same thing and evaluate through completely different mechanisms. "Require encryption of data storage" asks the device. "BitLocker" under Device Health asks the attestation service. On real hardware both work. On a VM only the first one does.
>
> When a compliance result contradicts what you can see on the device, the question to ask is *how is this setting evaluated*, not *what is wrong with the device*.

### Two defaults worth knowing

> **Microsoft's rule, devices with no policy**
>
> Intune has a tenant-level setting: **Mark devices with no compliance policy assigned as**, defaulting to ** Compliant**. Every device with no policy targeting it is therefore reported as compliant.
>
> In production this is usually wrong and should be set to **Not compliant**. Otherwise a device that has slipped out of all your groups reports green.
>
> intune.microsoft.com→ Devices→ Compliance→ Compliance policy settings

**"Not applicable"** in a policy report is not a failure. It means the setting does not apply to that platform or that device state. A Windows-only setting on an Android device reports Not applicable, not Non-compliant.

## 3. Assignment: the mistake that makes a policy do nothing

> **What broke, the profile targeted nothing**
>
> A configuration profile was created, saved, and applied to zero devices.
>
> **Cause:** `Dyn-Windows-Devices` had been added under **Excluded groups** instead of **Included groups**. The Included section read "No results" and this was not noticed.
>
> **Fix:** remove from Excluded, add to Included.
>
> **Why it is easy to do:** the two sections sit directly above one another on the Assignments tab, both with an identical "Add groups" button. Saving succeeds either way, a policy assigned to nobody is valid, just useless.

> **Standing check**
>
> After assigning any policy, open it again and read the Assignments tab back. Included should name a group. Exclusions should be empty unless you deliberately put something there.

## 4. BitLocker

> **Why**
>
> **BitLocker** encrypts the whole volume. Without the key, a stolen disk is noise. The key is sealed inside the **TPM** and released only if the boot sequence is unchanged, which is why it unlocks without a password on a healthy machine and demands a recovery key on a tampered one.
>
> A **recovery password** is the 48-digit fallback. If it is only on the device, it is useless when the device is what you have lost. Escrowing it to Intune is the entire point of managing BitLocker centrally.

> **What broke, error 0x80310030**
>
> ```
> BitLocker cannot be enabled. Bootable media detected.
> ```
>
> **Cause:** the Windows 11 ISO was still attached to the VM's virtual DVD drive. BitLocker refuses to encrypt while removable bootable media is present, because that media is a route to bypass the protection it is about to apply.
>
> **Fix, on the laptop:**
>
> ```
> Set-VMDvdDrive -VMName "W11-CORP-01" -Path $null
> ```

> **What broke, encryption stalled at 54.9%**
>
> Progress sat at 54.9% for several minutes with no error.
>
> **Two causes stacked:**
>
> 1. **The laptop was on battery.** BitLocker throttles encryption on battery power by design, to avoid draining a machine flat mid-operation. This is documented behaviour, not a fault.
> 2. **A checkpoint was active.** Its differencing disk had grown to 12.1 GB, so every write was hitting two files.
>
> **Fix:**
>
> - Plug the laptop in
> - `powercfg /setactive SCHEME_MIN`, switch to the High Performance power scheme
> - Delete the checkpoint. Host free space on D: went from 40.1 GB to 57.5 GB.

### Escrow, and how to confirm it

**[Browser]** intune.microsoft.com→ Devices→ All devices→ LABVMGOCE→ Recovery keys

Keys present. This is the check that matters, a recovery key that exists only on the encrypted device protects nobody.

> **Microsoft's rule, used space versus full volume**
>
> **Encrypt used disk space only** is fast and correct for a new device, because there is no prior data in the free space to recover.
>
> **Encrypt entire drive** is required for a device that has been in use, because deleted files remain recoverable in unallocated space until they are overwritten.
>
> The rule of thumb: new device, used space. Existing device, full drive.

## 5. The configuration profile: a logon banner

A deliberately visible setting was chosen, so the effect could be confirmed with eyes rather than trusted from a portal.

**[Browser]** intune.microsoft.com→ Devices→ Configuration→ Create→ New Policy→ Platform Windows 10 and later→ Profile type Settings catalog

Two settings, both under **Local Policies Security Options**:

- **Interactive Logon Message Title For Users Attempting To Log On**
- **Interactive Logon Message Text For Users Attempting To Log On**

> **Why a banner is a real control, not a toy**
>
> A logon banner is a standard requirement in regulated environments. It establishes that the user was notified of monitoring and acceptable use before accessing the system, which is what makes enforcement action defensible. It appears in most security baselines for exactly that reason.

After sync, the banner appeared on the VM at sign-in. No prompt, no notification, no user consent. That is the point: **a configuration profile silently changes the machine.**

## 6. Host cleanup

The lab kept running out of resources, so a full audit was done on the laptop.

| What | Action | Recovered |
|---|---|---|
| VM checkpoint and its differencing disk | Deleted | ~17 GB |
| Orphaned VM files | Removed | ~7 GB |
| Adobe Bridge, Adobe Synchronizer, Figma Agent, Grammarly, Slack background services | Stopped and disabled | Several GB RAM |
| Chrome extensions: SEO tools, Tag Assistant, Adobe extension, Career IO, MetaMask | Removed. MetaMask moved to backup at `D:\VMs\chrome-extensions-removed\METAMASK-FULL-BACKUP`, never deleted. NordPass left untouched. | Chrome process count and RAM down substantially |

> **What broke, Set-Service with an array**
>
> `Set-Service -Name` in Windows PowerShell 5.1 accepts one name at a time. `Stop-Service -Name` accepts an array. Passing an array to the first fails.
>
> **Fix:** a `foreach` loop. Similar-looking cmdlets in the same module do not necessarily share parameter behaviour.

## 7. What to remember for the exam

- Compliance **evaluates** and returns a verdict. Configuration **changes** the device, silently.
- Device Health Attestation settings read a boot-time signed report, not live state. A change made after boot needs a restart before it counts.
- Default for a device with no compliance policy is **Compliant**. Change it in production.
- "Not applicable" means the setting does not apply, not that it failed.
- Check Included versus Excluded on every assignment. A policy assigned to nobody saves without complaint.
- BitLocker refuses to start with bootable media attached, 0x80310030.
- BitLocker throttles on battery power. This is by design.
- Used-space encryption for new devices. Full-volume for devices already in use.
- Escrow the recovery key. Confirm it under the device's **Recovery keys** tab.

*Day 4 of 5, MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production.*
