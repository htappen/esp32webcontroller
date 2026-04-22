#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENOCD_PIDFILE="${OPENOCD_PIDFILE:-${ROOT_DIR}/.pi-openocd.pid}"

log() {
  printf '[pi-openocd] %s\n' "$1"
}

if [[ ! -f "${OPENOCD_PIDFILE}" ]]; then
  log "no pidfile present"
  exit 0
fi

openocd_pid="$(cat "${OPENOCD_PIDFILE}")"
rm -f "${OPENOCD_PIDFILE}"

if kill -0 "${openocd_pid}" >/dev/null 2>&1; then
  log "stopping OpenOCD pid ${openocd_pid}"
  sudo kill "${openocd_pid}"
fi
