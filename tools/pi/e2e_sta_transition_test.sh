#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

PHASE="${1:-}"
AP_SSID="${AP_SSID:-${CONTROLLER_DEVICE_AP_SSID}}"
AP_PASS="${AP_PASS:-}"
TEST_STA_SSID="${TEST_STA_SSID:-}"
TEST_STA_PASS="${TEST_STA_PASS:-}"
TEST_BAD_STA_SSID="${TEST_BAD_STA_SSID:-controller-invalid-ssid}"
TEST_BAD_STA_PASS="${TEST_BAD_STA_PASS:-invalid-password}"
BLE_NAME="${BLE_NAME:-${CONTROLLER_DEVICE_BLE_NAME}}"
FALLBACK_WAIT_SECONDS="${FALLBACK_WAIT_SECONDS:-70}"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
VENV_PYTHON="${VENV_DIR}/bin/python"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ -f "${SCRIPT_DIR}/local.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/local.env"
  set +a
fi

log() {
  printf '[pi-sta] %s\n' "$1"
}

fail() {
  printf '[pi-sta] %s\n' "$1" >&2
  exit 1
}

require_sta_creds() {
  if [[ -z "${TEST_STA_SSID}" ]]; then
    fail "TEST_STA_SSID is required for STA transition tests"
  fi
}

post_sta_update() {
  local base_url="$1"
  local ssid="$2"
  local pass="$3"
  curl --max-time 20 --fail --silent --show-error \
    -H 'Content-Type: application/json' \
    -d "{\"ssid\":\"${ssid}\",\"pass\":\"${pass}\"}" \
    "${base_url}/api/network/sta" > "${TMP_DIR}/sta_update_response.json"
  cat "${TMP_DIR}/sta_update_response.json"
}

wait_for_status() {
  local base_url="$1"
  local output_file="$2"
  local max_attempts="${3:-30}"
  local sleep_seconds="${4:-2}"

  for ((attempt = 1; attempt <= max_attempts; ++attempt)); do
    if curl --fail --silent --show-error "${base_url}/api/status" > "${output_file}"; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  return 1
}

wait_for_wifi_connection() {
  local ssid="$1"
  local pass="$2"
  local timeout_seconds="$3"
  local deadline=$(( $(date +%s) + timeout_seconds ))

  while (( $(date +%s) < deadline )); do
    if "${SCRIPT_DIR}/check_wifi_ap.sh" "${ssid}" "${pass}" >/dev/null 2>&1; then
      "${SCRIPT_DIR}/check_wifi_ap.sh" "${ssid}" "${pass}"
      return 0
    fi
    sleep 2
  done

  return 1
}

extract_sta_ip() {
  local input_file="$1"
  "${VENV_PYTHON}" - "${input_file}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)

print(status["network"]["staIp"])
PY
}

assert_sta_status() {
  local input_file="$1"
  local expected_ssid="$2"
  "${VENV_PYTHON}" - "${input_file}" "${expected_ssid}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)

net = status["network"]
expected_ssid = sys.argv[2]

if not net["staConnected"]:
    raise SystemExit("STA did not connect")
if net["apActive"]:
    raise SystemExit("AP should be disabled after STA success")
if net["connectionState"] != "sta_connected":
    raise SystemExit(f"unexpected connection state: {net['connectionState']}")
if net["activeStaSsid"] != expected_ssid:
    raise SystemExit(f"unexpected active STA SSID: {net['activeStaSsid']!r}")
if net["savedStaSsid"] != expected_ssid:
    raise SystemExit(f"unexpected saved STA SSID: {net['savedStaSsid']!r}")

print(json.dumps(net, separators=(",", ":"), sort_keys=True))
PY
}

assert_failed_candidate_preserved() {
  local input_file="$1"
  local expected_saved_ssid="$2"
  "${VENV_PYTHON}" - "${input_file}" "${expected_saved_ssid}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    status = json.load(handle)

net = status["network"]
expected_saved = sys.argv[2]

if net["connectionState"] != "sta_candidate_failed":
    raise SystemExit(f"unexpected connection state after bad update: {net['connectionState']}")
if not net["apActive"]:
    raise SystemExit("AP fallback should be active after bad candidate update")
if not net["hasSavedStaConfig"]:
    raise SystemExit("saved STA config should still exist after failed candidate update")
if net["savedStaSsid"] != expected_saved:
    raise SystemExit(f"saved STA SSID changed unexpectedly: {net['savedStaSsid']!r}")
if not net["lastCandidateFailed"]:
    raise SystemExit("status should report failed candidate update")

print(json.dumps(net, separators=(",", ":"), sort_keys=True))
PY
}

run_shared_network_e2e() {
  local sta_ip="$1"
  log "running BLE bridge verification over shared Wi-Fi"
  AP_SSID="${TEST_STA_SSID}" \
  AP_PASS="${TEST_STA_PASS}" \
  RAW_HTTP_BASE_URL="http://${sta_ip}" \
  MDNS_HTTP_BASE_URL="${CONTROLLER_DEVICE_LOCAL_URL}" \
  HTTP_BASE_URL="${CONTROLLER_DEVICE_LOCAL_URL}" \
  WS_URL="ws://${CONTROLLER_DEVICE_HOSTNAME}.local:81" \
  EXPECTED_AP_IP="0.0.0.0" \
  EXPECTED_AP_ACTIVE="0" \
  EXPECTED_STA_CONNECTED="1" \
  BLE_NAME="${BLE_NAME}" \
  "${SCRIPT_DIR}/e2e_ws_to_ble_test.sh"
}

require_sta_creds
"${SCRIPT_DIR}/bootstrap_pi.sh"
"${SCRIPT_DIR}/setup_python_harness.sh"

case "${PHASE}" in
  good-transition)
    log "joining ESP32 AP to submit a good STA update"
    "${SCRIPT_DIR}/check_wifi_ap.sh" "${AP_SSID}" "${AP_PASS}"
    post_sta_update "http://192.168.4.1" "${TEST_STA_SSID}" "${TEST_STA_PASS}"
    log "joining shared Wi-Fi to verify STA promotion"
    "${SCRIPT_DIR}/check_wifi_ap.sh" "${TEST_STA_SSID}" "${TEST_STA_PASS}"
    wait_for_status "${CONTROLLER_DEVICE_LOCAL_URL}" "${TMP_DIR}/sta_status.json" 40 2 || fail "timed out waiting for STA status over mDNS"
    assert_sta_status "${TMP_DIR}/sta_status.json" "${TEST_STA_SSID}"
    run_shared_network_e2e "$(extract_sta_ip "${TMP_DIR}/sta_status.json")"
    ;;
  verify-saved)
    log "joining shared Wi-Fi to verify saved credentials after reboot"
    "${SCRIPT_DIR}/check_wifi_ap.sh" "${TEST_STA_SSID}" "${TEST_STA_PASS}"
    wait_for_status "${CONTROLLER_DEVICE_LOCAL_URL}" "${TMP_DIR}/saved_status.json" 40 2 || fail "timed out waiting for saved STA reconnect"
    assert_sta_status "${TMP_DIR}/saved_status.json" "${TEST_STA_SSID}"
    run_shared_network_e2e "$(extract_sta_ip "${TMP_DIR}/saved_status.json")"
    ;;
  bad-update)
    log "joining shared Wi-Fi to submit a bad STA update"
    "${SCRIPT_DIR}/check_wifi_ap.sh" "${TEST_STA_SSID}" "${TEST_STA_PASS}"
    post_sta_update "${CONTROLLER_DEVICE_LOCAL_URL}" "${TEST_BAD_STA_SSID}" "${TEST_BAD_STA_PASS}"
    log "waiting for fallback AP after failed candidate update"
    wait_for_wifi_connection "${AP_SSID}" "${AP_PASS}" "${FALLBACK_WAIT_SECONDS}" || fail "timed out waiting for fallback AP visibility after bad STA update"
    wait_for_status "http://192.168.4.1" "${TMP_DIR}/bad_update_status.json" 40 2 || fail "timed out waiting for fallback AP after bad STA update"
    assert_failed_candidate_preserved "${TMP_DIR}/bad_update_status.json" "${TEST_STA_SSID}"
    ;;
  *)
    fail "usage: $(basename "$0") good-transition|verify-saved|bad-update"
    ;;
esac

log "STA transition phase ${PHASE} passed"
