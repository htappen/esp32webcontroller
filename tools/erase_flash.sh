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

if [[ -z "${PORT}" ]]; then
  printf '[erase] no serial port detected; pass a port or set PIO_UPLOAD_PORT\n' >&2
  exit 1
fi

activate_platformio_env
BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
ESPTOOL_CHIP="$(resolve_esptool_chip "${BOARD_NAME}")"

printf '[erase] erasing %s flash on %s\n' "${BOARD_NAME}" "${PORT}"
"${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
  --chip "${ESPTOOL_CHIP}" \
  --port "${PORT}" \
  erase_flash

printf '[erase] flash erase complete\n'
