#!/usr/bin/env bash
set -euo pipefail

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

if stdbuf -oL cat "${PORT}" >/dev/null 2>&1; then
  READER_CMD=(stdbuf -oL timeout "${DURATION_SECONDS}" cat "${PORT}")
elif sudo -n stdbuf -oL cat "${PORT}" >/dev/null 2>&1; then
  READER_CMD=(sudo -n stdbuf -oL timeout "${DURATION_SECONDS}" cat "${PORT}")
else
  printf '[uartlog] UART port is not readable and passwordless sudo is unavailable: %s\n' "${PORT}" >&2
  exit 1
fi

rm -f "${OUTPUT_FILE}"

"${READER_CMD[@]}" > "${OUTPUT_FILE}"
