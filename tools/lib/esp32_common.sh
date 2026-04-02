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
DEFAULT_HOST_MODE="ble"
LOCAL_CONTROLLER_ENV_FILE="${ROOT_DIR}/tools/local.env"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/device_identity.sh"

load_local_controller_env() {
  if [[ -f "${LOCAL_CONTROLLER_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${LOCAL_CONTROLLER_ENV_FILE}"
    set +a
  fi
}

load_local_controller_env

set_sta_seed_credentials() {
  local ssid="${1:-}"
  local pass="${2:-}"

  if [[ -n "${ssid}" ]]; then
    export CONTROLLER_DEFAULT_STA_SSID="${ssid}"
  fi

  if [[ -n "${pass}" ]]; then
    export CONTROLLER_DEFAULT_STA_PASS="${pass}"
  fi
}

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
  local board="${1}"
  local host_mode="${2:-${CONTROLLER_HOST_MODE:-${HOST_MODE:-${DEFAULT_HOST_MODE}}}}"
  host_mode="${host_mode,,}"

  case "${board}:${host_mode}" in
    s3:ble)
      printf 'esp32_s3_devkitc_1\n'
      ;;
    s3:usb_switch|s3:usb-switch|s3:switch)
      printf 'esp32_s3_devkitc_1_usb_switch\n'
      ;;
    wroom:ble)
      printf 'esp32_wroom_32d\n'
      ;;
    wroom:usb_switch|wroom:usb-switch|wroom:switch)
      printf '[esp32] board "%s" does not support native USB host mode\n' "${board}" >&2
      return 1
      ;;
    *)
      printf '[esp32] unsupported board/mode combination "%s:%s"\n' "${board}" "${host_mode}" >&2
      return 1
      ;;
  esac
}

canonical_host_mode() {
  local requested="${1:-${CONTROLLER_HOST_MODE:-${HOST_MODE:-${DEFAULT_HOST_MODE}}}}"
  requested="${requested,,}"

  case "${requested}" in
    ble|bluetooth)
      printf 'ble\n'
      ;;
    usb_switch|usb-switch|switch)
      printf 'usb_switch\n'
      ;;
    *)
      printf '[esp32] unsupported host mode "%s"; use "ble" or "usb_switch"\n' "${requested}" >&2
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
  local host_mode
  host_mode="$(canonical_host_mode "${2:-}")" || return 1
  board_to_pio_env "${board}" "${host_mode}"
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

prepare_controller_identity() {
  local mode="${1:-test}"
  local explicit_uuid="${2:-${CONTROLLER_DEVICE_UUID:-}}"
  resolve_device_identity "${mode}" "${explicit_uuid}" || return 1
  export CONTROLLER_DEVICE_UUID
  export CONTROLLER_DEVICE_ADJECTIVE
  export CONTROLLER_DEVICE_NOUN
  export CONTROLLER_DEVICE_FRIENDLY_NAME
  export CONTROLLER_DEVICE_AP_SSID
  export CONTROLLER_DEVICE_BLE_NAME
  export CONTROLLER_DEVICE_HOSTNAME
  export CONTROLLER_DEVICE_MDNS_INSTANCE_NAME
  export CONTROLLER_DEVICE_LOCAL_URL
  write_device_identity_header
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
