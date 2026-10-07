# 00-host-cleanup.ps1
# Reduces memory pressure and DNS conflicts on the Hyper-V host.
#
# SAFE BY DEFAULT. Run with no arguments and it reports what it would do.
# Pass -Execute to actually change anything.
#
#   .\00-host-cleanup.ps1             <- preview
#   .\00-host-cleanup.ps1 -Execute    <- do it
#
# MUST run as administrator.

param([switch]$Execute)

$ErrorActionPreference = 'Continue'

function Do-Step {
    param([string]$What, [scriptblock]$Action)
    if (-not $Execute) {
        Write-Host ("  WOULD DO   {0}" -f $What) -ForegroundColor Yellow
        return
    }
    try {
        & $Action
        Write-Host ("  DONE       {0}" -f $What) -ForegroundColor Green
    }
    catch {
        Write-Host ("  FAILED     {0}  :: {1}" -f $What, $_.Exception.Message) -ForegroundColor Red
    }
}

if ($Execute) { Write-Host "`nEXECUTE MODE`n" -ForegroundColor Red }
else          { Write-Host "`nPREVIEW ONLY. Re-run with -Execute to apply.`n" -ForegroundColor Green }

# ---------------------------------------------------------------------------
# 1. Remove the second VPN and DNS product.
#
# Two products both intercepting DNS is what broke the Hyper-V Default Switch's
# resolver. One is a tool. Two is a fault.
# ---------------------------------------------------------------------------

Write-Host "=== Cloudflare WARP ===" -ForegroundColor Cyan

$warp = Get-Package -Name "*Cloudflare*" -ErrorAction SilentlyContinue
if ($warp) {
    Do-Step "Uninstall $($warp.Name)" { Uninstall-Package -Name $warp.Name -Force -ErrorAction Stop }
}
else {
    Write-Host "  Not found via Get-Package. Try: winget uninstall Cloudflare.Warp" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 2. Remove the second antivirus engine.
#
# Defender is built into Windows and cannot be removed. A second real-time
# engine scanning the same files costs memory and slows disk operations.
# ---------------------------------------------------------------------------

Write-Host "`n=== Malwarebytes ===" -ForegroundColor Cyan

$mbam = Get-Package -Name "*Malwarebytes*" -ErrorAction SilentlyContinue
if ($mbam) {
    Do-Step "Uninstall $($mbam.Name)" { Uninstall-Package -Name $mbam.Name -Force -ErrorAction Stop }
}
else {
    Write-Host "  Not found via Get-Package. Uninstall from Settings, Apps." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. Defender for Endpoint sensor.
#
# The service is still running and still trying to report to a tenant whose
# Intune configuration was deleted.
#
# NOTE: this may fail. Tamper Protection deliberately blocks local changes to
# Defender services, which is the whole point of Tamper Protection. If it fails,
# the correct route is the offboarding package from the Defender portal under
# Settings, Endpoints, Offboarding.
# ---------------------------------------------------------------------------

Write-Host "`n=== Defender for Endpoint sensor ===" -ForegroundColor Cyan

if (Get-Service -Name 'Sense' -ErrorAction SilentlyContinue) {
    Do-Step "Stop and disable the Sense service" {
        Stop-Service -Name 'Sense' -Force -ErrorAction Stop
        Set-Service  -Name 'Sense' -StartupType Disabled -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# 4. Dell SupportAssist.
# Disabled rather than uninstalled, so it can be turned back on if a warranty
# or driver task ever needs it.
# ---------------------------------------------------------------------------

Write-Host "`n=== Dell services ===" -ForegroundColor Cyan

foreach ($s in @('SupportAssistAgent','DellClientManagementService')) {
    if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
        Do-Step "Stop and disable $s" {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $s -StartupType Disabled -ErrorAction Stop
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Startup entries.
#
# Removing the Run key entry does NOT uninstall anything. NordVPN still works,
# it simply stops launching itself at logon. Start it when you want it.
# ---------------------------------------------------------------------------

Write-Host "`n=== Startup entries ===" -ForegroundColor Cyan

$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
foreach ($entry in @('Intel Endurance Gaming','NordVPN')) {
    $existing = (Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue).$entry
    if ($existing) {
        Do-Step "Remove '$entry' from startup" {
            Remove-ItemProperty -Path $runKey -Name $entry -ErrorAction Stop
        }
    }
}

# ---------------------------------------------------------------------------
# 6. Temporary files. Roughly 1.2 GB, and the least important thing here.
# ---------------------------------------------------------------------------

Write-Host "`n=== Temporary files ===" -ForegroundColor Cyan

foreach ($p in @("$env:TEMP", 'C:\Windows\Temp', 'C:\Windows\Logs\CBS',
                 "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache")) {
    if (Test-Path $p) {
        Do-Step "Clear $p" {
            Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------

Write-Host ""
if ($Execute) {
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host ("Free RAM now: {0} GB of {1} GB" -f `
        [math]::Round($os.FreePhysicalMemory/1MB,2), `
        [math]::Round($os.TotalVisibleMemorySize/1MB,1)) -ForegroundColor Cyan
    Write-Host "Restart the laptop for the service changes to take full effect." -ForegroundColor Yellow
}
