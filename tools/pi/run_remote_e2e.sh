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
UART_PORT="${PI_UART_PORT:-}"
SERIAL_PORT="${PI_SERIAL_PORT:-}"
if [[ "${BOARD_NAME}" == "wroom" && -z "${SERIAL_PORT}" ]]; then
  SERIAL_PORT="${PORT}"
fi

has_sta_test_config() {
  if [[ -n "${TEST_STA_SSID:-}" ]]; then
    return 0
  fi
  [[ -f "${ROOT_DIR}/tools/pi/local.env" ]]
}

log() {
  printf '[pi-run] %s\n' "$1"
}

collect_changed_files() {
  {
    git -C "${ROOT_DIR}" diff --name-only --diff-filter=ACMRT HEAD -- . 2>/dev/null || true
    git -C "${ROOT_DIR}" ls-files --others --exclude-standard 2>/dev/null || true
  } | awk 'NF' | sort -u
}

needs_firmware_build() {
  local path="$1"
  case "${path}" in
    firmware/*|firmware_minimal/*|third_party/*|web/*)
      return 0
      ;;
    package.json|package-lock.json|pnpm-lock.yaml|npm-shrinkwrap.json)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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
  printf "AP_SSID='%s' BLE_NAME='%s' PAGE_URL='%s' MDNS_HTTP_BASE_URL='%s' HTTP_BASE_URL='%s' WS_URL='ws://%s.local:81' CONTROLLER_HOSTNAME='%s' CONTROLLER_LOCAL_URL='%s' EXPECTED_TRANSPORT='%s' EXPECTED_VARIANT='%s' CONTROLLER_DEVICE_UUID='%s' CONTROLLER_DEBUG_LOGS='%s' PI_UART_PORT='%s' PI_SERIAL_PORT='%s'" \
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
    "${CONTROLLER_DEVICE_UUID}" \
    "${CONTROLLER_DEBUG_LOGS:-0}" \
    "${UART_PORT}" \
    "${SERIAL_PORT}"
}

stage_repo_snapshot() {
  log "staging current repo snapshot on ${PI_HOST}:${REMOTE_BASE_DIR}"
  PI_HOST="${PI_HOST}" REMOTE_BASE_DIR="${REMOTE_BASE_DIR}" "${ROOT_DIR}/tools/pi/sync_repo_to_pi.sh"
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

mapfile -t changed_files < <(collect_changed_files)
firmware_build_required=0
for path in "${changed_files[@]}"; do
  if needs_firmware_build "${path}"; then
    firmware_build_required=1
    break
  fi
done

if [[ "${firmware_build_required}" == "1" ]]; then
  log "building, flashing, and validating ${BOARD_NAME} (${HOST_MODE}) from the Pi"
  remote_exec "SKIP_WEB_SYNC_IF_PREBUILT=1 CONTROLLER_BOARD='${BOARD_NAME}' CONTROLLER_HOST_MODE='${HOST_MODE}' CONTROLLER_DEVICE_UUID='${CONTROLLER_DEVICE_UUID}' CONTROLLER_DEBUG_LOGS='${CONTROLLER_DEBUG_LOGS:-0}' ./tools/pi/wait_for_acm_then_upload.sh --board '${BOARD_NAME}' --host-mode '${HOST_MODE}' --device-uuid '${CONTROLLER_DEVICE_UUID}' --port '${PORT}' --with-uploadfs"
else
  log "skipping firmware upload; only non-firmware files changed"
fi

log "running remote Pi end-to-end test"
if [[ "${HOST_MODE}" == "ble" ]]; then
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_ws_to_ble_test.sh'"
elif [[ "${HOST_MODE}" == "usb_switch" ]]; then
  remote_exec "$(remote_env_prefix) chmod +x './tools/pi/'*.sh './tools/pi/'*.py && './tools/pi/e2e_ws_to_switch_test.sh'"
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
