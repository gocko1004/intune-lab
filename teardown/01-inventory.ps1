# 01-inventory.ps1
# Lists everything the teardown will delete. Reads only. Deletes nothing.
# Run this first, read the output, and only then run the delete script.

$ErrorActionPreference = 'Continue'

# Each entry: a label, the Graph endpoint, and which property holds the readable name.
$targets = @(
    @{ Label = 'Device configuration profiles'; Uri = 'beta/deviceManagement/deviceConfigurations';                 Name = 'displayName' }
    @{ Label = 'Settings catalog policies';     Uri = 'beta/deviceManagement/configurationPolicies';                Name = 'name' }
    @{ Label = 'Compliance policies';           Uri = 'beta/deviceManagement/deviceCompliancePolicies';             Name = 'displayName' }
    @{ Label = 'Endpoint security policies';    Uri = 'beta/deviceManagement/intents';                              Name = 'displayName' }
    @{ Label = 'Device remediations';           Uri = 'beta/deviceManagement/deviceHealthScripts';                  Name = 'displayName' }
    @{ Label = 'Platform scripts';              Uri = 'beta/deviceManagement/deviceManagementScripts';              Name = 'displayName' }
    @{ Label = 'Update rings';                  Uri = 'beta/deviceManagement/deviceConfigurations';                 Name = 'displayName' }
    @{ Label = 'Feature update profiles';       Uri = 'beta/deviceManagement/windowsFeatureUpdateProfiles';         Name = 'displayName' }
    @{ Label = 'Quality update profiles';       Uri = 'beta/deviceManagement/windowsQualityUpdateProfiles';         Name = 'displayName' }
    @{ Label = 'Driver update profiles';        Uri = 'beta/deviceManagement/windowsDriverUpdateProfiles';          Name = 'displayName' }
    @{ Label = 'Assignment filters';            Uri = 'beta/deviceManagement/assignmentFilters';                    Name = 'displayName' }
    @{ Label = 'Applications';                  Uri = 'beta/deviceAppManagement/mobileApps';                        Name = 'displayName' }
    @{ Label = 'App protection (Android)';      Uri = 'beta/deviceAppManagement/androidManagedAppProtections';      Name = 'displayName' }
    @{ Label = 'App configuration policies';    Uri = 'beta/deviceAppManagement/targetedManagedAppConfigurations';  Name = 'displayName' }
    @{ Label = 'Autopilot profiles';            Uri = 'beta/deviceManagement/windowsAutopilotDeploymentProfiles';   Name = 'displayName' }
    @{ Label = 'Autopilot devices';             Uri = 'beta/deviceManagement/windowsAutopilotDeviceIdentities';     Name = 'serialNumber' }
    @{ Label = 'Enrolled devices';              Uri = 'beta/deviceManagement/managedDevices';                       Name = 'deviceName' }
    @{ Label = 'Entra device objects';          Uri = 'v1.0/devices';                                               Name = 'displayName' }
    @{ Label = 'Groups';                        Uri = 'v1.0/groups';                                                Name = 'displayName' }
    @{ Label = 'Users';                         Uri = 'v1.0/users';                                                 Name = 'userPrincipalName' }
)

$grandTotal = 0

foreach ($t in $targets) {
    Write-Host ""
    Write-Host "=== $($t.Label) ===" -ForegroundColor Cyan

    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/$($t.Uri)" -ErrorAction Stop
        $items = $response.value

        if ($null -eq $items -or $items.Count -eq 0) {
            Write-Host "  (none)" -ForegroundColor DarkGray
            continue
        }

        foreach ($i in $items) {
            $label = $i[$t.Name]
            if ([string]::IsNullOrWhiteSpace($label)) { $label = '(no name)' }
            Write-Host ("  {0}" -f $label)
            Write-Host ("      {0}" -f $i.id) -ForegroundColor DarkGray
        }

        Write-Host ("  --- {0} item(s)" -f $items.Count) -ForegroundColor Yellow
        $grandTotal += $items.Count
    }
    catch {
        Write-Host ("  FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ("TOTAL OBJECTS FOUND: {0}" -f $grandTotal) -ForegroundColor Cyan
Write-Host "Nothing has been deleted. This script only reads." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
