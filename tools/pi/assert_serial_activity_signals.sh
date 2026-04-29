#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-}"
LOG_LABEL="${2:-UART}"

if [[ -z "${LOG_FILE}" ]]; then
  printf '[serial-activity] log file is required\n' >&2
  exit 1
fi

if [[ ! -s "${LOG_FILE}" ]]; then
  printf '[serial-activity] no UART output captured from %s; logging problem\n' "${LOG_LABEL}" >&2
  exit 1
fi

require_match() {
  local pattern="$1"
  local description="$2"
  if ! grep -nE "${pattern}" "${LOG_FILE}" >/dev/null; then
    printf '[serial-activity] missing %s in %s log\n' "${description}" "${LOG_LABEL}" >&2
    printf '[serial-activity] %s tail:\n' "${LOG_LABEL}" >&2
    tail -n 80 "${LOG_FILE}" >&2 || true
    exit 1
  fi
}

require_match '\[ws\] client [0-9]+ connected' 'websocket connect log'
require_match '\[session\] assigned client_id=' 'session assignment log'
require_match '\[session\] applied ws=' 'session apply log'
require_match '\[ws\] client [0-9]+ disconnected' 'websocket disconnect log'

