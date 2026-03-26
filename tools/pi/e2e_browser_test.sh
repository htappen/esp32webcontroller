#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_SSID="${AP_SSID:-ESP32-Controller}"
AP_PASS="${AP_PASS:-}"
BLE_NAME="${BLE_NAME:-ESP32 Web Gamepad}"
PAGE_URL="${PAGE_URL:-http://game.local}"
EXPECTED_WS_URL="${EXPECTED_WS_URL:-ws://game.local:81}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"
BROWSER_BLE_CAPTURE_SECONDS="${BROWSER_BLE_CAPTURE_SECONDS:-8.0}"
BROWSER_CLICK_HOLD_SECONDS="${BROWSER_CLICK_HOLD_SECONDS:-1.0}"
BROWSER_POST_CLICK_SETTLE_SECONDS="${BROWSER_POST_CLICK_SETTLE_SECONDS:-1.0}"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log() {
  printf '[pi-browser] %s\n' "$1"
}

"${SCRIPT_DIR}/bootstrap_pi.sh"
"${SCRIPT_DIR}/setup_python_harness.sh"
"${SCRIPT_DIR}/check_wifi_ap.sh" "${AP_SSID}" "${AP_PASS}"
"${SCRIPT_DIR}/check_bluetooth.sh"

log "verifying controller page loads and A button emits the expected WebSocket payload"
"${VENV_PYTHON}" "${SCRIPT_DIR}/browser_ui_test.py" \
  --page-url "${PAGE_URL}" \
  --expected-ws-url "${EXPECTED_WS_URL}" \
  --payload-file "${TMP_DIR}/page_payload.json"

"${VENV_PYTHON}" - "${TMP_DIR}/page_payload.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

if payload["btn"]["a"] != 1:
    raise SystemExit("UI test payload did not press A")

print(json.dumps(payload, separators=(",", ":")))
PY

PAIR_OUTPUT="$("${SCRIPT_DIR}/pair_ble_gamepad.sh" "${BLE_NAME}")"
printf '%s\n' "${PAIR_OUTPUT}"
EVENT_DEVICE="$("${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device-name "${BLE_NAME}" --wait-timeout 10 --print-device)"
log "using input event device ${EVENT_DEVICE}"

log "verifying the UI click reaches the BLE input device"
"${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device "${EVENT_DEVICE}" --duration "${BROWSER_BLE_CAPTURE_SECONDS}" --output "${TMP_DIR}/browser_ble.jsonl" &
capture_pid=$!
sleep 0.2
"${VENV_PYTHON}" "${SCRIPT_DIR}/browser_ui_test.py" \
  --page-url "${PAGE_URL}" \
  --expected-ws-url "${EXPECTED_WS_URL}" \
  --click-hold-seconds "${BROWSER_CLICK_HOLD_SECONDS}" \
  --post-click-settle-seconds "${BROWSER_POST_CLICK_SETTLE_SECONDS}" \
  --payload-file "${TMP_DIR}/ble_payload.json"
wait "${capture_pid}"

"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" \
  --file "${TMP_DIR}/browser_ble.jsonl" \
  --expect-key 304=1 \
  --expect-key 304=0

log "Pi browser UI to BLE test passed"
