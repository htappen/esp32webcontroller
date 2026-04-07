#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT_CANDIDATES=("/dev/ttyACM0" "/dev/ttyACM1")
ATTEMPTS="${PI_S3_WATCHDOG_RESET_ATTEMPTS:-8}"
SLEEP_SECS="${PI_S3_WATCHDOG_RESET_SLEEP_SECS:-1}"

log() {
  printf '[pi-reset] %s\n' "$*"
}

for attempt in $(seq 1 "${ATTEMPTS}"); do
  for port in "${PORT_CANDIDATES[@]}"; do
    if [[ -e "${port}" ]]; then
      log "issuing watchdog reset on ${port} (attempt ${attempt}/${ATTEMPTS})"
      if bash "${ROOT_DIR}/tools/reboot_board.sh" "${port}"; then
        log "watchdog reset succeeded on ${port}"
        exit 0
      fi
      log "watchdog reset failed on ${port}"
    fi
  done
  sleep "${SLEEP_SECS}"
done

log "no stable /dev/ttyACM* port found for watchdog reset; continuing without serial reset"
exit 0
