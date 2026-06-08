# ADP-OS local configuration boundary checks
# Ensures diagnostic and preview commands do not mutate user-owned configs/local.json.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function New-BoundarySandbox {
    $sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-local-config-boundary-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

    $trackedFiles = & git -C $projectRoot ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while preparing local config boundary sandbox."
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

function Write-SentinelLocalConfig {
    param(
        [string]$SandboxRoot,
        [string]$RuntimeNamespace = ""
    )

    $stateRoot = Join-Path $SandboxRoot ".adp-boundary-state"
    $platform = [ordered]@{
        boundary_sentinel = "preserve-platform-field"
        runtime_namespace = if ([string]::IsNullOrWhiteSpace($RuntimeNamespace)) { $null } else { $RuntimeNamespace }
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

    $localConfig = [ordered]@{
        platform = $platform
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
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    # Resolve pwsh full path from the current process, falling back to PATH lookup.
    # On some CI runners, bare "pwsh" is not in PATH even when pwsh is the active shell.
    $pwshPath = try { (Get-Process -Id $PID).Path } catch { $null }
    if (-not $pwshPath) {
        $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    }
    if (-not $pwshPath) {
        throw "Cannot resolve pwsh executable path for sandboxed test execution."
    }

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
        $process = Start-Process -FilePath $pwshPath `
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

function Assert-TextContains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name output did not contain expected pattern: $Pattern`n$Text"
    }
}

function Assert-TextNotContains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        throw "$Name output contained forbidden pattern: $Pattern`n$Text"
    }
}

function Assert-NoRuntimeVmDirectories {
    param(
        [string]$Name,
        [string]$SandboxRoot
    )

    $vmRoot = Join-Path (Join-Path $SandboxRoot ".adp-boundary-state") "vms"
    foreach ($vmDirectoryName in @("adp-agent", "adp-v2-agent")) {
        $vmDirectory = Join-Path $vmRoot $vmDirectoryName
        if (Test-Path -LiteralPath $vmDirectory) {
            throw "$Name created VM directory unexpectedly: $vmDirectory"
        }
    }
}

function Write-BoundarySeedUserData {
    param(
        [string]$SandboxRoot,
        [string]$SeedDirectoryName,
        [string]$Address,
        [int]$Prefix = 24,
        [string]$Gateway = "203.0.113.2"
    )

    $seedDirectory = Join-Path (Join-Path (Join-Path $SandboxRoot ".adp-boundary-state") "vms") "seeds\$SeedDirectoryName"
    New-Item -ItemType Directory -Path $seedDirectory -Force | Out-Null
    $userData = @"
#cloud-config
network:
  version: 2
  ethernets:
    ens33:
      addresses:
        - $Address/$Prefix
      routes:
        - to: default
          via: $Gateway
"@
    Set-Content -LiteralPath (Join-Path $seedDirectory "user-data") -Value $userData -Encoding UTF8
}

function Write-BoundaryFakeRuntimeVm {
    param(
        [string]$SandboxRoot,
        [string]$VmDirectoryName,
        [string]$VmxFileName,
        [string]$VmdkFileName
    )

    $vmDirectory = Join-Path (Join-Path (Join-Path $SandboxRoot ".adp-boundary-state") "vms") $VmDirectoryName
    New-Item -ItemType Directory -Path $vmDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $vmDirectory $VmxFileName) -Value ".encoding = `"UTF-8`"" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $vmDirectory $VmdkFileName) -Value "# boundary placeholder" -Encoding ASCII
}

function Install-BoundaryProviderStub {
    param([string]$SandboxRoot)

    $stubPath = Join-Path $SandboxRoot "adapters\windows\vmware\vmware-provider.ps1"
    $stubContent = @'
function Write-BoundaryProviderCall {
    param([string]$Message)

    $stateRoot = Join-Path (Get-ProjectRoot) ".adp-boundary-state"
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $stateRoot "provider-calls.log") -Value $Message -Encoding UTF8
}

function Initialize-VMwareProvider {
    param([string]$ProjectRoot, [hashtable]$InitArgs = @{})
    Write-BoundaryProviderCall -Message "Initialize-VMwareProvider"
    return $true
}

function Initialize-Provider {
    param([string]$ProviderType, [string]$ProjectRoot, [hashtable]$InitArgs = @{})
    Write-BoundaryProviderCall -Message "Initialize-Provider:$ProviderType"
    return [pscustomobject]@{ Success = $true; Data = $ProviderType; Error = $null }
}

function Get-ProviderInfo {
    return [pscustomobject]@{ Success = $true; Data = "boundary-provider-stub"; Error = $null }
}

function Get-ProviderCapabilities {
    return [pscustomobject]@{
        Success = $true
        Data = @{
            SupportsNAT = $true
            SupportsCloning = $false
            SupportsLiveMigration = $false
            SupportsSnapshots = $false
            SupportsGuestExec = $false
            SupportsDynamicResize = $false
            ProviderType = "boundary-provider-stub"
            ProviderVersion = "test"
        }
        Error = $null
    }
}

function Get-VMStatus {
    param([string]$Name, [string]$VmxPath)
    if ($Name) {
        Write-BoundaryProviderCall -Message "Get-VMStatus:$Name"
    } elseif ($VmxPath) {
        Write-BoundaryProviderCall -Message "Get-VMStatusPath:$VmxPath"
    } else {
        Write-BoundaryProviderCall -Message "Get-VMStatus"
    }
    return [pscustomobject]@{ Success = $true; Data = "not-created"; Error = $null }
}

function Get-RunningVMs {
    Write-BoundaryProviderCall -Message "Get-RunningVMs"
    return @()
}

function Start-VM {
    param([string]$Name, [string]$VmxPath, [string]$Mode = "nogui")
    if ($Name) { Write-BoundaryProviderCall -Message "Start-VM:$Name" }
    return [pscustomobject]@{ Success = $false; Data = $null; Error = "boundary provider stub does not start VMs" }
}

function Test-VMwareNatConfigMatchesHost {
    Write-BoundaryProviderCall -Message "Test-VMwareNatConfigMatchesHost"
    return [pscustomobject]@{ Checked = $false; Matches = $true; Host = $null; Config = $null; Message = "boundary provider stub skips host NAT detection" }
}
'@

    Set-Content -LiteralPath $stubPath -Value $stubContent -Encoding UTF8
}

function Get-BoundaryProviderCallLogPath {
    param([string]$SandboxRoot)

    return Join-Path (Join-Path $SandboxRoot ".adp-boundary-state") "provider-calls.log"
}

function Clear-BoundaryProviderCallLog {
    param([string]$SandboxRoot)

    Remove-Item -LiteralPath (Get-BoundaryProviderCallLogPath -SandboxRoot $SandboxRoot) -Force -ErrorAction SilentlyContinue
}

function Get-BoundaryProviderCallLog {
    param([string]$SandboxRoot)

    $path = Get-BoundaryProviderCallLogPath -SandboxRoot $SandboxRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return ""
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Assert-CommandDoesNotMutateLocalConfig {
    param(
        [string]$Name,
        [string]$SandboxRoot,
        [string]$ScriptPath,
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $localConfigPath = Join-Path $SandboxRoot "configs\local.json"
    $beforeHash = (Get-FileHash -LiteralPath $localConfigPath -Algorithm SHA256).Hash
    $result = Invoke-BoundaryCommand -SandboxRoot $SandboxRoot -ScriptPath $ScriptPath -Arguments $Arguments
    Assert-LocalConfigUnchanged -Name $Name -SandboxRoot $SandboxRoot -LocalConfigPath $localConfigPath -BeforeHash $beforeHash -Result $result -AllowedExitCodes $AllowedExitCodes
    return $result
}

$sandboxRoot = New-BoundarySandbox

try {
    Write-SentinelLocalConfig -SandboxRoot $sandboxRoot | Out-Null

    $installScript = Join-Path $sandboxRoot "install.ps1"
    $cliScript = Join-Path $sandboxRoot "cli\adp.ps1"

    $commands = @(
        [pscustomobject]@{
            Name = "install skip checks"
            Script = $installScript
            Arguments = @("-SkipDependencyCheck", "-SkipVMValidation", "-NoRegisterCommand")
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
            AllowedExitCodes = @(0, 1)
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
        $null = Assert-CommandDoesNotMutateLocalConfig `
            -Name $command.Name `
            -SandboxRoot $sandboxRoot `
            -ScriptPath $command.Script `
            -Arguments $command.Arguments `
            -AllowedExitCodes $command.AllowedExitCodes
    }
} finally {
    $tempRoot = [System.IO.Path]::GetTempPath()
    foreach ($path in @($sandboxRoot)) {
        if ($path -and (Test-Path -LiteralPath $path) -and [System.IO.Path]::GetFullPath($path).StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$namespacedSandboxRoot = New-BoundarySandbox

try {
    Write-SentinelLocalConfig -SandboxRoot $namespacedSandboxRoot -RuntimeNamespace "v2" | Out-Null
    Install-BoundaryProviderStub -SandboxRoot $namespacedSandboxRoot

    $namespacedCliScript = Join-Path $namespacedSandboxRoot "cli\adp.ps1"

    Clear-BoundaryProviderCallLog -SandboxRoot $namespacedSandboxRoot
    $namespacedPlan = Assert-CommandDoesNotMutateLocalConfig `
        -Name "namespaced up plan" `
        -SandboxRoot $namespacedSandboxRoot `
        -ScriptPath $namespacedCliScript `
        -Arguments @("up", "agent", "-Plan", "-IsoPath", "Z:\adp-boundary\missing.iso") `
        -AllowedExitCodes @(0)

    Assert-TextContains -Name "namespaced up plan resource" -Text $namespacedPlan.Output -Pattern 'Namespace:\s+v2\s+\(resource:\s+v2-agent\)'
    Assert-TextContains -Name "namespaced up plan VMX" -Text $namespacedPlan.Output -Pattern 'adp-v2-agent[\\/]adp-v2-agent\.vmx'
    Assert-TextContains -Name "namespaced up plan create preview" -Text $namespacedPlan.Output -Pattern 'Would create VM from ISO|将从 ISO 创建 VM'
    Assert-TextNotContains -Name "namespaced up plan no legacy blocker" -Text $namespacedPlan.Output -Pattern 'first VM creation has not been migrated|will not create the default|VM factory migration|首次 VM 创建尚未迁移'
    Assert-TextNotContains -Name "namespaced up plan no legacy VMX" -Text $namespacedPlan.Output -Pattern 'VMX:\s+.*adp-agent[\\/]adp-agent\.vmx'
    $planProviderLog = Get-BoundaryProviderCallLog -SandboxRoot $namespacedSandboxRoot
    Assert-TextContains -Name "namespaced up plan provider resource lookup" -Text $planProviderLog -Pattern 'Get-VMStatus:v2-agent'
    Assert-TextNotContains -Name "namespaced up plan no legacy provider lookup" -Text $planProviderLog -Pattern 'Get-VMStatus:agent|Start-VM:agent'
    Assert-NoRuntimeVmDirectories -Name "namespaced up plan" -SandboxRoot $namespacedSandboxRoot

    Clear-BoundaryProviderCallLog -SandboxRoot $namespacedSandboxRoot
    $namespacedPreflight = Assert-CommandDoesNotMutateLocalConfig `
        -Name "namespaced up create preflight failure" `
        -SandboxRoot $namespacedSandboxRoot `
        -ScriptPath $namespacedCliScript `
        -Arguments @("up", "agent", "-IsoPath", "Z:\adp-boundary\missing.iso") `
        -AllowedExitCodes @(1)

    Assert-TextContains -Name "namespaced preflight resource" -Text $namespacedPreflight.Output -Pattern 'Namespace:\s+v2\s+\(resource:\s+v2-agent\)'
    Assert-TextContains -Name "namespaced preflight VMX" -Text $namespacedPreflight.Output -Pattern 'adp-v2-agent[\\/]adp-v2-agent\.vmx'
    Assert-TextContains -Name "namespaced preflight missing ISO" -Text $namespacedPreflight.Output -Pattern 'OS ISO not found|未找到 OS ISO'
    Assert-TextNotContains -Name "namespaced preflight no legacy blocker" -Text $namespacedPreflight.Output -Pattern 'first VM creation has not been migrated|will not create the default|VM factory migration|首次 VM 创建尚未迁移'
    Assert-TextNotContains -Name "namespaced preflight no legacy VMX" -Text $namespacedPreflight.Output -Pattern 'VMX:\s+.*adp-agent[\\/]adp-agent\.vmx'
    $preflightProviderLog = Get-BoundaryProviderCallLog -SandboxRoot $namespacedSandboxRoot
    Assert-TextContains -Name "namespaced preflight provider resource lookup" -Text $preflightProviderLog -Pattern 'Get-VMStatus:v2-agent'
    Assert-TextNotContains -Name "namespaced preflight no legacy provider lookup" -Text $preflightProviderLog -Pattern 'Get-VMStatus:agent|Start-VM:agent'
    Assert-NoRuntimeVmDirectories -Name "namespaced up create preflight failure" -SandboxRoot $namespacedSandboxRoot

    Write-BoundarySeedUserData -SandboxRoot $namespacedSandboxRoot -SeedDirectoryName "agent" -Address "203.0.113.201"
    Write-BoundarySeedUserData -SandboxRoot $namespacedSandboxRoot -SeedDirectoryName "v2-agent" -Address "203.0.113.202"
    Write-BoundaryFakeRuntimeVm -SandboxRoot $namespacedSandboxRoot -VmDirectoryName "adp-v2-agent" -VmxFileName "adp-v2-agent.vmx" -VmdkFileName "adp-v2-agent.vmdk"

    $namespacedStatus = Assert-CommandDoesNotMutateLocalConfig `
        -Name "namespaced status seed drift" `
        -SandboxRoot $namespacedSandboxRoot `
        -ScriptPath $namespacedCliScript `
        -Arguments @("status", "agent") `
        -AllowedExitCodes @(0)

    Assert-TextContains -Name "namespaced status uses resource seed path" -Text $namespacedStatus.Output -Pattern 'network drift: seed uses 203\.0\.113\.202/24|网络漂移:\s+seed 使用 203\.0\.113\.202/24'
    Assert-TextNotContains -Name "namespaced status does not read legacy seed path" -Text $namespacedStatus.Output -Pattern '203\.0\.113\.201'

    $namespacedDoctor = Assert-CommandDoesNotMutateLocalConfig `
        -Name "namespaced doctor seed drift" `
        -SandboxRoot $namespacedSandboxRoot `
        -ScriptPath $namespacedCliScript `
        -Arguments @("doctor") `
        -AllowedExitCodes @(0, 1)

    Assert-TextContains -Name "namespaced doctor uses resource seed path" -Text $namespacedDoctor.Output -Pattern 'agent seed network drift \(seed 203\.0\.113\.202/24, configured 203\.0\.113\.135\)'
    Assert-TextNotContains -Name "namespaced doctor does not read legacy seed path" -Text $namespacedDoctor.Output -Pattern '203\.0\.113\.201'
} finally {
    $tempRoot = [System.IO.Path]::GetTempPath()
    foreach ($path in @($namespacedSandboxRoot)) {
        if ($path -and (Test-Path -LiteralPath $path) -and [System.IO.Path]::GetFullPath($path).StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Output "Local config boundary checks OK"
