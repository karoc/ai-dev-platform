# ADP-OS setup command.
# Delegates to the stock one-click setup script.

[CmdletBinding()]
param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$NoRegisterCommand,
    [switch]$Plan
)

$setupScript = Join-Path (Get-ProjectRoot) "setup.ps1"
$setupArgs = @()
if ($Distro -and $Distro -ne "ubuntu") { $setupArgs += @("-Distro", $Distro) }
if ($IsoPath) { $setupArgs += @("-IsoPath", $IsoPath) }
if ($SkipIsoDownload) { $setupArgs += "-SkipIsoDownload" }
if ($SkipDoctor) { $setupArgs += "-SkipDoctor" }
if ($NonInteractive) { $setupArgs += "-NonInteractive" }
if ($Force) { $setupArgs += "-Force" }
if ($NoRegisterCommand) { $setupArgs += "-NoRegisterCommand" }
if ($Plan) { $setupArgs += "-Plan" }

& $setupScript @setupArgs
exit $LASTEXITCODE
