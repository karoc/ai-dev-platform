# ADP-OS resource conflict diagnostics.
# Shared read-only helpers for multi-checkout runtime safety.

function Normalize-ADPResourcePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
    } catch {
        return $Path.TrimEnd('\', '/')
    }
}

function Get-ADPUserProfilePath {
    if ($env:USERPROFILE) {
        return $env:USERPROFILE
    }
    if ($env:HOME) {
        return $env:HOME
    }
    return ""
}

function Get-ADPCheckoutCommandContext {
    $projectRoot = Get-ProjectRoot
    $registration = $null
    $registrationError = ""

    try {
        $registrationScript = Join-Path $projectRoot "scripts\adpos-registration.ps1"
        if (Test-Path -LiteralPath $registrationScript) {
            . $registrationScript
            $registration = Get-ADPOSExistingRegistration -ProjectRoot $projectRoot
        }
    } catch {
        $registrationError = [string]$_
    }

    $bindingStatus = "unknown"
    $commandPrefix = ".\adpos.cmd"
    $globalHome = ""

    if ($registration) {
        $globalHome = [string]$registration.Home
        if ($registration.IsDifferentHome) {
            $bindingStatus = "different-checkout"
        } elseif ($registration.Home -or $registration.PathHomes.Count -gt 0 -or $registration.ShimExists) {
            $bindingStatus = "current-checkout"
            $commandPrefix = "adpos"
        } else {
            $bindingStatus = "not-registered"
        }
    } elseif ($registrationError) {
        $bindingStatus = "unavailable"
    }

    return [pscustomobject]@{
        ProjectRoot       = $projectRoot
        CommandPrefix     = $commandPrefix
        BindingStatus     = $bindingStatus
        GlobalHome        = $globalHome
        RegistrationError = $registrationError
        ShimPath          = if ($registration) { [string]$registration.ShimPath } else { "" }
        UserPathHasBin    = if ($registration) { [bool]$registration.UserPathHasBin } else { $false }
        MachinePathHasBin = if ($registration) { [bool]$registration.MachinePathHasBin } else { $false }
    }
}

function Format-ADPCheckoutCommand {
    param(
        [object]$CommandContext,
        [string]$Arguments
    )

    $prefix = "adpos"
    if ($CommandContext -and $CommandContext.CommandPrefix) {
        $prefix = [string]$CommandContext.CommandPrefix
    }

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        return $prefix
    }
    return "$prefix $Arguments"
}

function Write-ADPCheckoutBindingSummary {
    param([object]$CommandContext)

    if (-not $CommandContext) {
        $CommandContext = Get-ADPCheckoutCommandContext
    }

    switch ($CommandContext.BindingStatus) {
        "current-checkout" {
            Write-UIHost -English "Command:      adpos is bound to this checkout ($($CommandContext.ProjectRoot))" -Chinese "命令:        adpos 已绑定到当前 checkout ($($CommandContext.ProjectRoot))" -ForegroundColor DarkGray
        }
        "different-checkout" {
            Write-UIHost -English "Command:      global adpos points to another checkout ($($CommandContext.GlobalHome))" -Chinese "命令:        全局 adpos 指向另一个 checkout ($($CommandContext.GlobalHome))" -ForegroundColor Yellow
            Write-UIHost -English "Local use:    .\adpos.cmd from this checkout ($($CommandContext.ProjectRoot))" -Chinese "本地使用:    在当前 checkout 中运行 .\adpos.cmd ($($CommandContext.ProjectRoot))" -ForegroundColor Yellow
        }
        "not-registered" {
            Write-UIHost -English "Command:      global adpos is not registered for this checkout; local command is .\adpos.cmd" -Chinese "命令:        全局 adpos 未注册到当前 checkout；本地命令为 .\adpos.cmd" -ForegroundColor Yellow
        }
        "unavailable" {
            Write-UIHost -English "Command:      global adpos binding could not be inspected; local command is .\adpos.cmd" -Chinese "命令:        无法检查全局 adpos 绑定；本地命令为 .\adpos.cmd" -ForegroundColor Yellow
        }
    }
}

function Get-ADPRuntimeResourceProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRuntime,
        [string]$VmxPath
    )

    $rt = Get-RuntimeConfig $TargetRuntime
    $platformConfig = Get-PlatformConfig
    $workspaceRoot = Resolve-Path "workspace_root"
    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$TargetRuntime"
    $resolvedVmxPath = if ($VmxPath) { $VmxPath } else { Join-Path $vmStore "$vmName\$vmName.vmx" }
    $sshAlias = "adp-os-$vmName"
    $sessionName = $vmName
    $userProfile = Get-ADPUserProfilePath
    $sshKeyPath = if ($userProfile) { Join-Path "$userProfile\.ssh\adp-os" "adp-os" } else { "" }
    $sshPort = if ($rt.PSObject.Properties.Name -contains "ssh_port" -and $rt.ssh_port) { [int]$rt.ssh_port } else { 22 }
    $sshUser = if ($platformConfig.defaults.admin_user) { [string]$platformConfig.defaults.admin_user } else { "adp" }

    return [pscustomobject]@{
        Runtime           = $TargetRuntime
        ProjectRoot       = Get-ProjectRoot
        WorkspaceRoot     = $workspaceRoot
        WorkspacePath     = Join-Path $workspaceRoot $rt.workspace
        VmStore           = $vmStore
        VmxPath           = $resolvedVmxPath
        StaticIp          = Get-RuntimeStaticIP $TargetRuntime
        SshAlias          = $sshAlias
        SshUser           = $sshUser
        SshPort           = $sshPort
        SshKeyPath        = $sshKeyPath
        MutagenSession    = $sessionName
        ExpectedRemoteUrl = "${sshAlias}:/home/adp/workspace"
    }
}

function Get-ADPRunningVmxPathsForResourceCheck {
    try {
        if (Get-Command Get-RunningVMs -ErrorAction SilentlyContinue) {
            return @(Get-RunningVMs | ForEach-Object { Normalize-ADPResourcePath -Path $_ })
        }
    } catch {
        return @()
    }

    return @()
}

function Get-ADPRuntimeDuplicateConflict {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRuntime,
        [Parameter(Mandatory = $true)]
        [string]$ManagedVmxPath,
        [string[]]$RunningVmxPaths = @()
    )

    $running = @()
    if (Get-Command Get-ADPRunningRuntimeVMs -ErrorAction SilentlyContinue) {
        $running = @(Get-ADPRunningRuntimeVMs -RunningVmxPaths $RunningVmxPaths -RuntimeName $TargetRuntime -ManagedVmxPath $ManagedVmxPath)
    }

    $duplicates = @($running | Where-Object { -not $_.IsManagedByCurrentCheckout })
    $hasConflict = ($running.Count -gt 1 -or $duplicates.Count -gt 0)

    return [pscustomobject]@{
        Runtime                  = $TargetRuntime
        ManagedVmxPath           = Normalize-ADPResourcePath -Path $ManagedVmxPath
        RunningVms               = $running
        DuplicateVms             = $duplicates
        HasDuplicateRunningVm    = $hasConflict
        OtherRunningVmxPaths     = @($duplicates | ForEach-Object { $_.NormalizedVmxPath })
        BlocksRuntimeMutation    = $hasConflict
    }
}

function ConvertTo-ADPDuplicateVmJson {
    param([object[]]$RunningVms)

    return @($RunningVms | ForEach-Object {
        [pscustomobject]@{
            RuntimeName                 = $_.RuntimeName
            VmxPath                     = $_.VmxPath
            NormalizedVmxPath           = $_.NormalizedVmxPath
            IsManagedByCurrentCheckout  = [bool]$_.IsManagedByCurrentCheckout
        }
    })
}

function Write-ADPRuntimeResourceConflictGuidance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Profile,
        [Parameter(Mandatory = $true)]
        [object]$Conflict,
        [object]$CommandContext,
        [string]$Action = "runtime operation"
    )

    if (-not $CommandContext) {
        $CommandContext = Get-ADPCheckoutCommandContext
    }

    $statusCommand = Format-ADPCheckoutCommand -CommandContext $CommandContext -Arguments "status $($Profile.Runtime)"
    $doctorCommand = Format-ADPCheckoutCommand -CommandContext $CommandContext -Arguments "doctor"
    $upPlanCommand = Format-ADPCheckoutCommand -CommandContext $CommandContext -Arguments "up $($Profile.Runtime) -Plan"
    $syncStatusCommand = Format-ADPCheckoutCommand -CommandContext $CommandContext -Arguments "sync status"

    Write-UIHost -English "  resource conflict: duplicate running VM for runtime '$($Profile.Runtime)'" -Chinese "  资源冲突:      runtime '$($Profile.Runtime)' 存在重复运行的 VM" -ForegroundColor Red
    Write-UIHost -English "  blocked action:    $Action" -Chinese "  已阻止动作:    $Action" -ForegroundColor Red
    Write-UIHost -English "  checkout:          $($Profile.ProjectRoot)" -Chinese "  当前 checkout:  $($Profile.ProjectRoot)" -ForegroundColor DarkGray
    if ($CommandContext.BindingStatus -eq "different-checkout") {
        Write-UIHost -English "  global adpos:      $($CommandContext.GlobalHome) (different checkout)" -Chinese "  全局 adpos:      $($CommandContext.GlobalHome) (另一个 checkout)" -ForegroundColor Yellow
        Write-UIHost -English "  local command:     .\adpos.cmd" -Chinese "  本地命令:        .\adpos.cmd" -ForegroundColor Yellow
    } else {
        Write-UIHost -English "  command prefix:    $($CommandContext.CommandPrefix)" -Chinese "  命令前缀:        $($CommandContext.CommandPrefix)" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  workspace_root:    $($Profile.WorkspaceRoot)" -Chinese "  workspace_root:    $($Profile.WorkspaceRoot)" -ForegroundColor DarkGray
    Write-UIHost -English "  vm_store:          $($Profile.VmStore)" -Chinese "  vm_store:          $($Profile.VmStore)" -ForegroundColor DarkGray
    Write-UIHost -English "  static_ip:         $(if ($Profile.StaticIp) { $Profile.StaticIp } else { 'not configured' })" -Chinese "  static_ip:         $(if ($Profile.StaticIp) { $Profile.StaticIp } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  SSH alias:         $($Profile.SshAlias)" -Chinese "  SSH alias:         $($Profile.SshAlias)" -ForegroundColor DarkGray
    Write-UIHost -English "  SSH key:           $($Profile.SshKeyPath)" -Chinese "  SSH key:           $($Profile.SshKeyPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  Mutagen session:   $($Profile.MutagenSession)" -Chinese "  Mutagen session:   $($Profile.MutagenSession)" -ForegroundColor DarkGray
    Write-UIHost -English "  expected VMX:      $($Profile.VmxPath)" -Chinese "  预期 VMX:        $($Profile.VmxPath)" -ForegroundColor DarkGray

    foreach ($vm in @($Conflict.RunningVms)) {
        $owner = if ($vm.IsManagedByCurrentCheckout) {
            Get-UIText -English "current checkout" -Chinese "当前 checkout"
        } else {
            Get-UIText -English "other checkout or stale VM" -Chinese "其他 checkout 或 stale VM"
        }
        Write-UIHost -English "  running VMX:       $($vm.NormalizedVmxPath) [$owner]" -Chinese "  运行 VMX:        $($vm.NormalizedVmxPath) [$owner]" -ForegroundColor Yellow
    }

    Write-UIHost -English "  next:" -Chinese "  下一步:" -ForegroundColor Yellow
    Write-UIHost -English "    - If the other VM is stale, stop it from its owning checkout or VMware UI, then rerun: $statusCommand" -Chinese "    - 如果另一个 VM 已 stale，请从其所属 checkout 或 VMware UI 停止它，然后重新运行: $statusCommand" -ForegroundColor Yellow
    Write-UIHost -English "    - If both checkouts must stay active, configure distinct workspace_root, vm_store, and topology.$($Profile.Runtime).static_ip before starting this runtime." -Chinese "    - 如果两个 checkout 都要保留运行，请先为当前 checkout 配置不同的 workspace_root、vm_store 和 topology.$($Profile.Runtime).static_ip。" -ForegroundColor Yellow
    Write-UIHost -English "    - Recheck with: $doctorCommand; $syncStatusCommand; $upPlanCommand" -Chinese "    - 重新检查: $doctorCommand; $syncStatusCommand; $upPlanCommand" -ForegroundColor DarkGray
}
