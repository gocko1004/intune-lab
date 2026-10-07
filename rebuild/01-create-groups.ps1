# 01-create-groups.ps1
# Creates the remaining lab groups through Microsoft Graph.
# Requires an existing Connect-MgGraph session holding Group.ReadWrite.All.

# ---------------------------------------------------------------------------
# The group definitions.
#
# Every security group in Entra needs these four properties, dynamic or not:
#
#   displayName      what you see in the portal
#   mailEnabled      $false for a security group. $true would make it a
#                    distribution or Microsoft 365 group, which behaves differently
#   mailNickname     REQUIRED even though the group has no mailbox. Graph rejects
#                    the request without it. Must be unique and have no spaces
#   securityEnabled  $true. This is what makes it a security group
#
# A DYNAMIC group needs three more:
#
#   groupTypes                     must contain "DynamicMembership"
#   membershipRule                 the rule itself
#   membershipRuleProcessingState  "On" to evaluate it, "Paused" to stop evaluating
#
# An ASSIGNED group leaves groupTypes as an empty array and omits the other two.
# That single difference is the whole distinction between the two kinds.
# ---------------------------------------------------------------------------

$groups = @(

    @{
        displayName  = 'Dyn-Android-Devices'
        mailNickname = 'dyn-android-devices'
        dynamic      = $true
        # Two values joined with -or. A personally owned work profile reports as
        # AndroidForWork. A fully managed corporate device reports as Android.
        # Matching only one of them silently misses half an Android estate.
        rule         = '(device.deviceOSType -eq "Android") or (device.deviceOSType -eq "AndroidForWork")'
    },

    @{
        displayName  = 'All-Corp-Devices'
        mailNickname = 'all-corp-devices'
        dynamic      = $true
        # deviceOwnership is set at enrolment. "Company" or "Personal".
        rule         = '(device.deviceOwnership -eq "Company")'
    },

    @{
        displayName  = 'IT-Admins'
        mailNickname = 'it-admins'
        dynamic      = $false
        # Assigned. Members added by hand below.
    },

    @{
        displayName  = 'All-BYOD'
        mailNickname = 'all-byod'
        dynamic      = $false
        # Assigned, deliberately. App protection policies target users, and which
        # users are in the bring-your-own-device programme is a decision, not a
        # queryable attribute.
    },

    @{
        displayName  = 'Grp-Ring-Pilot'
        mailNickname = 'grp-ring-pilot'
        dynamic      = $false
        # Assigned, and this one exists BECAUSE a dynamic group cannot be its own
        # exception. The broad update ring targets Dyn-Windows-Devices and excludes
        # this group. Without a separate assigned group there is no way to carve a
        # pilot out of a dynamic membership.
    }
)

# ---------------------------------------------------------------------------

foreach ($g in $groups) {

    # Build the request body as a hashtable. Graph wants JSON; PowerShell
    # converts this for us on the way out.
    $body = @{
        displayName     = $g.displayName
        mailEnabled     = $false
        mailNickname    = $g.mailNickname
        securityEnabled = $true
    }

    if ($g.dynamic) {
        $body.groupTypes                    = @('DynamicMembership')
        $body.membershipRule                = $g.rule
        $body.membershipRuleProcessingState = 'On'
    }
    else {
        # Empty array, not absent. Graph treats a missing groupTypes as an error
        # on some paths and an empty array is the explicit "assigned" signal.
        $body.groupTypes = @()
    }

    try {
        $created = Invoke-MgGraphRequest -Method POST `
            -Uri  'https://graph.microsoft.com/v1.0/groups' `
            -Body ($body | ConvertTo-Json -Depth 3) `
            -ContentType 'application/json' `
            -ErrorAction Stop

        $type = if ($g.dynamic) { 'Dynamic Device' } else { 'Assigned' }
        Write-Host ("CREATED  {0}   [{1}]" -f $created.displayName, $type) -ForegroundColor Green
        Write-Host ("         {0}" -f $created.id) -ForegroundColor DarkGray

        if ($g.dynamic) {
            Write-Host ("         rule: {0}" -f $g.rule) -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host ("FAILED   {0}  :: {1}" -f $g.displayName, $_.Exception.Message) -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Add anna.test to IT-Admins.
#
# Adding a member is not a property of the group, it is a separate call against
# the group's members collection. The body uses an @odata.id pointing at the
# full URL of the object being added, which is how Graph expresses a reference
# rather than a value.
# ---------------------------------------------------------------------------

Write-Host ""

try {
    $itAdmins = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq 'IT-Admins'").value[0]

    $anna = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq 'anna.test@labtenant.onmicrosoft.com'").value[0]

    $ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($anna.id)" }

    Invoke-MgGraphRequest -Method POST `
        -Uri  "https://graph.microsoft.com/v1.0/groups/$($itAdmins.id)/members/`$ref" `
        -Body ($ref | ConvertTo-Json) `
        -ContentType 'application/json' `
        -ErrorAction Stop

    Write-Host "ADDED    anna.test to IT-Admins" -ForegroundColor Green
}
catch {
    Write-Host ("FAILED   adding anna.test  :: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Verify. Membership type is checked FIRST, before any member count is read.
# A group with zero members tells you nothing until you know which kind it is.
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Verification ===" -ForegroundColor Cyan

$all = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/groups').value

foreach ($g in $all | Sort-Object displayName) {
    $type = if ($g.groupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' }
    Write-Host ("  {0,-24} {1,-10} {2}" -f $g.displayName, $type, $g.membershipRule)
}
