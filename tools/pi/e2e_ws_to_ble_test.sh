#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_SSID="${AP_SSID:-ESP32-Controller}"
AP_PASS="${AP_PASS:-}"
BLE_NAME="${BLE_NAME:-ESP32 Web Gamepad}"
RAW_HTTP_BASE_URL="${RAW_HTTP_BASE_URL:-http://192.168.4.1}"
MDNS_HTTP_BASE_URL="${MDNS_HTTP_BASE_URL:-http://game.local}"
HTTP_BASE_URL="${HTTP_BASE_URL:-http://192.168.4.1}"
WS_URL="${WS_URL:-ws://192.168.4.1:81}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log() {
  printf '[pi-e2e] %s\n' "$1"
}

fail() {
  printf '[pi-e2e] %s\n' "$1" >&2
  exit 1
}

fetch_status() {
  local base_url="$1"
  local output_file="$2"
  curl --fail --silent --show-error "${base_url}/api/status" > "${output_file}"
}

assert_http_endpoints_equivalent() {
  local raw_status_file="${TMP_DIR}/status_raw.json"
  local mdns_status_file="${TMP_DIR}/status_mdns.json"

  log "verifying raw IP and game.local return equivalent status payloads"
  fetch_status "${RAW_HTTP_BASE_URL}" "${raw_status_file}"
  fetch_status "${MDNS_HTTP_BASE_URL}" "${mdns_status_file}"

  "${VENV_PYTHON}" - "${raw_status_file}" "${mdns_status_file}" <<'PY'
import json
import sys

def normalize(status):
    return {
        "network": {
            "mode": status["network"]["mode"],
            "apActive": status["network"]["apActive"],
            "staConnected": status["network"]["staConnected"],
            "apIp": status["network"]["apIp"],
            "staIp": status["network"]["staIp"],
        },
        "host": {
            "advertising": status["host"]["advertising"],
            "connected": status["host"]["connected"],
        },
        "controller": {
            "wsConnected": status["controller"]["wsConnected"],
            "seq": status["controller"]["seq"],
            "t": status["controller"]["t"],
        },
    }

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    raw_status = json.load(handle)

with open(sys.argv[2], "r", encoding="utf-8") as handle:
    mdns_status = json.load(handle)

if raw_status["network"]["apIp"] != "192.168.4.1":
    raise SystemExit("unexpected AP IP from raw endpoint")

if mdns_status["network"]["apIp"] != raw_status["network"]["apIp"]:
    raise SystemExit("game.local resolved to a different AP IP")

if normalize(raw_status) != normalize(mdns_status):
    raise SystemExit(
        "raw IP and game.local returned different stable status fields:\n"
        f"raw={json.dumps(normalize(raw_status), sort_keys=True)}\n"
        f"mdns={json.dumps(normalize(mdns_status), sort_keys=True)}"
    )

print(json.dumps(normalize(raw_status), separators=(",", ":"), sort_keys=True))
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
"${SCRIPT_DIR}/check_wifi_ap.sh" "${AP_SSID}" "${AP_PASS}"
"${SCRIPT_DIR}/check_bluetooth.sh"

log "waiting for ESP32 HTTP status endpoint"
fetch_status "${HTTP_BASE_URL}" "${TMP_DIR}/status.json"
"${VENV_PYTHON}" - "${TMP_DIR}/status.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)

if status["network"]["apIp"] != "192.168.4.1":
    raise SystemExit("unexpected AP IP")
print(json.dumps(status, separators=(",", ":")))
PY

assert_http_endpoints_equivalent

PAIR_OUTPUT="$("${SCRIPT_DIR}/pair_ble_gamepad.sh" "${BLE_NAME}")"
printf '%s\n' "${PAIR_OUTPUT}"
EVENT_DEVICE="$("${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device-name "${BLE_NAME}" --wait-timeout 10 --print-device)"
log "using input event device ${EVENT_DEVICE}"

cat > "${TMP_DIR}/neutral.json" <<'JSON'
{"t":1,"seq":1,"btn":{"a":0,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/button_a.json" <<'JSON'
{"t":2,"seq":2,"btn":{"a":1,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/axis_lx.json" <<'JSON'
{"t":3,"seq":3,"btn":{"a":0,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":1.0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/timeout_press.json" <<'JSON'
{"t":4,"seq":4,"btn":{"a":1,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":1.0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON

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

log "Pi direct WebSocket to BLE test passed"
