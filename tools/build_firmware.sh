#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

BOARD_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      printf '[build] unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

activate_platformio_env

BOARD_NAME="$(resolve_board "${BOARD_OVERRIDE}")"
ENV_NAME="$(resolve_pio_env "${BOARD_NAME}")"

printf '[build] building %s via %s\n' "${BOARD_NAME}" "${ENV_NAME}"
(
  cd "${FIRMWARE_DIR}"
  pio run -e "${ENV_NAME}"
)
