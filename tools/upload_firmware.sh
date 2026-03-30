#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

UPLOAD_PORT=""
BOARD_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      if [[ -z "${UPLOAD_PORT}" ]]; then
        UPLOAD_PORT="$1"
        shift
      else
        printf '[upload] unknown argument: %s\n' "$1" >&2
        exit 1
      fi
      ;;
  esac
done

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

BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
ENV_NAME="$(resolve_pio_env "${BOARD_NAME}")"

log "using PlatformIO core dir: ${PLATFORMIO_CORE_DIR}"
log "using board target: ${BOARD_NAME} (${ENV_NAME})"
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
  pio_run -e "${ENV_NAME}" -t uploadfs
)

log "uploading firmware image"
(
  cd "${FIRMWARE_DIR}"
  pio_run -e "${ENV_NAME}" -t upload
)

log "upload complete"
log "if auto-reset does not start flashing, hold BOOT, tap EN/RESET, then retry"
