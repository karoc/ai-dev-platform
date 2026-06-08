# ADP-OS isolate apply contract checks.
# Ensures checkout isolation apply writes only ignored local config overrides.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Get-TestPwshPath {
    $processPath = try { (Get-Process -Id $PID).Path } catch { $null }
    if ($processPath) {
        return $processPath
    }

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCommand) {
        return $pwshCommand.Source
    }

    $pwshExeCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwshExeCommand) {
        return $pwshExeCommand.Source
    }

    throw "Cannot resolve pwsh executable path for isolate apply contract checks."
}

function New-IsolateApplySandbox {
    $sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-isolate-apply-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

    $trackedFiles = & git -C $projectRoot ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while preparing isolate apply sandbox."
    }

    foreach ($relativePath in $trackedFiles) {
        $source = Join-Path $projectRoot $relativePath
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }

        $target = Join-Path $sandboxRoot $relativePath
        $targetDirectory = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    return $sandboxRoot
}

function Invoke-SandboxAdpos {
    param(
        [string]$SandboxRoot,
        [string[]]$Arguments
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $SandboxRoot "cli\adp.ps1")) + $Arguments
        $process = Start-Process -FilePath (Get-TestPwshPath) `
            -ArgumentList $processArguments `
            -WorkingDirectory $SandboxRoot `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        $outText = Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = "$outText`n$errText"
        }
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Write-ExistingLocalConfig {
    param([string]$SandboxRoot)

    $localConfig = [ordered]@{
        platform = [ordered]@{
            boundary_sentinel = "preserve-platform-field"
            runtime_namespace = "old"
            paths = [ordered]@{
                workspace_root = "D:\old\workspaces"
                iso_cache      = "D:\old\iso"
                vm_store       = "D:\old\vms"
            }
            defaults = [ordered]@{
                admin_user = "keep-user"
            }
            provider = [ordered]@{
                config = [ordered]@{
                    vm_store = "D:\old\vms"
                    vmrun_path = "D:\tools\vmrun.exe"
                }
            }
        }
        topology = [ordered]@{
            agent = [ordered]@{
                memory = 24576
                boundary_sentinel = "preserve-runtime-field"
                static_ip = "192.168.242.201"
            }
        }
        sync_profiles = [ordered]@{
            agent = [ordered]@{
                ignore = @("keep-me")
            }
        }
        unsupported_section = [ordered]@{
            keep = "keep-unsupported"
        }
    }

    $localPath = Join-Path $SandboxRoot "configs\local.json"
    $localConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $localPath -Encoding utf8
    return $localPath
}

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name did not contain expected pattern: $Pattern`nOutput:`n$Text"
    }
}

function Assert-ExitCode {
    param(
        [string]$Name,
        [int]$Actual,
        [int]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected exit code $Expected but got $Actual"
    }
}

function Assert-Equal {
    param(
        [string]$Name,
        $Actual,
        $Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected '$Expected' but got '$Actual'"
    }
}

function Assert-NoRuntimeVmDirectories {
    param([string]$SandboxRoot)

    $unexpected = @(
        Join-Path $SandboxRoot ".adp-boundary-state\vms\adp-v2-agent"
        Join-Path $SandboxRoot ".adp-boundary-state\vms\adp-agent"
        Join-Path $SandboxRoot "adp-v2-agent"
    ) | Where-Object { Test-Path -LiteralPath $_ }

    if ($unexpected.Count -gt 0) {
        throw "isolate -Apply created unexpected VM-looking directories: $($unexpected -join ', ')"
    }
}

function Assert-IsolatedLocalConfig {
    param([string]$LocalConfigPath)

    $config = Get-Content -LiteralPath $LocalConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal -Name "runtime namespace" -Actual $config.platform.runtime_namespace -Expected "v2"
    Assert-Equal -Name "workspace root" -Actual $config.platform.paths.workspace_root -Expected '${env:USERPROFILE}\adp-workspaces-v2'
    Assert-Equal -Name "path VM store" -Actual $config.platform.paths.vm_store -Expected '${env:USERPROFILE}\adp-vms-v2'
    Assert-Equal -Name "provider VM store" -Actual $config.platform.provider.config.vm_store -Expected '${env:USERPROFILE}\adp-vms-v2'
    Assert-Equal -Name "agent static IP" -Actual $config.topology.agent.static_ip -Expected "192.168.242.145"
    Assert-Equal -Name "frontend static IP" -Actual $config.topology.frontend.static_ip -Expected "192.168.242.141"
}

function Assert-PreservedLocalConfigFields {
    param([string]$LocalConfigPath)

    $config = Get-Content -LiteralPath $LocalConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal -Name "platform sentinel preserved" -Actual $config.platform.boundary_sentinel -Expected "preserve-platform-field"
    Assert-Equal -Name "iso cache preserved" -Actual $config.platform.paths.iso_cache -Expected "D:\old\iso"
    Assert-Equal -Name "default user preserved" -Actual $config.platform.defaults.admin_user -Expected "keep-user"
    Assert-Equal -Name "provider vmrun path preserved" -Actual $config.platform.provider.config.vmrun_path -Expected "D:\tools\vmrun.exe"
    Assert-Equal -Name "agent memory preserved" -Actual $config.topology.agent.memory -Expected 24576
    Assert-Equal -Name "sync profile preserved" -Actual $config.sync_profiles.agent.ignore[0] -Expected "keep-me"
    Assert-Equal -Name "unsupported top-level section preserved" -Actual $config.unsupported_section.keep -Expected "keep-unsupported"
}

$sandboxRoot = New-IsolateApplySandbox

try {
    $localConfigPath = Write-ExistingLocalConfig -SandboxRoot $sandboxRoot
    $initialHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash

    $conflictingModes = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments @("isolate", "-Plan", "-Apply", "-Namespace", "v2")
    $afterConflictingModesHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash
    $backupFilesAfterConflictingModes = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRoot "configs") -Filter "local.json.bak*" -File -ErrorAction SilentlyContinue)
    Assert-ExitCode -Name "isolate apply rejects plan apply combination" -Actual $conflictingModes.ExitCode -Expected 1
    Assert-Contains -Name "isolate apply conflicting mode guidance" -Text $conflictingModes.Output -Pattern "Use either -Plan or -Apply, not both"
    Assert-Equal -Name "isolate apply conflicting mode hash" -Actual $afterConflictingModesHash -Expected $initialHash
    Assert-Equal -Name "isolate apply conflicting mode backup count" -Actual $backupFilesAfterConflictingModes.Count -Expected 0

    $invalidNamespace = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments @("isolate", "-Apply", "-Namespace", "default")
    $afterInvalidNamespaceHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash
    $backupFilesAfterInvalidNamespace = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRoot "configs") -Filter "local.json.bak*" -File -ErrorAction SilentlyContinue)
    Assert-ExitCode -Name "isolate apply rejects default namespace" -Actual $invalidNamespace.ExitCode -Expected 1
    Assert-Contains -Name "isolate apply invalid namespace guidance" -Text $invalidNamespace.Output -Pattern "Use a specific namespace such as 'v2'"
    Assert-Equal -Name "isolate apply invalid namespace hash" -Actual $afterInvalidNamespaceHash -Expected $initialHash
    Assert-Equal -Name "isolate apply invalid namespace backup count" -Actual $backupFilesAfterInvalidNamespace.Count -Expected 0

    $apply = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments @("isolate", "-Apply", "-Namespace", "v2")
    Assert-ExitCode -Name "isolate apply" -Actual $apply.ExitCode -Expected 0
    Assert-Contains -Name "isolate apply updated local config" -Text $apply.Output -Pattern "Applied: updated configs\\\\local\.json"
    Assert-Contains -Name "isolate apply backup" -Text $apply.Output -Pattern "Backup:\s+.*local\.json\.bak\."
    Assert-Contains -Name "isolate apply preserved boundary" -Text $apply.Output -Pattern "Preserved: unrelated configs\\\\local\.json fields"
    Assert-Contains -Name "isolate apply host boundary" -Text $apply.Output -Pattern "Not changed: VMs, SSH aliases, sync sessions, PATH entries, or global adpos bindings"
    Assert-IsolatedLocalConfig -LocalConfigPath $localConfigPath
    Assert-PreservedLocalConfigFields -LocalConfigPath $localConfigPath

    $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRoot "configs") -Filter "local.json.bak*" -File -ErrorAction SilentlyContinue)
    Assert-Equal -Name "isolate apply backup count" -Actual $backupFiles.Count -Expected 1
    $backupHash = (Get-FileHash -LiteralPath $backupFiles[0].FullName -Algorithm SHA256).Hash
    Assert-Equal -Name "isolate apply backup content hash" -Actual $backupHash -Expected $initialHash
    Assert-NoRuntimeVmDirectories -SandboxRoot $sandboxRoot

    $beforeSecondHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash
    $second = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments @("isolate", "-Apply", "-Namespace", "v2")
    $afterSecondHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash
    $backupFilesAfterSecond = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRoot "configs") -Filter "local.json.bak*" -File -ErrorAction SilentlyContinue)
    Assert-ExitCode -Name "isolate apply idempotent" -Actual $second.ExitCode -Expected 0
    Assert-Contains -Name "isolate apply idempotent output" -Text $second.Output -Pattern "Already isolated: configs\\\\local\.json was not changed"
    Assert-Equal -Name "isolate apply idempotent hash" -Actual $afterSecondHash -Expected $beforeSecondHash
    Assert-Equal -Name "isolate apply idempotent backup count" -Actual $backupFilesAfterSecond.Count -Expected 1
} finally {
    $tempRoot = [System.IO.Path]::GetTempPath()
    if ($sandboxRoot -and (Test-Path -LiteralPath $sandboxRoot) -and [System.IO.Path]::GetFullPath($sandboxRoot).StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$missingLocalSandboxRoot = New-IsolateApplySandbox

try {
    $missingLocalConfigPath = Join-Path $missingLocalSandboxRoot "configs\local.json"
    Remove-Item -LiteralPath $missingLocalConfigPath -Force -ErrorAction SilentlyContinue
    $applyMissing = Invoke-SandboxAdpos -SandboxRoot $missingLocalSandboxRoot -Arguments @("isolate", "-Apply", "-Namespace", "v2")
    Assert-ExitCode -Name "isolate apply missing local config" -Actual $applyMissing.ExitCode -Expected 0
    Assert-Contains -Name "isolate apply missing local config backup" -Text $applyMissing.Output -Pattern "Backup:\s+none; configs\\\\local\.json did not exist before apply"
    if (-not (Test-Path -LiteralPath $missingLocalConfigPath)) {
        throw "isolate -Apply did not create configs/local.json when missing."
    }
    Assert-IsolatedLocalConfig -LocalConfigPath $missingLocalConfigPath
} finally {
    $tempRoot = [System.IO.Path]::GetTempPath()
    if ($missingLocalSandboxRoot -and (Test-Path -LiteralPath $missingLocalSandboxRoot) -and [System.IO.Path]::GetFullPath($missingLocalSandboxRoot).StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $missingLocalSandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Output "isolate apply contract OK"
