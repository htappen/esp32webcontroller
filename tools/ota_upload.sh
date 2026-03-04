#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <ip> <firmware.bin>" >&2
  exit 1
fi

IP="$1"
BIN="$2"

python -m esptool --chip esp32 --port "socket://${IP}:3232" write_flash 0x10000 "${BIN}"
