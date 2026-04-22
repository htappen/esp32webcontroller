#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

HTTP_BASE_URL="${HTTP_BASE_URL:-${CONTROLLER_DEVICE_LOCAL_URL}}"
WS_URL="${WS_URL:-ws://${CONTROLLER_DEVICE_HOSTNAME}.local:81}"
EXPECTED_USB_VIDPID="${EXPECTED_USB_VIDPID:-045e:028e}"
DEVICE_NAME="${XINPUT_DEVICE_NAME:-Microsoft X-Box 360 pad}"
USB_ENUM_TIMEOUT_SECONDS="${USB_ENUM_TIMEOUT_SECONDS:-12}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"
TMP_DIR="${XINPUT_EVENT_TMP_DIR:-$(mktemp -d)}"
KEEP_TMP="${KEEP_XINPUT_EVENT_TMP:-0}"

cleanup() {
  local status=$?
  if [[ "${KEEP_TMP}" == "1" || "${status}" -ne 0 ]]; then
    printf '[pi-xinput-events] preserved logs in %s\n' "${TMP_DIR}" >&2
  else
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

log() {
  printf '[pi-xinput-events] %s\n' "$1"
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

fetch_status() {
  local output_file="$1"
  curl --fail --silent --show-error "${HTTP_BASE_URL}/api/status" > "${output_file}"
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

log "loading xpad and joydev"
sudo modprobe xpad
sudo modprobe joydev

log "waiting for USB enumeration as ${EXPECTED_USB_VIDPID}"
if ! wait_for_usb_enumeration; then
  lsusb >&2 || true
  exit 1
fi
lsusb | grep -i "${EXPECTED_USB_VIDPID}"

EVENT_DEVICE="$("${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device-name "${DEVICE_NAME}" --wait-timeout "${USB_ENUM_TIMEOUT_SECONDS}" --print-device)"
log "using input event device ${EVENT_DEVICE}"

fetch_status "${TMP_DIR}/status_before.json"

cat > "${TMP_DIR}/button_a.json" <<'JSON'
{"t":2,"seq":2,"btn":{"a":1,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/axis_lx.json" <<'JSON'
{"t":3,"seq":3,"btn":{"a":0,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":1.0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON

log "asserting A button packet produces BTN_SOUTH press"
button_log="$(capture_case button_a 1.2 "${TMP_DIR}/button_a.json" 0.9)"
fetch_status "${TMP_DIR}/status_after_button.json"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${button_log}" --expect-key 304=1

log "asserting left-stick X packet produces positive ABS_X movement"
axis_log="$(capture_case axis_lx 1.2 "${TMP_DIR}/axis_lx.json" 0.9)"
fetch_status "${TMP_DIR}/status_after_axis.json"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${axis_log}" --expect-abs-range 0:20000:32767

log "XInput event smoke test passed"
