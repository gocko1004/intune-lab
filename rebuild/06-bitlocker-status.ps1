# 06-bitlocker-status.ps1
# RUNS INSIDE THE VIRTUAL MACHINE, in an elevated session. Reads only.
#
# WHY THIS EXISTS
# Intune's encryption report said "TPM not used for protection of OS volume,
# but is required by policy". The device said the TPM is a protector and
# protection is on. The report can lag by up to 24 hours, so it might be stale,
# or Windows might be reporting something the protector list does not show.
#
# The report is a copy of what the device sent. This reads the original.
#
# DELIBERATELY DOES NOT PRINT THE RECOVERY PASSWORD.
# manage-bde -protectors -get prints it in full. That is how the previous key
# ended up in a screenshot and had to be rotated.

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# 1. The volume and its protectors, IDs and types only.
# ---------------------------------------------------------------------------

Write-Host "`n=== Volume C: ===" -ForegroundColor Cyan

$v = Get-BitLockerVolume -MountPoint 'C:'
"  Encryption method:   {0}" -f $v.EncryptionMethod
"  Protection status:   {0}" -f $v.ProtectionStatus
"  Volume status:       {0}" -f $v.VolumeStatus
foreach ($kp in $v.KeyProtector) {
    "  Protector:           {0,-18} {1}" -f $kp.KeyProtectorType, $kp.KeyProtectorId
}

# ---------------------------------------------------------------------------
# 2. Which boot measurements the TPM protector is sealed to.
#
# The TPM only releases the key if the boot measures the same as when the key
# was sealed. The measurements are Platform Configuration Registers, PCRs.
#
#   PCR 7   Secure Boot state and the certificates in its databases
#   PCR 11  BitLocker access control
#
# A profile of 7, 11 means the key is tied to Secure Boot. That is the modern
# default when Secure Boot is on, and the reason a Secure Boot change can
# trigger a recovery prompt if BitLocker is not suspended first.
#
# -Type TPM limits the output to the TPM protector, so no password is shown.
# ---------------------------------------------------------------------------

# FIRST VERSION BUG: a Select-String filter kept the "PCR Validation Profile:"
# label and dropped the next line, which holds the actual values. A filter that
# hides the answer looks exactly like an empty answer. Now prints everything
# after the header, which is safe because -Type TPM never includes a password.

Write-Host "`n=== TPM protector ===" -ForegroundColor Cyan
manage-bde -protectors -get C: -Type TPM | Select-Object -Skip 4 | Where-Object { $_.Trim() } | ForEach-Object { "  " + $_.Trim() }

# ---------------------------------------------------------------------------
# 3. The policy as it actually arrived on the device.
#
# Intune writes received policy here. If a value is missing or different from
# the portal, the problem is delivery, not BitLocker.
# ---------------------------------------------------------------------------

Write-Host "`n=== Policy received by the device ===" -ForegroundColor Cyan

# FIRST VERSION BUG: this asked for eight value names I assumed. Four came back
# "(not present)", which could mean the setting never arrived OR that I guessed
# the name wrong. An empty answer to a wrongly named question looks exactly
# like "not set". Same trap as Select-Object inventing empty columns.
#
# Now it lists every value that is ACTUALLY in the key, under its real name.
# Nothing assumed.
#
# Two places are read:
#   current\device\BitLocker            the merged result Windows applies
#   providers\<id>\default\Device\BitLocker   what each management source sent.
#                                       Intune is one provider, identified by a GUID

function Show-Key {
    param([string]$Path)
    $item = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if (-not $item) { Write-Host "  (key does not exist)" -ForegroundColor Red; return }
    $names = $item.GetValueNames() | Where-Object { $_ -notmatch '_(ProviderSet|WinningProvider|LastWrite)$' } | Sort-Object
    if (-not $names) { Write-Host "  (key exists but holds no values)" -ForegroundColor Yellow; return }
    foreach ($n in $names) {
        $val = [string]$item.GetValue($n)
        # Administrative template values arrive as XML fragments. Trim for the screen.
        $val = ($val -replace '\s+', ' ')
        if ($val.Length -gt 80) { $val = $val.Substring(0,80) + '...' }
        "  {0,-42} {1}" -f $n, $val
    }
}

Write-Host "  [merged: current\device\BitLocker]" -ForegroundColor DarkGray
Show-Key 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker'

Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\PolicyManager\providers' -ErrorAction SilentlyContinue | ForEach-Object {
    $bl = Join-Path $_.PSPath 'default\Device\BitLocker'
    if (Test-Path $bl) {
        Write-Host ("`n  [provider {0}]" -f $_.PSChildName) -ForegroundColor DarkGray
        Show-Key $bl
    }
}

# ---------------------------------------------------------------------------
# 4. What BitLocker itself logged about applying the policy.
#
# This log is the device's own account. Event 814 lists the policy values it
# evaluated. Event 813 and its neighbours record why something did not happen.
# ---------------------------------------------------------------------------

Write-Host "`n=== BitLocker Management log, newest first ===" -ForegroundColor Cyan

Get-WinEvent -LogName 'Microsoft-Windows-BitLocker/BitLocker Management' -MaxEvents 12 -ErrorAction SilentlyContinue |
    ForEach-Object {
        $msg = ($_.Message -replace '\s+', ' ')
        if ($msg.Length -gt 150) { $msg = $msg.Substring(0,150) + '...' }
        "  {0:dd.MM HH:mm}  {1,4}  {2}" -f $_.TimeCreated, $_.Id, $msg
    }

Write-Host ""
