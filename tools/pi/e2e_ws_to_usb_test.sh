#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

AP_SSID="${AP_SSID:-${CONTROLLER_DEVICE_AP_SSID}}"
AP_PASS="${AP_PASS:-}"
RAW_HTTP_BASE_URL="${RAW_HTTP_BASE_URL:-http://192.168.4.1}"
HTTP_BASE_URL="${HTTP_BASE_URL:-${CONTROLLER_DEVICE_LOCAL_URL}}"
WS_URL="${WS_URL:-ws://192.168.4.1:81}"
EXPECTED_TRANSPORT="${EXPECTED_TRANSPORT:-usb}"
EXPECTED_VARIANT="${EXPECTED_VARIANT:-pc}"
EXPECTED_USB_VIDPID="${EXPECTED_USB_VIDPID:-045e:028e}"
USB_ENUM_TIMEOUT_SECONDS="${USB_ENUM_TIMEOUT_SECONDS:-12}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log() {
  printf '[pi-usb-e2e] %s\n' "$1"
}

dump_host_diagnostics() {
  log "capturing host-side USB diagnostics"
  lsusb >&2 || true
  printf '\n--- dmesg ---\n' >&2
  dmesg | tail -n 200 >&2 || true
  printf '\n--- /proc/bus/input/devices ---\n' >&2
  cat /proc/bus/input/devices >&2 || true
}

debug_serial_jtag_visible() {
  lsusb | grep -qi '303a:1001'
}

fetch_status() {
  local base_url="$1"
  local output_file="$2"
  curl --fail --silent --show-error "${base_url}/api/status" > "${output_file}"
}

wait_for_usb_enumeration() {
  local deadline=$((SECONDS + USB_ENUM_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if lsusb | grep -qi "${EXPECTED_USB_VIDPID}"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_xpad_binding() {
  local deadline=$((SECONDS + USB_ENUM_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if dmesg | tail -n 200 | grep -Eqi "xpad|Xbox 360|X-Box 360"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_input_node() {
  local deadline=$((SECONDS + USB_ENUM_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if compgen -G "/dev/input/js*" > /dev/null || grep -q "Microsoft X-Box 360 pad" /proc/bus/input/devices; then
      return 0
    fi
    sleep 1
  done

  return 1
}

"${SCRIPT_DIR}/bootstrap_pi.sh"
"${SCRIPT_DIR}/setup_python_harness.sh"

log "loading Linux input drivers for wired Xbox 360 class devices"
sudo modprobe xpad
sudo modprobe joydev

log "waiting for USB enumeration as ${EXPECTED_USB_VIDPID}"
wait_for_usb_enumeration || {
  dump_host_diagnostics
  if debug_serial_jtag_visible; then
    printf '[pi-usb-e2e] saw Espressif USB-Serial/JTAG (303a:1001), not the expected gamepad VID/PID %s; check that the S3 OTG/device USB path is connected to the Pi host\n' "${EXPECTED_USB_VIDPID}" >&2
  fi
  exit 1
}
lsusb | grep -i "${EXPECTED_USB_VIDPID}"

log "waiting for xpad to bind the controller"
wait_for_xpad_binding || {
  dump_host_diagnostics
  exit 1
}

log "waiting for Linux input nodes"
wait_for_input_node || {
  dump_host_diagnostics
  exit 1
}

log "capturing USB host visibility"
grep -n "Microsoft X-Box 360 pad" /proc/bus/input/devices || true
ls /dev/input/js* 2>/dev/null || true

log "waiting for controller access point ${AP_SSID}"
"${SCRIPT_DIR}/check_wifi_ap.sh" "${AP_SSID}" "${AP_PASS}" || {
  dump_host_diagnostics
  exit 1
}

log "verifying controller status in USB mode"
fetch_status "${HTTP_BASE_URL}" "${TMP_DIR}/status_before.json"
"${VENV_PYTHON}" - "${TMP_DIR}/status_before.json" "${EXPECTED_TRANSPORT}" "${EXPECTED_VARIANT}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)

transport = sys.argv[2]
variant = sys.argv[3]
host = status["host"]

if host["transport"] != transport:
    raise SystemExit(f"unexpected host transport: {host['transport']!r}")
if host["variant"] != variant:
    raise SystemExit(f"unexpected host variant: {host['variant']!r}")

print(json.dumps(host, separators=(",", ":"), sort_keys=True))
PY

cat > "${TMP_DIR}/button_a.json" <<'JSON'
{"t":2,"seq":2,"btn":{"a":1,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON

log "sending a controller packet over WebSocket"
"${VENV_PYTHON}" "${SCRIPT_DIR}/send_controller_packet.py" --url "${WS_URL}" --packet-file "${TMP_DIR}/button_a.json" --hold-open 0.3
sleep 0.4
fetch_status "${RAW_HTTP_BASE_URL}" "${TMP_DIR}/status_after.json"
"${VENV_PYTHON}" - "${TMP_DIR}/status_after.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)

controller = status["controller"]
host = status["host"]

if not controller["seq"]:
    raise SystemExit("controller sequence did not advance after WebSocket packet")
if host["transport"] != "usb":
    raise SystemExit(f"unexpected host transport after packet: {host['transport']!r}")

print(json.dumps({"host": host, "controller": controller}, separators=(",", ":"), sort_keys=True))
PY

log "Pi direct WebSocket to USB test passed"
