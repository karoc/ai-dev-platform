# ADP-OS VMware Adapter mock tests
# Mocks Invoke-Vmrun — no real vmrun.exe calls.
param()
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

Describe "VMware Adapter mock tests" {
    BeforeAll {
        . (Join-Path $repoRoot "adapters\windows\vmware\vmware.ps1")
        $script:Verified = $true
        $script:VmrunPath = "C:\mock\vmrun.exe"
    }

    # ── Error handling ─────────────────────────────────────
    Describe "Invoke-Vmrun" {
        It "throws when adapter is not initialized" {
            $saved = $script:Verified
            $script:Verified = $false
            try {
                { Invoke-Vmrun -Arguments @("list") } | Should -Throw
            } finally {
                $script:Verified = $saved
            }
        }

        It "returns failure on timeout" {
            Mock Start-Process { return @{ WaitForExit = { $false }; Kill = {} } }
            Mock Get-Content { return "" }
            Mock Remove-Item {}
            $result = Invoke-Vmrun -Arguments @("start", "test.vmx")
            $result.Success | Should -Be $false
            $result.StdErr | Should -BeLike "*timed out*"
        }

        It "returns success when vmrun exits 0" {
            Mock Start-Process { return @{ ExitCode = 0; WaitForExit = { $true } } }
            Mock Get-Content { return "OK" }
            Mock Remove-Item {}
            $result = Invoke-Vmrun -Arguments @("list")
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
        }
    }

    # ── Start / Stop ───────────────────────────────────────
    Describe "Start-VM" {
        It "calls vmrun start with correct arguments" {
            $observed = $null
            Mock Invoke-Vmrun {
                param([string[]]$Arguments)
                $observed = $Arguments -join " "
                return @{ Success = $true; ExitCode = 0 }
            }
            $result = Start-VM -VmxPath "C:\vms\adp-agent\adp-agent.vmx" -Mode "nogui"
            $result.Success | Should -Be $true
            $observed | Should -Be "start C:\vms\adp-agent\adp-agent.vmx nogui"
        }
    }

    Describe "Stop-VM" {
        It "calls vmrun stop soft/hard correctly" {
            $observed = $null
            Mock Invoke-Vmrun {
                param([string[]]$Arguments)
                $observed = $Arguments -join " "
                return @{ Success = $true; ExitCode = 0 }
            }
            Stop-VM -VmxPath "C:\vms\x\x.vmx" -Mode "hard"
            $observed | Should -Be "stop C:\vms\x\x.vmx hard"

            Stop-VM -VmxPath "C:\vms\x\x.vmx" -Mode "soft"
            $observed | Should -Be "stop C:\vms\x\x.vmx soft"
        }
    }

    # ── Get-VMStatus ───────────────────────────────────────
    Describe "Get-VMStatus" {
        It "returns not-created when VMX does not exist" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*.vmx" }
            Get-VMStatus -VmxPath "C:\vms\missing\missing.vmx" | Should -Be "not-created"
        }

        It "returns running when VM is in vmrun list" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*.vmx" }
            Mock Invoke-Vmrun {
                param([string[]]$Arguments)
                if ($Arguments -eq @("list")) {
                    return @{ Success = $true; StdOut = "Total running VMs: 1`nC:\vms\adp-agent\adp-agent.vmx"; ExitCode = 0 }
                }
                return @{ Success = $false; StdErr = "err"; ExitCode = 1 }
            }
            Get-VMStatus -VmxPath "C:\vms\adp-agent\adp-agent.vmx" | Should -Be "running"
        }

        It "returns stopped when VMX exists but VM is not running" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -like "*.vmx" }
            Mock Invoke-Vmrun {
                param([string[]]$Arguments)
                if ($Arguments -eq @("list")) {
                    return @{ Success = $true; StdOut = "Total running VMs: 0"; ExitCode = 0 }
                }
                return @{ Success = $false; StdErr = "VM is not running"; ExitCode = 1 }
            }
            Get-VMStatus -VmxPath "C:\vms\adp-agent\adp-agent.vmx" | Should -Be "stopped"
        }
    }

    # ── Snapshots ──────────────────────────────────────────
    Describe "Create-VMSnapshot" {
        It "passes vmx and name to vmrun snapshot" {
            $observed = $null
            Mock Invoke-Vmrun {
                param([string[]]$Arguments)
                $observed = $Arguments -join " "
                return @{ Success = $true; ExitCode = 0 }
            }
            $result = Create-VMSnapshot -VmxPath "C:\vms\x\x.vmx" -SnapshotName "pre-update"
            $result.Success | Should -Be $true
            $observed | Should -Be "snapshot C:\vms\x\x.vmx pre-update"
        }
    }

    Describe "Restore-VMSnapshot" {
        It "calls revertToSnapshot with correct arguments" {
            $observed = $null
            Mock Invoke-Vmrun {
                param([string[]]$Arguments)
                $observed = $Arguments -join " "
                return @{ Success = $true; ExitCode = 0 }
            }
            $result = Restore-VMSnapshot -VmxPath "C:\vms\x\x.vmx" -SnapshotName "clean"
            $result.Success | Should -Be $true
            $observed | Should -Be "revertToSnapshot C:\vms\x\x.vmx clean"
        }
    }

    Describe "List-VMSnapshots" {
        It "parses snapshot names from vmrun output" {
            Mock Invoke-Vmrun {
                return @{ Success = $true; StdOut = "clean`npost-install`npre-update"; ExitCode = 0 }
            }
            $snaps = List-VMSnapshots -VmxPath "C:\vms\x\x.vmx"
            $snaps.Count | Should -Be 3
            $snaps[0] | Should -Be "clean"
        }

        It "returns empty array on vmrun failure" {
            Mock Invoke-Vmrun { return @{ Success = $false; StdOut = ""; ExitCode = 1 } }
            (List-VMSnapshots -VmxPath "C:\vms\x\x.vmx").Count | Should -Be 0
        }
    }

    # ── VMX path construction ──────────────────────────────
    Describe "Normalize-VMXPath" {
        It "resolves relative to full path" {
            $n = Normalize-VMXPath -VmxPath "agent\agent.vmx"
            $n | Should -Not -BeNullOrEmpty
            $n | Should -Not -Be "agent\agent.vmx"
        }

        It "returns empty for null/whitespace" {
            Normalize-VMXPath -VmxPath $null  | Should -Be ""
            Normalize-VMXPath -VmxPath "   "  | Should -Be ""
        }
    }

    Describe "Get-ADPRuntimeNameFromVmxPath" {
        It "extracts runtime name from adp-<name>.vmx" {
            $name = Get-ADPRuntimeNameFromVmxPath -VmxPath "C:\vms\adp-agent\adp-agent.vmx"
            $name | Should -Be "agent"
        }

        It "returns empty for non-ADP vmx and null" {
            Get-ADPRuntimeNameFromVmxPath -VmxPath "C:\vms\other\other.vmx" | Should -Be ""
            Get-ADPRuntimeNameFromVmxPath -VmxPath $null | Should -Be ""
        }
    }

    # ── IP resolution ──────────────────────────────────────
    Describe "Get-VMIP" {
        It "resolves IP via quick probe" {
            Mock Invoke-Vmrun {
                param([string[]]$Arguments, [int]$TimeoutSeconds)
                if ($Arguments[0] -eq "getGuestIPAddress" -and $Arguments.Count -eq 2) {
                    return @{ Success = $true; StdOut = "192.168.242.131"; ExitCode = 0 }
                }
                return @{ Success = $false; ExitCode = 1 }
            }
            Get-VMIP -VmxPath "C:\vms\adp-agent\adp-agent.vmx" | Should -Be "192.168.242.131"
        }

        It "throws when all three IP layers fail" {
            Mock Invoke-Vmrun { return @{ Success = $false; StdOut = ""; StdErr = "err"; ExitCode = 1 } }
            Mock Get-VMIPFromDhcpLeases { return $null }
            Mock Get-VMMacAddresses { return @() }
            { Get-VMIP -VmxPath "C:\vms\adp-agent\adp-agent.vmx" } | Should -Throw
        }
    }
}
