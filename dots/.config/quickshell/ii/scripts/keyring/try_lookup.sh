#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure DB-Bus session address is valid
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS}" == "disabled:" ]]; then
    if [[ -S "/run/user/$(id -u)/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi
fi

# Crucial: Check if the keyring is unlocked FIRST before running secret-tool!
# Running secret-tool while locked prompts the GUI password modal on the screen.
if ! "${SCRIPT_DIR}/is_unlocked.sh" >/dev/null 2>&1; then
    echo 'locked'
    exit 2
fi

data=$(secret-tool lookup 'application' 'illogical-impulse' 2>/dev/null)
if [[ -z "$data" ]]; then
    echo 'not found'
    exit 1
fi
echo "$data"

