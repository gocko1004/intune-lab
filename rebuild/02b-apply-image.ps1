# 02b-apply-image.ps1
# Builds a bootable Windows 11 virtual disk by applying the image directly,
# instead of booting the installer from a DVD.
#
# MUST run as administrator.
#
# WHY THIS EXISTS
# Hyper-V's Generation 2 UEFI firmware on this host cannot boot the Windows
# installation ISO. A Generation 1 machine boots the same ISO fine, and the ISO
# matches Microsoft's published SHA-256, so the media is good and the UEFI DVD
# boot path is what is broken.
#
# This route does not touch that path. It writes Windows onto the disk from the
# host, makes the disk bootable, and hands the virtual machine a disk that is
# already a working Windows installation.
#
# This is also what imaging actually is. Every deployment tool in the old world,
# MDT and Configuration Manager included, is a wrapper around these same steps.

$ErrorActionPreference = 'Stop'

$vmName    = 'W11-CORP-01'
$vmPath    = 'D:\VMs'
$vhdPath   = "$vmPath\$vmName\$vmName.vhdx"
$isoPath   = 'D:\VMs\Win11_25H2_EnglishInternational_x64_v2.iso'
$imageIdx  = 6          # Windows 11 Pro
$switch    = 'Default Switch'

# ---------------------------------------------------------------------------
# 1. Clear out anything from previous attempts.
# ---------------------------------------------------------------------------

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $vmName -Force
}
if (Test-Path "$vmPath\$vmName") {
    Remove-Item "$vmPath\$vmName" -Recurse -Force
}
New-Item -ItemType Directory -Path "$vmPath\$vmName" -Force | Out-Null

# ---------------------------------------------------------------------------
# 2. Create and mount the virtual disk.
#
# Mount-VHD attaches it to the HOST as a real disk. From here on the host sees
# it as physical storage, which is what lets DISM write into it.
#
# The disk number is captured rather than assumed. Guessing a disk number and
# partitioning the wrong one destroys the host.
# ---------------------------------------------------------------------------

Write-Host "Creating virtual disk..." -ForegroundColor Cyan
New-VHD -Path $vhdPath -SizeBytes 64GB -Dynamic | Out-Null

$disk = Mount-VHD -Path $vhdPath -Passthru | Get-Disk
Write-Host ("Mounted as disk number {0}" -f $disk.Number) -ForegroundColor Cyan

Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false

# ---------------------------------------------------------------------------
# 3. Partition it the way UEFI requires.
#
# A UEFI machine needs TWO partitions at minimum:
#
#   EFI System Partition, FAT32, small. The firmware can only read FAT32, and
#   this is where the boot loader lives. Its GPT type GUID is fixed and is what
#   tells the firmware "this is the one to look in".
#
#   Windows partition, NTFS, the rest. The operating system itself.
#
# This is the difference from a BIOS disk, which boots from a boot sector and
# needs neither.
# ---------------------------------------------------------------------------

Write-Host "Partitioning..." -ForegroundColor Cyan

$efi = New-Partition -DiskNumber $disk.Number -Size 500MB `
        -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null
$efiLetter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $efi.PartitionNumber).DriveLetter

$win = New-Partition -DiskNumber $disk.Number -UseMaximumSize `
        -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter
Format-Volume -Partition $win -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null
$winLetter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $win.PartitionNumber).DriveLetter

Write-Host ("EFI partition:     {0}:" -f $efiLetter) -ForegroundColor DarkGray
Write-Host ("Windows partition: {0}:" -f $winLetter) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 4. Apply the Windows image.
#
# install.wim holds every edition in one file. Index 6 is Windows 11 Pro.
# Expand-WindowsImage unpacks that edition into the partition. This is the
# single step that the entire Windows installer exists to perform.
#
# Takes several minutes. 7 GB of compressed image becomes roughly 20 GB on disk.
# ---------------------------------------------------------------------------

$mounted = Get-DiskImage -ImagePath $isoPath
if (-not $mounted.Attached) {
    $mounted = Mount-DiskImage -ImagePath $isoPath -PassThru
    Start-Sleep 2
}
$isoLetter = ($mounted | Get-Volume).DriveLetter

Write-Host ("Applying image index {0} from {1}: ... this takes several minutes" -f $imageIdx, $isoLetter) -ForegroundColor Cyan

Expand-WindowsImage -ImagePath "${isoLetter}:\sources\install.wim" `
                    -Index $imageIdx `
                    -ApplyPath "${winLetter}:\"

# ---------------------------------------------------------------------------
# 5. Make it bootable.
#
# bcdboot copies the boot loader into the EFI partition and writes the Boot
# Configuration Data that tells the firmware where Windows lives.
#
# Without this the disk contains a complete Windows installation that no
# firmware can find. The files being present is not the same as being bootable.
# ---------------------------------------------------------------------------

# bcdboot.exe is a NATIVE EXECUTABLE, not a PowerShell command. It reports
# failure through $LASTEXITCODE, and $ErrorActionPreference = 'Stop' does not
# apply to it. The first version of this script did not read that exit code,
# so a failed bcdboot printed its complaint and the script carried on building
# a machine that could never boot. Check it.

Write-Host "Writing boot files..." -ForegroundColor Cyan

$bootOutput = & "${winLetter}:\Windows\System32\bcdboot.exe" "${winLetter}:\Windows" /s "${efiLetter}:" /f UEFI 2>&1
$bootOutput | ForEach-Object { Write-Host ("  {0}" -f $_) }

if ($LASTEXITCODE -ne 0) {
    throw "bcdboot failed with exit code $LASTEXITCODE. The disk holds Windows but no boot loader."
}

# The exit code is a claim. This is the fact.
if (-not (Test-Path "${efiLetter}:\EFI\Microsoft\Boot\bootmgfw.efi")) {
    throw "bcdboot reported success but bootmgfw.efi is not on the EFI partition."
}

# ---------------------------------------------------------------------------
# 6. Detach the disk from the host so the virtual machine can own it.
# ---------------------------------------------------------------------------

Dismount-VHD -Path $vhdPath
Dismount-DiskImage -ImagePath $isoPath | Out-Null

# ---------------------------------------------------------------------------
# 7. Build the machine around the finished disk.
#
# No DVD drive at all. Nothing to boot from except the hard disk, which is now
# a complete Windows installation.
#
# Secure Boot and the Trusted Platform Module are added afterwards, once Windows
# is confirmed running. Enabling the module locks the Secure Boot template
# permanently, and doing that before knowing the machine boots is what cost an
# afternoon.
# ---------------------------------------------------------------------------

Write-Host "Creating the virtual machine..." -ForegroundColor Cyan

New-VM -Name $vmName -Generation 2 -MemoryStartupBytes 4GB `
       -VHDPath $vhdPath -SwitchName $switch -Path $vmPath | Out-Null

Set-VMMemory    -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes 4GB
Set-VMProcessor -VMName $vmName -Count 2
Set-VMFirmware  -VMName $vmName -EnableSecureBoot Off
Set-VM          -Name   $vmName -AutomaticCheckpointsEnabled $false

$hdd = Get-VMHardDiskDrive -VMName $vmName
Set-VMFirmware -VMName $vmName -FirstBootDevice $hdd

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Get-VM -Name $vmName | Select-Object Name, Generation, State, MemoryStartup | Format-List
Write-Host "Connect, then start from inside the window:" -ForegroundColor Yellow
Write-Host "  vmconnect.exe localhost $vmName" -ForegroundColor Yellow
Write-Host "It boots straight into out-of-box setup. Stop at the first screen." -ForegroundColor Yellow
