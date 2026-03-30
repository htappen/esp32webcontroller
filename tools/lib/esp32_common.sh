#!/usr/bin/env bash

if [[ -n "${ESP32_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
ESP32_COMMON_SH_LOADED=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIRMWARE_DIR="${ROOT_DIR}/firmware"
VENV_DIR="${ROOT_DIR}/.venv"
PLATFORMIO_CORE_DIR="${ROOT_DIR}/.platformio"
DEFAULT_BOARD="s3"

canonical_board_name() {
  local requested="${1:-${CONTROLLER_BOARD:-${BOARD:-${PIO_BOARD:-${DEFAULT_BOARD}}}}}"
  requested="${requested,,}"

  case "${requested}" in
    s3|esp32-s3|esp32_s3|esp32_s3_devkitc_1|esp32-s3-devkitc-1)
      printf 's3\n'
      ;;
    wroom|esp32|classic|esp32-wroom-32d|esp32_wroom_32d)
      printf 'wroom\n'
      ;;
    *)
      printf '[esp32] unsupported board "%s"; use "s3" or "wroom"\n' "${requested}" >&2
      return 1
      ;;
  esac
}

board_to_pio_env() {
  case "${1}" in
    s3)
      printf 'esp32_s3_devkitc_1\n'
      ;;
    wroom)
      printf 'esp32_wroom_32d\n'
      ;;
    *)
      printf '[esp32] unsupported canonical board "%s"\n' "${1}" >&2
      return 1
      ;;
  esac
}

board_to_esptool_chip() {
  case "${1}" in
    s3)
      printf 'esp32s3\n'
      ;;
    wroom)
      printf 'esp32\n'
      ;;
    *)
      printf '[esp32] unsupported canonical board "%s"\n' "${1}" >&2
      return 1
      ;;
  esac
}

resolve_board() {
  canonical_board_name "${1:-}"
}

resolve_pio_env() {
  local board
  board="$(resolve_board "${1:-}")" || return 1
  board_to_pio_env "${board}"
}

resolve_esptool_chip() {
  local board
  board="$(resolve_board "${1:-}")" || return 1
  board_to_esptool_chip "${board}"
}

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
