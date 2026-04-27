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
WS_URL="${WS_URL:-ws://${CONTROLLER_DEVICE_HOSTNAME}.local:81}"
EXPECTED_TRANSPORT="${EXPECTED_TRANSPORT:-usb}"
EXPECTED_VARIANT="${EXPECTED_VARIANT:-switch}"
EXPECTED_USB_VIDPID="${EXPECTED_USB_VIDPID:-0f0d:00c1}"
EXPECTED_CONTROLLER_COUNT="${EXPECTED_CONTROLLER_COUNT:-4}"
USB_ENUM_TIMEOUT_SECONDS="${USB_ENUM_TIMEOUT_SECONDS:-12}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"
UART_PORT="${PI_UART_PORT:-/dev/serial0}"
DEBUG_LOGS_REQUIRED="${CONTROLLER_DEBUG_LOGS:-0}"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap 'stop_serial_log; cleanup' EXIT

log() {
  printf '[pi-switch-e2e] %s\n' "$1"
}

serial_log_file="${TMP_DIR}/serial.log"
serial_log_pid=""

start_serial_log() {
  local serial_port="${1:-${UART_PORT}}"
  if [[ ! -e "${serial_port}" ]]; then
    if [[ "${DEBUG_LOGS_REQUIRED}" == "1" ]]; then
      log "expected UART port for debug logging but none was available at ${serial_port}"
      return 1
    fi
    log "no UART port available for logging at ${serial_port}"
    return 0
  fi
  log "capturing UART log from ${serial_port}"
  bash "${SCRIPT_DIR}/capture_uart_log.sh" "${serial_port}" 9999 "${serial_log_file}" &
  serial_log_pid=$!
  sleep 0.2
}

stop_serial_log() {
  if [[ -n "${serial_log_pid}" ]]; then
    kill "${serial_log_pid}" >/dev/null 2>&1 || true
    serial_log_pid=""
  fi
}

dump_host_diagnostics() {
  log "capturing host-side USB diagnostics"
  lsusb >&2 || true
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

ensure_controller_reachable() {
  local preflight_status="${TMP_DIR}/status_preflight.json"
  if fetch_status "${HTTP_BASE_URL}" "${preflight_status}" >/dev/null 2>&1; then
    log "controller already reachable at ${HTTP_BASE_URL}; skipping AP join"
    return 0
  fi

  log "waiting for controller access point ${AP_SSID}"
  "${SCRIPT_DIR}/check_wifi_ap.sh" "${AP_SSID}" "${AP_PASS}"
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

capture_case() {
  local name="$1"
  local duration="$2"
  local packet_file="$3"
  local log_file="${TMP_DIR}/${name}.jsonl"

  "${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --usb-vid 0x0f0d --usb-pid 0x00c1 --all-matching --duration "${duration}" --output "${log_file}" &
  local capture_pid=$!
  sleep 0.2
  start_serial_log
  "${VENV_PYTHON}" "${SCRIPT_DIR}/browser_send_controller_packet.py" --page-url "${HTTP_BASE_URL}" --packet-file "${packet_file}" --hold-open 0.8 --status-url "${HTTP_BASE_URL}/api/status"
  stop_serial_log
  wait "${capture_pid}"
  if [[ "${DEBUG_LOGS_REQUIRED}" == "1" && ! -s "${serial_log_file}" ]]; then
    printf '[pi-switch-e2e] debug logging is enabled but no UART output was captured from %s\n' "${UART_PORT}" >&2
    exit 1
  fi
  printf '%s\n' "${log_file}"
}

"${SCRIPT_DIR}/bootstrap_pi.sh"
bash "${SCRIPT_DIR}/setup_python_harness.sh"

log "loading Linux input drivers for Switch-style HID controllers"
sudo modprobe hid_nintendo
sudo modprobe joydev

log "waiting for USB enumeration as ${EXPECTED_USB_VIDPID}"
wait_for_usb_enumeration || {
  dump_host_diagnostics
  if debug_serial_jtag_visible; then
    printf '[pi-switch-e2e] saw Espressif USB-Serial/JTAG (303a:1001), not the expected gamepad VID/PID %s; check that the S3 OTG/device USB path is connected to the Pi host\n' "${EXPECTED_USB_VIDPID}" >&2
  fi
  exit 1
}
lsusb | grep -i "${EXPECTED_USB_VIDPID}"

log "waiting for Linux input nodes"
controller_count="$("${VENV_PYTHON}" "${SCRIPT_DIR}/controller_test_core.py" count-devices --usb-vid 0x0f0d --usb-pid 0x00c1)"
if [[ "${controller_count}" != "${EXPECTED_CONTROLLER_COUNT}" ]]; then
  printf '[pi-switch-e2e] expected %s Linux input controllers, found %s\n' "${EXPECTED_CONTROLLER_COUNT}" "${controller_count}" >&2
  dump_host_diagnostics
  exit 1
fi
log "saw ${controller_count} enumerated Switch controller interfaces"

EVENT_DEVICE="$("${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --usb-vid 0x0f0d --usb-pid 0x00c1 --wait-timeout 10 --print-device)"
log "using input event device ${EVENT_DEVICE}"

ensure_controller_reachable || {
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
cat > "${TMP_DIR}/neutral.json" <<'JSON'
{"t":1,"seq":1,"btn":{"a":0,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/axis_lx.json" <<'JSON'
{"t":3,"seq":3,"btn":{"a":0,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":1.0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/timeout_press.json" <<'JSON'
{"t":4,"seq":4,"btn":{"a":1,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":1.0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON

log "sending a neutral controller packet over WebSocket"
start_serial_log
"${VENV_PYTHON}" "${SCRIPT_DIR}/browser_send_controller_packet.py" --page-url "${HTTP_BASE_URL}" --packet-file "${TMP_DIR}/neutral.json" --hold-open 0.8 --status-url "${HTTP_BASE_URL}/api/status"
stop_serial_log
if [[ "${DEBUG_LOGS_REQUIRED}" == "1" && ! -s "${serial_log_file}" ]]; then
  printf '[pi-switch-e2e] debug logging is enabled but no UART output was captured from %s\n' "${UART_PORT}" >&2
  exit 1
fi
deadline=$((SECONDS + 6))
while (( SECONDS < deadline )); do
  fetch_status "${HTTP_BASE_URL}" "${TMP_DIR}/status_after.json"
  if "${VENV_PYTHON}" - "${TMP_DIR}/status_before.json" "${TMP_DIR}/status_after.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    before = json.load(handle)
with open(sys.argv[2], "r", encoding="utf-8") as handle:
    after = json.load(handle)

if after["controller"]["debug"]["wsPacketsReceived"] > before["controller"]["debug"]["wsPacketsReceived"]:
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    break
  fi
  sleep 0.5
done
"${VENV_PYTHON}" - "${TMP_DIR}/status_before.json" "${TMP_DIR}/status_after.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    before = json.load(handle)
with open(sys.argv[2], "r", encoding="utf-8") as handle:
    after = json.load(handle)

controller = after["controller"]
host = after["host"]
before_debug = before["controller"]["debug"]
after_debug = after["controller"]["debug"]

if host["transport"] != "usb":
    raise SystemExit(f"unexpected host transport after packet: {host['transport']!r}")
if after_debug["wsPacketsReceived"] <= before_debug["wsPacketsReceived"]:
    raise SystemExit("websocket received counter did not advance after packet send")
if after_debug["wsPacketsApplied"] <= before_debug["wsPacketsApplied"]:
    raise SystemExit("websocket applied counter did not advance after packet send")

print(json.dumps({"host": host, "controller": controller, "debugBefore": before_debug, "debugAfter": after_debug}, separators=(",", ":"), sort_keys=True))
PY

if [[ -s "${serial_log_file}" ]]; then
  log "captured serial log"
  sed -n '1,200p' "${serial_log_file}"
fi

log "asserting neutral packet does not press buttons"
neutral_log="$(capture_case neutral 1.0 "${TMP_DIR}/neutral.json")"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${neutral_log}" --forbid-keydown

log "asserting A button packet produces BTN_SOUTH press"
button_log="$(capture_case button_a 1.2 "${TMP_DIR}/button_a.json")"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${button_log}" --expect-key 304=1

log "asserting left-stick X packet produces positive ABS_X movement"
axis_log="$(capture_case axis_lx 1.2 "${TMP_DIR}/axis_lx.json")"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${axis_log}" --expect-abs-range 0:20000:32767

log "asserting packet timeout returns controls to neutral"
timeout_log="$(capture_case timeout_reset 1.7 "${TMP_DIR}/timeout_press.json")"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${timeout_log}" --expect-key 304=1 --expect-key 304=0 --expect-abs-range 0:20000:32767 --expect-abs-range 0:0:0

log "Pi direct WebSocket to Switch test passed"
