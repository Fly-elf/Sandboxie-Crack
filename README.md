# Sandboxie-Crack

A personal fork of [sandboxie-plus/Sandboxie](https://github.com/sandboxie-plus/Sandboxie) that builds its
own installers in CI. The application code is upstream's — the only difference is that these builds are
signed with a self-issued certificate instead of a commercial one, so installing them takes a few extra
steps. [Jump to the install instructions.](#install)

For supported, properly signed builds use the
[official releases](https://github.com/sandboxie-plus/Sandboxie/releases/latest) instead, and report bugs
in the application itself [upstream](https://github.com/sandboxie-plus/Sandboxie/issues).

## What is Sandboxie

Sandboxie runs Windows programs inside an isolated environment, so they can execute or install without
permanently changing your drives or registry — useful for testing untrusted software, containing a
browser, or throwing away changes afterwards. This fork builds the **Plus** edition, with the modern Qt
interface.

Official repository: [sandboxie-plus/Sandboxie](https://github.com/sandboxie-plus/Sandboxie) ·
Documentation: [sandboxie-docs](https://sandboxie-plus.github.io/sandboxie-docs)

## Install

**Requirements:** Windows 7 or later, 64-bit, with administrator rights. Secure Boot and Memory Integrity
have to be off — Sandboxie's kernel driver is not signed by a certificate Windows trusts out of the box.
If that trade-off is not acceptable to you, use the official builds.

Run every command below in an **elevated PowerShell** (right-click → *Run as administrator*).

### 1. Download

Grab the installer for your architecture from the [Releases page](../../releases):

| File | For |
| --- | --- |
| `Sandboxie-Plus-x64-v<version>.exe` | 64-bit Intel/AMD |
| `Sandboxie-Plus-arm64-v<version>.exe` | ARM64 |

### 2. Turn off Secure Boot

```powershell
Confirm-SecureBootUEFI   # must print False
```

If it prints `True`, reboot into UEFI/BIOS setup and disable Secure Boot — step 4 cannot work otherwise.
An error saying the cmdlet is not supported means the machine uses legacy BIOS; carry on.

### 3. Turn off Memory Integrity

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
    /v Enabled /t REG_DWORD /d 0 /f
```

Or: Windows Security → *Device security* → *Core isolation* → **Memory integrity** off.

### 4. Enable test signing, then reboot

```powershell
bcdedit /set testsigning on
```

Reboot. Windows will show a "Test Mode" watermark on the desktop from now on.

### 5. Run the installer

```powershell
.\Sandboxie-Plus-x64-v1.18.2.exe
```

Leave the **Trust the certificate the Sandboxie driver is signed with** task ticked. The installer imports
the certificate into the machine's `Root` and `TrustedPublisher` stores, which is what lets Windows load
the driver; uninstalling removes it again. The task is only offered when the certificate is not already
trusted, so it disappears on later updates.

If test signing is off, the installer says so on the Ready page and tells you the command to fix it.

Launch Sandboxie-Plus from the Start menu. Done.

**Future updates:** steps 2 to 4 are permanent, and the certificate stays trusted, so from here on updating
is just running the new installer, or the [update script](#updating) below.

### If the driver still will not start

Error 577, `SBIE1103` or `SBIE9153` all mean the same thing: the signature was not accepted. Check that
test signing is on and that the certificate really landed in the stores:

```powershell
bcdedit /enum "{current}" | Select-String testsigning          # must say Yes
Get-AuthenticodeSignature 'C:\Program Files\Sandboxie-Plus\SbieDrv.sys' | Select-Object Status
```

`Status` should be `Valid`. If it is not, import the certificate by hand and start the services:

```powershell
$sys  = 'C:\Program Files\Sandboxie-Plus\SbieDrv.sys'
$cert = (Get-AuthenticodeSignature $sys).SignerCertificate
foreach ($name in 'Root', 'TrustedPublisher') {
    $store = Get-Item "Cert:\LocalMachine\$name"
    $store.Open('ReadWrite'); $store.Add($cert); $store.Close()
}
& 'C:\Program Files\Sandboxie-Plus\KmdUtil.exe' start SbieDrv
& 'C:\Program Files\Sandboxie-Plus\KmdUtil.exe' start SbieSvc
```

A Windows update can silently re-enable Memory Integrity, so re-check step 3 as well.

To undo everything, uninstall Sandboxie-Plus and run:

```powershell
bcdedit /set testsigning off
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
    /v Enabled /t REG_DWORD /d 1 /f
```

## Updating

The built-in updater is disabled in this fork, because it only accepts installers signed with upstream's key.
[`scripts/Update-Sandboxie.ps1`](./scripts/Update-Sandboxie.ps1) does the same job against this repository's
releases, like `winget upgrade`:

```powershell
.\Update-Sandboxie.ps1 -CheckOnly   # report the newest version, no elevation needed
.\Update-Sandboxie.ps1              # from an elevated PowerShell: asks, then installs
```

It looks at the latest stable release (the rolling `nightly` is ignored) and does nothing when you are up to
date. Otherwise it downloads the installer for your architecture, checks it against `SHA256SUMS.txt` and against
the certificate that signed the installed driver, terminates sandboxed programs, closes SandMan and runs the
installer silently. SandMan is reopened if it was running.

| Option | Effect |
| --- | --- |
| `-Yes` | Do not ask for confirmation. |
| `-TrustNewSigner` | Accept an installer signed by a different certificate than the installed driver, for when the signing certificate was replaced on purpose. |
| `-Repo <owner>/<repo>` | Update from another repository. |

### Automatic updates

Task Scheduler is the Windows counterpart of `cron`. From an elevated PowerShell, put the script where only
administrators can write to it (the task runs it elevated) and register a weekly task:

```powershell
$dir = "$env:ProgramFiles\Sandboxie-Updater"
New-Item -ItemType Directory -Force $dir | Out-Null
Invoke-WebRequest https://raw.githubusercontent.com/Fly-elf/Sandboxie-Crack/master/scripts/Update-Sandboxie.ps1 `
    -OutFile "$dir\Update-Sandboxie.ps1"

$action    = New-ScheduledTaskAction -Execute powershell.exe `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\Update-Sandboxie.ps1`" -Yes"
$trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 12:00
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask 'Update Sandboxie-Plus' -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

The task runs in your own session, so SandMan reopens where you can see it, and elevated without a prompt.
`-StartWhenAvailable` runs a missed update as soon as the machine is on again. Upstream releases reach this
fork within about four days of being published. An update terminates sandboxed programs, so pick a time when
nothing important runs inside a sandbox, and change `-DaysOfWeek` and `-At` to taste.

```powershell
Start-ScheduledTask 'Update Sandboxie-Plus'                                                 # run it now
Get-ScheduledTaskInfo 'Update Sandboxie-Plus' | Select-Object LastRunTime, LastTaskResult   # 0 = success
Unregister-ScheduledTask 'Update Sandboxie-Plus' -Confirm:$false                            # remove it
```

The task uses the copy of the script downloaded above: download it again to pick up changes to the script itself.

## Building from source

Windows only. Treat [`.github/workflows/main.yml`](./.github/workflows/main.yml) as the authoritative
build reference and see [`AGENTS.md`](./AGENTS.md) for the repository layout.

- **Core** — MSBuild with the Windows SDK and WDK: `Sandboxie/SandboxDll.sln`, `Sandboxie/Sandbox.sln`,
  `Sandboxie/SandboxDrv.sln`
- **Qt UI** — qmake and Jom via `SandboxiePlus/qmake_plus.cmd`
- **Tools** — `SandboxieTools/SandboxieTools.sln`
- **Dependency versions** — [`Installer/buildVariables.cmd`](./Installer/buildVariables.cmd)

Building only assembles the binaries into `Installer/SbiePlus_x64`. The installer is packaged separately
by [`.github/workflows/release.yml`](./.github/workflows/release.yml), which takes the artifacts of a
successful CI run, signs the driver, compiles `Installer/Sandboxie-Plus.iss` with Inno Setup and publishes
the result. Run it by hand with:

```bash
gh workflow run release.yml --repo <owner>/<repo> --ref master
```

To sign builds with your own certificate, set the `SIGN_CERT_PFX` (base64 of a `.pfx`) and
`SIGN_CERT_PASSWORD` repository secrets. Without them the driver keeps a throwaway certificate that
changes on every build, so the installer adds a new one to the certificate stores on every update.

The certificate-trust task is not part of `Installer/Sandboxie-Plus.iss`; it is appended to a working copy
at packaging time from [`.github/installer/cert_trust.iss`](./.github/installer/cert_trust.iss), so the
upstream installer script stays untouched.

## Syncing with upstream

GitHub's *Sync fork* button refuses to run whenever upstream changes a file that was also changed here —
in practice `README.md`, which is fully rewritten in this fork. Syncing is done by a workflow, or from the
command line.

### Automatic sync

[`sync-upstream.yml`](./.github/workflows/sync-upstream.yml) runs every Monday and Thursday. It merges the
newest upstream `vX.Y.Z` tag into `master` (that exact commit, not upstream's `master`), keeps this fork's
`README.md` on conflict, tags the merge commit `X.Y.Z` and pushes. The push starts CI, and a successful CI run
on a tagged commit is published by `release.yml` as a regular release rather than the rolling `nightly`. A
conflict in any other file fails the run and leaves `master` untouched; merge by hand as described below.

Run it ahead of schedule from the *Actions* tab. With *dry run* ticked it merges without pushing and lists the
changed files. Only the latest tag is considered, and nothing happens when it is already merged.

The workflow pushes with a personal access token, because the default `GITHUB_TOKEN` cannot push upstream's
changes to `.github/workflows`. Create a fine-grained token for this repository only, with **Contents** and
**Workflows** set to read and write, then store it as the `SYNC_TOKEN` secret:

```bash
gh secret set SYNC_TOKEN --repo <owner>/<repo>
```

Fine-grained tokens expire after at most a year. When the sync fails with an authentication error, issue a new
one and set the secret again.

### Manual sync

One-time setup:

```bash
git remote add upstream https://github.com/sandboxie-plus/Sandboxie.git
```

Each sync:

```bash
git fetch upstream
git merge-tree --write-tree --name-only master upstream/master   # optional dry run: lists conflicting files
git merge upstream/master
```

If `README.md` is the only conflict, keep the local version and finish the merge:

```bash
git checkout --ours README.md
git add README.md
git commit --no-edit
git push origin master
```

For any other conflicting file, list them with `git diff --name-only --diff-filter=U`, resolve the
`<<<<<<<` / `=======` / `>>>>>>>` markers by hand, then `git add` them and commit. To back out before
committing, run `git merge --abort`.

Files edited in this fork that upstream also touches, such as `Sandboxie/core/drv/verify.c`, can merge
without a conflict and still change behavior. Review `git diff HEAD` on them before committing the merge.

## Licensing and credits

All application code, and all credit for it, belongs to the upstream project and its contributors —
originally Ronen Tzur, then Invincea and Sophos, and since April 2020 the community fork led by David
Xanatos. The full contributor, translator and sponsor lists are in
[upstream's README](https://github.com/sandboxie-plus/Sandboxie/blob/master/README.md).

Dual-licensed, unchanged from upstream: [`LICENSE.Classic`](./LICENSE.Classic) (GPLv3) and
[`LICENSE.Plus`](./LICENSE.Plus) (custom). Individual components carry their own licenses, listed in
[`AGENTS.md`](./AGENTS.md#licensing). Do not mix, remove or alter the copyright and license headers.

Security issues in Sandboxie itself must be reported upstream following [`SECURITY.md`](./SECURITY.md),
never in a public issue.
