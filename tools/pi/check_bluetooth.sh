#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[pi-bt] %s\n' "$1"
}

fail() {
  printf '[pi-bt] %s\n' "$1" >&2
  exit 1
}

log "unblocking bluetooth rfkill state"
sudo rfkill unblock bluetooth || true
sudo systemctl start bluetooth

if ! bluetoothctl show >/dev/null 2>&1; then
  fail "bluetoothctl show failed"
fi

if bluetoothctl show | grep -q $'\tPowered: yes'; then
  log "bluetooth adapter already powered"
  exit 0
fi

log "powering bluetooth adapter on"
printf 'power on\nquit\n' | bluetoothctl >/dev/null
sleep 1

if ! bluetoothctl show | grep -q $'\tPowered: yes'; then
  bluetoothctl show >&2
  fail "bluetooth adapter is not powered"
fi

log "bluetooth adapter ready"
