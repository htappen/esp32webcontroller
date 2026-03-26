#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PI_HOST="${PI_HOST:-controller-pi}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/tmp/controller-pi-e2e}"
PORT="${1:-}"
RUN_BROWSER_TEST="${RUN_BROWSER_TEST:-1}"

log() {
  printf '[pi-run] %s\n' "$1"
}

log "building, flashing, and validating ESP32 startup locally"
"${ROOT_DIR}/tools/hardware_integration_test.sh" "${PORT}"

log "staging Pi helper scripts on ${PI_HOST}:${REMOTE_BASE_DIR}"
tar -C "${ROOT_DIR}" -cf - tools/pi | ssh "${PI_HOST}" "rm -rf '${REMOTE_BASE_DIR}' && mkdir -p '${REMOTE_BASE_DIR}' && tar -C '${REMOTE_BASE_DIR}' -xf -"

log "running remote Pi end-to-end test"
ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_ws_to_ble_test.sh'"

if [[ "${RUN_BROWSER_TEST}" == "1" ]]; then
  log "running remote Pi browser UI end-to-end test"
  ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_browser_test.sh'"
fi
