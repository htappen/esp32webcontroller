#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/tools/lib/esp32_common.sh"

PORT_CANDIDATES=("/dev/ttyACM0" "/dev/ttyACM1")
SERIAL_ATTEMPTS="${PI_S3_RECOVERY_SERIAL_ATTEMPTS:-5}"
SERIAL_SLEEP_SECS="${PI_S3_RECOVERY_SERIAL_SLEEP_SECS:-1}"
TRY_JTAG="${PI_S3_RECOVERY_TRY_JTAG:-1}"
STOP_OPENOCD_AFTER="${PI_S3_RECOVERY_STOP_OPENOCD_AFTER:-1}"
GDB_BIN="${ROOT_DIR}/.platformio/packages/toolchain-xtensa-esp32s3/bin/xtensa-esp32s3-elf-gdb"
GDB_CMDS="${ROOT_DIR}/tools/pi/reset_run_s3.gdb"

log() {
  printf '[pi-recover] %s\n' "$*"
}

report_usb_state() {
  log "USB state:"
  if command -v lsusb >/dev/null 2>&1; then
    lsusb | grep -E '303a:1001|045e:028e|Espressif|Xbox|X-Box' || true
  else
    log "lsusb not available"
  fi

  log "ACM ports:"
  local found=0
  local port
  for port in /dev/ttyACM*; do
    if [[ -e "${port}" ]]; then
      printf '%s\n' "${port}"
      found=1
    fi
  done
  if [[ "${found}" == "0" ]]; then
    log "no /dev/ttyACM* ports visible"
  fi
}

try_serial_watchdog_reset() {
  local attempt
  local port

  for attempt in $(seq 1 "${SERIAL_ATTEMPTS}"); do
    for port in "${PORT_CANDIDATES[@]}"; do
      if [[ ! -e "${port}" ]]; then
        continue
      fi

      log "trying serial watchdog reset on ${port} (${attempt}/${SERIAL_ATTEMPTS})"
      if CONTROLLER_BOARD=s3 bash "${ROOT_DIR}/tools/reboot_board.sh" "${port}"; then
        log "serial watchdog reset succeeded on ${port}"
        sleep 2
        report_usb_state
        return 0
      fi
      log "serial watchdog reset failed on ${port}"
    done
    sleep "${SERIAL_SLEEP_SECS}"
  done

  return 1
}

try_jtag_reset_run() {
  if [[ "${TRY_JTAG}" != "1" ]]; then
    log "JTAG reset fallback disabled"
    return 1
  fi

  if [[ ! -x "${GDB_BIN}" ]]; then
    log "missing gdb binary: ${GDB_BIN}"
    return 1
  fi

  log "preparing Pi GPIO strap lines for external ESP32-S3 JTAG"
  bash "${ROOT_DIR}/tools/pi/prepare_s3_gpio_jtag.sh"

  log "starting OpenOCD for GPIO-JTAG reset"
  if ! bash "${ROOT_DIR}/tools/pi/start_openocd_s3_gpio_jtag.sh"; then
    log "OpenOCD did not attach"
    return 1
  fi

  log "issuing JTAG reset run"
  if "${GDB_BIN}" -q -batch -x "${GDB_CMDS}" >/tmp/pi-recover-gdb.log 2>&1; then
    log "JTAG reset run succeeded"
    if [[ "${STOP_OPENOCD_AFTER}" == "1" ]]; then
      bash "${ROOT_DIR}/tools/pi/stop_openocd_s3_gpio_jtag.sh"
    fi
    sleep 2
    report_usb_state
    return 0
  fi

  log "JTAG reset run failed; GDB log follows"
  sed -n '1,120p' /tmp/pi-recover-gdb.log || true
  if [[ "${STOP_OPENOCD_AFTER}" == "1" ]]; then
    bash "${ROOT_DIR}/tools/pi/stop_openocd_s3_gpio_jtag.sh"
  fi
  return 1
}

log "forcing Pi GPIO3/GPIO4 low before recovery attempts"
if ! command -v pinctrl >/dev/null 2>&1; then
  log "pinctrl not available; this recovery helper must run on the Raspberry Pi"
  exit 1
fi

bash "${ROOT_DIR}/tools/pi/prepare_s3_gpio_jtag.sh"
report_usb_state

if try_serial_watchdog_reset; then
  exit 0
fi

log "serial watchdog reset unavailable; trying GPIO-JTAG reset fallback"
if try_jtag_reset_run; then
  exit 0
fi

log "recovery failed; board may still need manual EN/RESET or wiring check"
report_usb_state
exit 1
