# 02d-write-boot.ps1
# Writes the UEFI boot loader onto an existing, already-applied Windows disk.
# MUST run as administrator.
#
# WHY THIS EXISTS
# 02b-apply-image.ps1 applied Windows correctly and then ran bcdboot, which
# did nothing. The script reported success anyway.
#
# THE BUG, because it is worth more than the fix:
#
#   bcdboot.exe is a native executable, not a PowerShell command.
#   $ErrorActionPreference = 'Stop' does not apply to native executables.
#   A native executable reports failure through its EXIT CODE, in $LASTEXITCODE.
#   Nothing in 02b read it.
#
# So bcdboot failed, said so on its own output, and the script moved straight
# on to building the machine. Every later symptom, the boot loader message and
# the network boot fallback, came from that one unchecked exit code.
#
# This script checks it. That is the actual difference.

$ErrorActionPreference = 'Stop'

$vmName  = 'W11-CORP-01'
$vhdPath = "D:\VMs\$vmName\$vmName.vhdx"

# GPT partition type GUIDs. Fixed values defined by the UEFI specification.
$GUID_ESP     = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'   # EFI System Partition
$GUID_WINDOWS = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'   # Basic data partition

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Mount read-write this time, because we are going to write to it.
# ---------------------------------------------------------------------------

$disk = Mount-VHD -Path $vhdPath -Passthru | Get-Disk
Write-Host ("Mounted as disk {0}" -f $disk.Number) -ForegroundColor Cyan

try {
    # -----------------------------------------------------------------------
    # Find the partitions by TYPE GUID, never by number.
    #
    # Initialize-Disk silently creates a 16 MB Microsoft Reserved Partition as
    # partition 1, so the EFI partition is 2 and Windows is 3 on this disk. On
    # a disk partitioned by the Windows installer the numbers differ again.
    # Matching the GUID is correct on every layout.
    # -----------------------------------------------------------------------

    $parts = Get-Partition -DiskNumber $disk.Number

    $esp = $parts | Where-Object GptType -eq $GUID_ESP
    $win = $parts | Where-Object GptType -eq $GUID_WINDOWS

    if (-not $esp) { throw "No EFI System Partition on this disk." }
    if (-not $win) { throw "No Windows partition on this disk." }

    # -----------------------------------------------------------------------
    # Both partitions need a drive letter, because bcdboot takes paths.
    #
    # The letters are re-read from the disk after any assignment rather than
    # trusted from the object returned earlier. Formatting and mounting can
    # both change a letter underneath you, which is how 02b ended up handing
    # bcdboot a path with nothing in front of the colon.
    # -----------------------------------------------------------------------

    if (-not $esp.DriveLetter) {
        Set-Partition -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber -NewDriveLetter (
            [char[]](70..90) | Where-Object { -not (Test-Path "${_}:") } | Select-Object -First 1
        )
        Start-Sleep 1
    }
    if (-not $win.DriveLetter) {
        Set-Partition -DiskNumber $disk.Number -PartitionNumber $win.PartitionNumber -NewDriveLetter (
            [char[]](70..90) | Where-Object { -not (Test-Path "${_}:") } | Select-Object -First 1
        )
        Start-Sleep 1
    }

    $espLetter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber).DriveLetter
    $winLetter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $win.PartitionNumber).DriveLetter

    if (-not $espLetter) { throw "EFI partition has no drive letter. bcdboot cannot target it." }
    if (-not $winLetter) { throw "Windows partition has no drive letter." }

    Write-Host ("EFI partition:     {0}:" -f $espLetter) -ForegroundColor DarkGray
    Write-Host ("Windows partition: {0}:" -f $winLetter) -ForegroundColor DarkGray

    # Confirm Windows is really there before trying to make it bootable.
    if (-not (Test-Path "${winLetter}:\Windows\System32\ntoskrnl.exe")) {
        throw "No Windows installation found on ${winLetter}:. Re-run 02b-apply-image.ps1 first."
    }

    # -----------------------------------------------------------------------
    # Run bcdboot, and this time actually read what it says.
    #
    #   ${winLetter}:\Windows   the installation to create an entry for
    #   /s ${espLetter}:        where to put the boot files
    #   /f UEFI                 write UEFI boot files only, not BIOS ones
    #
    # 2>&1 merges the error stream into the output stream so failures are
    # captured rather than scrolling past. $LASTEXITCODE is the verdict.
    # -----------------------------------------------------------------------

    Write-Host "`nRunning bcdboot..." -ForegroundColor Cyan

    $bcdbootExe = "${winLetter}:\Windows\System32\bcdboot.exe"
    $output = & $bcdbootExe "${winLetter}:\Windows" /s "${espLetter}:" /f UEFI 2>&1
    $code   = $LASTEXITCODE

    $output | ForEach-Object { Write-Host ("  {0}" -f $_) }
    Write-Host ("  exit code: {0}" -f $code) -ForegroundColor $(if ($code -eq 0) { 'Green' } else { 'Red' })

    if ($code -ne 0) {
        # The image's own bcdboot can fail on a host whose servicing stack
        # differs. The host's copy targets the same file layout and is the
        # standard fallback.
        Write-Host "`nRetrying with the host's bcdboot..." -ForegroundColor Yellow

        $output = & "$env:SystemRoot\System32\bcdboot.exe" "${winLetter}:\Windows" /s "${espLetter}:" /f UEFI 2>&1
        $code   = $LASTEXITCODE

        $output | ForEach-Object { Write-Host ("  {0}" -f $_) }
        Write-Host ("  exit code: {0}" -f $code) -ForegroundColor $(if ($code -eq 0) { 'Green' } else { 'Red' })
    }

    # -----------------------------------------------------------------------
    # Verify against the file system, not against the exit code.
    #
    # An exit code of 0 is a claim. The presence of bootmgfw.efi is the fact.
    # -----------------------------------------------------------------------

    Write-Host "`n=== Verification ===" -ForegroundColor Cyan

    $loader = "${espLetter}:\EFI\Microsoft\Boot\bootmgfw.efi"
    $bcd    = "${espLetter}:\EFI\Microsoft\Boot\BCD"

    $ok = $true
    foreach ($f in @($loader, $bcd)) {
        if (Test-Path $f) {
            Write-Host ("  PRESENT  {0}  ({1:N0} bytes)" -f $f, (Get-Item $f).Length) -ForegroundColor Green
        }
        else {
            Write-Host ("  MISSING  {0}" -f $f) -ForegroundColor Red
            $ok = $false
        }
    }

    if (-not $ok) { throw "Boot files still missing. Do not start the machine, it will fail the same way." }
}
finally {
    Dismount-VHD -Path $vhdPath
    Write-Host "`nDisk dismounted." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Point the firmware at the hard disk.
#
# The boot order survives from the earlier build, but setting it again costs
# nothing and removes it as a variable if this still fails.
# ---------------------------------------------------------------------------

$hdd = Get-VMHardDiskDrive -VMName $vmName
Set-VMFirmware -VMName $vmName -FirstBootDevice $hdd
Set-VMFirmware -VMName $vmName -EnableSecureBoot Off

Write-Host "`n=== Ready ===" -ForegroundColor Green
Write-Host "  vmconnect.exe localhost $vmName" -ForegroundColor Yellow
Write-Host "  Start-VM -Name $vmName" -ForegroundColor Yellow
