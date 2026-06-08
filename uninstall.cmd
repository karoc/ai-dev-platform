@echo off
REM ADP-OS uninstall wrapper for stock Windows shells.
REM Removes the user-level adpos command registration. It does not delete VMs or workspaces.

setlocal

set "PWSH="
set "WINPS="
set "UNINSTALL_ARGS=%*"
if /i "%~1"=="uninstall" set "UNINSTALL_ARGS=%2 %3 %4 %5 %6 %7 %8 %9"

for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do (
    if not defined PWSH call :UsePowerShell7 "%%P"
)

if not defined PWSH call :UsePowerShell7 "%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH call :UsePowerShell7 "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
if not defined PWSH call :UsePowerShell7 "%LocalAppData%\Programs\PowerShell\7\pwsh.exe"
if not defined PWSH call :UsePowerShell7 "%UserProfile%\AppData\Local\Microsoft\WindowsApps\pwsh.exe"

if not defined PWSH goto UseWindowsPowerShellFallback

"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %UNINSTALL_ARGS%
exit /b %ERRORLEVEL%

:UseWindowsPowerShellFallback
set "WINPS_CANDIDATE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%WINPS_CANDIDATE%" set "WINPS=%WINPS_CANDIDATE%"
if not defined WINPS (
    for /f "delims=" %%P in ('where powershell.exe 2^>nul') do (
        if not defined WINPS if exist "%%P" set "WINPS=%%P"
    )
)
if not defined WINPS goto NoWindowsPowerShellFallback
"%WINPS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %UNINSTALL_ARGS%
exit /b %ERRORLEVEL%

:NoWindowsPowerShellFallback
echo ADP-OS uninstall needs Windows PowerShell 5.1 or PowerShell 7.
echo No VM, workspace, ISO cache, tool, log, or repository file was removed.
exit /b 1

:UsePowerShell7
if not exist "%~1" exit /b 0
"%~1" -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }" >nul 2>nul
if not errorlevel 1 set "PWSH=%~1"
exit /b 0
