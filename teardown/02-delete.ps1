# 02-delete.ps1
# Tears down the lab tenant.
#
# SAFE BY DEFAULT. Run with no arguments and it prints what it WOULD delete and stops.
# Pass -Execute to actually delete.
#
#   .\02-delete.ps1              <- preview only, deletes nothing
#   .\02-delete.ps1 -Execute     <- deletes
#
# Order matters. Autopilot registration is removed before the Entra device object,
# because deleting the Entra object first orphans the hardware hash with no way to reach it.
# DESKTOP-D8QPBL1 is deleted last, because it is the machine running this script and
# removing its Entra device object can end the session.

param(
    [switch]$Execute
)

$ErrorActionPreference = 'Continue'

# Never delete these, whatever else happens.
$protectedUsers = @(
    'admin@labtenant.onmicrosoft.com'
)

$protectedGroups = @(
    'All Company',      # created by Microsoft 365 licensing
    'labtenant'           # created by Microsoft 365 licensing
)

$protectedApps = @(
    'Intune Company Portal',
    'Microsoft Authenticator',
    'Managed Home Screen',
    'Microsoft Intune'
)

$protectedPolicies = @(
    'Default EDR policy for all devices',   # Microsoft-created, present in every tenant
    'Restart stopped Office C2R svc',       # Microsoft-supplied remediation sample
    'Update stale Group Policies'           # Microsoft-supplied remediation sample
)

$script:deleted = 0
$script:skipped = 0
$script:failed  = 0

function Remove-Target {
    param(
        [string]$Label,
        [string]$Uri,
        [string]$Name
    )

    if ($Name -in $protectedUsers -or $Name -in $protectedGroups -or
        $Name -in $protectedApps  -or $Name -in $protectedPolicies) {
        Write-Host ("  SKIP    {0}  [protected]" -f $Name) -ForegroundColor DarkGray
        $script:skipped++
        return
    }

    if (-not $Execute) {
        Write-Host ("  WOULD DELETE  {0}" -f $Name) -ForegroundColor Yellow
        $script:deleted++
        return
    }

    try {
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/$Uri" -ErrorAction Stop
        Write-Host ("  DELETED {0}" -f $Name) -ForegroundColor Green
        $script:deleted++
    }
    catch {
        Write-Host ("  FAILED  {0}  :: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
        $script:failed++
    }
}

function Clear-Collection {
    param(
        [string]$Label,
        [string]$ListUri,
        [string]$NameProperty,
        [string]$DeleteUriTemplate,   # {0} is replaced with the object id
        [string[]]$OnlyThese          # optional. if given, only objects with these names are deleted
    )

    Write-Host ""
    Write-Host "=== $Label ===" -ForegroundColor Cyan

    try {
        $items = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/$ListUri" -ErrorAction Stop).value
    }
    catch {
        Write-Host ("  FAILED to list: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return
    }

    if ($null -eq $items -or $items.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
        return
    }

    foreach ($i in $items) {
        $name = $i[$NameProperty]
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $i.id }

        if ($OnlyThese -and $name -notin $OnlyThese) {
            Write-Host ("  SKIP    {0}  [not in list]" -f $name) -ForegroundColor DarkGray
            $script:skipped++
            continue
        }

        Remove-Target -Label $Label -Uri ($DeleteUriTemplate -f $i.id) -Name $name
    }
}

Write-Host ""
if ($Execute) {
    Write-Host "############################################" -ForegroundColor Red
    Write-Host "  EXECUTE MODE. THIS WILL DELETE OBJECTS."   -ForegroundColor Red
    Write-Host "############################################" -ForegroundColor Red
}
else {
    Write-Host "############################################" -ForegroundColor Green
    Write-Host "  PREVIEW MODE. Nothing will be deleted."    -ForegroundColor Green
    Write-Host "  Re-run with -Execute to delete."           -ForegroundColor Green
    Write-Host "############################################" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 1. Policies
# ---------------------------------------------------------------------------

Clear-Collection -Label 'Settings catalog policies' `
    -ListUri 'beta/deviceManagement/configurationPolicies' `
    -NameProperty 'name' `
    -DeleteUriTemplate 'beta/deviceManagement/configurationPolicies/{0}'

Clear-Collection -Label 'Device configuration profiles and update rings' `
    -ListUri 'beta/deviceManagement/deviceConfigurations' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/deviceConfigurations/{0}'

Clear-Collection -Label 'Compliance policies' `
    -ListUri 'beta/deviceManagement/deviceCompliancePolicies' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/deviceCompliancePolicies/{0}'

Clear-Collection -Label 'Feature update profiles' `
    -ListUri 'beta/deviceManagement/windowsFeatureUpdateProfiles' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/windowsFeatureUpdateProfiles/{0}'

Clear-Collection -Label 'Quality update profiles' `
    -ListUri 'beta/deviceManagement/windowsQualityUpdateProfiles' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/windowsQualityUpdateProfiles/{0}'

Clear-Collection -Label 'Device remediations' `
    -ListUri 'beta/deviceManagement/deviceHealthScripts' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/deviceHealthScripts/{0}'

Clear-Collection -Label 'Platform scripts' `
    -ListUri 'beta/deviceManagement/deviceManagementScripts' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/deviceManagementScripts/{0}'

Clear-Collection -Label 'Assignment filters' `
    -ListUri 'beta/deviceManagement/assignmentFilters' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/assignmentFilters/{0}'

# ---------------------------------------------------------------------------
# 2. Applications and app policies
# ---------------------------------------------------------------------------

Clear-Collection -Label 'Applications' `
    -ListUri 'beta/deviceAppManagement/mobileApps' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceAppManagement/mobileApps/{0}'

Clear-Collection -Label 'App protection policies (Android)' `
    -ListUri 'beta/deviceAppManagement/androidManagedAppProtections' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceAppManagement/androidManagedAppProtections/{0}'

Clear-Collection -Label 'App configuration policies' `
    -ListUri 'beta/deviceAppManagement/targetedManagedAppConfigurations' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceAppManagement/targetedManagedAppConfigurations/{0}'

# ---------------------------------------------------------------------------
# 3. Autopilot. Profile first, then the device registration.
#    This must happen BEFORE the Entra device objects are removed.
# ---------------------------------------------------------------------------

Clear-Collection -Label 'Autopilot deployment profiles' `
    -ListUri 'beta/deviceManagement/windowsAutopilotDeploymentProfiles' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'beta/deviceManagement/windowsAutopilotDeploymentProfiles/{0}'

Clear-Collection -Label 'Autopilot device registrations' `
    -ListUri 'beta/deviceManagement/windowsAutopilotDeviceIdentities' `
    -NameProperty 'serialNumber' `
    -DeleteUriTemplate 'beta/deviceManagement/windowsAutopilotDeviceIdentities/{0}'

# ---------------------------------------------------------------------------
# 4. Enrolled devices. Lab machine and phone first, working laptop last.
# ---------------------------------------------------------------------------

Clear-Collection -Label 'Enrolled devices, lab and phone' `
    -ListUri 'beta/deviceManagement/managedDevices' `
    -NameProperty 'deviceName' `
    -DeleteUriTemplate 'beta/deviceManagement/managedDevices/{0}' `
    -OnlyThese @('AB-18949', 'GocePetrov_AndroidForWork_8/27/2026_1:47 PM')

Clear-Collection -Label 'Entra device objects, lab and phone' `
    -ListUri 'v1.0/devices' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'v1.0/devices/{0}' `
    -OnlyThese @('AB-18949', 'GocePetrov_AndroidForWork_8/27/2026_1:47 PM')

# ---------------------------------------------------------------------------
# 5. Groups and users
# ---------------------------------------------------------------------------

Clear-Collection -Label 'Groups' `
    -ListUri 'v1.0/groups' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'v1.0/groups/{0}'

Clear-Collection -Label 'Users' `
    -ListUri 'v1.0/users' `
    -NameProperty 'userPrincipalName' `
    -DeleteUriTemplate 'v1.0/users/{0}'

# ---------------------------------------------------------------------------
# 6. The machine running this script. Last, deliberately.
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "### DESKTOP-D8QPBL1 is the machine running this script." -ForegroundColor Yellow
Write-Host "### Removing its Entra device object may end your session." -ForegroundColor Yellow

Clear-Collection -Label 'Enrolled device, this laptop' `
    -ListUri 'beta/deviceManagement/managedDevices' `
    -NameProperty 'deviceName' `
    -DeleteUriTemplate 'beta/deviceManagement/managedDevices/{0}' `
    -OnlyThese @('DESKTOP-D8QPBL1')

Clear-Collection -Label 'Entra device object, this laptop' `
    -ListUri 'v1.0/devices' `
    -NameProperty 'displayName' `
    -DeleteUriTemplate 'v1.0/devices/{0}' `
    -OnlyThese @('DESKTOP-D8QPBL1')

# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
if ($Execute) {
    Write-Host ("Deleted: {0}   Skipped: {1}   Failed: {2}" -f $script:deleted, $script:skipped, $script:failed) -ForegroundColor Cyan
}
else {
    Write-Host ("Would delete: {0}   Would skip: {1}" -f $script:deleted, $script:skipped) -ForegroundColor Cyan
    Write-Host "Nothing was deleted. Re-run with -Execute." -ForegroundColor Green
}
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Not handled by this script, do these in the portal:" -ForegroundColor Yellow
Write-Host "  - Conditional Access policies (need Policy.ReadWrite.ConditionalAccess)"
Write-Host "  - The Hyper-V virtual machine and its disks"
Write-Host "  - Entra tenant device settings, back to defaults"
