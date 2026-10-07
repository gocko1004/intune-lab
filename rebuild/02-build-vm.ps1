# 02-build-vm.ps1
# Builds the lab virtual machine in Hyper-V.
# MUST run in PowerShell as administrator. Hyper-V cmdlets refuse otherwise.
#
# ORDER CHANGED after the first build failed to boot.
#
# The first attempt enabled the virtual Trusted Platform Module and Secure Boot
# before installing Windows. The module initialised on the first boot attempt,
# which PERMANENTLY LOCKS the Secure Boot template and cannot be undone without
# disabling the module. Neither is needed to run Windows setup.
#
# This version installs Windows first, then adds both afterwards, in 05-harden-vm.ps1.

$vmName   = 'W11-CORP-01'
$vmPath   = 'D:\VMs'
$vhdPath  = "$vmPath\$vmName\$vmName.vhdx"
$isoPath  = 'D:\VMs\Win11_25H2_EnglishInternational_x64_v2.iso'
$switch   = 'Default Switch'

# ---------------------------------------------------------------------------
# Remove any previous machine and its disks.
# Remove-VM deletes the machine and LEAVES THE DISKS. The folder delete is not
# optional; skipping it is the usual reason a Hyper-V host quietly fills up.
# ---------------------------------------------------------------------------

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $vmName -Force
}
if (Test-Path "$vmPath\$vmName") {
    Remove-Item -Path "$vmPath\$vmName" -Recurse -Force
}

# ---------------------------------------------------------------------------
# Create the machine.
#
# -Generation 2 cannot be changed later. Generation 1 is BIOS-style: no UEFI,
# no Secure Boot, no Trusted Platform Module. Windows 11 needs all three.
#
# Memory is static 4 GB, not dynamic. Windows setup runs in Windows PE, which
# has no dynamic memory driver, so during installation the machine only ever
# receives its startup allocation regardless of the maximum.
# ---------------------------------------------------------------------------

New-VM -Name $vmName `
       -Generation 2 `
       -MemoryStartupBytes 4GB `
       -NewVHDPath $vhdPath `
       -NewVHDSizeBytes 64GB `
       -SwitchName $switch `
       -Path $vmPath

Set-VMMemory    -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes 4GB
Set-VMProcessor -VMName $vmName -Count 2

# ---------------------------------------------------------------------------
# Secure Boot OFF for the installation only.
# Turned back on in 05-harden-vm.ps1 once Windows is on disk.
# ---------------------------------------------------------------------------

Set-VMFirmware -VMName $vmName -EnableSecureBoot Off

# ---------------------------------------------------------------------------
# Installation media, and boot from it.
# The hard disk is deliberately left OUT of the boot order. With nothing to
# fall through to, a failure is unambiguously about the DVD rather than about
# an empty disk, which is what muddied the last round of diagnosis.
# ---------------------------------------------------------------------------

Add-VMDvdDrive -VMName $vmName -Path $isoPath
$dvd = Get-VMDvdDrive -VMName $vmName
Set-VMFirmware -VMName $vmName -BootOrder $dvd

# ---------------------------------------------------------------------------
# Automatic checkpoints off. On by default, and the reason the previous build
# ended with 71 GB of differencing disks on top of a 35 GB base.
# ---------------------------------------------------------------------------

Set-VM -Name $vmName -AutomaticCheckpointsEnabled $false

# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Built, not started ===" -ForegroundColor Cyan
Get-VM -Name $vmName | Select-Object Name, Generation, State, MemoryStartup, ProcessorCount, AutomaticCheckpointsEnabled | Format-List
Get-VMFirmware -VMName $vmName | Select-Object SecureBoot | Format-List
Get-VMDvdDrive -VMName $vmName | Select-Object Path | Format-List

Write-Host "Connect FIRST, then start from inside the window:" -ForegroundColor Yellow
Write-Host "  vmconnect.exe localhost $vmName" -ForegroundColor Yellow
