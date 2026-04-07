#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT="${1:-}"
PORT="$(resolve_serial_port "${PORT}" || true)"
BOARD_NAME="$(resolve_board "${CONTROLLER_BOARD:-}" || true)"

if [[ -z "${PORT}" ]]; then
  printf '[reboot] no serial port detected; pass a port or set PIO_UPLOAD_PORT\n' >&2
  exit 1
fi

activate_platformio_env

if [[ "${BOARD_NAME}" == "s3" ]]; then
  printf '[reboot] issuing ESP32-S3 watchdog reset on %s\n' "${PORT}"
  "${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
    --chip esp32s3 \
    --port "${PORT}" \
    --after watchdog_reset \
    chip_id >/dev/null
else
  printf '[reboot] toggling reset on %s\n' "${PORT}"
  "${VENV_DIR}/bin/python" - "${PORT}" <<'PY'
import sys
import time

import serial

port = sys.argv[1]
ser = serial.Serial(port, 115200, timeout=0.25)
ser.dtr = False
ser.rts = True
time.sleep(0.1)
ser.rts = False
time.sleep(0.1)
ser.close()
PY
fi

printf '[reboot] board reboot complete\n'
