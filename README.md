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

The driver will fail to start at the end of the installation. That is expected — Windows does not trust
the signing certificate yet. Nothing is broken; continue with step 6.

### 6. Trust the signing certificate

The certificate is embedded in the driver itself, so you can import it straight from the installed file:

```powershell
$sys  = 'C:\Program Files\Sandboxie-Plus\SbieDrv.sys'
$cert = (Get-AuthenticodeSignature $sys).SignerCertificate

foreach ($name in 'Root', 'TrustedPublisher') {
    $store = Get-Item "Cert:\LocalMachine\$name"
    $store.Open('ReadWrite')
    $store.Add($cert)
    $store.Close()
}
```

### 7. Start Sandboxie

```powershell
& 'C:\Program Files\Sandboxie-Plus\KmdUtil.exe' start SbieDrv
& 'C:\Program Files\Sandboxie-Plus\KmdUtil.exe' start SbieSvc
sc.exe query SbieDrv    # STATE : 4  RUNNING
```

Launch Sandboxie-Plus from the Start menu. Done.

**Future updates:** steps 2 to 4 are permanent, and step 6 only has to be repeated if the signing
certificate changes. Each release lists the certificate's SHA-1 thumbprint in its notes, so you can tell
at a glance whether you already trust it.

### If the driver still will not start

Error 577, `SBIE1103` or `SBIE9153` all mean the same thing: the signature was not accepted. Check that
test signing really is on and that the certificate landed in both stores:

```powershell
bcdedit /enum "{current}" | Select-String testsigning          # must say Yes
Get-AuthenticodeSignature 'C:\Program Files\Sandboxie-Plus\SbieDrv.sys' | Select-Object Status
```

`Status` should be `Valid`. If it is not, redo step 6 and reboot. A Windows update can silently re-enable
Memory Integrity, so re-check step 3 as well.

To undo everything, uninstall Sandboxie-Plus and run:

```powershell
bcdedit /set testsigning off
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
    /v Enabled /t REG_DWORD /d 1 /f
```

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
changes on every build, meaning step 6 above has to be repeated after every update.

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
