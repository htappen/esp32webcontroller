#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[pi-bootstrap] %s\n' "$1"
}

apt_install_if_missing() {
  local cmd="$1"
  local package="$2"

  if command -v "${cmd}" >/dev/null 2>&1; then
    return 0
  fi

  log "installing ${package} for ${cmd}"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${package}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[pi-bootstrap] missing required command: %s\n' "${cmd}" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd nmcli
require_cmd bluetoothctl
require_cmd curl
require_cmd lsusb
require_cmd sudo

apt_install_if_missing openocd openocd
apt_install_if_missing gdb gdb-multiarch

if ! python3 -m venv -h >/dev/null 2>&1; then
  printf '[pi-bootstrap] python3 venv module is not available\n' >&2
  exit 1
fi

log "ensuring bluetooth service is running"
sudo systemctl start bluetooth

if [[ ! -f /usr/share/openocd/scripts/interface/raspberrypi-native.cfg ]]; then
  printf '[pi-bootstrap] missing Raspberry Pi GPIO OpenOCD interface config: %s\n' \
    "/usr/share/openocd/scripts/interface/raspberrypi-native.cfg" >&2
  exit 1
fi

if [[ ! -f /usr/share/openocd/scripts/target/esp32s3.cfg ]]; then
  printf '[pi-bootstrap] missing ESP32-S3 target OpenOCD config: %s\n' \
    "/usr/share/openocd/scripts/target/esp32s3.cfg" >&2
  exit 1
fi

log "debugger prerequisites available"
log "OpenOCD interface config: /usr/share/openocd/scripts/interface/raspberrypi-native.cfg"
log "OpenOCD target config: /usr/share/openocd/scripts/target/esp32s3.cfg"
log "repo GPIO JTAG config: tools/pi/esp32s3_rpi_gpio_jtag.cfg"
log "Pi GPIO JTAG prep helper: tools/pi/prepare_s3_gpio_jtag.sh"
log "Pi GPIO3 low helper: tools/pi/set_gpio3_low.sh"
log "Pi GPIO4 low helper: tools/pi/set_gpio4_low.sh"
log "xtensa-esp32s3-elf-gdb comes from the PlatformIO toolchain after the first S3 build"

log "Pi runtime checks passed"
