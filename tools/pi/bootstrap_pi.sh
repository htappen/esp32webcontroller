#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[pi-bootstrap] %s\n' "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[pi-bootstrap] missing required command: %s\n' "${cmd}" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd nmcli
require_cmd bluetoothctl
require_cmd curl
require_cmd sudo

log "ensuring bluetooth service is running"
sudo systemctl start bluetooth

log "Pi runtime checks passed"
