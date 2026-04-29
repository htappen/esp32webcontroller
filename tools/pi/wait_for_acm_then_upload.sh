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
DEBUG_LOGS_REQUIRED="${CONTROLLER_DEBUG_LOGS:-0}"
BOOT_LOG_PORT="${PI_UART_PORT:-/dev/serial0}"
BOOT_LOG_FILE="$(mktemp)"
BOOT_LOG_PID=""

log() {
  printf '[pi-wait-upload] %s\n' "$1"
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

start_boot_log_capture() {
  if [[ "${BOARD_OVERRIDE}" != "s3" || "${DEBUG_LOGS_REQUIRED}" != "1" ]]; then
    return 0
  fi

  if [[ ! -e "${BOOT_LOG_PORT}" ]]; then
    log "debug logging is enabled but boot UART port is unavailable at ${BOOT_LOG_PORT}"
    return 1
  fi

  log "capturing boot UART log from ${BOOT_LOG_PORT}"
  bash "${ROOT_DIR}/tools/pi/capture_uart_log.sh" "${BOOT_LOG_PORT}" "${PI_BOOT_LOG_DURATION_SECONDS:-300}" "${BOOT_LOG_FILE}" &
  BOOT_LOG_PID=$!
  sleep 0.2
}

stop_boot_log_capture() {
  if [[ -n "${BOOT_LOG_PID}" ]]; then
    kill "${BOOT_LOG_PID}" >/dev/null 2>&1 || true
    wait "${BOOT_LOG_PID}" >/dev/null 2>&1 || true
    BOOT_LOG_PID=""
  fi
}

dump_boot_log() {
  if [[ -s "${BOOT_LOG_FILE}" ]]; then
    log "captured boot UART log:"
    cat "${BOOT_LOG_FILE}"
  else
    log "no boot UART log captured from ${BOOT_LOG_PORT}"
  fi
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
      if ! start_boot_log_capture; then
        exit 1
      fi
      set +e
      env \
        SKIP_WEB_SYNC_IF_PREBUILT="${SKIP_WEB_SYNC_IF_PREBUILT:-1}" \
        CONTROLLER_BOARD="${BOARD_OVERRIDE}" \
        CONTROLLER_HOST_MODE="${HOST_MODE_OVERRIDE}" \
        CONTROLLER_DEVICE_UUID="${DEVICE_UUID}" \
        CONTROLLER_DEFAULT_STA_SSID="${STA_SSID_OVERRIDE}" \
        CONTROLLER_DEFAULT_STA_PASS="${STA_PASS_OVERRIDE}" \
        SKIP_POST_UPLOAD_REBOOT="${SKIP_POST_UPLOAD_REBOOT:-0}" \
        SKIP_UPLOADFS="${SKIP_UPLOADFS}" \
        "${ROOT_DIR}/tools/upload_firmware.sh" \
          "${upload_args[@]}"
      upload_status=$?
      set -e
      sleep 2
      stop_boot_log_capture
      dump_boot_log
      if [[ "${BOARD_OVERRIDE}" == "s3" && "${DEBUG_LOGS_REQUIRED}" == "1" && ! -s "${BOOT_LOG_FILE}" ]]; then
        printf '[pi-wait-upload] debug logging is enabled but no boot UART output was captured from %s\n' "${BOOT_LOG_PORT}" >&2
        exit 1
      fi
      exit "${upload_status}"
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
    printf '[pi-wait-upload] hold BOOT, tap EN/RESET, then release BOOT when /dev/ttyACM* appears\n' >&2
    exit 1
  fi

  sleep "${WAIT_INTERVAL_SECONDS}"
done
