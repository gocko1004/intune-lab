# 07-defender-status.ps1
# RUNS INSIDE THE VIRTUAL MACHINE, in an elevated session. Reads only.
#
# Checks that the Defender Antivirus policy ES-Defender-AV actually arrived and
# took effect, rather than trusting the portal's "succeeded".
#
# TWO SOURCES, AND THEY ANSWER DIFFERENT QUESTIONS
#   Get-MpPreference                        what Defender is DOING
#   PolicyManager\current\device\Defender   what Intune SENT
# If Intune sent a value and Defender is not using it, something in between
# overrode or rejected it. If both agree, the policy is in force.
#
# LESSON CARRIED OVER FROM 06-bitlocker-status.ps1
# Asking for a property name that does not exist returns nothing, and nothing
# looks exactly like "not set". Every name below is checked for existence first,
# and a missing one is reported as MISSING NAME, not as an empty value.

$ErrorActionPreference = 'Continue'

$mp = Get-MpPreference

# Property, expected value, and how to read the number.
$checks = @(
    @{ n='DisableRealtimeMonitoring'; want='False'; note='False = real-time protection on' }
    @{ n='DisableBehaviorMonitoring'; want='False'; note='False = behaviour monitoring on' }
    @{ n='DisableScriptScanning';     want='False'; note='False = script scanning on' }
    @{ n='DisableIOAVProtection';     want='False'; note='False = downloads and attachments scanned' }
    @{ n='MAPSReporting';             want='2';     note='cloud protection. 0 off, 1 basic, 2 advanced' }
    @{ n='CloudBlockLevel';           want='2';     note='0 default, 2 High, 4 High+, 6 zero tolerance' }
    @{ n='CloudExtendedTimeout';      want='50';    note='extra seconds to wait for a cloud verdict' }
    @{ n='SubmitSamplesConsent';      want='1';     note='0 prompt, 1 safe samples auto, 2 never, 3 all' }
    @{ n='PUAProtection';             want='1';     note='0 off, 1 block, 2 audit' }
    @{ n='EnableNetworkProtection';   want='1';     note='0 off, 1 block, 2 audit' }
    @{ n='SignatureUpdateInterval';   want='4';     note='hours between definition checks' }
)

Write-Host "`n=== What Defender is doing (Get-MpPreference) ===" -ForegroundColor Cyan

$names = $mp.PSObject.Properties.Name
foreach ($c in $checks) {
    if ($names -notcontains $c.n) {
        Write-Host ("  MISSING NAME  {0,-28} the property does not exist. My name is wrong, not the setting" -f $c.n) -ForegroundColor Magenta
        continue
    }
    $have = [string]$mp.($c.n)
    $ok   = $have -eq $c.want
    $tag  = if ($ok) { 'OK  ' } else { 'DIFF' }
    $col  = if ($ok) { 'Green' } else { 'Yellow' }
    Write-Host ("  {0}  {1,-28} {2,-6} want {3,-6} {4}" -f $tag, $c.n, $have, $c.want, $c.note) -ForegroundColor $col
}

# ---------------------------------------------------------------------------
# Engine state. Running mode matters: "Normal" means Defender is the active
# antivirus. "Passive" means another antivirus product is registered as
# primary and Defender is only standing by, in which case most settings above
# are configured but not enforced.
# ---------------------------------------------------------------------------

Write-Host "`n=== Engine state (Get-MpComputerStatus) ===" -ForegroundColor Cyan

$st = Get-MpComputerStatus
foreach ($n in @('AMRunningMode','RealTimeProtectionEnabled','IsTamperProtected',
                 'AntivirusSignatureLastUpdated','AMProductVersion')) {
    if ($st.PSObject.Properties.Name -contains $n) { "  {0,-32} {1}" -f $n, $st.$n }
    else { Write-Host ("  MISSING NAME  {0}" -f $n) -ForegroundColor Magenta }
}

# ---------------------------------------------------------------------------
# What Intune sent. Listed under the real value names, nothing assumed.
# DisableLocalAdminMerge is checked here because Get-MpPreference does not
# report it.
# ---------------------------------------------------------------------------

# FIRST VERSION BUG: this section printed nothing at all on the first run. It
# reported a missing key, but had no branch for a key that EXISTS AND IS EMPTY,
# so it went silent. Silence is the worst possible output: it cannot be told
# apart from the script not reaching this line. Every outcome now says what it is.
#
# Three places are checked, because MDM Defender policy is not kept in one spot:
#   PolicyManager\current\device\Defender         the merged MDM view
#   PolicyManager\providers\<id>\...\Defender     what each source sent
#   Policies\Microsoft\Windows Defender\Policy Manager   where Defender itself reads MDM policy

function Show-Key {
    param([string]$Label, [string]$Path)
    Write-Host ("  [{0}]" -f $Label) -ForegroundColor DarkGray
    $item = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if (-not $item) { Write-Host "    (key does not exist)" -ForegroundColor DarkYellow; return }
    $names = $item.GetValueNames() | Where-Object { $_ -notmatch '_(ProviderSet|WinningProvider|LastWrite)$' } | Sort-Object
    if (-not $names) { Write-Host "    (key exists but holds no values)" -ForegroundColor DarkYellow; return }
    foreach ($n in $names) { "    {0,-38} {1}" -f $n, $item.GetValue($n) }
}

Write-Host "`n=== What Intune sent ===" -ForegroundColor Cyan

Show-Key 'merged: PolicyManager\current\device\Defender' 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Defender'

Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\PolicyManager\providers' -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Join-Path $_.PSPath 'default\Device\Defender'
    if (Test-Path $p) { Show-Key ("provider " + $_.PSChildName) $p }
}

Show-Key 'Defender reads: Policies\Microsoft\Windows Defender\Policy Manager' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager'

Write-Host ""
