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
EXPECTED_VARIANT="${EXPECTED_VARIANT:-pc}"
EXPECTED_USB_VIDPID="${EXPECTED_USB_VIDPID:-045e:028e}"
USB_ENUM_TIMEOUT_SECONDS="${USB_ENUM_TIMEOUT_SECONDS:-12}"
EXPECTED_CONTROLLER_COUNT="${EXPECTED_CONTROLLER_COUNT:-4}"
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
  printf '\n--- lsmod | grep xpad ---\n' >&2
  lsmod | grep '^xpad' >&2 || true
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

count_xinput_controllers() {
  python3 - <<'PY'
import re

device_name = "Microsoft X-Box 360 pad"
with open("/proc/bus/input/devices", "r", encoding="utf-8") as handle:
    blocks = handle.read().strip().split("\n\n")

count = 0
for block in blocks:
    name_match = re.search(r'^N: Name="(.+)"$', block, flags=re.MULTILINE)
    handlers_match = re.search(r"^H: Handlers=(.+)$", block, flags=re.MULTILINE)
    if not name_match or not handlers_match:
        continue
    if name_match.group(1) != device_name:
        continue
    handlers = handlers_match.group(1).split()
    if any(handler.startswith("event") for handler in handlers):
        count += 1

print(count)
PY
}

capture_case() {
  local name="$1"
  local duration="$2"
  local packet_file="$3"
  local hold_open="$4"
  local log_file="${TMP_DIR}/${name}.jsonl"

  "${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device "${EVENT_DEVICE}" --duration "${duration}" --output "${log_file}" &
  local capture_pid=$!
  sleep 0.2
  "${VENV_PYTHON}" "${SCRIPT_DIR}/send_controller_packet.py" --url "${WS_URL}" --packet-file "${packet_file}" --hold-open "${hold_open}"
  wait "${capture_pid}"
  printf '%s\n' "${log_file}"
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
controller_count="$(count_xinput_controllers)"
if [[ "${controller_count}" != "${EXPECTED_CONTROLLER_COUNT}" ]]; then
  printf '[pi-usb-e2e] expected %s Linux input controllers, found %s\n' "${EXPECTED_CONTROLLER_COUNT}" "${controller_count}" >&2
  dump_host_diagnostics
  exit 1
fi
log "saw ${controller_count} enumerated XInput controller interfaces"
EVENT_DEVICE="$("${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device-name "Microsoft X-Box 360 pad" --wait-timeout 10 --print-device)"
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
"${VENV_PYTHON}" "${SCRIPT_DIR}/send_controller_packet.py" --url "${WS_URL}" --packet-file "${TMP_DIR}/neutral.json" --hold-open 0.3
sleep 0.4
fetch_status "${HTTP_BASE_URL}" "${TMP_DIR}/status_after.json"
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

log "asserting neutral packet does not press buttons"
neutral_log="$(capture_case neutral 1.0 "${TMP_DIR}/neutral.json" 0.6)"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${neutral_log}" --forbid-keydown

log "asserting A button packet produces BTN_SOUTH press"
button_log="$(capture_case button_a 1.2 "${TMP_DIR}/button_a.json" 0.9)"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${button_log}" --expect-key 304=1

log "asserting left-stick X packet produces positive ABS_X movement"
axis_log="$(capture_case axis_lx 1.2 "${TMP_DIR}/axis_lx.json" 0.9)"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${axis_log}" --expect-abs-range 0:20000:32767

log "asserting packet timeout returns controls to neutral"
timeout_log="$(capture_case timeout_reset 1.7 "${TMP_DIR}/timeout_press.json" 1.2)"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${timeout_log}" --expect-key 304=1 --expect-key 304=0 --expect-abs-range 0:20000:32767 --expect-abs-range 0:0:0

log "Pi direct WebSocket to USB test passed"
