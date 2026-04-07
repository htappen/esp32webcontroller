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

def open_serial():
    deadline = time.time() + 5.0
    last_error = None
    while time.time() < deadline:
        try:
            return serial.Serial(port, 115200, timeout=0.25)
        except serial.SerialException as exc:
            last_error = exc
            time.sleep(0.1)
    if last_error is not None:
        raise last_error
    raise RuntimeError(f'failed to open serial port {port}')

ser = open_serial()
try:
    ser.dtr = False
    ser.rts = True
    time.sleep(0.1)
    ser.rts = False
    time.sleep(0.1)
except serial.SerialException:
    pass

end = time.time() + duration
chunks = []
while time.time() < end:
    try:
        if ser is None or not ser.is_open:
            ser = open_serial()
        data = ser.read(4096)
        if data:
            chunks.append(data)
    except serial.SerialException:
        try:
            if ser is not None:
                ser.close()
        except Exception:
            pass
        ser = None
        time.sleep(0.1)
sys.stdout.write(b''.join(chunks).decode('utf-8', 'replace'))" \
  "${PORT}" "${DURATION_SECONDS}"
