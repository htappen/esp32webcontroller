#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_NAME="${1:-ESP32 Web Gamepad}"

log() {
  printf '[pi-pair] %s\n' "$1"
}

fail() {
  printf '[pi-pair] %s\n' "$1" >&2
  exit 1
}

"${SCRIPT_DIR}/check_bluetooth.sh"
python3 "${SCRIPT_DIR}/bluez_pair_gamepad.py" --device-name "${DEVICE_NAME}" || fail "agent-based pairing failed"
