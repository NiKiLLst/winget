# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single PowerShell script (`Winget.ps1`, ~1150 lines) that provisions Windows 10/11 workstations
in a corporate setting: installs/updates software via WinGet, applies OS tweaks, runs Windows Update,
optionally renames the PC and joins a domain, then writes a report. Target users are sysadmins
(including juniors) doing repeatable, traceable PC onboarding.

There is no build system, dependency manifest, or automated test suite — the repo is the script
plus its README and a committed config file. Code, comments, log messages, and the README are
written in **Italian**; match that convention when editing.

## Running

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Winget.ps1
```

The script self-elevates to Administrator (relaunches itself via `Start-Process -Verb RunAs`) and
self-updates from the local Git repo before doing any provisioning work. It **reboots the machine**
multiple times during a normal run, so it cannot be executed end-to-end in a sandbox. The README
direction is to validate changes by running a full pass in a VM.

To sanity-check edits without running, parse the script:
```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw .\Winget.ps1),[ref]$null)"
```

## Architecture — the reboot/resume state machine

The single most important thing to understand: **the script is designed to survive reboots and
resume itself.** A normal run is not one process — it is a chain of processes across reboots,
coordinated by a scheduled task and on-disk state files. Any edit to control flow must preserve this.

Four runtime files live in `logs\` (gitignored, recreated each run):

- `ExecutionPlan.json` — all initial user choices (target PC name, join flag, domain, selected apps,
  credential file paths, `DomainUserName`). Written once during the upfront input phase; read on every resume.
- `JoinDomainState.txt` — the **savepoint**: a small JSON `{Action, Step, ...}`. Its presence means
  "this is a resume, not a fresh start." `Action` is one of `RenameOnly`, `JoinDomain`, `Progress`,
  `ShowSummary`. For `JoinDomain`, `Step` is `Renamed` (rename done, ready to join) or `Joined`
  (joined, post-join setup pending).
- `DomainJoinCredential.xml` — domain *admin* credential (used to perform the join). `Export-Clixml`,
  DPAPI-encrypted, bound to the user that wrote it.
- `DomainUserCredential.xml` — credential of the *end-user* domain account that will use the PC. Used
  to add that account to local Administrators and to configure a one-shot autologon so post-join
  provisioning runs in that user's context.

`WingetResumeTask` is a scheduled task (trigger: AtLogOn, RunLevel Highest) registered *before* a
reboot and unregistered immediately on resume. It is what relaunches the script after Windows restarts.

Execution model:

1. **Self-elevation + self-update** run unconditionally first. `$env:WINGET_SELFUPDATED` guards
   against an infinite relaunch loop after a successful `git pull`.
2. **Upfront input phase** (only when no savepoint exists): *all* interactive prompts happen here, in
   this order — local admin user, domain join + domain, join-admin credentials, end-user domain
   credentials, PC name + confirm. Domain/credentials are gathered *before* the PC name because the
   name's availability check needs them. Credentials are verified against the domain as they are
   entered (`Get-TestedDomainCredential` → `Test-DomainCredential`). After this the run is fully
   non-interactive. The result is `ExecutionPlan.json`.
3. **Resume dispatch** (when a savepoint exists): branches on `Action` to continue mid-rename,
   mid-join, show the final report, or resume from a `Progress` step.
4. **Domain join phase** (when join was requested): runs *before* provisioning. `Invoke-DomainJoinPhase`
   does the join, then `Invoke-PostJoinSetup` adds the end-user to local Administrators, sets a one-shot
   autologon, and reboots. Provisioning then resumes (as a `Progress` savepoint) in the end-user's
   logon session. These functions never return — they always reboot or `exit`. Any failure keeps the
   savepoint and resume task so a relaunch continues from the stuck `Step`.
5. **Provisioning steps** are ordered by `$stepOrder = @("SysInfo","AppsInstalled","TweaksApplied","WindowsUpdate")`.
   `Test-StepNeeded` compares against the savepoint's `Step` so completed steps are skipped on resume.
   Each step calls `Write-StateFile @{Action="Progress"; Step=...}` after finishing.

**When adding or reordering a provisioning step:** add it to `$stepOrder`, wrap it in a
`Test-StepNeeded` check, and write a `Progress` savepoint after it — otherwise resume idempotency breaks.

**When editing the join flow:** failures must never `exit 1` and abandon the machine — keep the
savepoint and resume task registered so a relaunch resumes. The autologon stores the end-user password
in clear text under `HKLM\...\Winlogon`; `Clear-Autologon` removes it at every terminal state (closing
section and the `ShowSummary` branch).

## Other key pieces

- **App install** — `Install-Or-Update-WinGetPackage` checks installed state, upgrades or installs,
  and interprets `$LASTEXITCODE`. The app list is `$availableApps`; `$appFallbacks` maps a package ID
  to an alternative tried if the primary install fails (e.g. `Mozilla.Firefox` → `Mozilla.Firefox.it`).
- **Reporting** — three `$script:`-scoped collections (`$appResults`, `$wuResults`, `$tweaks`) are
  populated throughout the run; `Write-Summary` renders them to `Scheda_<COMPUTERNAME>_<date>.txt`
  next to the log file.
- **Logging** — `Write-Log` writes timestamped lines to console and to `$logPath`.
- **PowerShell modules** — `Microsoft.WinGet.Client` and `PSWindowsUpdate` are installed on demand
  via `Install-ModuleIfMissing`; the script degrades gracefully if they cannot be installed.

## Configuration touchpoints

- `winget-config.json` — **committed** to the repo; persists `LogPath` between runs. Editing the log
  path at runtime rewrites this file.
- `$domain = "test.local"` (in `Winget.ps1`) — placeholder default domain; the real domain is
  normally supplied interactively.
- `$availableApps` — the install candidate list; commenting a line with `#` excludes that app.
