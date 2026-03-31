#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/device_identity.sh"
PI_HOST="${PI_HOST:-controller-pi}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/tmp/controller-pi-e2e}"
PORT="${1:-}"
RUN_BROWSER_TEST="${RUN_BROWSER_TEST:-1}"
RUN_STA_TESTS="${RUN_STA_TESTS:-auto}"
BOARD_NAME="${CONTROLLER_BOARD:-s3}"
DEVICE_UUID="${CONTROLLER_DEVICE_UUID:-${DEFAULT_TEST_DEVICE_UUID}}"

has_sta_test_config() {
  if [[ -n "${TEST_STA_SSID:-}" ]]; then
    return 0
  fi
  [[ -f "${ROOT_DIR}/tools/pi/local.env" ]]
}

log() {
  printf '[pi-run] %s\n' "$1"
}

resolve_test_identity() {
  resolve_device_identity "test" "${DEVICE_UUID}"
  export CONTROLLER_DEVICE_UUID
  export CONTROLLER_DEVICE_FRIENDLY_NAME
  export CONTROLLER_DEVICE_AP_SSID
  export CONTROLLER_DEVICE_BLE_NAME
  export CONTROLLER_DEVICE_HOSTNAME
  export CONTROLLER_DEVICE_MDNS_INSTANCE_NAME
  export CONTROLLER_DEVICE_LOCAL_URL
}

remote_env_prefix() {
  printf "AP_SSID='%s' BLE_NAME='%s' PAGE_URL='%s' MDNS_HTTP_BASE_URL='%s' HTTP_BASE_URL='%s' WS_URL='ws://%s.local:81' CONTROLLER_HOSTNAME='%s' CONTROLLER_LOCAL_URL='%s'" \
    "${CONTROLLER_DEVICE_AP_SSID}" \
    "${CONTROLLER_DEVICE_BLE_NAME}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "${CONTROLLER_DEVICE_HOSTNAME}" \
    "${CONTROLLER_DEVICE_HOSTNAME}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}"
}

resolve_test_identity

log "building, flashing, and validating ${BOARD_NAME} startup locally"
CONTROLLER_BOARD="${BOARD_NAME}" CONTROLLER_DEVICE_UUID="${CONTROLLER_DEVICE_UUID}" ERASE_FLASH_FIRST=1 \
  "${ROOT_DIR}/tools/hardware_integration_test.sh" "${PORT}"

log "staging Pi helper scripts on ${PI_HOST}:${REMOTE_BASE_DIR}"
tar -C "${ROOT_DIR}" -cf - tools/pi tools/lib | ssh "${PI_HOST}" "rm -rf '${REMOTE_BASE_DIR}' && mkdir -p '${REMOTE_BASE_DIR}' && tar -C '${REMOTE_BASE_DIR}' -xf -"

log "running remote Pi end-to-end test"
ssh "${PI_HOST}" "$(remote_env_prefix) chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_ws_to_ble_test.sh'"

if [[ "${RUN_BROWSER_TEST}" == "1" ]]; then
  log "running remote Pi browser page smoke test"
  ssh "${PI_HOST}" "$(remote_env_prefix) chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_browser_test.sh'"
fi

if [[ "${RUN_STA_TESTS}" == "1" || ( "${RUN_STA_TESTS}" == "auto" && has_sta_test_config ) ]]; then
  log "running remote Pi STA transition test with good credentials"
  ssh "${PI_HOST}" "$(remote_env_prefix) chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' good-transition"

  log "rebooting ESP32 locally to verify saved STA reconnect"
  "${ROOT_DIR}/tools/reboot_board.sh" "${PORT}"
  ssh "${PI_HOST}" "$(remote_env_prefix) chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' verify-saved"

  log "running remote Pi failed STA update rollback test"
  ssh "${PI_HOST}" "$(remote_env_prefix) chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' bad-update"

  log "rebooting ESP32 locally to confirm prior saved STA credentials still win after bad update"
  "${ROOT_DIR}/tools/reboot_board.sh" "${PORT}"
  ssh "${PI_HOST}" "$(remote_env_prefix) chmod +x '${REMOTE_BASE_DIR}/tools/pi/'*.sh '${REMOTE_BASE_DIR}/tools/pi/'*.py && '${REMOTE_BASE_DIR}/tools/pi/e2e_sta_transition_test.sh' verify-saved"
else
  log "skipping STA transition tests because no local STA credentials were provided"
fi
