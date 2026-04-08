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

BOOTLOADER_OFFSET="${BOOTLOADER_OFFSET:-0x1000}"
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

activate_platformio_env

BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
HOST_MODE="$(canonical_host_mode "${HOST_MODE_OVERRIDE}")"
ENV_NAME="$(resolve_pio_env "${BOARD_NAME}" "${HOST_MODE}")"
ESPTOOL_CHIP="$(resolve_esptool_chip "${BOARD_NAME}")"
set_sta_seed_credentials "${STA_SSID_OVERRIDE}" "${STA_PASS_OVERRIDE}"
prepare_controller_identity "build" "${DEVICE_UUID}"
UPLOAD_PORT="$(resolve_serial_port "${UPLOAD_PORT}" || true)"

if [[ -z "${UPLOAD_PORT}" ]]; then
  log "no serial upload port detected"
  exit 1
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
  "${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
    --chip "${ESPTOOL_CHIP}" \
    --port "${UPLOAD_PORT}" \
    erase_flash
fi

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

log "direct prebuilt flash complete"
