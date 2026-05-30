# ADP-OS local configuration boundary checks
# Ensures diagnostic and preview commands do not mutate user-owned configs/local.json.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function New-BoundarySandbox {
    $sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-local-config-boundary-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

    $trackedFiles = & git -C $projectRoot ls-files
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while preparing local config boundary sandbox."
    }

    foreach ($relativePath in $trackedFiles) {
        $source = Join-Path $projectRoot $relativePath
        $target = Join-Path $sandboxRoot $relativePath
        $targetDirectory = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    return $sandboxRoot
}

function Write-SentinelLocalConfig {
    param([string]$SandboxRoot)

    $stateRoot = Join-Path $SandboxRoot ".adp-boundary-state"
    $localConfig = [ordered]@{
        platform = [ordered]@{
            boundary_sentinel = "preserve-platform-field"
            paths = [ordered]@{
                workspace_root = Join-Path $stateRoot "workspaces"
                iso_cache      = Join-Path $stateRoot "iso"
                vm_store       = Join-Path $stateRoot "vms"
            }
            defaults = [ordered]@{
                ubuntu_iso = "missing-boundary.iso"
            }
            network = [ordered]@{
                mode = "static"
                vmware_nat = [ordered]@{
                    cidr            = "203.0.113.0/24"
                    prefix          = 24
                    gateway         = "203.0.113.2"
                    dns             = @("203.0.113.2", "1.1.1.1")
                    interface_match = "en*"
                }
            }
        }
        topology = [ordered]@{
            frontend = [ordered]@{
                static_ip = "203.0.113.131"
            }
            backend = [ordered]@{
                static_ip = "203.0.113.133"
            }
            agent = [ordered]@{
                static_ip = "203.0.113.135"
                boundary_sentinel = "preserve-runtime-field"
            }
        }
    }

    $localPath = Join-Path $SandboxRoot "configs\local.json"
    $localConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $localPath -Encoding utf8
    return $localPath
}

function Invoke-BoundaryCommand {
    param(
        [string]$SandboxRoot,
        [string]$UserProfile,
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
        $process = Start-Process -FilePath "pwsh" `
            -ArgumentList $processArguments `
            -WorkingDirectory $SandboxRoot `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -Environment @{ USERPROFILE = $UserProfile; HOME = $UserProfile }

        $outText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = "$outText`n$errText"
        }
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Assert-LocalConfigUnchanged {
    param(
        [string]$Name,
        [string]$SandboxRoot,
        [string]$LocalConfigPath,
        [string]$BeforeHash,
        [object]$Result,
        [int[]]$AllowedExitCodes
    )

    if ($AllowedExitCodes -notcontains $Result.ExitCode) {
        throw "$Name exit code was $($Result.ExitCode), expected one of: $($AllowedExitCodes -join ', ').`n$($Result.Output)"
    }

    $afterHash = (Get-FileHash -LiteralPath $LocalConfigPath -Algorithm SHA256).Hash
    if ($afterHash -ne $BeforeHash) {
        throw "$Name changed configs/local.json.`n$($Result.Output)"
    }

    $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $SandboxRoot "configs") -Filter "local.json.bak*" -File -ErrorAction SilentlyContinue)
    if ($backupFiles.Count -gt 0) {
        throw "$Name created local config backup files without explicit apply: $($backupFiles.Name -join ', ').`n$($Result.Output)"
    }
}

function Assert-CommandDoesNotMutateLocalConfig {
    param(
        [string]$Name,
        [string]$SandboxRoot,
        [string]$UserProfile,
        [string]$ScriptPath,
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $localConfigPath = Join-Path $SandboxRoot "configs\local.json"
    $beforeHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash
    $result = Invoke-BoundaryCommand -SandboxRoot $SandboxRoot -UserProfile $UserProfile -ScriptPath $ScriptPath -Arguments $Arguments
    Assert-LocalConfigUnchanged -Name $Name -SandboxRoot $SandboxRoot -LocalConfigPath $localConfigPath -BeforeHash $beforeHash -Result $result -AllowedExitCodes $AllowedExitCodes
}

$sandboxRoot = New-BoundarySandbox
$userProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-local-config-boundary-home-{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Path $userProfile -Force | Out-Null

try {
    Write-SentinelLocalConfig -SandboxRoot $sandboxRoot | Out-Null

    $installScript = Join-Path $sandboxRoot "install.ps1"
    $cliScript = Join-Path $sandboxRoot "cli\adp.ps1"

    $commands = @(
        [pscustomobject]@{
            Name = "install skip checks"
            Script = $installScript
            Arguments = @("-SkipDependencyCheck", "-SkipVMValidation")
            AllowedExitCodes = @(0)
        }
        [pscustomobject]@{
            Name = "init without runtime"
            Script = $cliScript
            Arguments = @("init")
            AllowedExitCodes = @(0, 1)
        }
        [pscustomobject]@{
            Name = "doctor first run"
            Script = $cliScript
            Arguments = @("doctor", "-FirstRun")
            AllowedExitCodes = @(0, 1)
        }
        [pscustomobject]@{
            Name = "status all runtimes"
            Script = $cliScript
            Arguments = @("status")
            AllowedExitCodes = @(0, 1)
        }
        [pscustomobject]@{
            Name = "up plan"
            Script = $cliScript
            Arguments = @("up", "agent", "-Plan", "-IsoPath", "Z:\adp-boundary\missing.iso")
            AllowedExitCodes = @(0)
        }
        [pscustomobject]@{
            Name = "up create preflight failure"
            Script = $cliScript
            Arguments = @("up", "agent", "-IsoPath", "Z:\adp-boundary\missing.iso")
            AllowedExitCodes = @(1)
        }
        [pscustomobject]@{
            Name = "network configure-local plan"
            Script = $cliScript
            Arguments = @("network", "configure-local", "-Plan")
            AllowedExitCodes = @(0, 1)
        }
        [pscustomobject]@{
            Name = "network configure-local default"
            Script = $cliScript
            Arguments = @("network", "configure-local")
            AllowedExitCodes = @(0, 1)
        }
        [pscustomobject]@{
            Name = "network apply plan without VM"
            Script = $cliScript
            Arguments = @("network", "apply", "agent", "-Plan")
            AllowedExitCodes = @(1)
        }
    )

    foreach ($command in $commands) {
        Assert-CommandDoesNotMutateLocalConfig `
            -Name $command.Name `
            -SandboxRoot $sandboxRoot `
            -UserProfile $userProfile `
            -ScriptPath $command.Script `
            -Arguments $command.Arguments `
            -AllowedExitCodes $command.AllowedExitCodes
    }
} finally {
    $tempRoot = [System.IO.Path]::GetTempPath()
    foreach ($path in @($sandboxRoot, $userProfile)) {
        if ($path -and (Test-Path -LiteralPath $path) -and [System.IO.Path]::GetFullPath($path).StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Output "Local config boundary checks OK"
