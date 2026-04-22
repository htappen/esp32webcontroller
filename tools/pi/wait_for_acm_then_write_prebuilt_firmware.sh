#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PORT=""
BOARD_OVERRIDE="${CONTROLLER_BOARD:-s3}"
HOST_MODE_OVERRIDE="${CONTROLLER_HOST_MODE:-usb_xinput}"
DEVICE_UUID="${CONTROLLER_DEVICE_UUID:-}"
STA_SSID_OVERRIDE="${CONTROLLER_DEFAULT_STA_SSID:-}"
STA_PASS_OVERRIDE="${CONTROLLER_DEFAULT_STA_PASS:-}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-120}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-0.05}"
ERASE_FIRST="${ERASE_FIRST:-0}"
PORT_CANDIDATES=("/dev/ttyACM0" "/dev/ttyACM1")
RECOVERY_ATTEMPTED=0

log() {
  printf '[pi-wait-write-prebuilt] %s\n' "$1"
}

is_s3_board() {
  case "${BOARD_OVERRIDE,,}" in
    s3|esp32-s3|esp32_s3|esp32_s3_devkitc_1|esp32-s3-devkitc-1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

build_flash_args() {
  local args=(
    --board "${BOARD_OVERRIDE}"
    --host-mode "${HOST_MODE_OVERRIDE}"
    --device-uuid "${DEVICE_UUID}"
    --sta-ssid "${STA_SSID_OVERRIDE}"
    --sta-pass "${STA_PASS_OVERRIDE}"
  )

  if [[ "${ERASE_FIRST}" == "1" ]]; then
    args+=(--erase-first)
  fi

  printf '%s\n' "${args[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --board)
      BOARD_OVERRIDE="${2:-}"
      shift 2
      ;;
    --host-mode)
      HOST_MODE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --device-uuid)
      DEVICE_UUID="${2:-}"
      shift 2
      ;;
    --sta-ssid)
      STA_SSID_OVERRIDE="${2:-}"
      shift 2
      ;;
    --sta-pass)
      STA_PASS_OVERRIDE="${2:-}"
      shift 2
      ;;
    --wait-timeout)
      WAIT_TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --wait-interval)
      WAIT_INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --erase-first)
      ERASE_FIRST="1"
      shift
      ;;
    *)
      printf '[pi-wait-write-prebuilt] unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -n "${PORT}" ]]; then
  PORT_CANDIDATES=("${PORT}")
fi

try_recovery_once() {
  if [[ "${RECOVERY_ATTEMPTED}" == "1" ]]; then
    return 1
  fi
  if ! is_s3_board; then
    return 1
  fi
  if [[ "${CONTROLLER_SKIP_S3_RECOVERY:-0}" == "1" ]]; then
    log "S3 no-button recovery disabled by CONTROLLER_SKIP_S3_RECOVERY=1"
    return 1
  fi

  RECOVERY_ATTEMPTED=1
  log "timed out waiting for ACM; trying S3 no-button recovery"
  CONTROLLER_BOARD=s3 "${ROOT_DIR}/tools/pi/recover_s3_without_button.sh"
}

log "waiting for ACM port before direct prebuilt flash"
log "port candidates: ${PORT_CANDIDATES[*]}"
log "board=${BOARD_OVERRIDE} host_mode=${HOST_MODE_OVERRIDE} timeout=${WAIT_TIMEOUT_SECONDS}s interval=${WAIT_INTERVAL_SECONDS}s erase_first=${ERASE_FIRST}"

deadline_epoch="$(python3 - <<PY
import time
print(time.monotonic() + float(${WAIT_TIMEOUT_SECONDS}))
PY
)"

while true; do
  for candidate in "${PORT_CANDIDATES[@]}"; do
    if [[ -e "${candidate}" ]]; then
      log "detected upload port: ${candidate}"
      mapfile -t flash_args < <(build_flash_args)
      exec env \
        CONTROLLER_BOARD="${BOARD_OVERRIDE}" \
        CONTROLLER_HOST_MODE="${HOST_MODE_OVERRIDE}" \
        CONTROLLER_DEVICE_UUID="${DEVICE_UUID}" \
        CONTROLLER_DEFAULT_STA_SSID="${STA_SSID_OVERRIDE}" \
        CONTROLLER_DEFAULT_STA_PASS="${STA_PASS_OVERRIDE}" \
        ERASE_FIRST="${ERASE_FIRST}" \
        "${ROOT_DIR}/tools/write_prebuilt_firmware.sh" \
          "${flash_args[@]}" \
          "${candidate}"
    fi
  done

  timed_out="$(python3 - <<PY
import time
deadline = float(${deadline_epoch})
print(1 if time.monotonic() >= deadline else 0)
PY
)"
  if [[ "${timed_out}" == "1" ]]; then
    if try_recovery_once; then
      deadline_epoch="$(python3 - <<PY
import time
print(time.monotonic() + float(${WAIT_TIMEOUT_SECONDS}))
PY
)"
      continue
    fi
    printf '[pi-wait-write-prebuilt] timed out waiting for an ACM port\n' >&2
    exit 1
  fi

  sleep "${WAIT_INTERVAL_SECONDS}"
done
