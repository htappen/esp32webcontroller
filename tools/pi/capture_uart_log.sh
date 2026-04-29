#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/esp32_common.sh"

PORT="${1:-${PI_UART_PORT:-/dev/serial0}}"
DURATION_SECONDS="${2:-8}"
OUTPUT_FILE="${3:-}"

if [[ -z "${OUTPUT_FILE}" ]]; then
  printf '[uartlog] output file is required\n' >&2
  exit 1
fi

if [[ ! -e "${PORT}" ]]; then
  printf '[uartlog] UART port not found: %s\n' "${PORT}" >&2
  exit 1
fi

free_busy_port() {
  if ! command -v sudo >/dev/null 2>&1 || ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  local lsof_output
  if ! lsof_output="$(sudo -n lsof "${PORT}" 2>/dev/null)"; then
    return 0
  fi

  local busy_pids
  busy_pids="$(printf '%s\n' "${lsof_output}" | awk 'NR > 1 {print $2}' | sort -u)"
  if [[ -z "${busy_pids}" ]]; then
    return 0
  fi

  printf '[uartlog] freeing busy UART port %s held by PID(s): %s\n' "${PORT}" "${busy_pids}" >&2
  sudo -n kill ${busy_pids} >/dev/null 2>&1 || true
  sleep 0.2
}

free_busy_port

run_pio_monitor() {
  if ! activate_platformio_env; then
    return 1
  fi
  if ! command -v pio >/dev/null 2>&1; then
    return 1
  fi

  if command -v script >/dev/null 2>&1; then
    script -qec "timeout '${DURATION_SECONDS}' pio device monitor --port '${PORT}' --baud 115200" /dev/null
  else
    timeout "${DURATION_SECONDS}" pio device monitor --port "${PORT}" --baud 115200
  fi
}

rm -f "${OUTPUT_FILE}"

if run_pio_monitor > "${OUTPUT_FILE}" 2>&1; then
  exit 0
else
  pio_status=$?
  free_busy_port
  if run_pio_monitor > "${OUTPUT_FILE}" 2>&1; then
    exit 0
  fi
fi

if command -v tail >/dev/null 2>&1; then
  READER_CMD=(timeout "${DURATION_SECONDS}" tail -n 0 -f "${PORT}")
elif stdbuf -oL cat "${PORT}" >/dev/null 2>&1; then
  READER_CMD=(stdbuf -oL timeout "${DURATION_SECONDS}" cat "${PORT}")
elif sudo -n stdbuf -oL cat "${PORT}" >/dev/null 2>&1; then
  READER_CMD=(sudo -n stdbuf -oL timeout "${DURATION_SECONDS}" cat "${PORT}")
else
  printf '[uartlog] pio monitor failed and UART fallback readers are unavailable: %s\n' "${PORT}" >&2
  exit 1
fi

"${READER_CMD[@]}" > "${OUTPUT_FILE}" 2>&1
