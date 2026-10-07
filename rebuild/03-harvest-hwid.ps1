# 03-harvest-hwid.ps1
# RUNS INSIDE THE VIRTUAL MACHINE, at the out-of-box screen.
# Pushed in from the host with Copy-VMFile. Not run on the host.
#
# Produces the Autopilot hardware hash for this machine and writes it to a CSV.
#
# WHAT THE HASH IS
# Autopilot has to recognise a machine before it has a name or a user. So it
# identifies the hardware instead. The hash is built from values that cannot be
# changed from inside Windows: the TPM endorsement key, UEFI variables, disk
# and network adapter identifiers, manufacturer and model. Those are combined
# and encoded into one Base64 blob of roughly 4000 characters.
#
# Upload that blob to Intune and the machine is known. When it next reaches the
# internet during setup, it reports its hash, Microsoft matches it, and the
# Autopilot profile comes down before anyone has typed anything.
#
# It also explains a real-world gotcha: replace the motherboard and the hash
# changes, so the machine stops being recognised and has to be re-registered.

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. TLS 1.2.
#
# Windows PowerShell 5.1 still defaults to older TLS versions on a fresh
# install. The PowerShell Gallery refuses anything below 1.2, and the failure
# looks like a generic "unable to download" rather than anything about TLS.
# This one line saves an hour of looking in the wrong place.
# ---------------------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# 2. The NuGet provider.
#
# Install-Script downloads from the Gallery, and the Gallery is a NuGet feed.
# Without the provider present, PowerShell stops and asks to install it
# interactively. In an unattended script that prompt is a hang, not an error.
# Installing it up front removes the prompt.
# ---------------------------------------------------------------------------

Write-Host "Installing the NuGet provider..." -ForegroundColor Cyan
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

# The Gallery is untrusted by default, which is another interactive prompt.
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# ---------------------------------------------------------------------------
# 3. The script itself.
#
# Get-WindowsAutopilotInfo is a community script published by Microsoft's
# Michael Niehaus. It is the standard tool. It reads the hash out of WMI, from
# the MDM_DevDetail_Ext01 class, which is where Windows exposes it.
#
# Install-Script, not Install-Module. A script and a module are different
# things in the Gallery: a module exports commands, a script is a single file
# you run. This is a file.
# ---------------------------------------------------------------------------

Write-Host "Installing Get-WindowsAutopilotInfo..." -ForegroundColor Cyan
Install-Script -Name Get-WindowsAutopilotInfo -Force

# ---------------------------------------------------------------------------
# 4. Run it.
#
# Called by full path rather than by name. Install-Script adds the scripts
# folder to the PATH environment variable, but the CURRENT session already
# read PATH at startup and will not see the change. Calling by name here fails
# on a fresh session and works on the second try, which is the kind of
# inconsistency that wastes an afternoon.
# ---------------------------------------------------------------------------

$scriptPath = Join-Path $env:ProgramFiles 'WindowsPowerShell\Scripts\Get-WindowsAutopilotInfo.ps1'
if (-not (Test-Path $scriptPath)) {
    throw "Get-WindowsAutopilotInfo.ps1 not found at $scriptPath"
}

New-Item -ItemType Directory -Path 'C:\HWID' -Force | Out-Null
$csv = 'C:\HWID\AutopilotHWID.csv'

Write-Host "Reading the hardware hash..." -ForegroundColor Cyan
& $scriptPath -OutputFile $csv

# ---------------------------------------------------------------------------
# 5. Verify, and show what is actually in the file.
#
# The CSV has three columns:
#   Device Serial Number      from the firmware
#   Windows Product ID        the installed edition's identifier
#   Hardware Hash             the blob
#
# Printing the first and last characters of the hash proves it is real without
# filling the screen with 4000 characters you cannot read anyway.
# ---------------------------------------------------------------------------

if (-not (Test-Path $csv)) { throw "No CSV produced." }

$row = Import-Csv $csv | Select-Object -First 1

Write-Host ""
Write-Host "=== Hardware hash captured ===" -ForegroundColor Green
Write-Host ("  Serial number:  {0}" -f $row.'Device Serial Number')
Write-Host ("  Product ID:     {0}" -f $row.'Windows Product ID')
Write-Host ("  Hash length:    {0} characters" -f $row.'Hardware Hash'.Length)
Write-Host ("  Hash starts:    {0}..." -f $row.'Hardware Hash'.Substring(0,40))
Write-Host ("  Hash ends:      ...{0}" -f $row.'Hardware Hash'.Substring($row.'Hardware Hash'.Length-40))
Write-Host ""
Write-Host "  File: $csv" -ForegroundColor Yellow
