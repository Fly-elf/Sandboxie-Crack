# Sandboxie-Crack

A personal fork of [sandboxie-plus/Sandboxie](https://github.com/sandboxie-plus/Sandboxie) that builds and
publishes its own installers straight from CI, without a commercial code-signing certificate.

The application code is upstream's. What this fork adds is a release pipeline: every push to `master`
compiles the project, packages it into an Inno Setup installer and publishes it as a GitHub release.
Because the kernel driver is not signed by a certificate Windows trusts out of the box, installing these
builds takes a few extra steps — [that is what most of this README is about](#installation).

> **This is not the official Sandboxie.** For supported, properly signed builds use the
> [upstream releases](https://github.com/sandboxie-plus/Sandboxie/releases/latest). Report bugs in the
> application itself upstream, not here.

---

## What Sandboxie is

Sandboxie is a sandbox-based isolation tool for Windows NT systems. It runs programs inside an isolated
environment so they can execute or install without permanently modifying local and mapped drives or the
Windows registry — useful for testing untrusted software, containing browsers, or throwing away changes
after the fact.

It ships in two editions built from the same core, so both have the same security and compatibility:

| Edition | UI | Status |
| --- | --- | --- |
| **Plus** | Modern Qt interface (`SandMan.exe`) | Actively developed upstream, gets all new features |
| **Classic** | Legacy MFC interface (`SbieCtrl.exe`) | No longer developed |

This fork builds and packages **Plus**. For the feature list, documentation and project history see
[upstream's README](https://github.com/sandboxie-plus/Sandboxie/blob/master/README.md) and the
[Sandboxie documentation](https://sandboxie-plus.github.io/sandboxie-docs).

---

## Download

Installers are published on the [Releases page](../../releases). The rolling `nightly` tag always holds the
build from the most recent successful CI run on `master`:

| Asset | For |
| --- | --- |
| `Sandboxie-Plus-x64-v<version>.exe` | 64-bit Intel/AMD |
| `Sandboxie-Plus-arm64-v<version>.exe` | ARM64 |
| `SHA256SUMS.txt` | Checksums for both |

Verify the download before running it:

```powershell
Get-FileHash .\Sandboxie-Plus-x64-v1.18.2.exe -Algorithm SHA256
type .\SHA256SUMS.txt
```

**Requirements:** Windows 7 or later, 64-bit. Administrator rights. Secure Boot and Memory Integrity must
be turned off (see below) — if you are not willing to do that, use the upstream signed builds instead.

---

## Why installation is not just "run the .exe"

Sandboxie's core is `SbieDrv.sys`, a kernel-mode driver. 64-bit Windows refuses to load kernel drivers
that are not signed by a certificate chaining to a root it trusts, and this fork has no such certificate.

Two details make it stricter than usual:

- `Sandboxie/core/drv/SboxDrv.vcxproj` builds the driver with `/INTEGRITYCHECK`, which sets
  `FORCE_INTEGRITY` in the PE header. Windows then validates the embedded signature on every load
  *regardless* of the general driver-signature policy. So booting with "Disable driver signature
  enforcement" is not a reliable shortcut here.
- The driver needs `PsSetCreateProcessNotifyRoutineEx` (`core/drv/process.c`) and `ObRegisterCallbacks`
  (`core/drv/obj_flt.c`), both of which require a signed, integrity-checked image.

`bcdedit /set testsigning on` **on its own is not enough.** Test signing tells Windows to accept
certificates that do not chain to a Microsoft root — it does not tell it to accept a certificate it has
never seen. You need *both*: test signing enabled **and** the signing certificate trusted on the machine.

Note that Safe Mode does **not** disable driver signature enforcement on 64-bit Windows; that is a
different (and, as noted above, unreliable) boot option.

One thing works in your favour: Sandboxie disables its own internal caller-signature checks when the OS
is in test-signing mode (`core/drv/util.c`, `MyIsCallerSigned`), so the unsigned user-mode binaries
(`SandMan.exe`, `SbieSvc.exe`, `SbieDll.dll`, …) are fine as they are.

---

## Installation

Everything below runs from an **elevated** PowerShell prompt (right-click → *Run as administrator*).

### Step 1 — Turn off Secure Boot

```powershell
Confirm-SecureBootUEFI    # must report False
```

If it reports `True`, reboot into UEFI/BIOS setup and disable Secure Boot. With Secure Boot on, step 3
fails with *"The value is protected by Secure Boot policy"*. On legacy BIOS machines the cmdlet throws
"not supported on this platform", which means Secure Boot is not in play — carry on.

### Step 2 — Turn off Memory Integrity (HVCI)

Windows Security → *Device security* → *Core isolation* → turn **Memory integrity** off, or:

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
    /v Enabled /t REG_DWORD /d 0 /f
```

HVCI enforces a stricter signing policy that test-signed drivers do not satisfy. A reboot is required.

### Step 3 — Enable test signing

```powershell
bcdedit /set testsigning on
bcdedit /enum "{current}" | Select-String testsigning   # should say Yes
```

Reboot. Windows will show a "Test Mode" watermark on the desktop from now on.

### Step 4 — Trust the signing certificate

This is the step people miss. Which certificate you trust depends on how the build was signed — check it:

```powershell
Get-AuthenticodeSignature .\SbieDrv.sys |
    Select-Object Status,
                  @{n='Subject';   e={$_.SignerCertificate.Subject}},
                  @{n='Thumbprint';e={$_.SignerCertificate.Thumbprint}}
```

- **`CN=<your name>`** — a persistent certificate was configured for the build (see
  [Signing your builds](#signing-your-builds)). Import it once and you are done for every future build.
- **`CN=WDKTestCert <something>`** — no persistent certificate was configured, so the driver carries the
  throwaway certificate the WDK generates on the build machine. It is **different for every build**, so
  you have to repeat this step after every update.

Either way, the certificate is embedded in the file, so you can import it straight from the driver:

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

Both stores are needed: `Root` so the chain validates, `TrustedPublisher` so the driver loads without a
trust prompt. If you have the `.cer` file to hand instead, `Import-Certificate` does the same job:

```powershell
Import-Certificate -FilePath .\SbieSigning.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath .\SbieSigning.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

### Step 5 — Install

```powershell
.\Sandboxie-Plus-x64-v1.18.2.exe
```

If you trusted the certificate in step 4 *before* installing, the installer starts the driver and service
itself and you are done.

If you installed first and only then trusted the certificate — the usual case, since that is where
`SbieDrv.sys` lands on disk — the driver failed to start during installation. Nothing is broken: the
service entries were created, they just could not load. Start them now:

```powershell
& 'C:\Program Files\Sandboxie-Plus\KmdUtil.exe' start SbieDrv
& 'C:\Program Files\Sandboxie-Plus\KmdUtil.exe' start SbieSvc
```

To get the driver on disk *before* installing, extract it in portable mode instead:

```powershell
.\Sandboxie-Plus-x64-v1.18.2.exe /PORTABLE=1 /DIR=C:\SbieExtract /VERYSILENT
```

Portable mode skips the driver and service installation entirely, so you get the files, trust the
certificate from `C:\SbieExtract\SbieDrv.sys`, then run the installer normally.

### Step 6 — Confirm it works

```powershell
sc.exe query SbieDrv     # STATE : 4  RUNNING
sc.exe query SbieSvc     # STATE : 4  RUNNING
```

Then launch Sandboxie-Plus and run something in a box. `Get-AuthenticodeSignature` reporting `Valid` for
`SbieDrv.sys` after step 4 is a good sign that the trust chain took.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Error 577` / *"Windows cannot verify the digital signature"* | Certificate not trusted, or test signing off | Redo steps 3 and 4 and reboot |
| `SBIE1103 Sandboxie driver (SbieDrv) version … failed to start` | Same as above | Same as above |
| `SBIE9153 Cannot start driver (SbieDrv)` | Same as above | Same as above |
| `bcdedit` says *"protected by Secure Boot policy"* | Secure Boot still on | Step 1 |
| Driver stops loading after a Windows update | Update re-enabled Memory Integrity, or reset the boot config | Re-check steps 2 and 3 |
| Driver stops loading after installing a new nightly | Per-build WDK certificate changed | Repeat step 4, or set up a [persistent certificate](#signing-your-builds) |
| *"Test Mode"* watermark on the desktop | Expected — test signing is on | Cosmetic; removable only by turning test signing off |

To undo everything:

```powershell
bcdedit /set testsigning off
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
    /v Enabled /t REG_DWORD /d 1 /f
```

Then re-enable Secure Boot in UEFI, uninstall Sandboxie-Plus, and remove the certificate from
`Cert:\LocalMachine\Root` and `Cert:\LocalMachine\TrustedPublisher`.

---

## Signing your builds

By default the driver keeps the throwaway `WDKTestCert` signature that the WDK generates on the CI runner.
It is regenerated on every run, so you have to re-trust it after every build. Configuring a persistent
certificate of your own means you trust it **once**.

### 1. Create a self-signed code-signing certificate

On macOS or Linux, with OpenSSL:

```bash
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out SbieSigning.cer -days 3650 -nodes \
  -subj "/CN=Sandboxie-Crack Local Build" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE"

# 3DES/SHA-1 wrapping: OpenSSL 3's AES-256 default is not always readable by Windows CryptoAPI.
openssl pkcs12 -export -out SbieSigning.pfx -inkey key.pem -in SbieSigning.cer \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
```

On Windows, with PowerShell:

```powershell
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=Sandboxie-Crack Local Build' `
    -KeyAlgorithm RSA -KeyLength 4096 `
    -KeyExportPolicy Exportable `
    -CertStoreLocation Cert:\CurrentUser\My `
    -NotAfter (Get-Date).AddYears(10)

$pw = Read-Host -AsSecureString 'PFX password'
Export-PfxCertificate -Cert $cert -FilePath .\SbieSigning.pfx -Password $pw
Export-Certificate    -Cert $cert -FilePath .\SbieSigning.cer
```

### 2. Add it to the repository secrets

```bash
base64 -i SbieSigning.pfx | tr -d '\n' | gh secret set SIGN_CERT_PFX --repo <owner>/<repo>
gh secret set SIGN_CERT_PASSWORD --repo <owner>/<repo>    # paste the PFX password
```

On Windows:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('.\SbieSigning.pfx')) | Set-Content .\pfx.b64 -NoNewline
gh secret set SIGN_CERT_PFX --repo <owner>/<repo> < .\pfx.b64
gh secret set SIGN_CERT_PASSWORD --repo <owner>/<repo>
Remove-Item .\pfx.b64
```

Keep `SbieSigning.pfx` and `key.pem` out of the repository — they are the private key.

### 3. Trust it on the machines you install on

```powershell
Import-Certificate -FilePath .\SbieSigning.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath .\SbieSigning.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

From the next build onwards the release workflow signs `SbieDrv.sys` and both installers with this
certificate, and step 4 of the installation never has to be repeated. The release notes list the
certificate subject and SHA-1 thumbprint so you can confirm which one a given build used.

If the secrets are absent the workflow simply skips signing and says so in the log — nothing breaks.

---

## How releases are built

Two workflows, and the second never recompiles anything:

```
push to master
  └─ .github/workflows/main.yml  ("CI")
       ├─ Build_x64_Qt6    → artifacts: Sandboxie_x64, Assets
       └─ Build_ARM64_Qt6  → artifact:  Sandboxie_ARM64
             │
             └─ on success, workflow_run triggers
                  .github/workflows/release.yml  ("Release")
                    ├─ downloads those artifacts
                    ├─ signs SbieDrv.sys (if a certificate is configured)
                    ├─ compiles the installers with Inno Setup 6.3.3
                    ├─ signs the installers
                    └─ publishes them to the rolling `nightly` release
```

`Release` can also be run by hand from the Actions tab, or:

```bash
# package the latest successful CI run into the nightly release
gh workflow run release.yml --repo <owner>/<repo> --ref master

# package a specific CI run under a permanent tag
gh workflow run release.yml --repo <owner>/<repo> --ref master \
    -f run_id=32264345434 -f tag=v1.18.2
```

Passing a `tag` other than `nightly` produces a normal release instead of a rolling pre-release.

The installer is compiled from `Installer/Sandboxie-Plus.iss`, with two directives disabled in a working
copy of the script (the file in the repository is never modified):

- `SignTool=sha256` — removed, because this pipeline signs with `signtool` directly rather than through
  Inno Setup.
- The optional *Install ImDisk 3.0* task — removed, because `imdisk_files.cab` and `imdisk_install.bat`
  are third-party files that this repository does not produce. If they are ever added next to the `.iss`,
  the workflow detects them and keeps the task enabled.

---

## Known limitations

- **The in-app updater does not work.** `Sandboxie/common/verify.c` validates a sidecar `.sig` file against
  a public key hardcoded in the source, so only builds signed with the upstream project's private key pass.
  Update by downloading a new installer.
- **No ImDisk 3.0 task**, as described above. Encrypted/RAM boxes that rely on ImBox still work.
- **Test Mode watermark** stays on the desktop while test signing is enabled.
- **Reduced platform security.** Secure Boot and HVCI protect against real attacks; turning them off to run
  a self-signed kernel driver is a genuine trade-off. Do this on a machine where that is acceptable.

---

## Building from source

Windows-only. See [`AGENTS.md`](./AGENTS.md) for the repository layout, and treat
[`.github/workflows/main.yml`](./.github/workflows/main.yml) as the authoritative build reference —
the per-component `ReadMe.md` files lag behind the current toolchain.

In short: MSBuild plus the Windows SDK and WDK for the core (`Sandboxie/SandboxDll.sln`,
`Sandboxie/Sandbox.sln`, `Sandboxie/SandboxDrv.sln`), qmake and Jom via
`SandboxiePlus/qmake_plus.cmd` for the Qt UI, and `SandboxieTools/SandboxieTools.sln` for the tools.
Dependency versions live in [`Installer/buildVariables.cmd`](./Installer/buildVariables.cmd).

Note that building the project does **not** produce an installer: `Installer/copy_build.cmd` only
assembles the binaries into `Installer/SbiePlus_x64`. Packaging happens in the `Release` workflow, which
is the tested path — run it by hand as shown above rather than driving `ISCC.exe` yourself.

---

## Licensing and credits

All application code, and all credit for it, belongs to the upstream project and its contributors —
originally Ronen Tzur, then Invincea and Sophos, and since April 2020 the community fork led by
David Xanatos. See upstream's
[README](https://github.com/sandboxie-plus/Sandboxie/blob/master/README.md) for the full contributor,
translator and sponsor lists.

Dual-licensed, unchanged from upstream: [`LICENSE.Classic`](./LICENSE.Classic) (GPLv3) and
[`LICENSE.Plus`](./LICENSE.Plus) (custom). Individual components carry their own licenses — see
[`AGENTS.md`](./AGENTS.md#licensing) for the full list. Do not mix, remove or alter the copyright and
license headers.

Security issues in Sandboxie itself should be reported upstream following
[`SECURITY.md`](./SECURITY.md), never in a public issue.
