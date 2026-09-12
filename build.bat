@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT=%CD%"
set "BUILD_DIR=%ROOT%\build"
set "LOG=%BUILD_DIR%\windows-build.log"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

>"%LOG%" echo NoqeriOS Windows build started %DATE% %TIME%

echo [NoqeriOS] Checking Windows/WSL build environment...

:detect_wsl
where wsl.exe >nul 2>&1
if errorlevel 1 goto install_wsl_package

set "WSL_DISTRO="
for /f "usebackq delims=" %%D in (`wsl.exe -l -q 2^>nul`) do (
    if not defined WSL_DISTRO set "WSL_DISTRO=%%D"
)

if not defined WSL_DISTRO goto install_ubuntu
goto run_build

:install_wsl_package
echo [NoqeriOS] WSL is missing. Attempting automatic installation...
where winget.exe >nul 2>&1
if not errorlevel 1 (
    winget install --id Microsoft.WSL --exact --accept-package-agreements --accept-source-agreements >>"%LOG%" 2>&1
)

where wsl.exe >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command','dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart; dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart'" >>"%LOG%" 2>&1
)

where wsl.exe >nul 2>&1
if errorlevel 1 (
    set "FAIL_MESSAGE=WSL could not be installed automatically. Windows may require a reboot after enabling WSL and Virtual Machine Platform. Reboot, then run build.bat again."
    goto fail
)
goto detect_wsl

:install_ubuntu
echo [NoqeriOS] No WSL Linux distribution found. Installing Ubuntu...
wsl.exe --install -d Ubuntu --no-launch >>"%LOG%" 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-Process wsl.exe -Verb RunAs -Wait -ArgumentList '--install','-d','Ubuntu','--no-launch'" >>"%LOG%" 2>&1
)

set "WSL_DISTRO="
for /f "usebackq delims=" %%D in (`wsl.exe -l -q 2^>nul`) do (
    if not defined WSL_DISTRO set "WSL_DISTRO=%%D"
)
if not defined WSL_DISTRO (
    set "FAIL_MESSAGE=Ubuntu installation was requested, but WSL does not report an installed distribution yet. A Windows reboot may be required. Reboot and run build.bat again."
    goto fail
)

:run_build
echo [NoqeriOS] Using WSL distribution: %WSL_DISTRO%
set "WSL_ROOT="
for /f "usebackq delims=" %%P in (`wsl.exe -d "%WSL_DISTRO%" -u root -- wslpath -u "%ROOT%" 2^>nul`) do (
    if not defined WSL_ROOT set "WSL_ROOT=%%P"
)
if not defined WSL_ROOT (
    set "FAIL_MESSAGE=Could not translate the repository path into WSL. See the build log for details."
    goto fail
)

echo [NoqeriOS] Missing Linux build tools will be installed automatically.
echo [NoqeriOS] Building through C/C++ host tools + the Noqeri compiler...
wsl.exe -d "%WSL_DISTRO%" -u root -- bash -lc "cd '%WSL_ROOT%' && bash ./build.sh --bootstrap" >>"%LOG%" 2>&1
if errorlevel 1 (
    set "FAIL_MESSAGE=The Linux/WSL build failed. The last build messages are shown in the error box and the full log is in build\windows-build.log."
    goto fail
)

if not exist "%BUILD_DIR%\noqerios.iso" (
    set "FAIL_MESSAGE=The build command completed but build\noqerios.iso was not created."
    goto fail
)

echo.
echo [NoqeriOS] SUCCESS
echo ISO: "%BUILD_DIR%\noqerios.iso"
echo Log: "%LOG%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('NoqeriOS ISO built successfully.'+[Environment]::NewLine+[Environment]::NewLine+'%BUILD_DIR%\noqerios.iso','NoqeriOS Build','OK','Information')" >nul 2>&1
exit /b 0

:fail
if not defined FAIL_MESSAGE set "FAIL_MESSAGE=NoqeriOS build failed."
echo.
echo [NoqeriOS] ERROR: !FAIL_MESSAGE!
echo Full log: "%LOG%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$log='%LOG%'; $tail=''; if (Test-Path $log) { $tail=(Get-Content -Path $log -Tail 30 -ErrorAction SilentlyContinue) -join [Environment]::NewLine }; Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('!FAIL_MESSAGE!'+[Environment]::NewLine+[Environment]::NewLine+$tail+[Environment]::NewLine+[Environment]::NewLine+'Full log: %LOG%','NoqeriOS Build Error','OK','Error')" >nul 2>&1
echo.
echo The window will stay open so the error can be read.
pause
exit /b 1
