#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_SSID="${AP_SSID:-ESP32-Controller}"
AP_PASS="${AP_PASS:-}"
PAGE_URL="${PAGE_URL:-http://game.local}"
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
