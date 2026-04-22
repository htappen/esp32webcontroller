#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENOCD_PIDFILE="${OPENOCD_PIDFILE:-${ROOT_DIR}/.pi-openocd.pid}"

log() {
  printf '[pi-openocd] %s\n' "$1"
}

if [[ ! -f "${OPENOCD_PIDFILE}" ]]; then
  log "no pidfile present"
  if command -v pgrep >/dev/null 2>&1; then
    mapfile -t stale_pids < <(pgrep -f "[o]penocd.*esp32s3_rpi_gpio_jtag.cfg" || true)
    for stale_pid in "${stale_pids[@]}"; do
      if [[ -n "${stale_pid}" ]]; then
        log "stopping stale OpenOCD pid ${stale_pid}"
        sudo kill "${stale_pid}" >/dev/null 2>&1 || true
      fi
    done
  fi
  exit 0
fi

openocd_pid="$(cat "${OPENOCD_PIDFILE}")"
rm -f "${OPENOCD_PIDFILE}"

if kill -0 "${openocd_pid}" >/dev/null 2>&1; then
  log "stopping OpenOCD pid ${openocd_pid}"
  sudo kill "${openocd_pid}"
fi
