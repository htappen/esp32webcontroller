#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

HTTP_BASE_URL="${HTTP_BASE_URL:-${CONTROLLER_DEVICE_LOCAL_URL}}"
WS_URL="${WS_URL:-ws://${CONTROLLER_DEVICE_HOSTNAME}.local:81}"
EXPECTED_TRANSPORT="${EXPECTED_TRANSPORT:-usb}"
EXPECTED_VARIANT="${EXPECTED_VARIANT:-pc}"
EXPECTED_USB_VIDPID="${EXPECTED_USB_VIDPID:-045e:028e}"
DEVICE_NAME="${XINPUT_DEVICE_NAME:-Microsoft X-Box 360 pad}"
USB_ENUM_TIMEOUT_SECONDS="${USB_ENUM_TIMEOUT_SECONDS:-12}"
EXPECTED_CONTROLLER_COUNT="${EXPECTED_CONTROLLER_COUNT:-4}"
EXPECTED_INPUT_DRIVER="${EXPECTED_XINPUT_INPUT_DRIVER:-xpad}"
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

count_xinput_controllers() {
  python3 - "${DEVICE_NAME}" <<'PY'
import re
import sys

device_name = sys.argv[1]
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

assert_controller_status() {
  local status_file="$1"
  local expected_assigned="$2"
  local expected_active="$3"
  local expected_reserved="$4"
  local allow_disconnected="${5:-0}"
  local print_active_slot="${6:-0}"
  local args=(
    --status "${status_file}"
    --expect-assigned-slots "${expected_assigned}"
    --expect-active-slots "${expected_active}"
    --expect-reserved-slots "${expected_reserved}"
    --label "XInput controller"
  )
  if [[ "${allow_disconnected}" == "1" ]]; then
    args+=(--allow-disconnected)
  fi
  if [[ "${print_active_slot}" == "1" ]]; then
    args+=(--print-active-slot)
  fi
  "${VENV_PYTHON}" "${SCRIPT_DIR}/assert_controller_connected.py" "${args[@]}"
}

assert_controller_link() {
  local before_file="$1"
  local after_file="$2"
  "${VENV_PYTHON}" "${SCRIPT_DIR}/assert_controller_link.py" \
    --before "${before_file}" \
    --after "${after_file}" \
    --expect-transport "${EXPECTED_TRANSPORT}" \
    --expect-variant "${EXPECTED_VARIANT}" \
    --label "XInput controller" >&2
}

capture_case() {
  local name="$1"
  local duration="$2"
  local packet_file="$3"
  local hold_open="$4"
  local log_file="${TMP_DIR}/${name}.jsonl"
  local status_before_file="${TMP_DIR}/${name}.status_before.json"
  local status_during_file="${TMP_DIR}/${name}.status_during.json"
  local status_after_file="${TMP_DIR}/${name}.status_after.json"

  fetch_status "${status_before_file}"
  "${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device-name "${DEVICE_NAME}" --all-matching \
    --duration "${duration}" --output "${log_file}" &
  local capture_pid=$!
  sleep 0.2
  "${VENV_PYTHON}" "${SCRIPT_DIR}/send_controller_packet.py" --url "${WS_URL}" --packet-file "${packet_file}" --hold-open "${hold_open}" &
  local sender_pid=$!
  sleep 0.5
  fetch_status "${status_during_file}"
  wait "${sender_pid}"
  fetch_status "${status_after_file}"
  wait "${capture_pid}"
  assert_controller_link "${status_before_file}" "${status_after_file}"
  printf '%s\n' "${log_file}"
}

"${SCRIPT_DIR}/bootstrap_pi.sh"
bash "${SCRIPT_DIR}/setup_python_harness.sh"

log "loading xpad and joydev"
sudo modprobe xpad
sudo modprobe joydev

log "waiting for USB enumeration as ${EXPECTED_USB_VIDPID}"
if ! wait_for_usb_enumeration; then
  lsusb >&2 || true
  exit 1
fi
lsusb | grep -i "${EXPECTED_USB_VIDPID}"

controller_count="$(count_xinput_controllers)"
if [[ "${controller_count}" != "${EXPECTED_CONTROLLER_COUNT}" ]]; then
  printf '[pi-xinput-events] expected %s Linux input controllers named %s, found %s\n' "${EXPECTED_CONTROLLER_COUNT}" "${DEVICE_NAME}" "${controller_count}" >&2
  grep -n "${DEVICE_NAME}" /proc/bus/input/devices >&2 || true
  exit 1
fi
log "saw ${controller_count} enumerated XInput controller interfaces"

EVENT_DEVICES="$("${VENV_PYTHON}" "${SCRIPT_DIR}/capture_input_events.py" --device-name "${DEVICE_NAME}" --wait-timeout "${USB_ENUM_TIMEOUT_SECONDS}" --all-matching --print-device)"
log "using input event devices:"
printf '%s\n' "${EVENT_DEVICES}"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_driver.py" \
  --device-name "${DEVICE_NAME}" \
  --expect-driver "${EXPECTED_INPUT_DRIVER}" \
  --label "XInput controller input"

fetch_status "${TMP_DIR}/status_before.json"

cat > "${TMP_DIR}/button_a.json" <<'JSON'
{"t":2,"seq":2,"btn":{"a":1,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON
cat > "${TMP_DIR}/axis_lx.json" <<'JSON'
{"t":3,"seq":3,"btn":{"a":0,"b":0,"x":0,"y":0,"lb":0,"rb":0,"back":0,"start":0,"ls":0,"rs":0,"du":0,"dd":0,"dl":0,"dr":0},"ax":{"lx":1.0,"ly":0,"rx":0,"ry":0,"lt":0,"rt":0}}
JSON

log "asserting first controller connects and receives button input"
button_log="$(capture_case button_a 1.2 "${TMP_DIR}/button_a.json" 0.9)"
button_slot="$(assert_controller_status "${TMP_DIR}/button_a.status_during.json" 1 1 0 0 1)"
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${button_log}" --expect-key 304=1

assert_controller_status "${TMP_DIR}/button_a.status_after.json" 1 0 1 1 0 1

log "asserting reconnect within grace reuses the same controller slot"
axis_log="$(capture_case axis_lx 1.2 "${TMP_DIR}/axis_lx.json" 0.9)"
axis_slot="$(assert_controller_status "${TMP_DIR}/axis_lx.status_during.json" 1 1 0 0 1)"
if [[ "${axis_slot}" != "${button_slot}" ]]; then
  printf '[pi-xinput-events] expected reconnect to reuse slot %s, got %s\n' "${button_slot}" "${axis_slot}" >&2
  exit 1
fi
"${VENV_PYTHON}" "${SCRIPT_DIR}/assert_input_events.py" --file "${axis_log}" --expect-abs-range 0:20000:32767

assert_controller_status "${TMP_DIR}/axis_lx.status_after.json" 1 0 1 1 0 1

log "XInput event smoke test passed"
