#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRMWARE_DIR="${ROOT_DIR}/firmware"
VENV_DIR="${ROOT_DIR}/.venv"
PLATFORMIO_CORE_DIR="${ROOT_DIR}/.platformio"
PORT="${1:-${PIO_UPLOAD_PORT:-}}"

if [[ ! -d "${VENV_DIR}" ]]; then
  printf '[monitor] missing virtual environment at %s\n' "${VENV_DIR}" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

export PLATFORMIO_CORE_DIR

cd "${FIRMWARE_DIR}"
if [[ -n "${PORT}" ]]; then
  pio device monitor -b 115200 -p "${PORT}"
else
  pio device monitor -b 115200
fi
