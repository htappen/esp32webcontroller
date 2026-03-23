#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT="${1:-}"
ENV_NAME="${PIO_ENV:-${DEFAULT_ENV}}"
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

PORT="$(resolve_serial_port "${PORT}" || true)"
if [[ -z "${PORT}" ]]; then
  fail "no serial port detected; pass a port or set PIO_UPLOAD_PORT"
fi

activate_platformio_env

log "building firmware for ${ENV_NAME}"
(
  cd "${FIRMWARE_DIR}"
  pio run -e "${ENV_NAME}"
)

log "uploading filesystem and firmware to ${PORT}"
"${ROOT_DIR}/tools/upload_firmware.sh" "${PORT}"

log "capturing boot log from ${PORT}"
"${ROOT_DIR}/tools/capture_boot_log.sh" "${PORT}" 8 | tee "${LOG_FILE}"

grep -q "ESP32 web BLE controller scaffold booted" "${LOG_FILE}" \
  || fail "boot banner missing from serial log"

if grep -q "E NimBLEAdvertising: Host not synced!" "${LOG_FILE}"; then
  fail "BLE advertising started before NimBLE host sync completed"
fi

log "hardware startup checks passed"
