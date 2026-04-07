#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/device_identity.sh"
PI_HOST="${PI_HOST:-controller-pi}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/home/controller/controller-pi-e2e}"
PORT="${1:-}"
RUN_BROWSER_TEST="${RUN_BROWSER_TEST:-1}"
RUN_STA_TESTS="${RUN_STA_TESTS:-auto}"
BOARD_NAME="${CONTROLLER_BOARD:-s3}"
HOST_MODE="${CONTROLLER_HOST_MODE:-ble}"
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
  printf "AP_SSID='%s' BLE_NAME='%s' PAGE_URL='%s' MDNS_HTTP_BASE_URL='%s' HTTP_BASE_URL='%s' WS_URL='ws://%s.local:81' CONTROLLER_HOSTNAME='%s' CONTROLLER_LOCAL_URL='%s' EXPECTED_TRANSPORT='%s' EXPECTED_VARIANT='%s' CONTROLLER_DEVICE_UUID='%s'" \
    "${CONTROLLER_DEVICE_AP_SSID}" \
    "${CONTROLLER_DEVICE_BLE_NAME}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "${CONTROLLER_DEVICE_HOSTNAME}" \
    "${CONTROLLER_DEVICE_HOSTNAME}" \
    "${CONTROLLER_DEVICE_LOCAL_URL}" \
    "$([[ "${HOST_MODE}" == "ble" ]] && printf 'ble' || printf 'usb')" \
    "$([[ "${HOST_MODE}" == "usb_xinput" ]] && printf 'pc' || ([[ "${HOST_MODE}" == "usb_switch" ]] && printf 'switch' || printf 'default'))" \
    "${CONTROLLER_DEVICE_UUID}"
}

stage_repo_snapshot() {
  log "staging current repo snapshot on ${PI_HOST}:${REMOTE_BASE_DIR}"
  tar -C "${ROOT_DIR}" \
    --exclude=".git" \
    --exclude=".venv" \
    --exclude=".platformio" \
    --exclude="web/node_modules" \
    --exclude="third_party/virtual-gamepad-lib/node_modules" \
    -cf - . \
    | ssh "${PI_HOST}" "mkdir -p '${REMOTE_BASE_DIR}' && tar -C '${REMOTE_BASE_DIR}' -xf -"
}

ensure_remote_env() {
  log "ensuring Pi-side build environment exists"
  ssh "${PI_HOST}" "cd '${REMOTE_BASE_DIR}' && if [[ ! -x '.venv/bin/pio' ]]; then python3 -m venv '.venv' && . '.venv/bin/activate' && python -m pip install --upgrade pip && python -m pip install platformio; fi"
}

remote_exec() {
  ssh "${PI_HOST}" "cd '${REMOTE_BASE_DIR}' && $*"
}

resolve_test_identity

stage_repo_snapshot
ensure_remote_env

log "building, flashing, and validating ${BOARD_NAME} (${HOST_MODE}) from the Pi"
remote_exec "SKIP_WEB_SYNC_IF_PREBUILT=1 CONTROLLER_BOARD='${BOARD_NAME}' CONTROLLER_HOST_MODE='${HOST_MODE}' CONTROLLER_DEVICE_UUID='${CONTROLLER_DEVICE_UUID}' ERASE_FLASH_FIRST=1 ./tools/pi/flash_or_debug_s3.sh '${PORT}'"

log "running remote Pi end-to-end test"
if [[ "${HOST_MODE}" == "ble" ]]; then
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_ws_to_ble_test.sh'"
else
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_ws_to_usb_test.sh'"
fi

if [[ "${RUN_BROWSER_TEST}" == "1" ]]; then
  log "running remote Pi browser page smoke test"
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_browser_test.sh'"
fi

if [[ "${HOST_MODE}" == "ble" && ( "${RUN_STA_TESTS}" == "1" || ( "${RUN_STA_TESTS}" == "auto" && has_sta_test_config ) ) ]]; then
  log "running remote Pi STA transition test with good credentials"
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_sta_transition_test.sh' good-transition"

  log "rebooting ESP32 from the Pi to verify saved STA reconnect"
  remote_exec "./tools/reboot_board.sh '${PORT}'"
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_sta_transition_test.sh' verify-saved"

  log "running remote Pi failed STA update rollback test"
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_sta_transition_test.sh' bad-update"

  log "rebooting ESP32 from the Pi to confirm prior saved STA credentials still win after bad update"
  remote_exec "./tools/reboot_board.sh '${PORT}'"
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_sta_transition_test.sh' verify-saved"
else
  log "skipping STA transition tests because they only apply to BLE mode or no local STA credentials were provided"
fi
