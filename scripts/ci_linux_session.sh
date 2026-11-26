#!/usr/bin/env bash
# Runs a command inside a D-Bus session with an unlocked, empty GNOME keyring,
# the secret service a desktop login provides. A headless CI runner has none,
# and on it the app's secret-vault check (libsecret) ends the whole process, so
# every integration test that opens a workspace died. Usage, inside
# `dbus-run-session --`: scripts/ci_linux_session.sh <command> [args...]
set -eu
eval "$(printf '\n' | gnome-keyring-daemon --unlock --components=secrets)"
export GNOME_KEYRING_CONTROL
exec "$@"
