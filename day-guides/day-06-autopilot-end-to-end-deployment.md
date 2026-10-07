# Day 6: Autopilot End-to-End Deployment

*Wiping a managed device remotely and letting Autopilot rebuild it. Four separate blockers, three of them created by our own earlier configuration.*

Monday 24 August 2026 · MD-102 study track · VM `W11-CORP-01` / `LABVMGOCE`

**Where the day ended**

- Intune remote **Wipe** executed successfully, device returned to a clean OOBE
- Autopilot fired on the second boot and downloaded its profile
- Microsoft Entra join succeeded after a tenant settings fix
- Enrollment Status Page started and completed Device preparation and Device setup
- **Account setup never completed.** Unresolved, carried to the next session
- VM rolled back to the pre-wipe checkpoint, so the lab is intact

## 1. The checkpoint, and why it is not optional

**LAPTOP**, PowerShell as administrator:

```
Checkpoint-VM -Name "W11-CORP-01" -SnapshotName "Pre-Autopilot-Clean"
```

> **Why**
>
> The machine about to be wiped took three days to build. It is Entra joined, Intune enrolled, BitLocker encrypted with an escrowed key, compliant on two settings, and carrying a configuration profile. A checkpoint captures all of that in about ten seconds.
>
> This turned out to be the single most important action of the day. When the deployment stalled, the rollback took under a minute and the lab was intact. Without it the evening would have ended with nothing.

> **Carry this forward**
>
> Checkpoint before anything destructive. Delete it once the outcome is known, Day 4 showed what a lingering differencing disk costs in disk space and write speed.

## 2. Wiping the device from Intune

The wipe was done through Intune rather than a local reset, deliberately. Remote actions are an MD-102 objective in their own right, and this is the realistic scenario: a returned laptop re-provisioned without anyone touching it.

**[Laptop]** intune.microsoft.com→ Devices→ All devices→ LABVMGOCE→ Wipe

### The two checkboxes, and what they actually do

| Checkbox | Setting used | Why |
|---|---|---|
| Wipe device, but keep enrollment state and associated user account | **Unchecked** | Ticking it leaves the device enrolled, so it never returns to a clean OOBE and Autopilot never runs. That kills the entire test. |
| Wipe device, and continue to wipe even if device loses power | **Unchecked** | The panel's own warning states it might prevent some devices running Windows 10 and later from starting up again. A VM on a mains-powered laptop is not going to lose power, so this is risk with no benefit. |

> **Why the power-loss option exists at all**
>
> On a physical device that dies mid-wipe, a partially wiped disk can be left in a state where some data survives. That option forces the wipe to resume and complete. The trade is that a wipe which cannot be interrupted can also leave a device unbootable if it fails. For a stolen laptop that trade is worth it. For a lab VM it is not.

### Timing

- **Command queued** Intune holds it until the device checks in.
- **Device receives** A few minutes when the device is online.
- **Reset runs** 20 to 45 minutes on a 4 GB VM.
- **Clean OOBE** Device restarts into setup.

The restart into the reset screen is the confirmation that the command landed. Nothing in the portal tells you sooner.

## 3. Autopilot did not fire on the first boot

> **What broke**
>
> After the wipe the device reached OOBE, but the work account was rejected at sign-in. The password was verified correct by typing it into the visible username field first, so it was not a keyboard layout problem this time.
>
> **Cause:** Autopilot had not fired, so OOBE was running its standard flow rather than the Autopilot one. A work account fails against a screen asking for a personal Microsoft account.

> **Microsoft's rule, the profile downloads once, early**
>
> > The Windows Autopilot profile is downloaded as soon as possible, and again after each reboot.
>
> If the network is not up at that first attempt, the device caches a blank profile and continues as an ordinary Windows setup. Microsoft's documented fix is to reboot so the download runs again.

**VM**, at any OOBE screen, Shift + F10 to open a command prompt, then:

```
shutdown /r /t 0
```

On the second boot the Autopilot sign-in appeared and the work account was accepted.

> **The diagnostic that settled it**
>
> Read the text above the sign-in box. "Sign in to your Microsoft account" means Autopilot did not fire. An Autopilot sign-in names the organisation or asks for a work or school account. This one line tells you which flow you are in and saves a lot of guessing at the password.

## 4. Error 801c03ed: our own Day 2 hardening

> **What broke**
>
> ```
> Something went wrong. 801c03ed
> ```
>
> Thrown at the Microsoft Entra join step, immediately after the credentials were accepted.

> **Microsoft's rule, 801c03ed has two documented causes**
>
> 1. The administrator policy does not allow the user to join devices
> 2. The user has exceeded the number of devices they are allowed to join
>
> Microsoft's Autopilot FAQ states it plainly: *the most common issue joining a device to Microsoft Entra ID is related to Microsoft Entra permissions.*

> **Why this is the most instructive failure of the week**
>
> Both causes were configured by us, on Day 2, deliberately, as good practice:
>
> - **Users may join devices to Microsoft Entra** restricted to `IT-Admins`
> - **Maximum number of devices per user** set to 5
>
> Every VM rebuild across the week left a device object behind. Those stale objects count towards the limit. So a correct security decision on Day 2 became the blocker on Day 6, and nothing about the error message points at it.
>
> This is the real shape of endpoint support work. The failure is rarely a broken product. It is a setting somebody chose, for a good reason, on a different day.

**[Laptop]** entra.microsoft.com→ Entra ID→ Devices→ Device settings

| Setting | Changed to |
|---|---|
| Users may join devices to Microsoft Entra ID | `All` |
| Maximum number of devices per user | `Unlimited` |

Changes take a few minutes to propagate. Retrying immediately produces the same error and wastes a reboot.

> **The production version of this fix**
>
> Setting both to unrestricted is the right call in a lab and the wrong call in production. In production you would instead add the specific user to the permitted group and delete the stale device objects. The proper cleanup path is Entra ID, Intune and Autopilot all three, Microsoft documents that deleting only the Entra object breaks the Autopilot anchor and causes join errors of its own.

## 5. The Enrollment Status Page stalled at Account setup

After the join succeeded, the ESP ran. Device preparation and Device setup completed. Account setup did not.

### The diagnostics page that was not available

> **What broke**
>
> Ctrl + Shift + D, Microsoft's documented shortcut for the Autopilot diagnostics page, did nothing.
>
> **Cause:** the diagnostics page has to be switched on in the ESP profile beforehand. It is not on by default.

> **Microsoft's rule, enabling the diagnostics page**
>
> Two settings in the ESP profile must both be **Yes**:
>
> - **Show app and profile configuration progress**
> - **Turn on log collection and diagnostics page for end users**
>
> It is then reached with the **View Diagnostics** button or Ctrl + Shift + D, and is supported only on Windows 11, in user-driven mode, when signing in with a work or school account.

> **Turn this on before the next run**
>
> A troubleshooting tool you have to enable in advance is useless the first time you need it. Both settings go on now, permanently, so the next stall is diagnosable instead of opaque.

### The leading suspect: the logon banner from Day 4

> **Microsoft's rule, policies that conflict with Autopilot**
>
> Under `Computer Configuration\Windows Settings\Security Settings\Local Policies\Security Options`, Microsoft names four GPOs that conflict with Autopilot. Two of them are exactly what we deployed on Day 4:
>
> - **Interactive logon: Message title for users attempting to log on**
> - **Interactive logon: Message text for users attempting to log on**
>
> Separately, and not scoped to any one mode, the same page warns that the out-of-box experience or user desktop autologon can fail when a device reboots during the device ESP, under policies *including any that disable autologon*.

> **Why the banner is the suspect**
>
> The ESP runs under an automatic logon. A logon banner interrupts that logon with a message box waiting to be dismissed, and there is no user present to dismiss it. The banner is also the only policy in the tenant that touches the logon path.
>
> **Honest limit on this:** Microsoft scopes those four GPOs to *pre-provisioning*, not user-driven deployment. So this is a well-supported hypothesis, not a confirmed diagnosis. The next run, with the banner unassigned, is what proves or kills it.

## 6. Enhanced Session Mode blocked a standard user

> **What broke**
>
> Signing in as Anna Test, a standard user, was refused with a message about not having the right to sign in remotely.
>
> **Cause:** Enhanced Session Mode had been enabled earlier in the day to get clipboard paste working:
>
> ```
> Set-VMHost -EnableEnhancedSessionMode $true
> ```
>
> Enhanced Session Mode connects into the guest over RDP. RDP sign-in requires membership of Remote Desktop Users or the equivalent logon right. A standard user on an Entra-joined device has neither.
>
> **Fix, in the vmconnect window's own menu bar on the host, not the guest UI:**
>
> **[Laptop]** View→ untick Enhanced Session
>
> Basic session is a console connection and needs no RDP rights.

> **Why this is worth knowing beyond the lab**
>
> Enhanced Session Mode gives you clipboard, drive redirection, and better resolution. It also silently changes what kind of sign-in you are performing. Two connections to the same VM, same credentials, different result, because one is a console logon and the other is a remote logon, and Windows treats those as different rights.

## 7. The rollback

**LAPTOP**, PowerShell as administrator:

```
Restore-VMCheckpoint -VMName "W11-CORP-01" -Name "Pre-Autopilot-Clean" -Confirm:$false
```

Back to the joined, enrolled, encrypted machine in under a minute.

> **What surprised us after the rollback**
>
> The logon banner was still there, even though its assignment had been removed in Intune minutes earlier.
>
> **Cause:** two things at once. The checkpoint restored the exact state captured before the wipe, banner included. And removing an assignment does not reach out and change the device, the change lands on the device's next policy sync.
>
> **Fix, on the VM:**
>
> **[VM]** Settings→ Accounts→ Access work or school→ the connected account→ Info→ Sync
>
> This is the same lesson as Day 4 from the other direction. A configuration profile changes the device when it syncs, and reverts it when it syncs. Neither happens the instant you click Save in the portal.

## 8. The plan for the next run

1. Banner configuration profile left unassigned
2. ESP diagnostics switched on: **Show app and profile configuration progress** and **Turn on log collection and diagnostics page for end users**, both Yes
3. VM startup memory raised to 6 GB, browser closed first
4. Fresh checkpoint before the wipe
5. Stale Entra device objects cleaned up rather than raising the limit

> **What actually got proved today**
>
> It is worth being accurate about this rather than filing it as a failure. The remote wipe worked. Autopilot registration worked. Profile download worked. Entra join worked. MDM enrolment worked. Two of the three ESP phases completed.
>
> The unfinished part is the last phase of the last step. Everything the exam actually tests about Autopilot ran correctly.

## 9. What to remember for the exam

- Intune **Wipe** with "keep enrollment state" ticked leaves the device enrolled, so Autopilot never runs.
- The Autopilot profile downloads early in OOBE and again after each reboot. No network at that moment means no Autopilot. Reboot to retry.
- **801c03ed** means the user is not permitted to join devices, or has hit the device limit. Both are Entra device settings, not Intune.
- Stale device objects count towards the per-user device limit.
- Deleting an Entra device object alone breaks the Autopilot anchor. Clean up Entra, Intune and Autopilot together.
- The ESP diagnostics page must be enabled in the ESP profile in advance. Ctrl + Shift + D does nothing otherwise.
- Interactive logon message title and text are named by Microsoft among GPOs that conflict with Autopilot.
- The ESP depends on autologon. Any policy that interrupts autologon can hang it.
- Removing a policy assignment changes the device at its next sync, not at the moment you save.
- Enhanced Session Mode is an RDP connection and requires RDP logon rights. Basic session does not.

*Day 6 of the MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production. Account setup remains unresolved and is carried forward.*
