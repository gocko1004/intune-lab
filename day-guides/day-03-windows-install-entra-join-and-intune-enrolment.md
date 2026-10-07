# Day 3: Windows Install, Entra Join and Intune Enrolment

*Three days lost to a virtual machine that would not boot, then a full day lost to an enrolment error with a one-click cause. The most expensive and most useful day of the week.*

Wednesday 19 to Thursday 20 August 2026 · MD-102 study track · VM `W11-CORP-01` / hostname `LABVMGOCE`

**What existed at the end of the day**

- Windows 11 installed on `W11-CORP-01`, applied with DISM rather than installed from the ISO
- Local administrator account `labadmin`, Swiss French keyboard layout, correct locale
- The device genuinely **Entra joined**, not merely registered
- MDM authority set on the tenant, the fix that unblocked everything
- Device successfully enrolled in Intune and visible under All devices
- 32 scheduled tasks under `\Microsoft\Windows\EnterpriseMgmt\`, the proof of enrolment

## Part 1: The VM would not boot. Three days.

### The symptom

```
SCSI DVD (0,1)
The boot loader failed.
```

The VM was correctly configured. The ISO was Microsoft's own. It refused to boot.

### What was eliminated, and how

| Hypothesis | How it was tested | Result |
|---|---|---|
| Corrupt ISO download | Redownloaded and compared hashes, byte-identical | Ruled out |
| ISO repacked or non-original | Inspected the file listing; `__chunk_data` in the root looked suspicious | **My error.** The byte-identical redownload disproved it. The file is normal. |
| Broken boot catalog | Read the raw El Torito boot catalog. Valid EFI section at LBA 555, valid FAT12 boot sector | Ruled out |
| Wrong architecture | Checked the PE header machine type: `0x8664`, correct for x64 | Ruled out |
| Secure Boot blocking | Tested with Secure Boot on and off | Ruled out |
| SCSI controller layout | Two different disk and DVD orderings | Ruled out |
| Dynamic memory / checkpoints | Both disabled | Ruled out |
| Corrupt VM definition | Deleted and rebuilt from scratch | Ruled out |

> **The real lesson from three days**
>
> Every one of those tests was reasonable. The mistake was not any single test, it was continuing to debug a path when a different path existed. The question that ended it was not "why won't this ISO boot?" but **"do I actually need to boot from an ISO?"**
>
> You do not. An ISO installer is a convenience wrapper around two operations: apply a Windows image to a disk, and write a bootloader. Both can be done directly.

### The fix: apply the image with DISM

> **Why**
>
> **"DISM"**, Deployment Image Servicing and Management. Microsoft's tool for working with Windows images offline. **"WIM"**, Windows Imaging Format, the compressed file inside the ISO that holds the actual operating system. The installer you normally click through is a front end that ultimately calls DISM.
>
> Doing it by hand skips the boot process entirely. The disk is mounted on the *laptop*, written to from the laptop, then unmounted and handed back to the VM. The VM never has to boot from removable media, so whatever was wrong with that path stops mattering.

- **1. Mount** Attach the VM's virtual disk to the laptop as a normal drive.
- **2. Partition** Create the EFI system partition and the Windows partition.
- **3. Apply** Expand the WIM onto the Windows partition.
- **4. Boot files** Write the UEFI bootloader. Unmount. Start the VM.

**Laptop, PowerShell as administrator.** Mount the disk and give it a GPT partition table:

```
Mount-VHD -Path "D:\VMs\W11-CORP-01\W11-CORP-01.vhdx"
Initialize-Disk -Number 1 -PartitionStyle GPT
```

Create the EFI System Partition, 500 MB, FAT32, with the GPT type GUID that marks it as an ESP:

```
New-Partition -DiskNumber 1 -Size 500MB `
  -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -DriveLetter S
Format-Volume -DriveLetter S -FileSystem FAT32 `
  -NewFileSystemLabel "SYSTEM" -Confirm:$false
```

> **Microsoft's rule, the ESP must be FAT32**
>
> **"ESP"**, EFI System Partition. The UEFI firmware reads the bootloader from here before Windows exists. The UEFI specification requires this partition to be FAT32; firmware is not required to understand NTFS. Format it NTFS and the machine will not boot, with no useful error.
>
> The GUID `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` is the standard GPT partition type identifier for an EFI System Partition. It is how firmware finds the partition in the first place.

Create and format the Windows partition using everything left:

```
New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter W
Format-Volume -DriveLetter W -FileSystem NTFS `
  -NewFileSystemLabel "Windows" -Confirm:$false
```

Apply the Windows image, then write the bootloader:

```
Expand-WindowsImage -ImagePath "E:\sources\install.wim" -Index 6 -ApplyPath "W:\"
bcdboot W:\Windows /s S: /f UEFI
```

> **Why -Index 6 and why /f UEFI**
>
> A single `install.wim` contains several editions, Home, Home N, Pro, Pro N, Education, Enterprise and so on. Each has an index number. Index 6 is the edition needed here. Run `Get-WindowsImage -ImagePath "E:\sources\install.wim"` to list them before choosing.
>
> `bcdboot` writes the Boot Configuration Data, the bootloader and its store. `/s S:` says put the boot files on the ESP. `/f UEFI` says write UEFI boot files only, not legacy BIOS ones. On a Generation 2 VM there is no BIOS path, so writing both is pointless and writing the wrong one leaves an unbootable machine.

Then dismount the disk and start the VM. It booted straight into OOBE.

## Part 2: Getting through OOBE

> **Why**
>
> **"OOBE"**, Out Of Box Experience. The setup wizard on first boot: region, keyboard, network, account. On a corporate device this is exactly where Autopilot takes over, which is why understanding it matters beyond just getting past it.

Windows 11 forces a Microsoft account during OOBE by default. For a lab you want a local account first, so the device can be joined deliberately rather than by accident.

**[VM]** At the network screen press Shift + F10 to open a command prompt→ type ms-cxh:localonly→ Enter

That opens the hidden local-account creation dialog. The lab account created was `labadmin`.

> **What broke, a correct password rejected at sign-in**
>
> The auto-generated password worked when pasted into a browser but failed at the Windows sign-in screen, repeatedly.
>
> **Cause:** the password contained `)`. The VM's keyboard layout differs from the layout the password was typed under. On a Swiss French layout the character produced by a given physical key is not the character on a US layout. The password was correct. The keystrokes were not.
>
> **Fix:** reset to an alphanumeric-only password. In a lab this is the right trade. In production you fix the keyboard layout instead.

### The permanent fix: an answer file

Rather than fighting OOBE by hand on every rebuild, an `unattend.xml` answer file was written to set locale, keyboard, timezone and the local account automatically.

```
<InputLocale>100c:0000100c</InputLocale>   <!-- Swiss French -->
<SystemLocale>fr-CH</SystemLocale>
<UILanguage>en-GB</UILanguage>
<UserLocale>fr-CH</UserLocale>
<TimeZone>W. Europe Standard Time</TimeZone>
```

> **Carry this forward**
>
> The answer file lives at `D:\VMs\unattend.xml`. Every future rebuild uses it. Three minutes of clicking, removed permanently, and the keyboard-layout problem cannot recur.

## Part 3: Entra join versus Entra register. The distinction that matters most.

These two look almost identical in the interface and mean completely different things. Getting them confused is one of the most common real-world support mistakes, and the exam tests it directly.

|  | Entra **joined** | Entra **registered** (workplace join) |
|---|---|---|
| What has an identity | The **device** belongs to the organisation | The **user's work account** is added to a personal device |
| Sign-in | You sign in to Windows with the work account | You sign in to Windows with a personal or local account |
| Typical use | Corporate-owned device | BYOD, personal phone or laptop |
| Intune management | Full device management | Limited, app-level |

> **What broke, registered instead of joined**
>
> On the **Access work or school** page there are two things you can do. Typing the email into the **Connect** box performs a *register*. Clicking the small blue link labelled **"Join this device to Microsoft Entra ID"** performs a *join*.
>
> The email box is large and obvious. The link is small text underneath. The wrong one was used.
>
> **Fix:** Disconnect the workplace account, then use the blue link.

**[VM]** Settings→ Accounts→ Access work or school→ Connect→ then the blue link Join this device to Microsoft Entra ID

### How to check which one actually happened

**[VM]** PowerShell→ dsregcmd /status

| Field | What it tells you |
|---|---|
| `AzureAdJoined` | `YES` means genuinely joined. This is the one that matters. |
| `WorkplaceJoined` | `YES` means registered. If this is YES and AzureAdJoined is NO, you did the wrong one. |
| `AzureAdPrt` | Primary Refresh Token. `YES` means the device holds a valid token and single sign-on works. |
| `MdmUrl` | Populated means the device knows where its management service is. Empty means it is joined but not managed. |
| `Device Name` | **Check this first, every time.** |

> **What broke, the command was run on the wrong machine**
>
> `dsregcmd /status` was run on the host laptop while believing it was running in the VM. It produced a full page of confident, coherent, entirely irrelevant output: `Device Name : DESKTOP-D8QPBL1`, `WorkplaceTenantName : PETROV`, prompt at `C:\Users\Admin`.
>
> **Cause:** two PowerShell windows that look identical.
>
> **Fix, and now a standing rule:** read `Device Name` before reading anything else. The VM is `LABVMGOCE`. Anything else means you are on the wrong machine. Every instruction in this lab is now tagged **[Laptop]** or **[VM]** for this reason.

## Part 4: Error 80180003, and a full day to find a one-click cause

### The symptom

```
Something went wrong.
This user is not authorized to enroll. You can try to do this again
or contact your system administrator with the error code 80180003.
```

The device was joined. The user was licensed. Enrolment refused.

### Everything eliminated, in order

| Checked | Where | Result |
|---|---|---|
| MDM user scope | Entra → Mobility (MDM and MAM) → Microsoft Intune → MDM user scope = All | Correct already |
| WIP / MAM user scope | Same blade | Not the cause |
| Enrolment restrictions | Intune → Devices → Enrollment → Enrollment device platform restrictions | Windows MDM allowed |
| Device limit restrictions | Intune → Devices → Enrollment → Enrollment device limit restrictions | Under limit |
| Stale device objects | Entra → Devices → All devices | Cleaned, no change |
| Licensing | admin.microsoft.com → Users → Licenses and apps | **Real gap found**, Intune Suite had no Plan 1 base. Bought one seat, CHF 6.50/month. Necessary, but not the cause. |

### The actual cause

> **Root cause, MDM authority was set to None**
>
> The tenant's **MDM authority** had never been set. Every other setting in the entire chain was correct and it did not matter, because the tenant had not declared which service was allowed to manage devices.

> **Why**
>
> **"MDM"**, Mobile Device Management. **MDM authority** is a single tenant-level value that names which service owns device management. Historically the choice was between Intune and Configuration Manager, and the setting still exists because a tenant must not have two systems fighting over the same devices.
>
> Until it is set, the answer to "who manages devices here?" is *nobody*, and every enrolment is correctly refused. The error message says the user is not authorised, which points you at the user. The user was never the problem.

### How it was found

Not by more manual checking. By running Microsoft's own diagnostic:

**[Browser]** https://aka.ms/IntuneWindowsEnrollment

It returned, in one line, what a full day of elimination had not:

> Devices cannot enroll because the MDM Authority is not set on the tenant.

### The fix, and why it is hard to find

> **Microsoft's rule, no menu path exists for this setting**
>
> The MDM authority blade is reachable only by direct URL. There is no navigation path to it through the Intune admin centre menus. On tenants created recently it is often set automatically, which is why it does not appear in most walkthroughs and why nothing in the interface hints that it is missing.

**[Browser]** https://intune.microsoft.com/#view/Microsoft_Intune_Enrollment/ChooseMDMAuthorityBlade→ select Intune MDM Authority

### Confirming enrolment actually happened

**[VM]** PowerShell→ `(Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*").Count`

Output: **32**.

> **Why this is the real proof**
>
> When a Windows device enrols, the MDM client creates a folder of scheduled tasks under `\Microsoft\Windows\EnterpriseMgmt\`. These tasks are what actually check in with Intune, pull policy and report status. Zero tasks means the device is not enrolled regardless of what any portal says. A populated folder means the management channel is genuinely live.
>
> This is a far better check than looking at the Intune portal, because the portal shows the record Intune holds, while the scheduled tasks show what the device itself believes.

## The enrolment failure checklist, in the order to check it

- **1. MDM authority** Is it set at all? Direct URL only.
- **2. Licence** Assigned, not just purchased. Plan 1 present as base.
- **3. MDM user scope** Does it include this user?
- **4. Restrictions** Platform allowed. Device limit not reached.
- **5. Diagnostic** aka.ms/IntuneWindowsEnrollment

> **The honest lesson**
>
> Step 5 should have been step 1. Microsoft publishes a diagnostic that reads the tenant's actual configuration and names the fault. A day was spent doing by hand what it does in seconds. When a vendor ships a diagnostic for exactly the problem you have, run it before you start reasoning.

## What to remember for the exam

- **Joined** = the device belongs to the org. **Registered** = a work account added to a personal device. `dsregcmd /status` tells you which.
- `AzureAdJoined : YES` is the field that confirms a real join. `WorkplaceJoined : YES` alone means you did the other thing.
- MDM authority is tenant-wide and must be set before any device can enrol.
- Error 80180003 blames the user. Check the tenant first.
- The ESP must be FAT32. UEFI firmware is not required to read NTFS.
- An enrolled Windows device has scheduled tasks under `\Microsoft\Windows\EnterpriseMgmt\`.
- `Get-WindowsImage` lists the editions inside an install.wim and their index numbers.

*Day 3 of 5, MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production. Lab credentials are deliberately excluded from this document.*
