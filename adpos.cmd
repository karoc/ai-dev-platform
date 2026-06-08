@echo off
REM ADP-OS CLI Wrapper
REM Preferred user-facing command. Run from the project root before setup registers global adpos.

setlocal

set "PWSH="
for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do (
    if not defined PWSH call :UsePowerShell7 "%%P"
)

if not defined PWSH call :UsePowerShell7 "%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH call :UsePowerShell7 "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
if not defined PWSH call :UsePowerShell7 "%LocalAppData%\Programs\PowerShell\7\pwsh.exe"
if not defined PWSH call :UsePowerShell7 "%UserProfile%\AppData\Local\Microsoft\WindowsApps\pwsh.exe"

if not defined PWSH (
    if /i "%~1"=="uninstall" (
        if exist "%~dp0uninstall.cmd" (
            call "%~dp0uninstall.cmd" %2 %3 %4 %5 %6 %7 %8 %9
            exit /b %ERRORLEVEL%
        )
    )
    echo ADP-OS requires PowerShell 7+ ^(pwsh.exe^).
    echo Install it, then rerun this command:
    echo   winget install --id Microsoft.PowerShell --source winget
    echo Or download the MSI from:
    echo   https://github.com/PowerShell/PowerShell/releases
    echo.
    echo Built-in Windows PowerShell 5.1 cannot run the ADP-OS control plane.
    exit /b 1
)

REM --version needs -Command mode because PowerShell treats --version as a native pwsh flag in -File mode.
if /i "%~1"=="--version" (
    "%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cli\adp.ps1' --version"
    exit /b %ERRORLEVEL%
)

"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0cli\adp.ps1" %*
exit /b %ERRORLEVEL%

:UsePowerShell7
if not exist "%~1" exit /b 0
"%~1" -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }" >nul 2>nul
if not errorlevel 1 set "PWSH=%~1"
exit /b 0
