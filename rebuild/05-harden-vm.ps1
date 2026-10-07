# 05-harden-vm.ps1
# Turns Secure Boot and the virtual Trusted Platform Module back on, now that
# Windows is installed and enrolled.
# MUST run as administrator.
#
# WHY THEY WERE OFF
# The first build enabled the TPM before Windows was installed. The TPM
# initialised on the first boot attempt, which LOCKED the Secure Boot template
# permanently, and the machine then could not boot the installer. Both were
# removed to get Windows onto the disk.
#
# WHY THEY COME BACK NOW
# BitLocker wants the TPM to hold its key. Compliance policies check for both.
# Windows 11 officially requires both. A managed corporate device without them
# is not a realistic lab device.
#
# THE ORDER IS THE WHOLE POINT OF THIS SCRIPT
#   1. Secure Boot template first
#   2. Key protector second
#   3. TPM last
# The template can only be changed while the TPM has never initialised. Do it in
# any other order and you are back to the error that cost an afternoon:
#   "Cannot modify the secure boot template ID property after the virtual TPM
#    is initialized"

$ErrorActionPreference = 'Stop'

$vmName = 'W11-CORP-01'

# ---------------------------------------------------------------------------
# The machine must be off. Firmware settings cannot change on a running machine,
# the same way you cannot change BIOS settings on a running laptop.
#
# No -TurnOff. This asks Windows to shut down properly through the integration
# service, so Lea's session closes cleanly instead of losing power.
# ---------------------------------------------------------------------------

$vm = Get-VM -Name $vmName
if ($vm.State -ne 'Off') {
    Write-Host "Shutting the machine down..." -ForegroundColor Cyan
    Stop-VM -Name $vmName -Force
}

# ---------------------------------------------------------------------------
# 1. Secure Boot, with the Windows template.
#
# Secure Boot means the firmware only runs a boot loader whose signature it
# trusts. The template is the list of trusted signers.
#
#   MicrosoftWindows                  trusts Microsoft's Windows signing key.
#                                     Correct for a Windows guest
#   MicrosoftUEFICertificateAuthority trusts third-party signed loaders, used
#                                     for Linux guests
#
# The boot loader bcdboot wrote is bootmgfw.efi from the Windows image, signed
# by Microsoft, so the Windows template accepts it.
# ---------------------------------------------------------------------------

# Guard: only touch the template if it is not already correct. If the TPM has
# ever initialised, even writing the SAME template value back can be refused.
$tpmAlreadyOn = (Get-VMSecurity -VMName $vmName).TpmEnabled
$templateOk   = (Get-VMFirmware -VMName $vmName).SecureBootTemplate -eq 'MicrosoftWindows'

Write-Host "Enabling Secure Boot..." -ForegroundColor Cyan
if ($templateOk) {
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On
}
else {
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows'
}

# ---------------------------------------------------------------------------
# 2. Key protector.
#
# A virtual TPM is a file on the host, and a file can be copied. The key
# protector encrypts the TPM's state so that a copied virtual machine does not
# carry a working copy of its TPM, and with it the BitLocker key.
#
# In a datacentre the protector comes from a Host Guardian Service, which only
# releases it to hosts that prove they are healthy. That is a shielded virtual
# machine. On a single lab host there is no guardian service, so this creates a
# LOCAL guardian instead, stored in the host's certificate store.
#
# Consequence worth knowing: move this VM to another host and it will not start
# until that host has the same guardian certificates.
# ---------------------------------------------------------------------------

# Guard: a key protector cannot be replaced while the TPM is enabled, and does
# not need to be. If the TPM is already on, steps 2 and 3 are already done.
if (-not $tpmAlreadyOn) {
    Write-Host "Creating the key protector..." -ForegroundColor Cyan
    Set-VMKeyProtector -VMName $vmName -NewLocalKeyProtector
}

# ---------------------------------------------------------------------------
# 3. The TPM itself.
#
# From here the Secure Boot template is locked. That is why it was set first.
# ---------------------------------------------------------------------------

if (-not $tpmAlreadyOn) {
    Write-Host "Enabling the virtual TPM..." -ForegroundColor Cyan
    Enable-VMTPM -VMName $vmName
}
else {
    Write-Host "TPM already enabled. Key protector and TPM steps skipped." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Verify from the configuration, not from the commands having run.
# ---------------------------------------------------------------------------

Write-Host "`n=== Verification ===" -ForegroundColor Cyan

$fw  = Get-VMFirmware -VMName $vmName
$sec = Get-VMSecurity -VMName $vmName

$checks = [ordered]@{
    'Secure Boot on'                 = ($fw.SecureBoot -eq 'On')
    'Template is MicrosoftWindows'   = ($fw.SecureBootTemplate -eq 'MicrosoftWindows')
    'TPM enabled'                    = $sec.TpmEnabled
}

$allOk = $true
foreach ($k in $checks.Keys) {
    if ($checks[$k]) { Write-Host ("  OK    {0}" -f $k) -ForegroundColor Green }
    else             { Write-Host ("  FAIL  {0}" -f $k) -ForegroundColor Red; $allOk = $false }
}

if (-not $allOk) { throw "Configuration did not take. Do not start the machine yet." }

# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Connect first, then start:" -ForegroundColor Yellow
Write-Host "  vmconnect.exe localhost $vmName" -ForegroundColor Yellow
Write-Host "  Start-VM -Name $vmName" -ForegroundColor Yellow
Write-Host ""
Write-Host "If it fails to boot with a Secure Boot violation, turn Secure Boot off again:" -ForegroundColor DarkGray
Write-Host "  Set-VMFirmware -VMName $vmName -EnableSecureBoot Off" -ForegroundColor DarkGray
Write-Host "The TPM can stay. Only the template is locked, the on and off switch is not." -ForegroundColor DarkGray
