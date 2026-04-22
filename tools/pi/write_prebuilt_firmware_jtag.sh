#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

BOARD_OVERRIDE="${CONTROLLER_BOARD:-s3}"
HOST_MODE_OVERRIDE="${CONTROLLER_HOST_MODE:-usb_xinput}"
OPENOCD_BOARD_CFG="${OPENOCD_BOARD_CFG:-${ROOT_DIR}/tools/pi/esp32s3_rpi_gpio_jtag.cfg}"
OPENOCD_LOG="${OPENOCD_LOG:-${ROOT_DIR}/.pi-openocd-jtag-flash.log}"

BOOTLOADER_OFFSET="${BOOTLOADER_OFFSET:-}"
PARTITIONS_OFFSET="${PARTITIONS_OFFSET:-0x8000}"
BOOT_APP0_OFFSET="${BOOT_APP0_OFFSET:-0xe000}"
FIRMWARE_OFFSET="${FIRMWARE_OFFSET:-0x10000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    --host-mode)
      HOST_MODE_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      printf '[jtag-flash] unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '[jtag-flash] %s\n' "$1"
}

BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
HOST_MODE="$(canonical_host_mode "${HOST_MODE_OVERRIDE}")"
ENV_NAME="$(resolve_pio_env "${BOARD_NAME}" "${HOST_MODE}")"
if [[ -z "${BOOTLOADER_OFFSET}" ]]; then
  BOOTLOADER_OFFSET="0x0"
fi

if [[ "${BOARD_NAME}" != "s3" ]]; then
  printf '[jtag-flash] GPIO-JTAG flashing only supports CONTROLLER_BOARD=s3\n' >&2
  exit 1
fi

if ! command -v pinctrl >/dev/null 2>&1; then
  printf '[jtag-flash] pinctrl not available; run this helper on the Raspberry Pi\n' >&2
  exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
  printf '[jtag-flash] openocd not available; run tools/pi/bootstrap_pi.sh first\n' >&2
  exit 1
fi

BUILD_DIR="${FIRMWARE_DIR}/.pio/build/${ENV_NAME}"
BOOTLOADER_BIN="${BUILD_DIR}/bootloader.bin"
PARTITIONS_BIN="${BUILD_DIR}/partitions.bin"
FIRMWARE_BIN="${BUILD_DIR}/firmware.bin"
BOOT_APP0_BIN="${PLATFORMIO_CORE_DIR}/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin"

for artifact in "${BOOTLOADER_BIN}" "${PARTITIONS_BIN}" "${FIRMWARE_BIN}" "${BOOT_APP0_BIN}"; do
  if [[ ! -f "${artifact}" ]]; then
    printf '[jtag-flash] missing prebuilt artifact: %s\n' "${artifact}" >&2
    exit 1
  fi
done

log "using board target: ${BOARD_NAME} (${HOST_MODE}; ${ENV_NAME})"
log "using OpenOCD config: ${OPENOCD_BOARD_CFG}"
log "writing log: ${OPENOCD_LOG}"
log "forcing Pi GPIO3/GPIO4 low before GPIO-JTAG flash"
bash "${ROOT_DIR}/tools/pi/prepare_s3_gpio_jtag.sh"
bash "${ROOT_DIR}/tools/pi/stop_openocd_s3_gpio_jtag.sh"

set +e
sudo openocd \
  -f "${OPENOCD_BOARD_CFG}" \
  -c "init" \
  -c "reset halt" \
  -c "program_esp ${BOOTLOADER_BIN} ${BOOTLOADER_OFFSET} verify" \
  -c "program_esp ${PARTITIONS_BIN} ${PARTITIONS_OFFSET} verify" \
  -c "program_esp ${BOOT_APP0_BIN} ${BOOT_APP0_OFFSET} verify" \
  -c "program_esp ${FIRMWARE_BIN} ${FIRMWARE_OFFSET} verify" \
  -c "reset run" \
  -c "shutdown" \
  >"${OPENOCD_LOG}" 2>&1
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
  log "GPIO-JTAG flash failed; OpenOCD log follows"
  sed -n '1,180p' "${OPENOCD_LOG}" || true
  exit "${status}"
fi

log "GPIO-JTAG flash complete"
