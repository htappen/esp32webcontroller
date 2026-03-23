#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRMWARE_DIR="${ROOT_DIR}/firmware"
VENV_DIR="${ROOT_DIR}/.venv"
PLATFORMIO_CORE_DIR="${ROOT_DIR}/.platformio"
UPLOAD_PORT="${1:-${PIO_UPLOAD_PORT:-}}"
DEFAULT_ENV="esp32_wroom_32d"

detect_serial_port() {
  local port
  for port in /dev/ttyUSB* /dev/ttyACM* /dev/cu.usbserial* /dev/cu.SLAB_USBtoUART /dev/cu.wchusbserial*; do
    if [[ -e "${port}" ]]; then
      printf '%s\n' "${port}"
      return 0
    fi
  done
  return 1
}

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

if [[ ! -d "${VENV_DIR}" ]]; then
  log "missing virtual environment at ${VENV_DIR}"
  exit 1
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

export PLATFORMIO_CORE_DIR

log "using PlatformIO core dir: ${PLATFORMIO_CORE_DIR}"
if [[ -z "${UPLOAD_PORT}" ]]; then
  UPLOAD_PORT="$(detect_serial_port || true)"
fi

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
