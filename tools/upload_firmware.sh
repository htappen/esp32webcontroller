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
SKIP_UPLOADFS="${SKIP_UPLOADFS:-0}"

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
    --skip-uploadfs)
      SKIP_UPLOADFS="1"
      shift
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

try_s3_recovery() {
  if [[ "${BOARD_NAME}" != "s3" ]]; then
    return 1
  fi
  if [[ "${CONTROLLER_SKIP_S3_RECOVERY:-0}" == "1" ]]; then
    log "S3 no-button recovery disabled by CONTROLLER_SKIP_S3_RECOVERY=1"
    return 1
  fi
  if [[ ! -x "${ROOT_DIR}/tools/pi/recover_s3_without_button.sh" ]]; then
    return 1
  fi

  log "trying S3 no-button recovery before retrying firmware update"
  CONTROLLER_BOARD="${BOARD_NAME}" "${ROOT_DIR}/tools/pi/recover_s3_without_button.sh"
}

try_s3_jtag_firmware_flash() {
  if [[ "${BOARD_NAME}" != "s3" ]]; then
    return 1
  fi
  if [[ "${CONTROLLER_SKIP_S3_JTAG_FLASH:-0}" == "1" ]]; then
    log "S3 GPIO-JTAG flash fallback disabled by CONTROLLER_SKIP_S3_JTAG_FLASH=1"
    return 1
  fi
  if [[ ! -x "${ROOT_DIR}/tools/pi/write_prebuilt_firmware_jtag.sh" ]]; then
    return 1
  fi

  log "building firmware image before GPIO-JTAG flash fallback"
  (
    cd "${FIRMWARE_DIR}"
    pio run -e "${ENV_NAME}"
  )
  if [[ "${SKIP_UPLOADFS}" != "1" ]]; then
    log "GPIO-JTAG fallback flashes firmware partitions only; filesystem image is not updated"
  fi
  log "serial upload unavailable; trying GPIO-JTAG firmware flash"
  CONTROLLER_BOARD="${BOARD_NAME}" CONTROLLER_HOST_MODE="${HOST_MODE}" \
    "${ROOT_DIR}/tools/pi/write_prebuilt_firmware_jtag.sh" \
      --board "${BOARD_NAME}" \
      --host-mode "${HOST_MODE}"
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
  if try_s3_recovery; then
    UPLOAD_PORT="$(resolve_serial_port "" || true)"
  fi
  if [[ -z "${UPLOAD_PORT}" ]]; then
    if try_s3_jtag_firmware_flash; then
      log "upload complete via GPIO-JTAG"
      exit 0
    fi
    log "pass a port as the first argument or set PIO_UPLOAD_PORT"
    log "common ports: /dev/ttyUSB0, /dev/ttyACM0, /dev/cu.usbserial-*"
    exit 1
  fi
  log "using upload port after recovery: ${UPLOAD_PORT}"
fi

if [[ "${SKIP_UPLOADFS}" == "1" ]]; then
  log "skipping filesystem image upload"
else
  log "uploading filesystem image"
  set +e
  (
    cd "${FIRMWARE_DIR}"
    pio_run -e "${ENV_NAME}" -t uploadfs
  )
  uploadfs_status=$?
  set -e

  if [[ "${uploadfs_status}" -ne 0 ]]; then
    log "filesystem upload failed with status ${uploadfs_status}"
    if try_s3_recovery; then
      UPLOAD_PORT="$(resolve_serial_port "" || true)"
      if [[ -n "${UPLOAD_PORT}" ]]; then
        log "retrying filesystem upload on ${UPLOAD_PORT}"
        (
          cd "${FIRMWARE_DIR}"
          pio_run -e "${ENV_NAME}" -t uploadfs
        )
      fi
    fi
    if try_s3_jtag_firmware_flash; then
      log "upload complete via GPIO-JTAG"
      exit 0
    fi
    exit "${uploadfs_status}"
  fi
fi

log "uploading firmware image"
set +e
(
  cd "${FIRMWARE_DIR}"
  pio_run -e "${ENV_NAME}" -t upload
)
upload_status=$?
set -e

if [[ "${upload_status}" -ne 0 ]]; then
  log "firmware upload failed with status ${upload_status}"
  if try_s3_recovery; then
    UPLOAD_PORT="$(resolve_serial_port "" || true)"
    if [[ -n "${UPLOAD_PORT}" ]]; then
      log "retrying firmware upload on ${UPLOAD_PORT}"
      (
        cd "${FIRMWARE_DIR}"
        pio_run -e "${ENV_NAME}" -t upload
      )
    fi
  fi
  if try_s3_jtag_firmware_flash; then
    log "upload complete via GPIO-JTAG"
    exit 0
  fi
  exit "${upload_status}"
fi

if [[ "${BOARD_NAME}" == "s3" ]]; then
  log "requesting post-upload watchdog reset"
  if ! CONTROLLER_BOARD="${BOARD_NAME}" "${ROOT_DIR}/tools/reboot_board.sh" "${UPLOAD_PORT}"; then
    log "post-upload watchdog reset failed; manual EN/RESET may still be required"
  fi
fi

log "upload complete"
log "if auto-reset does not start flashing, hold BOOT, tap EN/RESET, then retry"
