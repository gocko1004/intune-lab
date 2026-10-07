# 02c-diagnose-boot.ps1
# Reads what is actually on the virtual disk. Changes nothing.
# MUST run as administrator.
#
# WHY THIS EXISTS
# The machine reports "the boot loader did not load an operating system".
# That sentence is precise. The firmware found the disk, looked for a boot
# loader, and did not find one. It says nothing about Windows being absent.
#
# A UEFI machine boots in this order:
#   1. Read the GPT partition table.
#   2. Find the partition tagged with the EFI System Partition type GUID.
#   3. Mount it as FAT32.
#   4. Load \EFI\Microsoft\Boot\bootmgfw.efi from it.
#   5. That loader reads the Boot Configuration Data and starts Windows.
#
# Any one of those five can be missing. This script checks each in turn, so
# the fix targets the actual break instead of the first plausible one.

$ErrorActionPreference = 'Stop'

$vmName  = 'W11-CORP-01'
$vhdPath = "D:\VMs\$vmName\$vmName.vhdx"

# ---------------------------------------------------------------------------
# The disk cannot be mounted on the host while the machine owns it.
# ---------------------------------------------------------------------------

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
    Write-Host "Machine turned off." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Mount it read-only. Nothing here should write, and read-only makes that a
# guarantee rather than an intention.
# ---------------------------------------------------------------------------

$disk = Mount-VHD -Path $vhdPath -ReadOnly -Passthru | Get-Disk
Write-Host ("`nDisk number {0}, partition style {1}" -f $disk.Number, $disk.PartitionStyle) -ForegroundColor Cyan

if ($disk.PartitionStyle -ne 'GPT') {
    Write-Host "  WRONG. UEFI firmware cannot boot an MBR disk." -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Check 1 and 2. The partition table, and whether an EFI System Partition
# with the correct type GUID exists.
#
# The GUID is what the firmware matches on. A FAT32 partition with the wrong
# type GUID is invisible to it, however correct its contents are.
# ---------------------------------------------------------------------------

Write-Host "`n=== Partitions ===" -ForegroundColor Cyan

$parts = Get-Partition -DiskNumber $disk.Number

foreach ($p in $parts) {
    $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
    Write-Host ("  #{0}  {1,8:N0} MB  type {2}  letter '{3}'  fs '{4}'" -f `
        $p.PartitionNumber,
        ($p.Size / 1MB),
        $p.GptType,
        $p.DriveLetter,
        $vol.FileSystemType)
}

$esp = $parts | Where-Object GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$win = $parts | Where-Object GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

if (-not $esp) { Write-Host "`n  NO EFI SYSTEM PARTITION. This alone explains the failure." -ForegroundColor Red }
if (-not $win) { Write-Host "`n  NO BASIC DATA PARTITION." -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Check 3 and 4. Mount the EFI partition and look for the boot loader.
#
# The EFI partition usually has no drive letter, and Windows will not hand one
# out freely. Add-PartitionAccessPath attaches it to an empty folder instead,
# which works regardless of how many letters are free.
# ---------------------------------------------------------------------------

if ($esp) {
    Write-Host "`n=== EFI System Partition contents ===" -ForegroundColor Cyan

    $espVol = Get-Volume -Partition $esp -ErrorAction SilentlyContinue
    if ($espVol.FileSystemType -ne 'FAT32') {
        Write-Host ("  File system is '{0}', not FAT32. UEFI firmware reads FAT32 only." -f $espVol.FileSystemType) -ForegroundColor Red
    }

    $mountPoint = "$env:TEMP\esp-check"
    if (Test-Path $mountPoint) { Remove-Item $mountPoint -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $mountPoint -Force | Out-Null

    try {
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber -AccessPath $mountPoint
        Start-Sleep 1

        $files = Get-ChildItem $mountPoint -Recurse -Force -ErrorAction SilentlyContinue

        if (-not $files) {
            Write-Host "  EMPTY. bcdboot did not write anything here." -ForegroundColor Red
        }
        else {
            foreach ($f in $files | Where-Object { -not $_.PSIsContainer }) {
                Write-Host ("  {0,10:N0}  {1}" -f $f.Length, $f.FullName.Replace($mountPoint, ''))
            }
        }

        # The one file the firmware actually loads.
        $loader = Join-Path $mountPoint 'EFI\Microsoft\Boot\bootmgfw.efi'
        Write-Host ""
        if (Test-Path $loader) {
            Write-Host "  bootmgfw.efi PRESENT" -ForegroundColor Green
        }
        else {
            Write-Host "  bootmgfw.efi MISSING. This is the file the firmware looks for." -ForegroundColor Red
        }

        # The Boot Configuration Data store, which the loader reads next.
        $bcd = Join-Path $mountPoint 'EFI\Microsoft\Boot\BCD'
        if (Test-Path $bcd) {
            Write-Host "  BCD store   PRESENT" -ForegroundColor Green
        }
        else {
            Write-Host "  BCD store   MISSING" -ForegroundColor Red
        }
    }
    finally {
        Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber -AccessPath $mountPoint -ErrorAction SilentlyContinue
        Remove-Item $mountPoint -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Check 5. Is Windows itself actually on the data partition.
#
# Checked LAST on purpose. If the boot loader is missing, Windows being
# present or absent does not change the fix, and looking here first is how
# you end up reinstalling something that was never the problem.
# ---------------------------------------------------------------------------

if ($win) {
    Write-Host "`n=== Windows partition ===" -ForegroundColor Cyan

    $winLetter = $win.DriveLetter
    if (-not $winLetter) {
        Write-Host "  No drive letter. Cannot inspect." -ForegroundColor Yellow
    }
    else {
        foreach ($probe in @('Windows\System32\ntoskrnl.exe',
                             'Windows\System32\config\SYSTEM',
                             'Windows\System32\bcdboot.exe')) {
            $full = "${winLetter}:\$probe"
            if (Test-Path $full) { Write-Host ("  PRESENT  {0}" -f $probe) -ForegroundColor Green }
            else                 { Write-Host ("  MISSING  {0}" -f $probe) -ForegroundColor Red }
        }

        $used = (Get-Volume -DriveLetter $winLetter).Size - (Get-Volume -DriveLetter $winLetter).SizeRemaining
        Write-Host ("  Used on this partition: {0:N1} GB" -f ($used / 1GB)) -ForegroundColor DarkGray
        Write-Host "  A finished Windows 11 apply is 13 to 16 GB. There is no pagefile or" -ForegroundColor DarkGray
        Write-Host "  hibernation file yet, so this is smaller than an installed system on" -ForegroundColor DarkGray
        Write-Host "  real hardware. Under 10 GB would mean the apply did not finish." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------

Dismount-VHD -Path $vhdPath
Write-Host "`nDisk dismounted. Nothing was changed." -ForegroundColor Green
