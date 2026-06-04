# ADP-OS Circuit Breaker Module
# Circuit breaker pattern for retry/loop operations.
#
# Tracks consecutive identical error conditions. When the same error key
# repeats MaxConsecutiveErrors times in a row, the circuit opens and
# refuses further attempts — preventing infinite retry loops.
#
# Usage:
#   $cb = New-CircuitBreaker -MaxConsecutiveErrors 10 -Name "ssh-wait"
#   while ($true) {
#       if (Test-CircuitBreaker -CircuitBreaker $cb -ErrorKey "ssh-refused") {
#           # Circuit closed — error recorded, continue retrying
#       } else {
#           # Circuit open — stop retrying
#           Write-WarnLog -Message "Circuit breaker '$($cb.Name)' opened: same error '$($cb.ErrorKey)' $($cb.ConsecutiveCount) times" -Component "circuit-breaker"
#           break
#       }
#   }
#
# Functions:
#   New-CircuitBreaker          Create a new circuit breaker state
#   Test-CircuitBreaker          Record an error; returns $false if open
#   Reset-CircuitBreaker         Reset circuit to closed state
#   Get-CircuitBreakerSummary    Get human-readable status

function New-CircuitBreaker {
    param(
        [int]$MaxConsecutiveErrors = 10,
        [string]$Name = "default"
    )

    return @{
        Name                 = $Name
        MaxConsecutiveErrors = [Math]::Max(1, $MaxConsecutiveErrors)
        ErrorKey             = $null
        ConsecutiveCount     = 0
        TotalErrors          = 0
        OpenedAt             = $null
        IsOpen               = $false
    }
}

function Test-CircuitBreaker {
    param(
        [hashtable]$CircuitBreaker,
        [string]$ErrorKey
    )

    if ($CircuitBreaker.IsOpen) {
        return $false
    }

    $CircuitBreaker.TotalErrors++

    if ($CircuitBreaker.ErrorKey -eq $ErrorKey) {
        $CircuitBreaker.ConsecutiveCount++
    } else {
        $CircuitBreaker.ErrorKey = $ErrorKey
        $CircuitBreaker.ConsecutiveCount = 1
    }

    if ($CircuitBreaker.ConsecutiveCount -ge $CircuitBreaker.MaxConsecutiveErrors) {
        $CircuitBreaker.IsOpen = $true
        $CircuitBreaker.OpenedAt = Get-Date
        return $false
    }

    return $true
}

function Reset-CircuitBreaker {
    param([hashtable]$CircuitBreaker)

    $CircuitBreaker.ErrorKey = $null
    $CircuitBreaker.ConsecutiveCount = 0
    $CircuitBreaker.IsOpen = $false
    $CircuitBreaker.OpenedAt = $null
}

function Get-CircuitBreakerSummary {
    param([hashtable]$CircuitBreaker)

    $state = if ($CircuitBreaker.IsOpen) {
        Get-UIText -English "OPEN" -Chinese "断开"
    } else {
        Get-UIText -English "CLOSED" -Chinese "闭合"
    }

    $lastError = if ($CircuitBreaker.ErrorKey) { $CircuitBreaker.ErrorKey } else { "-" }
    $openedInfo = if ($CircuitBreaker.OpenedAt) {
        " @ $($CircuitBreaker.OpenedAt.ToString('HH:mm:ss'))"
    } else { "" }

    return "[$($CircuitBreaker.Name)] $state errors=$($CircuitBreaker.TotalErrors) consecutive=$($CircuitBreaker.ConsecutiveCount)/$($CircuitBreaker.MaxConsecutiveErrors) last='$lastError'$openedInfo"
}
