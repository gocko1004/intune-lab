# Screenshots

Taken in the lab and redacted before upload. Tenant name, tenant and device IDs, admin accounts,
serial numbers, recovery keys and passwords are blacked out, not blurred.

Grouped by process. Each row says what the screenshot shows and, where it records a failure, why it
happened. The full story is on the linked page.

## Enrolment

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `01-day03-mdm-authority-none.png` | Choose MDM Authority set to **None** | **Error 80180003**, "not authorized to enroll". The tenant had never declared which service manages devices, so every enrolment was refused. The error blames the user; the user was never the problem | [Day 3](../day-guides/day-03-windows-install-entra-join-and-intune-enrolment.md#the-actual-cause) |

## Windows Autopilot

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `10-day05-autopilot-profile-user-driven.png` | Deployment profile `APUserDrivenEntraJoin`: User-Driven, Microsoft Entra joined | User-driven because self-deploying mode needs a physical TPM 2.0 | [Day 5](../day-guides/day-05-windows-autopilot.md#4-the-deployment-profile) |
| `09-day05-ztdid-group-member-found.png` | `Dyn-Autopilot-Devices` with the lab VM as its member | **Profile stayed Not assigned** while it targeted `Dyn-Windows-Devices`: `deviceOSType` only matches enrolled devices. The ZTDid rule matches at registration | [Day 5](../day-guides/day-05-windows-autopilot.md#the-correct-rule) |
| `06-rebuild-corp-97322-in-intune.png` | `CORP-97322` in the Intune encryption report | The name comes from the profile's template `CORP-%RAND:5%`, proof the profile drove setup | [Rebuild](../rebuild/README.md#where-it-stands) |

## Compliance

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `07-rebuild-compliance-per-setting.png` | `CP-Windows` per setting: nine settings Compliant, 0 Not applicable | A Not applicable line was never checked. Zero means every check actually ran | [Rebuild](../rebuild/README.md#compliance) |

## Windows Update

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `11-lab-day11-feature-pin-deploys-25h2.png` | Policy `Feature-Pin-24H2`, Versions column **Windows 11, version 25H2** | **Name did not match behaviour.** The name was a label typed by a human; the Versions column is what the service does | [Lab log, Day 11](../LAB-LOG.md#day-11-a-policy-whose-name-did-not-match-what-it-deployed) |

## BitLocker

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `05-lab-day13-portal-key-access-denied.png` | Portal: "You do not have access to view this BitLocker recovery key" | **Wrong error.** The account was Global Administrator. The portal blade failed, not the permission | [Lab log, Day 13](../LAB-LOG.md#day-13-the-portal-said-no-access-it-was-wrong) |
| `05-lab-day13-graph-403-before-consent.png` | Graph Explorer: 403 Forbidden on `recoveryKeys` | Graph needs `BitlockerKey.ReadBasic.All` and `BitlockerKey.Read.All` consented | [Lab log, Day 13](../LAB-LOG.md#day-13-the-portal-said-no-access-it-was-wrong) |
| `05-lab-day13-graph-recoverykeys-200-ok.png` | Graph Explorer: 200 OK on the same endpoint | The API returned what the portal refused. The interface is only a client of the API | [Lab log, Day 13](../LAB-LOG.md#day-13-the-portal-said-no-access-it-was-wrong) |
| `12-lab-day13-three-recovery-keys.png` | Three recovery keys listed for one drive | Not a fault. Every encryption and every rotation escrows a new key and the old ones stay, which is why the recovery screen shows a Key ID | [Lab log, Day 13](../LAB-LOG.md#day-13-three-recovery-keys-one-disk) |

## Defender Antivirus and Edge SmartScreen

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `04-lab-day13-pua-protection-off.png` | Antivirus policy with **PUA Protection off** | **Insecure value enforced.** An explicit "off" overrides the device and still reports as applied. Fixed by setting it to block | [Lab log, Day 13](../LAB-LOG.md#day-13-the-antivirus-policy-was-enforcing-an-insecure-value) |
| `08-rebuild-edge-policy-smartscreen.png` | `edge://policy`: four SmartScreen policies true, Platform, Device, Mandatory, OK | The download switch belongs to Edge, so the Defender policy could not set it | [Rebuild](../rebuild/README.md#edge-smartscreen) |

## Firewall

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `13-lab-day14-firewall-merge-conflict.png` | Each merge setting listed twice as **Conflict**, Default Inbound Action Succeeded | **Policy did nothing.** An older profile set the merge switches to True, the new one to False, so Windows applied neither. Fixed by giving the firewall one owner | [Lab log, Day 14](../LAB-LOG.md#day-14-defaults-that-looked-like-success) |

## Conditional Access

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `14-lab-day15-whatif-report-only.png` | What If: `CA-Require-Compliant-Device` under Policies that will apply, State Report-only | Verified with the simulator rather than a sign-in, because the admin account is excluded from the policy | [Lab log, Day 15](../LAB-LOG.md#day-15-conditional-access-and-the-multifactor-authentication-gap-it-created) |

## Applications

| Screenshot | What it shows | Why it matters | Page |
|---|---|---|---|
| `15-lab-day17-7zip-installed.png` | 7-Zip 26.03 device install status: Installed on the lab VM | **False positive first.** `Test-Path` had returned True on the laptop, not the VM. Restarting the Intune Management Extension forced the install | [Lab log, Day 17](../LAB-LOG.md#day-17-test-path-returned-true-from-the-wrong-machine) |
| `16-lab-day19-app-protection-device-group.png` | App protection policy assigned to `Dyn-Windows-Devices`: 1 devices, 0 users | **Protects nothing.** App protection targets users inside apps, not devices. Reassigned to `All-BYOD` | [Lab log, Day 19](../LAB-LOG.md#day-19-app-protection-policies-target-users-not-devices) |
