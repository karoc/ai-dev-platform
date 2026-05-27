# ADP-OS Logging Module
# Structured logging with log levels and file rotation

$script:LogDir = $null
$script:LogLevel = "INFO"

$script:LogLevels = @{
    "DEBUG" = 0
    "INFO"  = 1
    "WARN"  = 2
    "ERROR" = 3
}

function Initialize-Logging {
    param(
        [string]$LogDirectory,
        [string]$Level = "INFO"
    )

    $script:LogDir = $LogDirectory
    $script:LogLevel = $Level

    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
}

function Write-Log {
    param(
        [string]$Level = "INFO",
        [string]$Message,
        [string]$Component = "core"
    )

    $levels = if ($script:LogLevels) {
        $script:LogLevels
    } else {
        @{
            "DEBUG" = 0
            "INFO"  = 1
            "WARN"  = 2
            "ERROR" = 3
        }
    }
    $effectiveLogLevel = if ($script:LogLevel) { $script:LogLevel } else { "INFO" }
    $currentLevel = $levels[$effectiveLogLevel]
    $msgLevel = $levels[$Level]

    if ($msgLevel -lt $currentLevel) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $formatted = "[$timestamp] [$Level] [$Component] $Message"

    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "White" }
        "DEBUG" { "Gray" }
        default { "White" }
    }

    Write-Host $formatted -ForegroundColor $color

    if ($script:LogDir) {
        $logFile = Join-Path $script:LogDir "adp-$(Get-Date -Format 'yyyy-MM-dd').log"
        Add-Content -Path $logFile -Value $formatted
    }
}

function Write-DebugLog { Write-Log -Level "DEBUG" @args }
function Write-InfoLog  { Write-Log -Level "INFO"  @args }
function Write-WarnLog  { Write-Log -Level "WARN"  @args }
function Write-ErrorLog { Write-Log -Level "ERROR" @args }
