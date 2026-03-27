#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT="${1:-}"
PORT="$(resolve_serial_port "${PORT}" || true)"

if [[ -z "${PORT}" ]]; then
  printf '[reboot] no serial port detected; pass a port or set PIO_UPLOAD_PORT\n' >&2
  exit 1
fi

activate_platformio_env

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

printf '[reboot] board reboot complete\n'
