#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"
PORT="${1:-}"

activate_platformio_env
PORT="$(resolve_serial_port "${PORT}" || true)"

cd "${FIRMWARE_DIR}"
if [[ -n "${PORT}" ]]; then
  pio device monitor -b 115200 -p "${PORT}"
else
  pio device monitor -b 115200
fi
