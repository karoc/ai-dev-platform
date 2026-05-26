#!/bin/bash
# ADP-OS Common Bootstrap Utilities
# Sourced by other setup scripts — not run directly

check-root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
    fi
}

mark-step() {
    echo "[$(date +%H:%M:%S)] $@"
}

is-installed() {
    command -v "$1" &>/dev/null
}

ensure-file() {
    local file="$1"
    local content="$2"
    if [ ! -f "$file" ]; then
        echo "$content" > "$file"
        echo "  Created: $file"
    fi
}

retry() {
    local n=0
    local max=3
    until "$@"; do
        n=$((n + 1))
        if [ $n -ge $max ]; then
            echo "Failed after $max attempts: $*"
            return 1
        fi
        echo "Retry $n/$max..."
        sleep 2
    done
}
