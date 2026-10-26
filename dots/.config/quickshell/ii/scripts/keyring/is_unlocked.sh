#!/usr/bin/env bash

# Ensure DB-Bus session address is valid
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS}" == "disabled:" ]]; then
    if [[ -S "/run/user/$(id -u)/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi
fi

locked_state=$(busctl --user get-property org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/login \
    org.freedesktop.Secret.Collection Locked 2>/dev/null)
if [[ "${locked_state}" == "b false" ]]; then
    echo 'Keyring is unlocked' >&2
    exit 0
else
    echo 'Keyring is locked' >&2
    exit 1
fi
