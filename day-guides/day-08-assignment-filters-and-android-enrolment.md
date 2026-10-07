# Day 8: Assignment Filters and Android Enrolment

*Changing who receives a policy without touching a single group, and bringing a second platform under management on real hardware.*

Wednesday 26 to Thursday 27 August 2026 · MD-102 study track · Windows virtual machine `AB-18949`, personal Android phone

**Where the day ended**

- An assignment filter built and proven in both directions on a live device
- The tenant bound to Managed Google Play, after a documented prerequisite cost an hour
- A personal Android phone enrolled as a work profile, evaluated, failed, remediated and compliant
- An Android compliance policy built, exposing that compliance is per-platform
- Apple management understood without an Apple device, deliberately not configured

## 1. What an assignment filter is

> **The problem it solves**
>
> Until today every policy went to a whole group. All of it, or none of it.
>
> Real estates need "this group, but only the Windows 11 machines" or "this group, but not the personally owned devices". Without filters you build a separate group for every combination. Twenty policies with three variations each is sixty groups to create, maintain, and eventually inherit from someone who has left with no idea what any of them are for.
>
> A filter is a reusable rule evaluated against the device at check-in. Build it once, apply it to as many assignments as you like, and the groups stay untouched.

**[Laptop]** intune.microsoft.com→ Tenant administration→ Assignment filters→ Create

Built as `Filter-Corporate-Owned`, platform Windows 10 and later, with the rule:

```
(device.deviceOwnership -eq "Corporate")
```

> **The habit worth forming**
>
> On the Rules page there is a **Preview devices** button. It lists exactly which enrolled devices the rule matches, before you assign anything to anyone.
>
> Validating targeting before deployment rather than after is the difference between a filter and a guess.

### The three modes

| Mode | Effect |
|---|---|
| Do not apply a filter | Everyone in the group receives the policy |
| **Include** filtered devices in assignment | Only devices matching the filter receive it |
| **Exclude** filtered devices in assignment | Matching devices are the ones that do **not** receive it |

## 2. Proving it, in five steps

> **Why the test setting was chosen carefully**
>
> The obvious test is to check whether the firewall is enabled after applying a firewall policy. That test is worthless, because **Windows enables the firewall by default**. A result of True is equally consistent with "the policy worked" and "the policy did nothing".
>
> `LogBlocked`, firewall logging of dropped packets, is **off** by default. Nothing turns it on by accident. So if it reads True, exactly one thing put it there.
>
> **To prove a policy works, choose a setting whose default is the opposite of what you are setting.**

Each step changed exactly one variable:

| # | Configuration | `LogBlocked` | What it proved |
|---|---|---|---|
| 1 | No policy | False | Baseline, the natural state |
| 2 | Policy assigned | **True** | Intune delivers to this device |
| 3 | Policy unassigned | **False** | Removal reverses it. No tattoo |
| 4 | Filter, Include mode | **True** | Adding a filter did not break a working assignment |
| 5 | Filter, **Exclude** mode | **False** | The filter alone stopped delivery |

> **The claim this establishes**
>
> Throughout steps 4 and 5 the device never left `Dyn-Autopilot-Devices`. Group membership was identical. The only change was the filter mode.
>
> **You can change who receives a policy without changing any group.** That is the whole point, and it is now demonstrated rather than assumed.

> **Timing, and a trap**
>
> Removals reach a device noticeably more slowly than assignments. The service has to work out what to withdraw rather than simply what to send.
>
> The verification that removes the guesswork is `mdmdiagnosticstool.exe`: if the setting's path is still listed in the device's own report, the withdrawal has not landed yet and there is nothing to troubleshoot.

## 3. Filters versus dynamic groups

|  | Assignment filter | Dynamic group |
|---|---|---|
| Targets on | Device properties: operating system, model, manufacturer, ownership, category | Any directory attribute, users or devices |
| Evaluated | At device check-in. **No membership lag** | On the directory's own schedule, with real lag |
| Usable by | Intune policies and apps only | Conditional Access, licensing, Autopilot, anything |
| Autopilot profile assignment | **Cannot do it** | **Required for it** |

> **Why the bottom row explains Day 5**
>
> A filter reads properties of an **enrolled** device. An Autopilot-registered device has not enrolled yet, so it has no properties to read. There is nothing for a filter to match.
>
> That is why the Autopilot deployment profile needed a dynamic group on the Zero Touch Deployment identifier, and why no filter could ever have replaced it.
>
> Most real tenants use both: dynamic groups where something outside Intune needs the membership, filters for narrowing assignments inside Intune.

## 4. Binding the tenant to Managed Google Play

> **Nothing Android works without this**
>
> Android Enterprise runs through Google. Before any Android device can enrol by any method, the Intune tenant must be linked to a Google enterprise.

**[Laptop]** intune.microsoft.com→ Devices→ Enrollment→ Android→ Managed Google Play

### The prerequisite that cost an hour

> **What broke**
>
> Google's sign-up sent a six-digit verification code to `admin@labtenant.onmicrosoft.com`. Opening that mailbox returned:
>
> ```
> Microsoft.Exchange.Clients.Owa2.Server.Core.OwaUserHasNoMailboxAndNoLicenseAssignedException
> ```
>
> The tenant had Intune Suite and Entra ID P2. Neither includes Exchange Online, so the account had no mailbox.

> **Microsoft's documentation states it twice**
>
> > The account must also have a mailbox set up to complete the validation process required by Google.
>
> > The Microsoft Entra account must have an active mailbox to complete the validation process required by Google.
>
> This is a hard prerequisite, not an optional convenience. Google validates the address regardless of which sign-in path is used.

> **The detour, and what it cost**
>
> Google offered **Sign in with Microsoft**, a federated path that appeared to bypass the code entirely. It failed with "Your account was not created" and no further detail. Reasonable to assume the mailbox was no longer needed. It was not.
>
> Resolved by taking a **Microsoft 365 Business Standard trial**, purely because it includes Exchange Online, and assigning it to the admin account. Search the Marketplace for the product you need rather than for a plan name: searching "Exchange Online" returned only a Defender add-on, while "Business Standard" returned the trial that actually provisions a mailbox.

> **The second failure, and its cause**
>
> Even with a mailbox, the sign-up failed again. Suspicion fell on NordVPN, which had broken portal blades twice earlier in this lab, and on Malwarebytes web filtering. Both were stopped. Neither was responsible.
>
> **The signup URL carries a single-use token issued at the moment you click Connect to Google now.** It had expired during the mailbox detour. Closing the blade, reopening it, and starting the flow fresh worked immediately.

> **Carry this forward**
>
> When a federated sign-up fails with no detail, **restart the flow from the originating blade before debugging anything else**. The token is issued when you click, not when you finish signing in. An hour went into browser and security software theories that were never the cause.

### The account choice, and why it matters permanently

> **This binding does not come undone easily**
>
> The account used becomes the tenant's Android administrator, permanently. Changing it means disconnecting and re-enrolling every Android device.
>
> Use an **organisational identity**, never a personal Gmail account. When the person owning that personal account leaves, the binding becomes unmanageable.
>
> Since August 2024 Microsoft recommends using the Microsoft Entra account rather than a Gmail address, which is the path taken here.

Google then offered optional free subscriptions: Google Workspace Essentials Starter and Chrome Enterprise Core. **Android Enterprise was already marked Included**, which is all Intune requires. The others were declined, on the principle that a free service still has to be managed and eventually cleaned up.

## 5. Enrolling a personal Android phone

**[Phone]** Play Store→ Intune Company Portal→ Sign in with work account→ Set up work profile

> **What a work profile actually is**
>
> Android creates a **second container** on the same phone. Work applications get a briefcase badge. Personal applications sit outside it, untouched.
>
> The separation is real, not cosmetic. Personal applications cannot see work files and work applications cannot see personal ones. Intune manages only the work side. It cannot read personal photos, messages or applications.
>
> This was demonstrated accidentally: a screenshot taken inside a work application saved to the work profile's storage and was unreachable from the personal side.

> **The separation is configurable, and that is exam material**
>
> An Android Enterprise device restrictions profile controls whether data may cross the boundary: copy and paste between profiles, sharing from work applications to personal ones, and contact visibility. The default is blocked.

## 6. Compliance is per-platform

> **What the phone reported**
>
> > No compliance policies have been assigned to the device. Your device must receive compliance policies before it can be used to access your organization's resources.

> **Two things caused that message together**
>
> 1. **Compliance policies are per-platform.** The Windows policy built on Day 4 does nothing for Android. Each platform needs its own
> 2. The tenant-wide setting **Mark devices with no compliance policy assigned as** had been changed from Compliant to **Not compliant** the previous day
>
> Yesterday that change was an abstract hardening decision. Today it appeared on a real phone as a blocked device. Under the default it would have been silently waved through as compliant, having never been assessed at all.

**[Laptop]** Devices→ Compliance→ Create policy→ Android Enterprise→ Personally-owned work profile

### The Android 12 split

> **Google changed how passwords are specified**
>
> The settings page is divided into two branches, and the reason is a genuine platform change:
>
> | Branch | Setting | Values |
> |---|---|---|
> | Android 12 and later | Password complexity | None, Low, Medium, High |
> | Android 11 and earlier | Required password type, plus minimum length | Numeric, alphabetic, alphanumeric, with symbols |
>
> On Android 12 Google removed granular length and character requirements and replaced them with three complexity tiers. You no longer say "at least six characters with a number". You pick a tier and Google decides what satisfies it.
>
> **Set both branches.** You do not know what version every device in an estate runs.

### Work profile password versus device password

> **Two separate settings, and the right one for bring-your-own-device**
>
> **Require a password to unlock work profile** secures only the work container.
>
> **Device password** settings secure the whole phone, including the personal side.
>
> On a personally owned device, take the work profile one. It is less intrusive, it is what a real organisation would set for bring-your-own-device, and it respects the container boundary rather than reaching across it.

### Actions for noncompliance, and the grace period

> **The setting most worth understanding**
>
> Every policy carries one action by default: **Mark device noncompliant**, scheduled at ** 0 days**, meaning immediately.
>
> Setting that schedule to three days creates a **grace period**: a device that fails is not marked noncompliant for three days, giving the user time to fix it before Conditional Access begins blocking them.
>
> Zero days is honest and brutal. Someone whose password expires overnight loses access to email before breakfast, with no warning and no route back except a support call.

### The chain, end to end

- **Policy assigned** To a dynamic Android device group.
- **Device evaluated** At its next check-in.
- **Check failed** No work profile password set.
- **User prompted** Company Portal named the exact failure.
- **Compliant** After setting the work profile lock.

> **Why this is worth describing at interview**
>
> The user was never told "your device is broken". They were told exactly which requirement failed and given a button to fix it. That is what a well-configured compliance policy does, and it is the difference between a policy that works and a policy that generates support tickets.

## 7. Apple, understood without an Apple device

**[Laptop]** Devices→ Enrollment→ Apple→ Apple MDM Push Certificate

Deliberately not configured. There are no Apple devices in this lab, and the certificate creates an annual renewal obligation with real consequences for forgetting it.

| Step | What happens |
|---|---|
| 1 | Consent to Microsoft sending device and user data to Apple |
| 2 | Download a certificate signing request from Intune |
| 3 | Take it to Apple's Push Certificates Portal, sign in with an Apple ID, upload it. Apple issues a certificate |
| 4 | Upload Apple's certificate back to Intune, with the Apple ID used |

> **The four facts that matter, all from step 4**
>
> - The certificate is valid for **one year** and must be renewed
> - It must be renewed with the **same Apple ID**. A different one is not a renewal, it is a new certificate
> - A new certificate means **every Apple device must be re-enrolled**, by hand
> - Therefore the Apple ID must be an **organisational account**. When the person owning a personal one leaves, the estate unmanages itself
>
> Structurally identical to the Google account binding earlier the same day: an identity that must outlive whoever configured it.

> **Also worth knowing**
>
> **Automated Device Enrolment** is Apple's equivalent of Windows Autopilot, driven by Apple Business Manager. **FileVault** is the macOS equivalent of BitLocker and lives under Endpoint security, Disk encryption.

## 8. What to remember for the exam

- A filter narrows an assignment without changing group membership. Include mode delivers only to matches; Exclude mode delivers to everyone except matches.
- Filters are evaluated at device check-in, so there is no membership lag. Dynamic groups are evaluated on the directory's schedule.
- A filter works only inside Intune. Conditional Access, licensing and Autopilot all need real groups.
- A filter cannot assign an Autopilot profile, because an unenrolled device has no properties to match.
- Limits: 200 filters per tenant, 3,072 characters per filter. Managed app filters apply only to app protection and app configuration policies.
- Deleting a filter requires removing it from every assignment first.
- Android Enterprise requires the tenant bound to Managed Google Play. Nothing Android works without it.
- That binding requires the Microsoft Entra account to have an **active mailbox**, because Google validates the address.
- The binding account is permanent. Changing it means re-enrolling every Android device.
- Android device administrator management is deprecated for devices with Google Mobile Services.
- Compliance policies are per-platform. A Windows policy does nothing for Android.
- On Android 12 and later, password rules are a complexity tier. On Android 11 and earlier, they are a type plus a minimum length.
- Work profile password and device password are separate settings. On bring-your-own-device, the work profile one is correct.
- Actions for noncompliance default to marking a device noncompliant at 0 days. A grace period gives users time to remediate.
- No Apple device can enrol without an Apple MDM push certificate, valid one year, renewable only with the same Apple ID.

*Day 8 of the MD-102 lab series. Written from the session record, 26 to 27 August 2026. Lab tenant only, not production. Every portal path and command in this document was executed during the session and its result verified.*
