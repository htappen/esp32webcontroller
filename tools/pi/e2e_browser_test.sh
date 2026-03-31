#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

AP_SSID="${AP_SSID:-${CONTROLLER_DEVICE_AP_SSID}}"
AP_PASS="${AP_PASS:-}"
PAGE_URL="${PAGE_URL:-${CONTROLLER_DEVICE_LOCAL_URL}}"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log() {
  printf '[pi-browser] %s\n' "$1"
}

"${SCRIPT_DIR}/bootstrap_pi.sh"
"${SCRIPT_DIR}/check_wifi_ap.sh" "${AP_SSID}" "${AP_PASS}"

log "verifying controller page loads and the browser hydrates the controller SVGs"
"${SCRIPT_DIR}/browser_ui_test.py" \
  --page-url "${PAGE_URL}" \
  --summary-file "${TMP_DIR}/page_summary.json"

log "Pi browser page smoke test passed"
