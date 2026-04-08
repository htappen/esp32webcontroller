#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT=""
BOARD_OVERRIDE="${CONTROLLER_BOARD:-s3}"
HOST_MODE_OVERRIDE="${CONTROLLER_HOST_MODE:-usb_xinput}"
DEVICE_UUID="${CONTROLLER_DEVICE_UUID:-${DEFAULT_TEST_DEVICE_UUID}}"
STA_SSID_OVERRIDE="${CONTROLLER_DEFAULT_STA_SSID:-}"
STA_PASS_OVERRIDE="${CONTROLLER_DEFAULT_STA_PASS:-}"
ERASE_FLASH_FIRST="${ERASE_FLASH_FIRST:-1}"

log() {
  printf '[pi-flash] %s\n' "$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    --host-mode)
      HOST_MODE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --device-uuid)
      DEVICE_UUID="${2:-}"
      shift 2
      ;;
    --sta-ssid)
      STA_SSID_OVERRIDE="${2:-}"
      shift 2
      ;;
    --sta-pass)
      STA_PASS_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      if [[ -z "${PORT}" ]]; then
        PORT="$1"
        shift
      else
        printf '[pi-flash] unknown argument: %s\n' "$1" >&2
        exit 1
      fi
      ;;
  esac
done

BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
HOST_MODE="$(canonical_host_mode "${HOST_MODE_OVERRIDE}")"

log "trying normal flash path first with no GPIO-JTAG prep"
set +e
CONTROLLER_BOARD="${BOARD_NAME}" \
  CONTROLLER_HOST_MODE="${HOST_MODE}" \
  CONTROLLER_DEVICE_UUID="${DEVICE_UUID}" \
  CONTROLLER_DEFAULT_STA_SSID="${STA_SSID_OVERRIDE}" \
  CONTROLLER_DEFAULT_STA_PASS="${STA_PASS_OVERRIDE}" \
  ERASE_FLASH_FIRST="${ERASE_FLASH_FIRST}" \
  "${ROOT_DIR}/tools/hardware_integration_test.sh" "${PORT}"
plain_flash_status=$?
set -e

if [[ "${plain_flash_status}" -eq 0 ]]; then
  log "normal flash/startup path passed; debugger not needed"
  exit 0
fi
if [[ "${BOARD_NAME}" != "s3" ]]; then
  log "plain flash/startup path failed with status ${plain_flash_status}"
  exit "${plain_flash_status}"
fi

log "plain flash/startup path failed with status ${plain_flash_status}; switching to GPIO-JTAG debug flow"
bash "${ROOT_DIR}/tools/pi/prepare_s3_gpio_jtag.sh"
bash "${ROOT_DIR}/tools/pi/reset_s3_watchdog_if_present.sh"

if CONTROLLER_BOARD="${BOARD_NAME}" \
  CONTROLLER_HOST_MODE="${HOST_MODE}" \
  CONTROLLER_DEVICE_UUID="${DEVICE_UUID}" \
  CONTROLLER_DEFAULT_STA_SSID="${STA_SSID_OVERRIDE}" \
  CONTROLLER_DEFAULT_STA_PASS="${STA_PASS_OVERRIDE}" \
  "${ROOT_DIR}/tools/upload_firmware.sh" \
    --board "${BOARD_NAME}" \
    --host-mode "${HOST_MODE}" \
    --device-uuid "${DEVICE_UUID}" \
    --sta-ssid "${STA_SSID_OVERRIDE}" \
    --sta-pass "${STA_PASS_OVERRIDE}" \
    "${PORT}"; then
  log "fallback reflash succeeded; launching GPIO-JTAG debugger"
else
  log "fallback reflash failed; launching GPIO-JTAG debugger against the last flashed image"
fi

exec env \
  CONTROLLER_BOARD="${BOARD_NAME}" \
  CONTROLLER_HOST_MODE="${HOST_MODE}" \
  "${ROOT_DIR}/tools/pi/debug_startup_s3.sh"
