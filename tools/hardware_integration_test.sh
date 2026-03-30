#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT=""
BOARD_OVERRIDE=""
ERASE_FLASH_FIRST="${ERASE_FLASH_FIRST:-0}"
BOOT_LOG_DURATION_SECONDS="${BOOT_LOG_DURATION_SECONDS:-}"
LOG_FILE="$(mktemp)"
cleanup() {
  rm -f "${LOG_FILE}"
}
trap cleanup EXIT

log() {
  printf '[hw-test] %s\n' "$1"
}

fail() {
  printf '[hw-test] %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      if [[ -z "${PORT}" ]]; then
        PORT="$1"
        shift
      else
        fail "unknown argument: $1"
      fi
      ;;
  esac
done

PORT="$(resolve_serial_port "${PORT}" || true)"
if [[ -z "${PORT}" ]]; then
  fail "no serial port detected; pass a port or set PIO_UPLOAD_PORT"
fi

activate_platformio_env
BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
ENV_NAME="${PIO_ENV:-$(resolve_pio_env "${BOARD_NAME}")}"

if [[ -z "${BOOT_LOG_DURATION_SECONDS}" ]]; then
  if [[ "${BOARD_NAME}" == "s3" ]]; then
    BOOT_LOG_DURATION_SECONDS=12
  else
    BOOT_LOG_DURATION_SECONDS=8
  fi
fi

if [[ "${ERASE_FLASH_FIRST}" == "1" ]]; then
  log "erasing ${BOARD_NAME} flash on ${PORT} before upload"
  "${ROOT_DIR}/tools/erase_flash.sh" --board "${BOARD_NAME}" "${PORT}"
fi

log "building firmware for ${BOARD_NAME} via ${ENV_NAME}"
(
  cd "${FIRMWARE_DIR}"
  pio run -e "${ENV_NAME}"
)

log "uploading filesystem and firmware to ${PORT}"
"${ROOT_DIR}/tools/upload_firmware.sh" --board "${BOARD_NAME}" "${PORT}"

log "capturing boot log from ${PORT}"
"${ROOT_DIR}/tools/capture_boot_log.sh" "${PORT}" "${BOOT_LOG_DURATION_SECONDS}" | tee "${LOG_FILE}"

grep -q "ESP32 web BLE controller scaffold booted" "${LOG_FILE}" \
  || {
    if [[ "${BOARD_NAME}" == "wroom" ]]; then
      fail "boot banner missing from serial log"
    fi
  }

if [[ "${BOARD_NAME}" == "s3" ]]; then
  if grep -Eq "Probe failed|assert failed:|Guru Meditation|Backtrace:" "${LOG_FILE}"; then
    fail "serial log captured an S3 startup fault"
  fi
fi

if grep -q "E NimBLEAdvertising: Host not synced!" "${LOG_FILE}"; then
  fail "BLE advertising started before NimBLE host sync completed"
fi

log "hardware startup checks passed"
