#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

DEVICE_NAME="${1:-${BLE_NAME:-${CONTROLLER_DEVICE_BLE_NAME}}}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"

log() {
  printf '[pi-pair] %s\n' "$1"
}

fail() {
  printf '[pi-pair] %s\n' "$1" >&2
  exit 1
}

"${SCRIPT_DIR}/check_bluetooth.sh"
"${SCRIPT_DIR}/setup_python_harness.sh"
"${VENV_PYTHON}" "${SCRIPT_DIR}/bluez_pair_gamepad.py" --device-name "${DEVICE_NAME}" || fail "agent-based pairing failed"
