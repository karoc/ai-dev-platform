# ADP-OS Mutagen Adapter (Windows)
# Sync session recovery and status helpers.

function Get-SyncSessionRecoveryInfo {
    param(
        [string]$SessionName,
        [string]$ExpectedLocalPath,
        [string]$ExpectedRemoteUrl,
        [bool]$RuntimeCreated,
        [string]$RuntimeName
    )

    $session = Get-SyncSessionInfo -SessionName $SessionName -ExpectedLocalPath $ExpectedLocalPath -ExpectedRemoteUrl $ExpectedRemoteUrl

    $result = [pscustomobject]@{
        Exists           = $session.Exists
        Health           = $session.Health
        Status           = $session.Status
        Detail           = $session.Detail
        AlphaUrl         = $session.AlphaUrl
        BetaUrl          = $session.BetaUrl
        RecoveryScenario = "none"
        RecoveryTitle    = ""
        RecoveryDetail   = ""
        RecoverySteps    = @()
        SafeCleanup      = $false
        StopCommand      = ""
        StartCommand     = ""
    }

    if (-not $session.Exists) {
        return $result
    }

    $result.StopCommand = "adpos sync stop $RuntimeName"
    $result.StartCommand = "adpos sync start $RuntimeName"

    # Detect root-emptying protection.
    if ($session.Health -eq "unhealthy" -and $session.Status -match '(?i)(root.?empty|empty.?root|safeguard|one.?side)') {
        $result.RecoveryScenario = "root-emptying"
        $result.RecoveryTitle = "Mutagen one-sided root emptying protection"
        $result.RecoveryDetail = "The synced root was emptied on one side or both sides, and Mutagen refused to keep mirroring the delete. This is expected safety behavior, not a platform crash."
        $result.RecoverySteps = @(
            "Repopulate one side from the source of truth, or recreate the project tree if you intentionally started over.",
            $result.StopCommand,
            $result.StartCommand,
            "adpos sync status"
        )
        $result.SafeCleanup = $true
        return $result
    }

    # Detect pre-runtime stale session.
    if (-not $RuntimeCreated) {
        $result.RecoveryScenario = "stale-before-creation"
        $result.RecoveryTitle = "Stale sync session before runtime creation"
        $result.RecoveryDetail = "A Mutagen session '$SessionName' exists, but the runtime VM has not been created in the current checkout. The session may belong to a previous checkout, a deleted VM, or a different clone."
        $result.RecoverySteps = @(
            "If the runtime was intentionally deleted or moved, stop the stale session: $($result.StopCommand)",
            "Create the runtime: adpos up $RuntimeName",
            "Start a fresh sync session: $($result.StartCommand)",
            "If the session belongs to another active clone, leave it alone."
        )
        $result.SafeCleanup = $true
        return $result
    }

    # Detect wrong-local, likely from another clone or checkout.
    if ($session.Health -eq "wrong-local") {
        $result.RecoveryScenario = "wrong-local-endpoint"
        $result.RecoveryTitle = "Sync session local endpoint mismatch"
        $result.RecoveryDetail = "The Mutagen session '$SessionName' points to a local path from a different checkout or clone. Current local path: $ExpectedLocalPath, session local path: $($session.AlphaUrl)."
        $result.RecoverySteps = @(
            "This session was likely created from a different clone of this repository.",
            "If the other clone is still active, consider which checkout should own the session.",
            "To reclaim for the current checkout: $($result.StopCommand), then $($result.StartCommand)",
            "To verify before stopping: adpos sync status"
        )
        $result.SafeCleanup = $true
        return $result
    }

    # Detect wrong-remote, likely from another clone or checkout.
    if ($session.Health -eq "wrong-remote") {
        $result.RecoveryScenario = "wrong-remote-endpoint"
        $result.RecoveryTitle = "Sync session remote endpoint mismatch"
        $result.RecoveryDetail = "The Mutagen session '$SessionName' points to a remote URL from a different clone or checkout. Current remote URL: $ExpectedRemoteUrl, session remote URL: $($session.BetaUrl)."
        $result.RecoverySteps = @(
            "This session was likely created from a different clone of this repository.",
            "Stop and recreate for the current checkout: $($result.StopCommand), then $($result.StartCommand)"
        )
        $result.SafeCleanup = $true
        return $result
    }

    # Detect unhealthy but not root-emptying: generic halted or error state.
    if ($session.Health -eq "unhealthy") {
        $result.RecoveryScenario = "unhealthy-session"
        $result.RecoveryTitle = "Sync session is unhealthy"
        $result.RecoveryDetail = "The Mutagen session '$SessionName' is in an unhealthy state: $($session.Status)."
        $result.RecoverySteps = @(
            "Stop and recreate: $($result.StopCommand), then $($result.StartCommand)",
            "Check sync status: adpos sync status"
        )
        $result.SafeCleanup = $true
        return $result
    }

    return $result
}

function Stop-SyncSession {
    param([string]$SessionName)
    Invoke-Mutagen -Arguments @("sync", "terminate", $SessionName)
}

function Get-SyncStatus {
    param([string]$SessionName)
    return Invoke-Mutagen -Arguments @("sync", "monitor", "--identifier", $SessionName)
}
