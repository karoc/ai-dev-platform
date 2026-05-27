# ADP-OS installer smoke tests
# Non-destructive behavior checks for installer diagnostics and local-state writes.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$install = Join-Path $projectRoot "install.ps1"

function Invoke-Install {
    param(
        [string[]]$Arguments,
        [string]$UserProfile
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $install) + $Arguments
        $process = Start-Process -FilePath "pwsh" `
            -ArgumentList $processArguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -Environment @{ USERPROFILE = $UserProfile }

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
        [scriptblock]$Inspect = $null
    )

    $userProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-install-smoke-home-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $userProfile -Force | Out-Null
    try {
        $result = Invoke-Install -Arguments $Arguments -UserProfile $userProfile
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
