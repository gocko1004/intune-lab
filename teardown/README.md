# Tenant teardown, 14 September 2026

Scripted teardown of the `labtenant.onmicrosoft.com` lab before rebuilding it from nothing. Everything
was removed through Microsoft Graph rather than by clicking, because the point of the rebuild is to
learn the work, not the portal.

The configuration was exported first. See `../tenant-export/`.

## Files

| File | What |
|---|---|
| `01-inventory.ps1` | Lists every object the teardown targets. `GET` only, deletes nothing |
| `02-delete.ps1` | The teardown. **Preview by default.** Deletes only when passed `-Execute` |

## How it was run

```powershell
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementApps.ReadWrite.All",`
  "DeviceManagementManagedDevices.ReadWrite.All","DeviceManagementManagedDevices.PrivilegedOperations.All",`
  "DeviceManagementServiceConfig.ReadWrite.All","DeviceManagementScripts.ReadWrite.All",`
  "Group.ReadWrite.All","User.ReadWrite.All","Device.ReadWrite.All"

.\01-inventory.ps1            # read the list
.\02-delete.ps1               # preview, deletes nothing
.\02-delete.ps1 -Execute      # delete
```

Consent was granted for the signed-in account only, not on behalf of the organisation. These are
delegated permissions so they are capped by the account's own rights either way, but the grant is
narrower.

## Result

77 objects before, 11 after. **65 deleted, 14 skipped, 2 failed** on the first pass, both failures
resolved afterwards.

Surviving objects are all Microsoft-created and deliberately protected in the script: the admin
account, the two groups Microsoft 365 licensing creates, four Microsoft-supplied apps, the default
endpoint detection and response policy, and two Microsoft remediation samples.

## Why the order is what it is

**Autopilot registration before the Entra device object.** Deleting the Entra object first orphans
the hardware hash with no way to reach it. That failure mode was diagnosed the hard way on Day 7,
when a snapshot rollback after a remote wipe left a device that believed it was enrolled while the
service had no record of it.

**The working laptop last.** `DESKTOP-D8QPBL1` is the machine running the script, and removing its
Entra device object can end the session that is doing the removing. Putting it last means a broken
session leaves nothing half-done.

In practice the session survived, because the Primary Refresh Token was already cached. Same
mechanism that hid a completely broken DNS configuration earlier the same day: cached tokens make a
dead authentication path look alive.

## The two failures, and what they teach

### Deleting a group does not clean up its assignments

`APUserDrivenEntraJoin`, the Autopilot deployment profile, refused to delete with a bare
`BadRequest`. Querying its assignments showed why:

```json
{
  "id": "18356edc-..._b83ed302-...-ce030510da1c_0",
  "target": {
    "@odata.type": "#microsoft.graph.groupAssignmentTarget",
    "groupId": "<group-id>"
  }
}
```

That group, `Dyn-Autopilot-Devices`, had been deleted twenty minutes earlier in the same run. **The
assignment survived it**, still pointing at an object that no longer exists, and the profile would
not delete while it was there.

Fix: delete the assignment, then the profile.

In a live tenant this is the real lesson. Deleting a group leaves dangling assignments behind on
every policy it was ever attached to, and those policies then behave oddly for reasons the portal
does not surface.

### A user holding a directory role cannot be deleted with user-write alone

`anna.test` returned `Forbidden`. She held Intune Administrator, assigned on Day 2 as a least
privilege exercise.

`User.ReadWrite.All` is not sufficient to delete a user who holds a directory role. Removing a
privileged account also requires role management rights. That is the control which stops an
application holding user-write access from deleting the administrators.

Fix: remove the role assignment first, then delete the account.

## Not done through Graph

Three things needed a different route:

- **Conditional Access policies.** Different permission scope, done in the portal. Worth noting that
  only one of the expected policies was still present, so something had removed the others at an
  unknown point
- **Entra tenant device settings**, returned to defaults: who may join, and the per-user device limit.
  **Correction, 25 September:** "Users may join devices" was found on Selected during the rebuild,
  not the default All. See `../rebuild/README.md`
- **The Hyper-V virtual machine**

```powershell
Stop-VM -Name "W11-CORP-01" -TurnOff -Force
Remove-VM -Name "W11-CORP-01" -Force
Remove-Item -Path "D:\VMs\W11-CORP-01" -Recurse -Force
```

The third line is not optional. **`Remove-VM` deletes the machine and leaves the disks**, which is
the most common reason a Hyper-V host silently fills up. Here that was 117 GB across a base disk and
two checkpoint files, the checkpoints being larger than the disk they branched from.

The host volume went from 36 GB free to 148 GB. It had been at 93% full, and a full host volume is
what stalled a Windows reset at 98% on Day 3 with nothing anywhere reporting the real cause.
