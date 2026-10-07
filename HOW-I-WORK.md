# How I work

## The method

1. **Copy the exact error text.** A paraphrase loses the code, and the code is what you search on.
2. **List what could cause it, cheapest check first.** Network and licences before rebuilds.
3. **Test one thing at a time, and record the result,** including "ruled out" and including my own
   mistakes. The table of eliminated causes on
   [Day 3](day-guides/day-03-windows-install-entra-join-and-intune-enrolment.md#what-was-eliminated-and-how)
   has a row that reads "My error".
4. **Prove it on the device, not only in the console.** Event logs, the `PolicyManager` registry tree,
   `dsregcmd /status`, `Get-MpPreference`, `manage-bde`, `edge://policy`.
5. **Fix it, then check the fix landed** where it matters, on the machine.
6. **Write it down the same day:** symptom, what I checked, cause, fix, and what would have found it
   faster.

## Rules the lab taught me

Each one cost time before it became a rule.

| Rule | Where it came from |
|---|---|
| "Succeeded" in a report describes delivery, not outcome. | [LAPS](LAB-LOG.md#day-9-windows-laps-returned-0x80070190-and-the-portal-said-nothing-useful), [Defender](LAB-LOG.md#day-13-the-antivirus-policy-was-enforcing-an-insecure-value) |
| An error message is a claim, not a diagnosis. | [BitLocker key](LAB-LOG.md#day-13-the-portal-said-no-access-it-was-wrong), [enrolment](day-guides/day-03-windows-install-entra-join-and-intune-enrolment.md#part-4-error-80180003-and-a-full-day-to-find-a-one-click-cause) |
| Prove the policy arrived before questioning what is in it. | [Defender](LAB-LOG.md#day-13-the-antivirus-policy-was-enforcing-an-insecure-value) |
| A log entry is a claim. The live setting is the fact. | [801C03ED in the rebuild](rebuild/README.md#the-801c03ed-finding) |
| Silence is not a result. Every check prints what it found, including "nothing". | [Rebuild, Defender](rebuild/README.md#defender-antivirus) |
| Check the tenant-wide switches early: MDM authority, LAPS, diagnostic data, the compliance default. | Days 3, 9, 11 |
| Run Microsoft's own diagnostic before reasoning from first principles. | [Day guides index](day-guides/README.md#the-two-most-expensive-lessons-of-the-week) |
| "Not found" and "cannot look" are different answers. | [Rebuild, failure 10](rebuild/README.md#what-broke) |
| A script that prints success has to check its own exit code. | [Rebuild, failure 2](rebuild/README.md#what-broke) |
| A wrong property name looks exactly like an unset setting. | [Select-Object](LAB-LOG.md#day-13-select-object-invented-a-setting-that-did-not-exist) |
| Our own hardening is often what blocks us later. | [Day guides index](day-guides/README.md#failure-patterns-seen-more-than-once) |

## Secrets

Recovery keys never go on a command line. The scripts that need one ask for it with
`Read-Host`, because anything typed as part of a command is saved to PowerShell's history
on disk ([04-fetch-hwid.ps1](rebuild/04-fetch-hwid.ps1)). `manage-bde -protectors -get` prints the
recovery password, so it is never run during a screen share.

## Tools

Intune admin center · Entra admin center · Microsoft 365 admin center · Defender portal ·
Graph Explorer · PowerShell 7 with the Microsoft Graph SDK · `Get-WinEvent` and Event Viewer ·
`dsregcmd` · `mdmdiagnosticstool` · `manage-bde` · `Get-MpPreference` · `citool` · Hyper-V and DISM

## How I use AI to learn

I study with Claude, Anthropic’s AI, as a tutor, the way you would learn next to a patient senior
colleague. It explains the concept and gives me one command at a time, with what the command does and
why it comes at that point. I type and run every command myself, read what comes back, and report it.
When something fails, we read the error rather than going around it. It quizzes me after each step,
because a working tenant is not proof that I understood it.

After each session the write-up is produced from the session record, and I check it against what I
saw on screen. The scripts in `rebuild/` and `teardown/` were written the same way, with the tutor’s
help, and run and debugged by me on the lab machine. The lab, every click and every command in it, is
mine.
