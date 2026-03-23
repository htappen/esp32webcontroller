#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

UPLOAD_PORT="${1:-}"

log() {
  printf '[upload] %s\n' "$1"
}

pio_run() {
  if [[ -n "${UPLOAD_PORT}" ]]; then
    pio run --upload-port "${UPLOAD_PORT}" "$@"
  else
    pio run "$@"
  fi
}

activate_platformio_env

log "using PlatformIO core dir: ${PLATFORMIO_CORE_DIR}"
UPLOAD_PORT="$(resolve_serial_port "${UPLOAD_PORT}" || true)"

if [[ -n "${UPLOAD_PORT}" ]]; then
  log "using upload port: ${UPLOAD_PORT}"
else
  log "no serial upload port detected"
  log "pass a port as the first argument or set PIO_UPLOAD_PORT"
  log "common ports: /dev/ttyUSB0, /dev/ttyACM0, /dev/cu.usbserial-*"
  exit 1
fi

log "uploading filesystem image"
(
  cd "${FIRMWARE_DIR}"
  pio_run -e "${DEFAULT_ENV}" -t uploadfs
)

log "uploading firmware image"
(
  cd "${FIRMWARE_DIR}"
  pio_run -e "${DEFAULT_ENV}" -t upload
)

log "upload complete"
log "if auto-reset does not start flashing, hold BOOT, tap EN/RESET, then retry"
