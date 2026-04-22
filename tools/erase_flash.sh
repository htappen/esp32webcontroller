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

try_s3_recovery() {
  if [[ "${BOARD_NAME}" != "s3" ]]; then
    return 1
  fi
  if [[ "${CONTROLLER_SKIP_S3_RECOVERY:-0}" == "1" ]]; then
    printf '[erase] S3 no-button recovery disabled by CONTROLLER_SKIP_S3_RECOVERY=1\n'
    return 1
  fi
  if [[ ! -x "${ROOT_DIR}/tools/pi/recover_s3_without_button.sh" ]]; then
    return 1
  fi

  printf '[erase] trying S3 no-button recovery before retrying erase\n'
  CONTROLLER_BOARD="${BOARD_NAME}" "${ROOT_DIR}/tools/pi/recover_s3_without_button.sh"
}

if [[ -z "${PORT}" ]]; then
  printf '[erase] no serial port detected\n'
  if try_s3_recovery; then
    PORT="$(resolve_serial_port "" || true)"
  fi
  if [[ -z "${PORT}" ]]; then
    printf '[erase] no serial port detected after recovery; pass a port or set PIO_UPLOAD_PORT\n' >&2
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
  if try_s3_recovery; then
    PORT="$(resolve_serial_port "" || true)"
    if [[ -n "${PORT}" ]]; then
      printf '[erase] retrying erase on %s\n' "${PORT}"
      "${VENV_DIR}/bin/python" "${PLATFORMIO_CORE_DIR}/packages/tool-esptoolpy/esptool.py" \
        --chip "${ESPTOOL_CHIP}" \
        --port "${PORT}" \
        erase_flash
    else
      printf '[erase] no serial port detected after recovery\n' >&2
      exit "${erase_status}"
    fi
  else
    exit "${erase_status}"
  fi
fi

printf '[erase] flash erase complete\n'
