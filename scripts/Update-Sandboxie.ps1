#Requires -Version 5.1
<#
.SYNOPSIS
    Updates Sandboxie-Plus from the latest release of this fork, like "winget upgrade".

.EXAMPLE
    .\Update-Sandboxie.ps1 -CheckOnly    # report only, no elevation needed
.EXAMPLE
    .\Update-Sandboxie.ps1 -Yes          # update without asking, from an elevated prompt
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Yes,
    [switch]$TrustNewSigner,
    [string]$Repo = 'Fly-elf/Sandboxie-Crack'
)

$ErrorActionPreference = 'Stop'

# Inno Setup uninstall entry (DisplayVersion, InstallLocation), $null when Sandboxie-Plus is not installed.
function Get-InstallEntry {
    $key = 'Microsoft\Windows\CurrentVersion\Uninstall\Sandboxie-Plus_is1'
    foreach ($path in "HKLM:\SOFTWARE\$key", "HKLM:\SOFTWARE\WOW6432Node\$key") {
        if (Test-Path $path) { return Get-ItemProperty $path }
    }
    return $null
}

# Architecture of the machine, not of this PowerShell process: 'x64' or 'arm64'.
function Get-NativeArch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { throw "Unsupported architecture: $arch" }
    }
}

# Latest stable release as returned by the GitHub API; pre-releases such as nightly are skipped.
function Get-LatestRelease([string]$Repo) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -UserAgent 'Update-Sandboxie'
    }
    catch {
        throw "Could not query the latest release of ${Repo}: $($_.Exception.Message)"
    }
}

function Assert-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $admin    = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole($admin)) {
        throw 'Run this script from an elevated PowerShell (right-click, Run as administrator).'
    }
}

# The progress bar makes Invoke-WebRequest several times slower in Windows PowerShell 5.1.
function Save-File([string]$Url, [string]$Path) {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $Url -OutFile $Path -UserAgent 'Update-Sandboxie' -UseBasicParsing
}

# Checks the installer against SHA256SUMS.txt, then against the certificate that signed the installed driver.
# The hash only catches a damaged download; the signer is what ties the update to the build already trusted here.
function Assert-InstallerTrusted([string]$File, [string]$SumsFile, [string]$InstallDir) {
    $name     = Split-Path $File -Leaf
    $line     = Get-Content $SumsFile | Where-Object { $_ -match "\s$([regex]::Escape($name))$" } | Select-Object -First 1
    if (-not $line) { throw "$name is not listed in SHA256SUMS.txt." }
    if ((Get-FileHash $File -Algorithm SHA256).Hash -ne ($line -split '\s+')[0]) {
        throw "SHA-256 mismatch for $name, the download is damaged."
    }

    $signature = Get-AuthenticodeSignature $File
    if ($signature.Status -eq 'HashMismatch' -or -not $signature.SignerCertificate) {
        throw "$name has no intact signature ($($signature.Status))."
    }

    $driver = Get-AuthenticodeSignature (Join-Path $InstallDir 'SbieDrv.sys')
    $known  = $driver.SignerCertificate
    if ($known -and $known.Thumbprint -ne $signature.SignerCertificate.Thumbprint -and -not $TrustNewSigner) {
        $subject = $signature.SignerCertificate.Subject
        throw "$name is signed by a different certificate than the installed driver ($subject). Use -TrustNewSigner if it was replaced on purpose."
    }
}

$entry = Get-InstallEntry
if (-not $entry) { throw 'Sandboxie-Plus is not installed. Follow the install steps in the README first.' }

$installed  = [version]$entry.DisplayVersion
$installDir = $entry.InstallLocation
if (-not $installDir -or -not (Test-Path $installDir)) { throw 'Could not locate the Sandboxie-Plus install directory.' }

$release = Get-LatestRelease $Repo
$latest  = [version]($release.tag_name -replace '^v', '')

if ($latest -le $installed) {
    Write-Host "Sandboxie-Plus $installed is up to date."
    return
}

Write-Host "Sandboxie-Plus $installed -> $latest available: $($release.html_url)"
if ($CheckOnly) { return }

Assert-Elevated

$arch      = Get-NativeArch
$installer = $release.assets | Where-Object { $_.name -like "Sandboxie-Plus-$arch-v*.exe" } | Select-Object -First 1
$sums      = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
if (-not $installer) { throw "Release $($release.tag_name) has no $arch installer." }
if (-not $sums)      { throw "Release $($release.tag_name) has no SHA256SUMS.txt." }

if (-not $Yes) {
    $answer = Read-Host "Install $latest now? Sandboxed programs will be terminated and SandMan closed [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'Cancelled.'
        return
    }
}

$temp = Join-Path $env:TEMP "Update-Sandboxie-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $installerFile = Join-Path $temp $installer.name
    $sumsFile      = Join-Path $temp $sums.name

    Write-Host "Downloading $($installer.name)..."
    Save-File $installer.browser_download_url $installerFile
    Save-File $sums.browser_download_url $sumsFile
    Assert-InstallerTrusted $installerFile $sumsFile $installDir

    $sandMan = @(Get-Process SandMan -ErrorAction SilentlyContinue)
    Start-Process (Join-Path $installDir 'Start.exe') '/terminate_all' -Wait
    foreach ($process in $sandMan | Where-Object { -not $_.HasExited }) {
        [void]$process.CloseMainWindow()
        if (-not $process.WaitForExit(5000)) { $process.Kill() }
    }

    $arguments = '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
    if ($sandMan) { $arguments += '/open_agent=1' }

    Write-Host 'Installing...'
    $setup = Start-Process $installerFile $arguments -Wait -PassThru
    if ($setup.ExitCode -ne 0) { throw "The installer failed with exit code $($setup.ExitCode)." }

    Write-Host "Updated Sandboxie-Plus $installed -> $((Get-InstallEntry).DisplayVersion)."
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
