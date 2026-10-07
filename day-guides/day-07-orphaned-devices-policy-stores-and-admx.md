# Day 7: Orphaned Devices, Policy Stores and Administrative Templates

*Recovering a device Intune could no longer reach, and three hours spent proving a policy worked when it had worked all along.*

Monday 24 to Tuesday 25 August 2026 · MD-102 study track · Virtual machine `W11-CORP-01`

**Where the day ended**

- Windows Autopilot deployment completed end to end, the objective that failed twice before
- A device that Intune had lost track of, recovered without Intune ever reaching it
- Both earlier failures traced to the host machine, not to any configuration mistake
- A settings catalog profile built, applied, removed, and confirmed in both directions
- Third-party application settings brought into Intune by importing an administrative template

## 1. What Intune is, in one paragraph

> **The mental model everything else rests on**
>
> Intune is a website where you set rules for company computers. You never touch the computers themselves. Each computer contacts Intune on a schedule, collects whatever rules apply to it, and puts them into effect.
>
> **Nothing happens the moment you click Save.** The change waits until that computer next makes contact. This one fact explains most of the confusion in this document, and most of the confusion of anyone learning this for the first time.
>
> The technical name for that contact is a **sync**, and the mechanism is called ** mobile device management (MDM)**. It is a pull system: the device asks, the service answers. The service cannot push anything to a device that never asks.

## 2. The device that vanished from Intune

> **What broke**
>
> **Devices** → **All devices** was completely empty. No computers listed at all, despite one having been managed the previous day.

Microsoft Entra, the identity service sitting behind Intune, still held a record for the device. Opening it showed something useful:

**[Laptop]** entra.microsoft.com→ Entra ID→ Devices→ All devices→ AB-25025

| Field | Value | What it told us |
|---|---|---|
| Join type | Microsoft Entra joined | The device still had a valid identity |
| Owner | Goce Petrov | The right device, not a stale duplicate |
| Mobile device management | **None** | Nothing is managing it. The day before, this read "Microsoft Intune" |
| Banner at the top | "This device is a Windows Autopilot device" | Its hardware registration survived, which turned out to be the way back |

### What an orphaned device is

> **In plain words**
>
> The computer still held everything it needed to be managed: a valid identity, a certificate proving that identity, and the address of the management service. From its own point of view it was a normal, enrolled, corporate machine.
>
> Intune had no record of it. There was no entry to click, so there was nothing to send a command to. Every remote action, including sync, wipe and policy delivery, requires a device record to act on.
>
> **The device thought it was managed. The service did not know it existed.** That is an orphan.

### How we created it

- **1. Wipe issued** Intune sent a factory reset command.
- **2. Device obeyed** The reset began and reported back.
- **3. Record removed** Intune deleted the device entry, correctly.
- **4. Snapshot restored** We rolled the virtual machine back to before the wipe.

> **Carry this forward**
>
> **Never restore a virtual machine snapshot after issuing a remote wipe.** The snapshot moves the device backwards in time. The service does not move with it. Everything after that point is the two of them disagreeing about reality.
>
> This is specific to lab work with virtual machines, but the same shape appears with physical hardware whenever a device is restored from a backup image after being retired in the console.

## 3. Recovering it, without Intune

> **The rule that made recovery possible**
>
> Intune keeps **two separate lists**, and confusing them is common.
>
> | List | Where it lives | What it holds |
> |---|---|---|
> | Managed devices | Devices → All devices | Computers currently under management |
> | Autopilot registrations | Devices → Enrollment → Windows → Devices | Hardware registered for automatic setup |
>
> A wipe removes the device from the **first** list. It never touches the **second**.

> **Why the second list survives**
>
> Autopilot identifies a machine by a **hardware hash**, a long code derived from its physical characteristics: the security chip, the motherboard, the disk, the network adapters. It is not stored on the computer's disk, so wiping the disk cannot remove it.
>
> Think of it as a fingerprint held on file. The person can change their name, their clothes and their address, and the fingerprint still identifies them.
>
> This is deliberate design, not a loophole. It is precisely how a laptop returned by a leaving employee gets handed to the next person without anyone in IT unboxing it.

### The fix

Because the registration survived, the device could be brought back **from its own side**, with Intune never reaching it at all.

**[Virtual machine]** Settings→ System→ Recovery→ Reset this PC→ Remove everything→ Local reinstall

> **Local reinstall versus cloud download**
>
> **Local reinstall** rebuilds Windows from files already on the disk. Fast, no download.
>
> **Cloud download** fetches a fresh copy from Microsoft, roughly 4 GB. Choose it when you suspect the local files are damaged. Here they were fine, so local was the right call.

On restart the machine reached the **out-of-box experience (OOBE)**, the first-run setup screens. It presented its hardware hash, Microsoft matched it against the registration, and Autopilot took over.

> **The screen that tells you Autopilot fired**
>
> Read the text above the sign-in box. **"Let's set things up for your work or school"** means the Autopilot profile downloaded and applied. **"Sign in to your Microsoft account"** means it did not, and a work account will be rejected there no matter how correct the password is.
>
> If it did not fire, press `Shift + F10` to open a command prompt and run `shutdown /r /t 0`. The profile is requested again on the next boot.

### Proof it genuinely rebuilt

The device came back into Intune named `AB-18949`. It had been `AB-25025`.

> **Why the name changing is the proof**
>
> The Autopilot deployment profile carries a **device name template**, a pattern that generates a name at setup time. A new name means the template ran again, which means this is a newly created device object rather than the old one reconnecting.
>
> Without that, "it came back" and "it was rebuilt" look identical from the console.

## 4. Why the previous attempt froze at 98 per cent

> **What broke**
>
> The reset stopped at 98 per cent and stayed there. The disk was working hard the whole time, which made it look like Windows was busy rather than stuck.

Measuring the host machine gave the answer immediately:

|  | Failed attempt | Successful attempt |
|---|---|---|
| Free space on drive D | **0 GB** | 77.4 GB |
| Virtual disk grew to | 22.97 GB, then died | 30.69 GB, then finished |

> **Why a full host disk looks exactly like a Windows fault**
>
> The virtual machine cannot see the real hard drive underneath it. It sees only its own virtual disk, which reports plenty of free space, so it keeps writing normally.
>
> The host cannot grow the file that backs that virtual disk, because the real drive is full. The write fails. The virtual machine treats a failed write as a temporary glitch and retries. Forever.
>
> The result is heavy disk activity with a progress bar that never moves. Everything about it points at Windows, and none of it is Windows.

> **Carry this forward**
>
> **Check free space on the host before any wipe or rebuild.** A full wipe-and-redeploy cycle on this setup consumes roughly 30 GB, so keep at least 40 GB free.
>
> No Microsoft documentation mentions this, because the host machine is not their concern. It is yours.

## 5. Error 0x800705AA, and why Dynamic Memory did not rescue it

> **What broke**
>
> ```
> Failed to restore 'W11-CORP-01'.
> Could not allocate 3536 MB of RAM: Insufficient system
> resources exist to complete the requested service. (0x800705AA)
> ```
>
> The host had 3.52 GB free. The virtual machine wanted 3.45 GB. It failed on the margin, because Hyper-V needs the requested memory plus its own overhead on top.

> **The word that explains it: restore**
>
> The message says **restore**, not start. The virtual machine was in a ** saved state**, which is Hyper-V's version of hibernation: the contents of its memory were written to disk when it was last shut down.
>
> Restoring a saved state means putting that memory back **exactly as it was**. It is not a fresh boot, so it cannot start smaller and grow. Dynamic Memory, which lets a machine begin with less and expand as needed, has no effect here, because there is nothing to negotiate.

> **Two ways out**
>
> - **Free memory on the host.** Two browsers were open, together holding 4.3 GB. Closing one solved it
> - **Discard the saved state** with `Remove-VMSavedState`, so the machine cold boots. Dynamic Memory then applies and it can start with whatever the host can spare. The cost is losing the suspended session

> **The Dynamic Memory settings used**
>
> ```
> Set-VMMemory -VMName "W11-CORP-01" -DynamicMemoryEnabled $true `
>   -MinimumBytes 2GB -StartupBytes 4GB -MaximumBytes 8GB
> ```
>
> On a 16 GB host running a browser and other work, a fixed allocation is the wrong choice. Dynamic Memory lets Hyper-V hand the virtual machine what is genuinely available and reclaim it under pressure. A fixed 6 GB would simply have failed to start.

## 6. Compliance policies, and the one you did not create

**[Laptop]** intune.microsoft.com→ Devices→ All devices→ AB-18949→ Device compliance

Two policies were listed. Only one had been built by hand.

| Policy | Evaluated as | Origin |
|---|---|---|
| `Win-Baseline-Compliance` | The signed-in user | Built on Day 4 |
| `Default Device Compliance Policy` | System account | **Built in.** Present in every tenant |

> **Microsoft's own wording**
>
> > Compliance policy settings are tenant-wide configurations that act like a built-in compliance policy that every device receives.
>
> It cannot be created and cannot be deleted. It evaluates under the system account because it belongs to no user.

### What a compliance policy actually does

> **It inspects. It does not fix.**
>
> A compliance policy looks at a device and returns a verdict: compliant or not. It changes nothing. Like a hygiene inspection, the inspector does not clean the kitchen, they record whether it was clean.
>
> A **configuration profile** is the opposite. It changes the device and returns no verdict.
>
> You need both. Configuration makes the device correct; compliance proves it, and gives Conditional Access something to act on.

### The default that fails open

**[Laptop]** intune.microsoft.com→ Endpoint security→ Device compliance→ Compliance policy settings

> **The setting, and why the default is wrong**
>
> **Mark devices with no compliance policy assigned as** ships set to **Compliant**.
>
> Meaning: a device that has never been assessed is treated as healthy. It is being waved through because of a missing check, not a passing one.
>
> Changed to **Not compliant**. Microsoft's guidance says the same: if you use Conditional Access with compliance policies, change this setting.

> **The distinction worth remembering**
>
> This setting only affects devices with **no policy assigned at all**. A device that has a policy and passes it stays compliant either way. Changing it does not put working devices at risk.

## 7. Building a settings catalog profile

**[Laptop]** intune.microsoft.com→ Devices→ Manage devices→ Configuration→ Create→ New policy

Platform **Windows 10 and later**, profile type ** Settings catalog**, named `Win-Security-Baseline-Lite`.

> **What the settings catalog is**
>
> A searchable list of thousands of individual Windows settings. You pick the ones you want and compose your own profile.
>
> They are written to a **configuration service provider (CSP)** on the device, which is the component that receives management instructions and puts them into effect. It is the same target that traditional Group Policy writes to, reached over the internet instead of from a domain controller inside a building.

> **Search, do not browse**
>
> Searching returns **categories** containing matches, not settings. Click a category and its settings appear below. With thousands of settings the tree is unusable for finding anything specific.

### Adding a setting is not the same as enabling it

> **What broke**
>
> Both SmartScreen settings were added to the profile and both showed **Disabled**. Saving at that point would have deployed a profile that switched SmartScreen off.
>
> Adding a setting brings it into the profile carrying a default value. It does not turn it on.

### The SMBv1 trap

> **A setting that means the opposite of what it looks like**
>
> Under **Administrative Templates\MS Security Guide**, `Configure SMB v1 server` was set to ** Enabled**, which looked like hardening.
>
> Its own description says otherwise:
>
> > Disabling this setting disables server-side processing of the SMBv1 protocol. (Recommended.) Enabling this setting enables server-side processing of the SMBv1 protocol. (Default.)
>
> **Enabled would have switched on the protocol WannaCry spread through.** Corrected to Disabled. Note it also requires a restart to take effect.

> **Why the client setting behaves differently**
>
> `Configure SMB v1 client driver` is Enabled *plus* a dropdown reading "Disable driver (recommended)". There, Enabled means "apply the choice in the dropdown", and the dropdown carries the action.
>
> The server setting has no dropdown, so Enabled and Disabled *are* the action. Same wording, opposite meaning, depending on whether the setting has a child value.

### Seven settings became fifty-five

> **Why the count jumped**
>
> Seven settings were chosen. The applied list showed 55. Selecting the firewall settings automatically pulled in their dependent child settings: logging, stealth mode, policy merge behaviour, default inbound and outbound actions, three of each, once per network profile.
>
> Those children arrive at their own defaults, which are not always what a security-minded person would choose.
>
> **Read the full applied list after every settings catalog profile.** What you tick is not always what ships.

## 8. Three hours on policy stores

> **What broke**
>
> Intune reported all 55 settings as **Succeeded**. The virtual machine reported the firewall logging setting as `False`. Repeatedly, across several syncs, a profile edit and a restart.

### The tool that settled it

Rather than continue guessing, we asked the device to write down everything it had received.

**[Virtual machine]** PowerShell as administrator

```
mdmdiagnosticstool.exe -out C:\MDMDiag
```

That produces a report listing every policy the device holds. Searching it for the firewall settings returned the answer in the path itself:

```
./Vendor/MSFT/Firewall/MdmStore/DomainProfile/EnableLogDroppedPackets
```

> **The rule nobody tells you**
>
> Windows Firewall does not keep its settings in one place. It keeps several separate **policy stores**:
>
> - **PersistentStore**, rules configured locally on that machine
> - **MdmStore**, rules delivered by mobile device management, which is Intune
> - **ActiveStore**, the combined result of all stores, which is what is actually enforced
>
> `Get-NetFirewallProfile` with no arguments reads **PersistentStore**. The setting was sitting in ** MdmStore** the entire time. Both readings were correct; they were describing different things.

**[Virtual machine]** The correct command

```
Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name, Enabled, LogBlocked
```

> **Carry this forward**
>
> When a setting is verifiably delivered but invisible on the device, you are almost certainly reading the wrong store rather than looking at a broken policy.
>
> `mdmdiagnosticstool.exe` is the device's own record and it outranks both the console and any single command. It also names the store in the path, which is what turns an unanswerable problem into a two-minute one.

## 9. Testing a policy in both directions

### Why the first test proved nothing

> **A test that cannot fail is not a test**
>
> The first check was whether the firewall was enabled. It was, on all three profiles. But **Windows enables the firewall by default**, so True was equally consistent with "the policy worked" and "the policy did nothing".

> **The rule this produces**
>
> **To prove a policy works, choose a setting whose default is the opposite of what you are setting.** Firewall logging is off by default, so seeing it on is unambiguous.

### Both halves

- **Assign** Profile attached, device synced. LogBlocked →
- **Unassign** Group removed, device synced. LogBlocked →

> **Why the removal half matters**
>
> Some settings **tattoo**. The policy is withdrawn and the setting stays behind permanently, because nothing was ever written to put it back. On a fleet of hundreds that is very difficult to undo.
>
> This setting reverted cleanly. That is now a verified fact rather than an assumption, which is the entire reason to run the test.

> **Timing**
>
> Removals take noticeably longer to reach a device than additions. The service has to work out what to withdraw rather than simply what to send. Several syncs and roughly fifteen minutes were needed here.

## 10. Importing an administrative template

> **The problem this solves**
>
> Intune knows about Windows settings and Microsoft's own applications. It knows nothing about Firefox, Adobe Reader, Zoom or anything else. Out of the box those applications cannot be managed from Intune at all.
>
> An **administrative template**, file extension `.admx`, is a file the software vendor publishes listing every policy their application supports. It is the same format Windows management has used for twenty years. Upload it and Intune gains those settings.
>
> The companion `.adml` file holds the display names and descriptions in one language.

**[Laptop]** intune.microsoft.com→ Devices→ Manage devices→ Configuration→ Import ADMX→ Import

### Order is mandatory

> **Dependencies**
>
> Firefox declares Mozilla as a parent namespace, so the files must be imported in order:
>
> 1. `mozilla.admx` with `en-US\mozilla.adml`. Wait for Status to read **Available**
> 2. `firefox.admx` with `en-US\firefox.adml`
>
> Reversed, the import fails with a missing namespace error. To check whether any template has dependencies, open it in a text editor and look for `using prefix` inside the `policyNamespaces` section.

| Documented limit | Value |
|---|---|
| Maximum templates per tenant | 20 |
| Maximum size per file | 1 MB |
| Language files per template | 1, and it must be `en-US` |
| Feature status | Public preview |
| Unsupported | Combo box setting types fail to import |

> **When not to import**
>
> Chrome and Edge settings are already built into the settings catalog. Microsoft's guidance is explicit: do not import templates for settings already available there. Importing Windows' own built-in templates is discouraged for the same reason, and done only when one is required as a parent for something else.

### Building a profile from imported settings

**[Laptop]** Configuration→ Create→ New policy→ Windows 10 and later→ Templates→ Imported Administrative templates (Preview)

> **Computer Configuration, not User Configuration**
>
> The settings tree offers both. **Computer Configuration** applies to the device regardless of who signs in. **User Configuration** follows one user. For device hardening, always the former.

Verified on the device afterwards:

```
Get-ItemProperty "HKLM:\SOFTWARE\Policies\Mozilla\Firefox" | Select-Object -Property * -Exclude PS*
```

| Value | Result | Meaning |
|---|---|---|
| `DisableTelemetry` | 1 | Usage data no longer leaves the machine |
| `BlockAboutConfig` | 1 | The user cannot reach Firefox's hidden settings page to undo policy |
| `PasswordManagerEnabled` | 0 | Credentials cannot be stored in the browser |

## 11. The mistake that repeated three times

> **Enabled means "on". It never means "secure".**
>
> | Setting | Enabled means | Wanted |
> |---|---|---|
> | Configure SMB v1 server | SMBv1 is switched on | Disabled |
> | Enable Log Dropped Packets | Logging is switched on | Enabled |
> | Password Manager | The password manager is switched on | Disabled |
>
> Each of the three was set wrongly on the first attempt, in the same way, for the same reason.

> **The habit that prevents it**
>
> If the setting's name does not contain a verb such as **Disable** or **Block**, the name tells you nothing about which direction is safe. Hover the information icon and read the description before choosing.
>
> Settings whose name already carries the verb, such as `DisableTelemetry`, behave as expected: Enabled disables telemetry.

## 12. What to remember for the exam

- A wipe removes the Intune device record. It does **not** remove the Autopilot registration, which is why a wiped device returns through Autopilot every time until it is deregistered.
- Deregistration happens at Devices → Enrollment → Windows → Devices, and it is what you do when a machine leaves the company.
- Retire removes company data and management, leaving personal data. Wipe is a factory reset. Delete removes only the console record and leaves the device configured and unmanaged.
- Autopilot devices cannot be deleted from the Entra admin center. The registration is the authority.
- Compliance policy settings are tenant-wide and act like a built-in policy every device receives.
- "Mark devices with no compliance policy assigned as" defaults to Compliant, which fails open. Change it when using Conditional Access.
- A compliance policy judges. A configuration profile changes. Conditional Access acts on the judgement.
- Adding a setting to a settings catalog profile brings it in at a default value, not enabled.
- Selecting a parent setting can silently pull in its children at their own defaults.
- Windows Firewall keeps multiple policy stores. Only ActiveStore shows what is enforced.
- `mdmdiagnosticstool.exe` produces the device's own record of every policy it holds, including the path that names the store.
- Administrative templates must be imported in dependency order, parent namespace first.
- Imported templates are limited to 20 files, 1 MB each, one `en-US` language file per template.
- Policy removal reaches a device more slowly than policy assignment.

*Day 7 of the MD-102 lab series. Written from the session record, 24 to 25 August 2026. Lab tenant only, not production. Every command and portal path in this document was executed and its output verified during the session.*
