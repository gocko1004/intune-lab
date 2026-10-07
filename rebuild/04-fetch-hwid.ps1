# 04-fetch-hwid.ps1
# Pulls the hardware hash off the virtual machine's disk WITHOUT booting it.
# MUST run as administrator. The machine must be off.
#
# WHY THIS EXISTS
# Copy-VMFile only moves files from host into guest. There is no reverse.
# The clipboard only types text in, never out. Enhanced session mode is not
# available at the out-of-box screen.
#
# So the way out is the disk itself. A virtual hard disk is a file, and the
# host can mount it and read it like any other volume. This is the same trick
# used to recover data from a machine that will not boot, and to inject drivers
# or answer files into an image before first start.
#
# It is also why an unencrypted virtual disk sitting on a file share is a
# serious problem. Anyone who can read the file can read the whole machine.
# BitLocker on the guest is what stops this, and it is the reason the lab
# enables it later.

$ErrorActionPreference = 'Stop'

$vmName  = 'W11-CORP-01'
$vhdPath = "D:\VMs\$vmName\$vmName.vhdx"
$destDir = 'C:\Intune-Packaging'

$GUID_WINDOWS = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

# A mounted disk cannot have two owners. Shut the machine down cleanly first,
# the same way 05-harden-vm.ps1 does, rather than failing and making you do it.
if ((Get-VM -Name $vmName -ErrorAction SilentlyContinue).State -ne 'Off') {
    Write-Host "Shutting the machine down..." -ForegroundColor Cyan
    Stop-VM -Name $vmName -Force
}

# Read-only. We are fetching, not fixing.
$disk = Mount-VHD -Path $vhdPath -ReadOnly -Passthru | Get-Disk

try {
    $win = Get-Partition -DiskNumber $disk.Number | Where-Object GptType -eq $GUID_WINDOWS
    $letter = $win.DriveLetter
    if (-not $letter) { throw "Windows partition has no drive letter." }

    Write-Host ("Windows partition mounted as {0}:" -f $letter) -ForegroundColor Cyan

    # -----------------------------------------------------------------------
    # Is the volume even readable.
    #
    # FIRST VERSION BUG: this check did not exist. After the TPM was added,
    # Windows turned on device encryption by itself, the volume came up
    # BitLocker-locked, and every Test-Path below returned False. The script
    # reported the files as MISSING and blamed Copy-VMFile, when the truth was
    # that it could not see anything at all.
    #
    # "Not found" and "cannot look" are different answers. Check which one you
    # have before interpreting the result.
    #
    # If locked, the 48-digit recovery password unlocks it. It comes from
    # Intune (device, Recovery keys) or Entra ID (device, BitLocker keys).
    #
    # Read-Host rather than a parameter on purpose. A secret typed as part of a
    # command line is saved to PSReadLine's history file on disk. Input given to
    # Read-Host is not.
    # -----------------------------------------------------------------------

    $bl = Get-BitLockerVolume -MountPoint "${letter}:" -ErrorAction SilentlyContinue
    if ($bl -and $bl.LockStatus -eq 'Locked') {
        Write-Host ""
        Write-Host "  Volume is BitLocker LOCKED. Protectors: $($bl.KeyProtector.KeyProtectorType -join ', ')" -ForegroundColor Yellow
        Write-Host "  Get the recovery password from Intune: device, Recovery keys." -ForegroundColor Yellow

        $rk = Read-Host '  48-digit recovery password'
        try {
            Unlock-BitLocker -MountPoint "${letter}:" -RecoveryPassword $rk -ErrorAction Stop | Out-Null
            Write-Host "  Unlocked." -ForegroundColor Green
        }
        finally {
            Remove-Variable rk -ErrorAction SilentlyContinue
        }
    }

    if ((Get-Volume -DriveLetter $letter).FileSystemType -ne 'NTFS') {
        throw "Volume ${letter}: is not readable as NTFS. Every file check below would lie. Stopping."
    }

    # -----------------------------------------------------------------------
    # Did the script we pushed in ever arrive, and did it run.
    # -----------------------------------------------------------------------

    $pushed = "${letter}:\h.ps1"
    $csv    = "${letter}:\HWID\AutopilotHWID.csv"

    Write-Host ""
    if (Test-Path $pushed) {
        Write-Host ("  ARRIVED  h.ps1  ({0:N0} bytes)" -f (Get-Item $pushed).Length) -ForegroundColor Green
    }
    else {
        Write-Host "  MISSING  h.ps1 on a readable volume, so Copy-VMFile did not deliver it." -ForegroundColor Red
    }

    # The Gallery install leaves a trace even if the hash step failed. Checking
    # it separates "never ran" from "ran and failed partway".
    $installed = "${letter}:\Program Files\WindowsPowerShell\Scripts\Get-WindowsAutopilotInfo.ps1"
    if (Test-Path $installed) {
        Write-Host "  PRESENT  Get-WindowsAutopilotInfo.ps1, so the download worked" -ForegroundColor Green
    }
    else {
        Write-Host "  ABSENT   Get-WindowsAutopilotInfo.ps1, so the script did not get that far" -ForegroundColor Yellow
    }

    # -----------------------------------------------------------------------
    # The hash itself.
    # -----------------------------------------------------------------------

    Write-Host ""
    if (Test-Path $csv) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $dest = Join-Path $destDir 'AutopilotHWID.csv'
        Copy-Item $csv $dest -Force

        $row = Import-Csv $dest | Select-Object -First 1

        Write-Host "=== Hardware hash recovered ===" -ForegroundColor Green
        Write-Host ("  Serial number: {0}" -f $row.'Device Serial Number')
        Write-Host ("  Product ID:    {0}" -f $row.'Windows Product ID')
        Write-Host ("  Hash length:   {0} characters" -f $row.'Hardware Hash'.Length)
        Write-Host ("  Copied to:     {0}" -f $dest) -ForegroundColor Yellow
    }
    else {
        Write-Host "  NO CSV. The hash was never written." -ForegroundColor Red
    }

    # -----------------------------------------------------------------------
    # Why the screen went black.
    #
    # Windows writes a memory dump and a record in the System event log when it
    # stops unexpectedly. The presence of a dump file is the fastest way to
    # separate "the operating system crashed" from "only the video stopped".
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "=== Crash check ===" -ForegroundColor Cyan

    $dumps = @("${letter}:\Windows\MEMORY.DMP") + (Get-ChildItem "${letter}:\Windows\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue).FullName

    $found = $false
    foreach ($d in $dumps | Where-Object { $_ -and (Test-Path $_) }) {
        Write-Host ("  CRASH DUMP  {0}  {1:N0} bytes  {2}" -f $d, (Get-Item $d).Length, (Get-Item $d).LastWriteTime) -ForegroundColor Red
        $found = $true
    }
    if (-not $found) {
        Write-Host "  No crash dump. Windows did not stop unexpectedly." -ForegroundColor Green
        Write-Host "  That points at the video output, not the operating system." -ForegroundColor DarkGray
    }
}
finally {
    Dismount-VHD -Path $vhdPath
    Write-Host "`nDisk dismounted." -ForegroundColor DarkGray
}
