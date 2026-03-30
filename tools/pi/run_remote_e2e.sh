#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PI_HOST="${PI_HOST:-controller-pi}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/tmp/controller-pi-e2e}"
PORT="${1:-}"
RUN_BROWSER_TEST="${RUN_BROWSER_TEST:-1}"
RUN_STA_TESTS="${RUN_STA_TESTS:-auto}"
BOARD_NAME="${CONTROLLER_BOARD:-s3}"

has_sta_test_config() {
  if [[ -n "${TEST_STA_SSID:-}" ]]; then
    return 0
  fi
  [[ -f "${ROOT_DIR}/tools/pi/local.env" ]]
}

log() {
  printf '[pi-run] %s\n' "$1"
}

log "building, flashing, and validating ${BOARD_NAME} startup locally"
CONTROLLER_BOARD="${BOARD_NAME}" ERASE_FLASH_FIRST=1 "${ROOT_DIR}/tools/hardware_integration_test.sh" "${PORT}"

log "staging Pi helper scripts on ${PI_HOST}:${REMOTE_BASE_DIR}"
tar -C "${ROOT_DIR}" -cf - tools/pi | ssh "${PI_HOST}" "rm -rf '${REMOTE_BASE_DIR}' && mkdir -p '${REMOTE_BASE_DIR}' && tar -C '${REMOTE_BASE_DIR}' -xf -"

log "running remote Pi end-to-end test"
ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_ws_to_ble_test.sh'"

if [[ "${RUN_BROWSER_TEST}" == "1" ]]; then
  log "running remote Pi browser page smoke test"
  ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_browser_test.sh'"
fi

if [[ "${RUN_STA_TESTS}" == "1" || ( "${RUN_STA_TESTS}" == "auto" && has_sta_test_config ) ]]; then
  log "running remote Pi STA transition test with good credentials"
  ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' good-transition"

  log "rebooting ESP32 locally to verify saved STA reconnect"
  "${ROOT_DIR}/tools/reboot_board.sh" "${PORT}"
  ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' verify-saved"

  log "running remote Pi failed STA update rollback test"
  ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' bad-update"

  log "rebooting ESP32 locally to confirm prior saved STA credentials still win after bad update"
  "${ROOT_DIR}/tools/reboot_board.sh" "${PORT}"
  ssh "${PI_HOST}" "chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' verify-saved"
else
  log "skipping STA transition tests because no local STA credentials were provided"
fi
