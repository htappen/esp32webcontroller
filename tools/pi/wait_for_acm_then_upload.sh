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
SKIP_UPLOADFS="${SKIP_UPLOADFS:-1}"
PORT_CANDIDATES=("/dev/ttyACM0" "/dev/ttyACM1")

log() {
  printf '[pi-wait-upload] %s\n' "$1"
}

build_upload_args() {
  local args=(
    --board "${BOARD_OVERRIDE}"
    --host-mode "${HOST_MODE_OVERRIDE}"
    --device-uuid "${DEVICE_UUID}"
    --sta-ssid "${STA_SSID_OVERRIDE}"
    --sta-pass "${STA_PASS_OVERRIDE}"
  )

  if [[ "${SKIP_UPLOADFS}" == "1" ]]; then
    args+=(--skip-uploadfs)
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
    --skip-uploadfs)
      SKIP_UPLOADFS="1"
      shift
      ;;
    --with-uploadfs)
      SKIP_UPLOADFS="0"
      shift
      ;;
    *)
      printf '[pi-wait-upload] unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -n "${PORT}" ]]; then
  PORT_CANDIDATES=("${PORT}")
fi

log "waiting for ACM port before upload"
log "port candidates: ${PORT_CANDIDATES[*]}"
log "board=${BOARD_OVERRIDE} host_mode=${HOST_MODE_OVERRIDE} timeout=${WAIT_TIMEOUT_SECONDS}s interval=${WAIT_INTERVAL_SECONDS}s skip_uploadfs=${SKIP_UPLOADFS}"

deadline_epoch="$(python3 - <<PY
import time
print(time.monotonic() + float(${WAIT_TIMEOUT_SECONDS}))
PY
)"

while true; do
  for candidate in "${PORT_CANDIDATES[@]}"; do
    if [[ -e "${candidate}" ]]; then
      log "detected upload port: ${candidate}"
      mapfile -t upload_args < <(build_upload_args)
      exec env \
        SKIP_WEB_SYNC_IF_PREBUILT="${SKIP_WEB_SYNC_IF_PREBUILT:-1}" \
        CONTROLLER_BOARD="${BOARD_OVERRIDE}" \
        CONTROLLER_HOST_MODE="${HOST_MODE_OVERRIDE}" \
        CONTROLLER_DEVICE_UUID="${DEVICE_UUID}" \
        CONTROLLER_DEFAULT_STA_SSID="${STA_SSID_OVERRIDE}" \
        CONTROLLER_DEFAULT_STA_PASS="${STA_PASS_OVERRIDE}" \
        SKIP_UPLOADFS="${SKIP_UPLOADFS}" \
        "${ROOT_DIR}/tools/upload_firmware.sh" \
          "${upload_args[@]}" \
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
    printf '[pi-wait-upload] timed out waiting for an ACM port\n' >&2
    exit 1
  fi

  sleep "${WAIT_INTERVAL_SECONDS}"
done
