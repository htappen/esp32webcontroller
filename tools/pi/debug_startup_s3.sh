#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIRMWARE_DIR="${ROOT_DIR}/firmware"
BOARD_NAME="${CONTROLLER_BOARD:-s3}"
HOST_MODE="${CONTROLLER_HOST_MODE:-usb_xinput}"
ENV_NAME="esp32_s3_devkitc_1"

case "${HOST_MODE}" in
  usb_xinput)
    ENV_NAME="esp32_s3_devkitc_1_usb_xinput"
    ;;
  usb_switch)
    ENV_NAME="esp32_s3_devkitc_1_usb_switch"
    ;;
  ble)
    ENV_NAME="esp32_s3_devkitc_1"
    ;;
  *)
    printf '[pi-debug] unsupported host mode: %s\n' "${HOST_MODE}" >&2
    exit 1
    ;;
esac

if [[ "${BOARD_NAME}" != "s3" ]]; then
  printf '[pi-debug] this helper only supports CONTROLLER_BOARD=s3\n' >&2
  exit 1
fi

ELF_PATH="${FIRMWARE_DIR}/.pio/build/${ENV_NAME}/firmware.elf"
GDB_BIN="${ROOT_DIR}/.platformio/packages/toolchain-xtensa-esp32s3/bin/xtensa-esp32s3-elf-gdb"
GDB_CMDS="${ROOT_DIR}/tools/pi/startup_debug.gdb"

if [[ ! -x "${GDB_BIN}" ]]; then
  printf '[pi-debug] missing gdb binary: %s\n' "${GDB_BIN}" >&2
  exit 1
fi

if [[ ! -f "${ELF_PATH}" ]]; then
  printf '[pi-debug] missing firmware ELF: %s\n' "${ELF_PATH}" >&2
  exit 1
fi

bash "${ROOT_DIR}/tools/pi/prepare_s3_gpio_jtag.sh"
bash "${ROOT_DIR}/tools/pi/reset_s3_watchdog_if_present.sh"
"${ROOT_DIR}/tools/pi/start_openocd_s3_gpio_jtag.sh"

exec "${GDB_BIN}" -q "${ELF_PATH}" -x "${GDB_CMDS}"
