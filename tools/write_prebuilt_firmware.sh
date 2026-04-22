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
ERASE_FIRST="${ERASE_FIRST:-0}"

BOOTLOADER_OFFSET="${BOOTLOADER_OFFSET:-}"
PARTITIONS_OFFSET="${PARTITIONS_OFFSET:-0x8000}"
BOOT_APP0_OFFSET="${BOOT_APP0_OFFSET:-0xe000}"
FIRMWARE_OFFSET="${FIRMWARE_OFFSET:-0x10000}"
FLASH_MODE="${FLASH_MODE:-dio}"
FLASH_FREQ="${FLASH_FREQ:-80m}"
FLASH_SIZE="${FLASH_SIZE:-4MB}"

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
    --erase-first)
      ERASE_FIRST="1"
      shift
      ;;
    *)
      if [[ -z "${UPLOAD_PORT}" ]]; then
        UPLOAD_PORT="$1"
        shift
      else
        printf '[write-prebuilt] unknown argument: %s\n' "$1" >&2
        exit 1
      fi
      ;;
  esac
done

log() {
  printf '[write-prebuilt] %s\n' "$1"
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

  log "trying S3 no-button recovery before retrying direct flash"
  CONTROLLER_BOARD="${BOARD_NAME}" "${ROOT_DIR}/tools/pi/recover_s3_without_button.sh"
}

try_s3_jtag_flash() {
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

  log "serial flash unavailable; trying GPIO-JTAG prebuilt flash"
  CONTROLLER_BOARD="${BOARD_NAME}" CONTROLLER_HOST_MODE="${HOST_MODE}" \
    "${ROOT_DIR}/tools/pi/write_prebuilt_firmware_jtag.sh" \
      --board "${BOARD_NAME}" \
      --host-mode "${HOST_MODE}"
}

activate_platformio_env

BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
HOST_MODE="$(canonical_host_mode "${HOST_MODE_OVERRIDE}")"
ENV_NAME="$(resolve_pio_env "${BOARD_NAME}" "${HOST_MODE}")"
ESPTOOL_CHIP="$(resolve_esptool_chip "${BOARD_NAME}")"
if [[ -z "${BOOTLOADER_OFFSET}" ]]; then
  if [[ "${BOARD_NAME}" == "s3" ]]; then
    BOOTLOADER_OFFSET="0x0"
  else
    BOOTLOADER_OFFSET="0x1000"
  fi
fi
set_sta_seed_credentials "${STA_SSID_OVERRIDE}" "${STA_PASS_OVERRIDE}"
prepare_controller_identity "build" "${DEVICE_UUID}"
UPLOAD_PORT="$(resolve_serial_port "${UPLOAD_PORT}" || true)"

if [[ -z "${UPLOAD_PORT}" ]]; then
  log "no serial upload port detected"
  if try_s3_recovery; then
    UPLOAD_PORT="$(resolve_serial_port "" || true)"
  fi
  if [[ -z "${UPLOAD_PORT}" ]]; then
    if try_s3_jtag_flash; then
      log "direct prebuilt flash complete via GPIO-JTAG"
      exit 0
    fi
    log "no serial upload port detected after recovery"
    exit 1
  fi
fi

BUILD_DIR="${FIRMWARE_DIR}/.pio/build/${ENV_NAME}"
BOOTLOADER_BIN="${BUILD_DIR}/bootloader.bin"
PARTITIONS_BIN="${BUILD_DIR}/partitions.bin"
FIRMWARE_BIN="${BUILD_DIR}/firmware.bin"
BOOT_APP0_BIN="${PLATFORMIO_CORE_DIR}/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin"

for artifact in "${BOOTLOADER_BIN}" "${PARTITIONS_BIN}" "${FIRMWARE_BIN}" "${BOOT_APP0_BIN}"; do
  if [[ ! -f "${artifact}" ]]; then
    printf '[write-prebuilt] missing prebuilt artifact: %s\n' "${artifact}" >&2
    exit 1
  fi
done

log "using PlatformIO core dir: ${PLATFORMIO_CORE_DIR}"
log "using board target: ${BOARD_NAME} (${HOST_MODE}; ${ENV_NAME})"
log "using device uuid: ${CONTROLLER_DEVICE_UUID}"
log "using device name: ${CONTROLLER_DEVICE_FRIENDLY_NAME}"
log "using device url: ${CONTROLLER_DEVICE_LOCAL_URL}"
log "using upload port: ${UPLOAD_PORT}"
log "flashing prebuilt images directly with esptool"

if [[ "${ERASE_FIRST}" == "1" ]]; then
  log "erasing flash before write"
  set +e
  "${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
    --chip "${ESPTOOL_CHIP}" \
    --port "${UPLOAD_PORT}" \
    erase_flash
  erase_status=$?
  set -e

  if [[ "${erase_status}" -ne 0 ]]; then
    log "erase before direct flash failed with status ${erase_status}"
    if try_s3_recovery; then
      UPLOAD_PORT="$(resolve_serial_port "" || true)"
      if [[ -n "${UPLOAD_PORT}" ]]; then
        log "retrying erase before direct flash on ${UPLOAD_PORT}"
        "${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
          --chip "${ESPTOOL_CHIP}" \
          --port "${UPLOAD_PORT}" \
          erase_flash
      fi
    fi
    if try_s3_jtag_flash; then
      log "direct prebuilt flash complete via GPIO-JTAG"
      exit 0
    fi
    exit "${erase_status}"
  fi
fi

set +e
"${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
  --chip "${ESPTOOL_CHIP}" \
  --port "${UPLOAD_PORT}" \
  --before default_reset \
  --after watchdog_reset \
  write_flash -z \
  --flash_mode "${FLASH_MODE}" \
  --flash_freq "${FLASH_FREQ}" \
  --flash_size "${FLASH_SIZE}" \
  "${BOOTLOADER_OFFSET}" "${BOOTLOADER_BIN}" \
  "${PARTITIONS_OFFSET}" "${PARTITIONS_BIN}" \
  "${BOOT_APP0_OFFSET}" "${BOOT_APP0_BIN}" \
  "${FIRMWARE_OFFSET}" "${FIRMWARE_BIN}"
write_status=$?
set -e

if [[ "${write_status}" -ne 0 ]]; then
  log "direct prebuilt flash failed with status ${write_status}"
  if try_s3_recovery; then
    UPLOAD_PORT="$(resolve_serial_port "" || true)"
    if [[ -n "${UPLOAD_PORT}" ]]; then
      log "retrying direct prebuilt flash on ${UPLOAD_PORT}"
      "${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
        --chip "${ESPTOOL_CHIP}" \
        --port "${UPLOAD_PORT}" \
        --before default_reset \
        --after watchdog_reset \
        write_flash -z \
        --flash_mode "${FLASH_MODE}" \
        --flash_freq "${FLASH_FREQ}" \
        --flash_size "${FLASH_SIZE}" \
        "${BOOTLOADER_OFFSET}" "${BOOTLOADER_BIN}" \
        "${PARTITIONS_OFFSET}" "${PARTITIONS_BIN}" \
        "${BOOT_APP0_OFFSET}" "${BOOT_APP0_BIN}" \
        "${FIRMWARE_OFFSET}" "${FIRMWARE_BIN}"
    else
      if try_s3_jtag_flash; then
        log "direct prebuilt flash complete via GPIO-JTAG"
        exit 0
      fi
      log "no serial upload port detected after recovery"
      exit "${write_status}"
    fi
  else
    if try_s3_jtag_flash; then
      log "direct prebuilt flash complete via GPIO-JTAG"
      exit 0
    fi
    exit "${write_status}"
  fi
fi

log "direct prebuilt flash complete"
