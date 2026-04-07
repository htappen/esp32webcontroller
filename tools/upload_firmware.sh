#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

UPLOAD_PORT=""
BOARD_OVERRIDE=""
HOST_MODE_OVERRIDE=""
DEVICE_UUID=""
STA_SSID_OVERRIDE=""
STA_PASS_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
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
    --host-mode)
      HOST_MODE_OVERRIDE="${2:-}"
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
HOST_MODE="$(canonical_host_mode "${HOST_MODE_OVERRIDE}")"
ENV_NAME="$(resolve_pio_env "${BOARD_NAME}" "${HOST_MODE}")"
set_sta_seed_credentials "${STA_SSID_OVERRIDE}" "${STA_PASS_OVERRIDE}"
prepare_controller_identity "build" "${DEVICE_UUID}"

log "using PlatformIO core dir: ${PLATFORMIO_CORE_DIR}"
log "using board target: ${BOARD_NAME} (${HOST_MODE}; ${ENV_NAME})"
log "using device uuid: ${CONTROLLER_DEVICE_UUID}"
log "using device name: ${CONTROLLER_DEVICE_FRIENDLY_NAME}"
log "using device url: ${CONTROLLER_DEVICE_LOCAL_URL}"
if [[ -n "${CONTROLLER_DEFAULT_STA_SSID:-}" ]]; then
  log "default saved STA ssid: ${CONTROLLER_DEFAULT_STA_SSID}"
fi
if [[ "${CONTROLLER_USB_XINPUT_DEFER_BEGIN:-0}" == "1" ]]; then
  log "deferring USB.begin() for usb_xinput diagnostics"
fi
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

if [[ "${BOARD_NAME}" == "s3" ]]; then
  log "requesting post-upload watchdog reset"
  if ! CONTROLLER_BOARD="${BOARD_NAME}" "${ROOT_DIR}/tools/reboot_board.sh" "${UPLOAD_PORT}"; then
    log "post-upload watchdog reset failed; manual EN/RESET may still be required"
  fi
fi

log "upload complete"
log "if auto-reset does not start flashing, hold BOOT, tap EN/RESET, then retry"
