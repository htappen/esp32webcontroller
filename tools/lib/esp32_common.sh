#!/usr/bin/env bash

if [[ -n "${ESP32_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
ESP32_COMMON_SH_LOADED=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIRMWARE_DIR="${ROOT_DIR}/firmware"
VENV_DIR="${ROOT_DIR}/.venv"
PLATFORMIO_CORE_DIR="${ROOT_DIR}/.platformio"
DEFAULT_ENV="esp32_wroom_32d"

require_virtualenv() {
  if [[ ! -d "${VENV_DIR}" ]]; then
    printf '[esp32] missing virtual environment at %s\n' "${VENV_DIR}" >&2
    return 1
  fi
}

activate_platformio_env() {
  require_virtualenv || return 1
  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"
  export PLATFORMIO_CORE_DIR
}

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

resolve_serial_port() {
  local requested_port="${1:-${PIO_UPLOAD_PORT:-}}"
  if [[ -n "${requested_port}" ]]; then
    printf '%s\n' "${requested_port}"
    return 0
  fi

  detect_serial_port
}
