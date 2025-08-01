@echo off
setlocal enabledelayedexpansion

REM ========================================================================
REM Sandboxie-Plus Installer Creation Script
REM ========================================================================
REM This script downloads artifacts from GitHub Actions and creates installers
REM 
REM Usage:
REM   create_installer.cmd [version] [run_id]
REM 
REM Parameters:
REM   version  - Version number (e.g., 1.14.9) - optional
REM   run_id   - GitHub Actions run ID - optional (uses latest if not provided)
REM
REM Requirements:
REM   - Windows with PowerShell
REM   - Inno Setup 6.3.3 installed
REM   - GitHub CLI (gh) installed and authenticated
REM ========================================================================

echo.
echo ========================================================================
echo Sandboxie-Plus Installer Creator
echo ========================================================================
echo.

REM Set default values
set "DEFAULT_VERSION=1.14.9"
set "REPO=Fly-elf/Sandboxie-Crack"
set "WORKFLOW=main.yml"

REM Parse arguments
if "%~1"=="" (
    set "VERSION=%DEFAULT_VERSION%"
) else (
    set "VERSION=%~1"
)

if "%~2"=="" (
    set "RUN_ID="
) else (
    set "RUN_ID=%~2"
)

echo Version: %VERSION%
if defined RUN_ID (
    echo Run ID: %RUN_ID%
) else (
    echo Run ID: [Will use latest successful run]
)
echo.

REM Check prerequisites
echo Checking prerequisites...

REM Check if gh CLI is installed
gh --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: GitHub CLI not found. Please install it from: https://cli.github.com/
    echo        And authenticate with: gh auth login
    pause
    exit /b 1
)

REM Check if Inno Setup is installed
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
) else (
    echo ERROR: Inno Setup 6 not found. Please install it from: https://jrsoftware.org/isdl.php
    pause
    exit /b 1
)

echo ✓ GitHub CLI found
echo ✓ Inno Setup found at: %ISCC%
echo.

REM Get run ID if not provided
if not defined RUN_ID (
    echo Getting latest successful workflow run...
    for /f "tokens=*" %%a in ('gh run list --repo %REPO% --workflow %WORKFLOW% --status success --limit 1 --json databaseId --jq ".[0].databaseId"') do set "RUN_ID=%%a"
    
    if not defined RUN_ID (
        echo ERROR: No successful workflow runs found
        pause
        exit /b 1
    )
    
    echo ✓ Found run ID: %RUN_ID%
)
echo.

REM Create directories
echo Setting up directories...
if exist "temp_installer" rmdir /s /q "temp_installer"
mkdir "temp_installer"
mkdir "temp_installer\SbiePlus_x64"
mkdir "temp_installer\SbiePlus_a64"
mkdir "temp_installer\Assets"
mkdir "temp_installer\Release"

echo ✓ Directories created
echo.

REM Download artifacts
echo Downloading artifacts from run %RUN_ID%...

echo - Downloading Sandboxie_x64...
gh run download %RUN_ID% --repo %REPO% --name Sandboxie_x64 --dir "temp_installer\SbiePlus_x64"
if errorlevel 1 (
    echo ERROR: Failed to download Sandboxie_x64 artifact
    goto cleanup
)

echo - Downloading Assets...
gh run download %RUN_ID% --repo %REPO% --name Assets --dir "temp_installer\Assets"
if errorlevel 1 (
    echo ERROR: Failed to download Assets artifact
    goto cleanup
)

echo - Downloading Sandboxie_ARM64 (optional)...
gh run download %RUN_ID% --repo %REPO% --name Sandboxie_ARM64 --dir "temp_installer\SbiePlus_a64" 2>nul
if errorlevel 1 (
    echo   (ARM64 artifacts not found, will skip ARM64 installer)
    set "SKIP_ARM64=1"
) else (
    echo ✓ ARM64 artifacts downloaded
    set "SKIP_ARM64="
)

echo ✓ Artifacts downloaded
echo.

REM Copy necessary files
echo Preparing installer files...
copy "Installer\Sandboxie-Plus.iss" "temp_installer\"
copy "Installer\Languages.iss" "temp_installer\"
copy "temp_installer\Assets\*" "temp_installer\"

echo ✓ Files prepared
echo.

REM Create x64 installer
echo Creating x64 installer...
cd temp_installer
"%ISCC%" "Sandboxie-Plus.iss" /DMyAppVersion=%VERSION% /DMyAppArch=x64 /DMyAppSrc=SbiePlus_x64 /ORelease
if errorlevel 1 (
    echo ERROR: Failed to create x64 installer
    cd ..
    goto cleanup
)
cd ..

echo ✓ x64 installer created

REM Create ARM64 installer (if artifacts available)
if not defined SKIP_ARM64 (
    echo Creating ARM64 installer...
    cd temp_installer
    "%ISCC%" "Sandboxie-Plus.iss" /DMyAppVersion=%VERSION% /DMyAppArch=arm64 /DMyAppSrc=SbiePlus_a64 /ORelease
    if errorlevel 1 (
        echo WARNING: Failed to create ARM64 installer
    ) else (
        echo ✓ ARM64 installer created
    )
    cd ..
)

REM Copy installers to final location
echo.
echo Copying installers to Installer\Release\...
if not exist "Installer\Release" mkdir "Installer\Release"
copy "temp_installer\Release\*.exe" "Installer\Release\"

REM Show results
echo.
echo ========================================================================
echo INSTALLERS CREATED SUCCESSFULLY!
echo ========================================================================
dir "Installer\Release\*.exe" /b
echo.
echo Location: %CD%\Installer\Release\
echo.

:cleanup
if exist "temp_installer" (
    echo Cleaning up temporary files...
    rmdir /s /q "temp_installer"
)

echo.
echo Press any key to exit...
pause >nul
