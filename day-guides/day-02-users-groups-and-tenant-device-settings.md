# Day 2: Users, Groups and Tenant Device Settings

*Populating the directory, learning the difference between assigned and dynamic membership, and setting the tenant-wide rules that decide who is allowed to join a device at all.*

Wednesday 19 August 2026 · MD-102 study track · Worked on the iMac, not the laptop

**What existed at the end of the day**

- 30 users in `labtenant.onmicrosoft.com`: 10 created by hand, 20 by PowerShell
- 5 groups: 3 assigned, 2 dynamic
- Anna Test holding the Intune Administrator role
- Tenant device settings locked down: only IT-Admins may join devices, maximum 5 devices per user
- PowerShell 7 and the Microsoft Graph SDK working on macOS

## 1. Why a directory needs to exist before anything else

Intune does not have its own users. It borrows them from Entra ID. Every policy, every enrolment restriction, every Autopilot profile is assigned to *a group*, and a group is a container of users or devices that live in Entra ID.

- **Entra ID** Holds users, groups, devices. The identity layer.
- **Group** The unit everything is targeted at. Never target individuals.
- **Intune policy** Compliance, configuration, Autopilot, apps. All assigned to groups.

> **Why**
>
> **"Entra ID"** is the current name for what was Azure Active Directory. Exam questions and older documentation still say Azure AD. They are the same thing. The rename happened in 2023 and the underlying commands still carry the old name, which is why you will see `AzureAdJoined` in output from a tool run in 2026.

## 2. Ten users by hand, twenty by script

Both routes were used deliberately, to feel the difference.

### By hand

**[Browser]** entra.microsoft.com→ Identity→ Users→ All users→ New user→ Create new user

**Ten users took roughly ten minutes.** Every field typed, every page confirmed.

### By PowerShell and Microsoft Graph

**Twenty users took 7.3 seconds.**

> **Why**
>
> **"Microsoft Graph"** is the single API behind every Microsoft 365 service. The portal you click in is itself just a website calling Graph. Anything the portal can do, Graph can do, and Graph can do it thirty times in a loop.
>
> **"SDK"**, software development kit. The `Microsoft.Graph` PowerShell module is a set of cmdlets that wrap Graph calls so you write `New-MgUser` instead of hand-building HTTP requests.
>
> This is the whole argument for scripting in endpoint management, and it is why `notions de PowerShell` appears on Romandie support job descriptions. Ten users is a coffee break. Three hundred users is a week you do not have.

> **What broke, silent data errors**
>
> Two records went in wrong and nothing complained:
>
> - `aul.test` instead of `paul.test`, a dropped first character in the source data
> - Job title `vice Desk Analyst` instead of `Service Desk Analyst`, the same class of error
>
> **Cause:** the script did exactly what it was told. Graph validates format, not intent. `aul.test@labtenant.onmicrosoft.com` is a perfectly valid user principal name.
>
> **The lesson:** bulk operations multiply mistakes at the same speed they multiply work. Always read back what was created. `Get-MgUser -All | Select DisplayName, UserPrincipalName, JobTitle` takes two seconds and catches this.

## 3. Assigned groups versus dynamic groups

Five groups were built, deliberately split across both types.

| Group | Type | How membership is decided |
|---|---|---|
| `IT-Admins` | Assigned | Someone adds a member by hand. Membership changes only when a human changes it. |
| `All-Corp-Devices` | Assigned | Same. |
| `All-BYOD` | Assigned | Same. |
| `Dyn-Windows-Devices` | Dynamic device | Entra evaluates a rule. Any device matching it joins automatically. |
| `Dyn-Android-Devices` | Dynamic device | Same, different rule. |

#### The two rules used

```
device.deviceOSType -eq "Windows"
device.deviceOSType -startsWith "Android"
```

> **Why -startsWith for Android and -eq for Windows**
>
> Android reports its OS type with variations, `Android`, `AndroidForWork`, `AndroidEnterprise` depending on enrolment mode. An exact match would miss most of them. Windows reports a single consistent value.
>
> This is a real habit worth keeping: match loosely where the platform is inconsistent, exactly where it is not.

> **Microsoft's rule, dynamic membership requires a licence**
>
> Dynamic group membership is a Microsoft Entra ID P1 feature. It is not available on the free tier. The Entra ID P2 trial activated on Day 1 covers it.
>
> Membership is also not instant. Entra evaluates rules on its own schedule. A newly created device can take several minutes to appear in a dynamic group, and a policy targeted at that group will not apply until it does. Many "the policy isn't working" problems are actually "the device isn't in the group yet".

**[Browser]** entra.microsoft.com→ Identity→ Groups→ All groups→ New group→ Group type Security→ Membership type Dynamic Device→ Add dynamic query

> **What broke, the member picker did not commit**
>
> Members selected in the group's member picker were not saved. No error appeared. The group simply stayed empty.
>
> **Cause:** the picker requires an explicit **Select** click at the bottom of the flyout before the parent blade registers the choice. Clicking a name only highlights it.
>
> **The lesson:** in the Entra portal, never trust a highlighted row. Confirm the group's member count afterwards.

## 4. Roles: giving someone Intune admin rights

Anna Test was given the **Intune Administrator** role.

**[Browser]** entra.microsoft.com→ Identity→ Roles & admins→ All roles→ Intune Administrator→ Add assignments

> **Why not just make everyone a Global Administrator**
>
> Because it is the fastest way to fail a security audit. **Least privilege** means an account holds only the rights its job needs. Intune Administrator can do everything in Intune and nothing outside it. If that account is compromised, the blast radius is the endpoint estate, not the entire tenant.

> **What broke, Intune Administrator could not edit Device settings**
>
> Signed in as Anna, the Entra **Device settings** page rendered read-only.
>
> **Cause:** Device settings live in Entra ID, not in Intune. Intune Administrator has no authority over them. The role that does is **Cloud Device Administrator**.
>
> **Why this matters:** "Intune Administrator" sounds like it covers devices. It covers the Intune service. Device *identity* settings belong to the identity platform. This distinction, Entra owns identity, Intune owns management, is one the exam tests repeatedly.

## 5. Tenant device settings: the gate before every enrolment

These are tenant-wide switches in Entra that decide who may join a device to the tenant at all. They sit *above* everything Intune does. If this gate is shut, no Intune configuration in the world will let a device in.

**[Browser]** entra.microsoft.com→ Identity→ Devices→ Overview→ Device settings

| Setting | Set to | Effect |
|---|---|---|
| Users may join devices to Microsoft Entra | `Selected → IT-Admins` | Only members of IT-Admins can perform an Entra join. Everyone else is refused. |
| Maximum number of devices per user | `5` | A user's sixth device is refused until one is removed. |

> **Carry this forward, the enrolment failure checklist starts here**
>
> When a device will not enrol, these two settings are the first two things to check, before touching anything in Intune:
>
> 1. Is the user in the group allowed to join devices?
> 2. Has the user already hit the device limit? Stale device objects from previous rebuilds count towards it.
>
> Both of these were checked and cleared during the Day 3 enrolment failure. Neither was the cause, but eliminating them was necessary.

## 6. Tooling note: PowerShell and Graph on macOS

Day 2 ran on the iMac, which meant getting the Microsoft tooling working outside Windows.

- PowerShell 7.7 preview installed via Homebrew. The binary is `pwsh-preview`, not `pwsh`.
- `Microsoft.Graph` SDK version 2.39.0. The module installs as a large set of submodules, one per Graph workload, and the first import is slow.

> **Why this is worth knowing**
>
> PowerShell 7 is cross-platform and built on .NET. Windows PowerShell 5.1, the version shipped inside Windows, is not. Most Graph work is fine on either, but 5.1 has real syntax differences that bite. One of them cost time later in the week: `Set-Service -Name` accepts a single name in 5.1, while `Stop-Service -Name` accepts an array. Passing an array to the first one fails. The fix was a `foreach` loop.

## 7. What to remember for the exam

- Everything in Intune is assigned to a group, never to an individual user or device.
- Assigned membership is manual. Dynamic membership is a rule Entra evaluates, and it requires Entra ID P1.
- Dynamic membership is not instant. Allow for evaluation delay before concluding a policy is broken.
- Entra ID owns device *identity*. Intune owns device *management*. Different roles govern each: Cloud Device Administrator versus Intune Administrator.
- "Users may join devices" and "Maximum devices per user" are tenant-wide gates that sit above all Intune configuration.
- Stale device objects count towards the per-user device limit.

*Day 2 of 5, MD-102 lab series. Written from the session record, 24 August 2026. Lab tenant only, none of this is production.*
