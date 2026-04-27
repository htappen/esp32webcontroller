#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT=""
BOARD_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      if [[ -z "${PORT}" ]]; then
        PORT="$1"
        shift
      else
        printf '[erase] unknown argument: %s\n' "$1" >&2
        exit 1
      fi
      ;;
  esac
done

PORT="$(resolve_serial_port "${PORT}" || true)"
BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"

if [[ -z "${PORT}" ]]; then
  printf '[erase] no serial port detected\n'
  if [[ -z "${PORT}" ]]; then
    printf '[erase] put the board in ROM download mode: hold BOOT, tap EN/RESET, then release BOOT when /dev/ttyACM* appears\n' >&2
    exit 1
  fi
fi

activate_platformio_env
ESPTOOL_CHIP="$(resolve_esptool_chip "${BOARD_NAME}")"

printf '[erase] erasing %s flash on %s\n' "${BOARD_NAME}" "${PORT}"
set +e
"${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
  --chip "${ESPTOOL_CHIP}" \
  --port "${PORT}" \
  erase_flash
erase_status=$?
set -e

if [[ "${erase_status}" -ne 0 ]]; then
  printf '[erase] flash erase failed with status %s\n' "${erase_status}"
  exit "${erase_status}"
fi

printf '[erase] flash erase complete\n'
