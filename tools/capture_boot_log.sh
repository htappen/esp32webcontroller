#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT="${1:-}"
DURATION_SECONDS="${2:-8}"
PORT="$(resolve_serial_port "${PORT}" || true)"

if [[ -z "${PORT}" ]]; then
  printf '[bootlog] no serial port detected; pass a port or set PIO_UPLOAD_PORT\n' >&2
  exit 1
fi

activate_platformio_env

python -c "import serial,time,sys
port = sys.argv[1]
duration = float(sys.argv[2])
ser = serial.Serial(port, 115200, timeout=0.25)
ser.dtr = False
ser.rts = True
time.sleep(0.1)
ser.rts = False
time.sleep(0.1)
end = time.time() + duration
chunks = []
while time.time() < end:
    data = ser.read(4096)
    if data:
        chunks.append(data)
sys.stdout.write(b''.join(chunks).decode('utf-8', 'replace'))" \
  "${PORT}" "${DURATION_SECONDS}"
