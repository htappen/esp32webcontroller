#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT="${1:-}"
PORT="$(resolve_serial_port "${PORT}" || true)"

if [[ -z "${PORT}" ]]; then
  printf '[erase] no serial port detected; pass a port or set PIO_UPLOAD_PORT\n' >&2
  exit 1
fi

activate_platformio_env

printf '[erase] erasing flash on %s\n' "${PORT}"
"${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
  --chip esp32 \
  --port "${PORT}" \
  erase_flash

printf '[erase] flash erase complete\n'
