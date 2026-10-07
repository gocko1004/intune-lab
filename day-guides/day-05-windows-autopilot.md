# Day 5: Windows Autopilot

*Registering a device by its hardware identity, building the deployment profile, and the group rule that decides whether any of it works.*

Monday 24 August 2026 · MD-102 study track · VM `LABVMGOCE`, serial `<serial-redacted>`

**What existed at the end of the day**

- Hardware hash harvested and imported, the VM is now a registered Autopilot device
- Deployment profile `APUserDrivenEntraJoin`: user-driven, Microsoft Entra joined
- Dynamic group `Dyn-Autopilot-Devices` built on the ZTDid rule, with `LABVMGOCE` confirmed inside it
- Profile status: **Assigned**
- Enrollment Status Page configured, with two settings deliberately changed before saving

## 1. What Autopilot actually is

It is worth being precise, because the name suggests something it is not.

> **Why**
>
> **Autopilot does not install Windows.** The device already has Windows on it, from the factory, or from an image. Autopilot takes the Windows that is already there and, during OOBE, transforms it into a corporate device: joins it to Entra ID, enrols it in Intune, applies policy, installs apps, and hands it to the user configured.
>
> The old way was to wipe the vendor's Windows and apply a corporate image. Autopilot skips that entirely. A device ships from the supplier straight to the employee's home, they open it, connect to wi-fi, sign in with their work account, and it configures itself. IT never touches the box.
>
> This is why it is on the exam and why it is on job descriptions. It is the difference between an IT team that unboxes 200 laptops and one that does not.

- **1. Register** Device's hardware identity uploaded to the tenant.
- **2. Group** Device lands in a dynamic group by ZTDid.
- **3. Profile** Deployment profile assigned to that group.
- **4. OOBE** Device recognises itself, joins, enrols, configures.

## 2. Harvesting the hardware hash

Autopilot identifies a device by a **hardware hash**, a long encoded string derived from the physical characteristics of the machine: TPM, motherboard, disk, network adapters. It is how the service recognises a specific device before that device has any identity, name or user.

**VM, PowerShell as administrator:**

```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
Install-Script -Name Get-WindowsAutopilotInfo -Force
Get-WindowsAutopilotInfo -OutputFile C:\HWID.csv
```

| Line | Why |
|---|---|
| `Set-ExecutionPolicy -Scope Process` | Windows blocks downloaded scripts by default. `-Scope Process` lifts the block for this shell only. Close the window and the machine's policy is untouched. Never change execution policy machine-wide to run one script. |
| `Install-Script Get-WindowsAutopilotInfo` | Microsoft's published script for reading the hash. It pulls the values out of WMI and writes them in the exact CSV shape the import expects. |
| `-OutputFile C:\HWID.csv` | Produces the CSV to upload. |

> **Microsoft's rule, the CSV format is exact**
>
> The upload accepts a CSV with precisely these headers:
>
> ```
> Device Serial Number,Windows Product ID,Hardware Hash
> ```
>
> Constraints that cause rejections:
>
> - Maximum 500 rows per file
> - No byte order mark. Opening the file in Excel and saving it will usually add one and break the import
> - Headers must match exactly, including spaces
>
> The file produced here was verified before upload: 4,091 bytes, 2 lines, no BOM, serial `<serial-redacted>`.

> **In the real world**
>
> You do not run this script on devices you are buying. The supplier registers them for you, using the same hardware identifiers, before the box ever ships. Running the script by hand is what you do for devices already in your possession, which is exactly the Windows 10 to Windows 11 migration situation Swiss companies are working through now.

## 3. Importing the device

**[Browser]** intune.microsoft.com→ Devices→ Enrollment→ Windows tab→ Devices (under Windows Autopilot)→ Import

> **What broke, Failed to fetch; error code 0**
>
> The import blade would not load. The error carried no useful detail.
>
> **Diagnosis:** an incognito window ruled out browser extensions, since incognito disables them. The blade still failed.
>
> **Cause:** NordVPN. It runs as a desktop application, not a browser extension, so incognito has no effect on it. It was intercepting the portal's API calls.
>
> **Fix:** disconnect NordVPN.
>
> **Note:** this was the second time in the same week that NordVPN silently broke something in this lab. When a Microsoft portal blade fails to load with no meaningful error, check the VPN before anything else.

Import takes a few minutes. The device then appears in the Autopilot devices list with **Profile status: Not assigned**, expected at this point, because no profile exists yet.

## 4. The deployment profile

**[Browser]** intune.microsoft.com→ Devices→ Enrollment→ Windows tab→ Deployment Profiles→ Create profile→ Windows PC

Named `APUserDrivenEntraJoin`.

> **What broke, no slashes allowed in the name**
>
> The first name used contained a slash and was rejected. Profile names take letters, numbers, hyphens and underscores. Renamed to `APUserDrivenEntraJoin`.

### User-driven versus self-deploying

|  | User-driven | Self-deploying |
|---|---|---|
| Who signs in | The assigned user, during OOBE | Nobody. No user interaction at all. |
| Result | Device joined and enrolled, user signed in and ready | Device configured and sitting at the sign-in screen |
| Typical use | Employee laptops | Kiosks, shared terminals, digital signage, meeting-room devices |
| Requirement | Works on a VM | **Physical TPM 2.0 required.** Does not work on a Hyper-V VM. |

> **Microsoft's rule, self-deploying needs a real TPM**
>
> Self-deploying mode uses the TPM to attest the device's identity to the service, because there is no user signing in to prove anything. That attestation requires a physical TPM 2.0 with a valid manufacturer certificate.
>
> A Hyper-V virtual TPM cannot provide one. This is the same limitation that made Device Health Attestation impossible on Day 4, appearing in a second place. User-driven mode was chosen for that reason, and it is the mode that matters for an employee-laptop scenario anyway.

Settings used:

- Deployment mode: **User-Driven**
- Join to Microsoft Entra ID as: **Microsoft Entra joined**

## 5. The group rule: the part that decides whether any of this works

> **What broke, profile stayed "Not assigned"**
>
> The profile was assigned to `Dyn-Windows-Devices`. The device stayed **Not assigned**.
>
> **Cause:** that group's rule is `device.deviceOSType -eq "Windows"`, which matches devices *already enrolled in Intune*. An Autopilot-registered device that has not yet been deployed is not enrolled. It exists only as an Autopilot registration. It never matched.
>
> This is a genuine ordering problem, not a typo. Autopilot has to target the device **before** it is enrolled, so the rule must match something that exists at registration time. `deviceOSType` does not.

### The correct rule

```
(device.devicePhysicalIDs -any (_ -startsWith "[ZTDid]"))
```

> **Why this works**
>
> **"ZTDid"**, Zero Touch Deployment ID. When a device is imported into Autopilot, the service stamps a ZTDid into the device object's `devicePhysicalIDs` property. It is present from the moment of registration, before any enrolment.
>
> Reading the rule: `devicePhysicalIDs` is a list. `-any` means "at least one item in this list satisfies the following". `_` is the item being tested. So: *does any physical ID on this device start with `[ZTDid]`?* If yes, it is an Autopilot-registered device.
>
> This is Microsoft's documented rule for the purpose, used verbatim. It is worth memorising, it appears on the exam and in every real deployment.

**[Browser]** entra.microsoft.com→ Identity→ Groups→ New group→ Type Security→ Name Dyn-Autopilot-Devices→ Membership type Dynamic Device→ Add dynamic query→ Edit (raw rule syntax)

On the group creation form, **Microsoft Entra roles can be assigned to the group** was left as **No**. That option is for groups that hold administrative role assignments; it is unrelated to device membership and setting it to Yes adds restrictions that are not wanted here.

Membership confirmed: `LABVMGOCE` present. Profile reassigned to `Dyn-Autopilot-Devices`. Profile status changed to **Assigned**.

## 6. The Enrollment Status Page

> **Why**
>
> The **ESP** is the progress screen the user watches during an Autopilot deployment. Without it the device appears to sit at a blank OOBE screen for twenty minutes while work happens invisibly, and users reboot it, which breaks the deployment.
>
> It also does something more important than reassurance: it can **block the user from reaching the desktop until required apps and policies have installed**. That is what prevents a user starting work on a half-configured machine.

**[Browser]** intune.microsoft.com→ Devices→ Enrollment→ Windows tab→ Enrollment Status Page

Two settings were deliberately changed before saving:

| Setting | Set to | Why |
|---|---|---|
| Install Windows updates during OOBE | **No** | Leaving this on adds a 30 to 60 minute patch cycle to every deployment. In production you may want it. In a lab you are demonstrating Autopilot, not Windows Update, and an hour per attempt makes iteration impossible. |
| Allow users to use device if installation error occurs | **Yes** | Set to No, any failure during deployment leaves the device locked at the ESP with no route forward except a rebuild. In a lab this costs an afternoon. This is the single most common way people brick their first Autopilot test. |

## 7. What to remember for the exam

- Autopilot configures existing Windows during OOBE. It does not install the operating system.
- Devices are identified by a **hardware hash**. In production the supplier registers them; you only harvest hashes by hand for devices you already own.
- CSV import: exactly three headers, maximum 500 rows, no BOM.
- The Autopilot group rule is `(device.devicePhysicalIDs -any (_ -startsWith "[ZTDid]"))`. Rules based on `deviceOSType` do not work, because the device is not enrolled yet.
- **User-driven** works anywhere. **Self-deploying** requires a physical TPM 2.0 and is for kiosks and shared devices.
- The ESP can block desktop access until required apps install. Configure the error-path behaviour before you ever run a deployment.
- Profile status "Not assigned" almost always means the group rule does not match, not that the profile is broken.

## 8. Standing before Day 6

Everything is in place for a full end-to-end deployment. Before wiping the VM to OOBE and running it:

> **Take a checkpoint first**
>
> A working, joined, enrolled, encrypted, compliant VM took three days to build once. A checkpoint before the wipe means a failed Autopilot run costs minutes instead of days.
>
> Delete it once the deployment succeeds, Day 4 showed what a lingering differencing disk does to disk space and write speed.

*Day 5 of 5, MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production.*
