# ADP-OS installer smoke tests
# Non-destructive behavior checks for installer diagnostics and local-state writes.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$install = Join-Path $projectRoot "install.ps1"

function Invoke-Install {
    param(
        [string[]]$Arguments,
        [string]$UserProfile,
        [hashtable]$Environment = @{}
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $install) + $Arguments
        $processEnvironment = @{ USERPROFILE = $UserProfile }
        foreach ($name in $Environment.Keys) {
            $processEnvironment[$name] = [string]$Environment[$name]
        }

        $process = Start-Process -FilePath "pwsh" `
            -ArgumentList $processArguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -Environment $processEnvironment

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

function Assert-ExitCode {
    param(
        [string]$Name,
        [object]$Result,
        [int]$Expected
    )

    if ($Result.ExitCode -ne $Expected) {
        throw "$Name exit code was $($Result.ExitCode), expected $Expected.`n$($Result.Output)"
    }
}

function Assert-OutputContains {
    param(
        [string]$Name,
        [object]$Result,
        [string]$Pattern
    )

    if ($Result.Output -notmatch $Pattern) {
        throw "$Name output did not match: $Pattern`n$($Result.Output)"
    }
}

function Assert-Install {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$ExitCode,
        [string[]]$Patterns,
        [hashtable]$Environment = @{},
        [scriptblock]$Inspect = $null
    )

    $userProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-install-smoke-home-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $userProfile -Force | Out-Null
    try {
        $result = Invoke-Install -Arguments $Arguments -UserProfile $userProfile -Environment $Environment
        Assert-ExitCode -Name $Name -Result $result -Expected $ExitCode
        foreach ($pattern in $Patterns) {
            Assert-OutputContains -Name $Name -Result $result -Pattern $pattern
        }
        if ($Inspect) {
            & $Inspect $userProfile $result
        }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Install `
    -Name "install skip checks missing ISO guidance" `
    -Arguments @("-SkipDependencyCheck", "-SkipVMValidation") `
    -ExitCode 0 `
    -Patterns @(
        "Dependency checks skipped by -SkipDependencyCheck",
        "ISO not found",
        "Or run: \.\\install\.ps1 -IsoPath <path-to-iso>",
        "VMware validation skipped by -SkipVMValidation",
        "agent .* \[agent/high-IO\]",
        "Dependency checks were skipped",
        "ADP-OS Phase 1 Bootstrap Complete"
    ) `
    -Inspect {
        param([string]$UserProfile)

        foreach ($path in @(
            (Join-Path $UserProfile "adp-workspaces\workspaces"),
            (Join-Path $UserProfile "adp-vms\vms"),
            (Join-Path $UserProfile ".adp-os\initialized")
        )) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "install did not create expected temporary path: $path"
            }
        }
    }

Assert-Install `
    -Name "install zh-CN skip checks missing ISO guidance" `
    -Arguments @("-SkipDependencyCheck", "-SkipVMValidation") `
    -ExitCode 0 `
    -Patterns @(
        "阶段 1",
        "\[1/6\] 检测平台",
        "\[2/6\] 检查依赖",
        "已通过 -SkipDependencyCheck 跳过依赖检查",
        "未找到 ISO",
        "或运行: \.\\install\.ps1 -IsoPath <path-to-iso>",
        "已通过 -SkipVMValidation 跳过 VMware 验证",
        "agent .* \[Agent 高 IO\]",
        "依赖检查已跳过",
        "ADP-OS 阶段 1 平台引导完成",
        "下一步:"
    ) `
    -Environment @{ ADP_LANG = "zh-CN" }

Assert-Install `
    -Name "install missing explicit ISO fails" `
    -Arguments @("-SkipDependencyCheck", "-SkipVMValidation", "-IsoPath", "Z:\adp-missing\ubuntu-26.04-live-server-amd64.iso") `
    -ExitCode 1 `
    -Patterns @("Specified ISO not found: Z:\\adp-missing\\ubuntu-26\.04-live-server-amd64\.iso")

$tinyIso = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-install-smoke-{0}.iso" -f ([guid]::NewGuid().ToString("N")))
try {
    "not a real ISO" | Set-Content -LiteralPath $tinyIso -Encoding ascii
    Assert-Install `
        -Name "install explicit ISO warning and cache copy" `
        -Arguments @("-SkipDependencyCheck", "-SkipVMValidation", "-IsoPath", $tinyIso) `
        -ExitCode 0 `
        -Patterns @(
            "ISO warning: file should be a \.iso and usually larger than 1 GB",
            "ISO copied to cache:",
            "VMware validation skipped by -SkipVMValidation",
            "ADP-OS Phase 1 Bootstrap Complete"
        ) `
        -Inspect {
            param([string]$UserProfile)

            $cachedIso = Join-Path $UserProfile "adp-iso\ubuntu-26.04-live-server-amd64.iso"
            if (-not (Test-Path -LiteralPath $cachedIso)) {
                throw "install did not copy explicit ISO into temporary cache: $cachedIso"
            }
        }
} finally {
    Remove-Item -LiteralPath $tinyIso -Force -ErrorAction SilentlyContinue
}

Write-Output "Installer smoke tests OK"
