#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENOCD_LOG="${OPENOCD_LOG:-${ROOT_DIR}/.pi-openocd.log}"
OPENOCD_PIDFILE="${OPENOCD_PIDFILE:-${ROOT_DIR}/.pi-openocd.pid}"
OPENOCD_BOARD_CFG="${OPENOCD_BOARD_CFG:-/usr/share/openocd/scripts/board/esp32s3-builtin.cfg}"
OPENOCD_WAIT_TIMEOUT_SECONDS="${OPENOCD_WAIT_TIMEOUT_SECONDS:-30}"
OPENOCD_RETRY_INTERVAL_SECONDS="${OPENOCD_RETRY_INTERVAL_SECONDS:-1}"

log() {
  printf '[pi-openocd] %s\n' "$1"
}

cleanup_stale_pidfile() {
  if [[ ! -f "${OPENOCD_PIDFILE}" ]]; then
    return 0
  fi

  existing_pid="$(cat "${OPENOCD_PIDFILE}")"
  if kill -0 "${existing_pid}" >/dev/null 2>&1; then
    log "OpenOCD already running with pid ${existing_pid}"
    exit 0
  fi
  rm -f "${OPENOCD_PIDFILE}"
}

if [[ ! -f "${OPENOCD_BOARD_CFG}" ]]; then
  printf '[pi-openocd] missing board config: %s\n' "${OPENOCD_BOARD_CFG}" >&2
  exit 1
fi

cleanup_stale_pidfile

deadline=$((SECONDS + OPENOCD_WAIT_TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  log "starting OpenOCD with ${OPENOCD_BOARD_CFG}"
  nohup sudo openocd -f "${OPENOCD_BOARD_CFG}" >"${OPENOCD_LOG}" 2>&1 &
  openocd_pid=$!
  echo "${openocd_pid}" >"${OPENOCD_PIDFILE}"

  for _ in $(seq 1 20); do
    if grep -q "Listening on port 3333" "${OPENOCD_LOG}" 2>/dev/null; then
      log "OpenOCD ready on gdb port 3333"
      exit 0
    fi
    if ! kill -0 "${openocd_pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done

  rm -f "${OPENOCD_PIDFILE}"
  log "OpenOCD did not attach yet; retrying"
  sleep "${OPENOCD_RETRY_INTERVAL_SECONDS}"
done

printf '[pi-openocd] timed out waiting for OpenOCD attach; see %s\n' "${OPENOCD_LOG}" >&2
exit 1
