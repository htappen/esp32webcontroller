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

log "flashing over ACM only"
exec env \
  CONTROLLER_BOARD="${BOARD_NAME}" \
  CONTROLLER_HOST_MODE="${HOST_MODE}" \
  CONTROLLER_DEVICE_UUID="${DEVICE_UUID}" \
  CONTROLLER_DEFAULT_STA_SSID="${STA_SSID_OVERRIDE}" \
  CONTROLLER_DEFAULT_STA_PASS="${STA_PASS_OVERRIDE}" \
  "${ROOT_DIR}/tools/pi/wait_for_acm_then_upload.sh" \
    --board "${BOARD_NAME}" \
    --host-mode "${HOST_MODE}" \
    --device-uuid "${DEVICE_UUID}" \
    --sta-ssid "${STA_SSID_OVERRIDE}" \
    --sta-pass "${STA_PASS_OVERRIDE}" \
    --with-uploadfs
