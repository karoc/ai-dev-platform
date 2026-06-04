@echo off
REM ADP-OS CLI Wrapper
REM Place this file in PATH or the project root, then run "adp <command>" instead of ".\cli\adp.ps1 <command>"

REM --version needs -Command mode (PowerShell 5.1 -File does not pass it through correctly)
if /i "%~1"=="--version" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cli\adp.ps1' --version"
    exit /b %ERRORLEVEL%
)

powershell.exe -ExecutionPolicy Bypass -File "%~dp0cli\adp.ps1" %*
