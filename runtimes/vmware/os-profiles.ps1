# ADP-OS OS Profiles
# Defines unattended install metadata for each supported Linux distribution
# Each profile contains: guestOS (VMX), seedType, bootArgs, completionMarker

$script:OSProfiles = @{
    "ubuntu-24.04" = @{
        guestOS = "ubuntu-64"
        seedType = "cloud-init"
        bootArgs = "autoinstall ds=nocloud;s=/cdrom/"
        completionMarker = "/home/adp/.adp-provisioned"
        packages = @(
            "git", "curl", "wget", "build-essential", "ca-certificates",
            "gnupg", "lsb-release", "software-properties-common",
            "apt-transport-https", "unzip", "jq", "tree", "tmux",
            "htop", "iotop", "openssh-server", "open-vm-tools", "ripgrep", "fd-find", "fzf"
        )
    }
    "ubuntu-26.04" = @{
        guestOS = "ubuntu-64"
        seedType = "cloud-init"
        bootArgs = "autoinstall ds=nocloud;s=/cdrom/"
        completionMarker = "/home/adp/.adp-provisioned"
        packages = @(
            "git", "curl", "wget", "build-essential", "ca-certificates",
            "gnupg", "lsb-release", "software-properties-common",
            "apt-transport-https", "unzip", "jq", "tree", "tmux",
            "htop", "iotop", "openssh-server", "open-vm-tools", "ripgrep", "fd-find", "fzf"
        )
    }
    "almalinux-9" = @{
        guestOS = "centos-64"
        seedType = "kickstart"
        bootArgs = "inst.ks=cdrom:/ks.cfg"
        completionMarker = "/home/adp/.adp-provisioned"
        packages = @(
            "git", "curl", "wget", "gcc", "gcc-c++", "make",
            "ca-certificates", "unzip", "jq", "tree", "tmux",
            "htop", "iotop", "openssh-server", "ripgrep", "fd-find", "fzf"
        )
    }
    "rockylinux-9" = @{
        guestOS = "centos-64"
        seedType = "kickstart"
        bootArgs = "inst.ks=cdrom:/ks.cfg"
        completionMarker = "/home/adp/.adp-provisioned"
        packages = @(
            "git", "curl", "wget", "gcc", "gcc-c++", "make",
            "ca-certificates", "unzip", "jq", "tree", "tmux",
            "htop", "iotop", "openssh-server", "ripgrep", "fd-find", "fzf"
        )
    }
    "debian-12" = @{
        guestOS = "debian-64"
        seedType = "preseed"
        bootArgs = "auto=true priority=critical file=/cdrom/preseed.cfg"
        completionMarker = "/home/adp/.adp-provisioned"
        packages = @(
            "git", "curl", "wget", "build-essential", "ca-certificates",
            "gnupg", "lsb-release", "software-properties-common",
            "apt-transport-https", "unzip", "jq", "tree", "tmux",
            "htop", "iotop", "openssh-server", "ripgrep", "fd-find", "fzf"
        )
    }
}

function Get-OSProfile {
    param([string]$OSName)

    $profile = $script:OSProfiles[$OSName]
    if (-not $profile) {
        throw "OS profile '$OSName' not found. Available: $($script:OSProfiles.Keys -join ', ')"
    }
    return $profile
}

function Get-AvailableOSProfiles {
    return $script:OSProfiles.Keys | Sort-Object
}
