#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/device_identity.sh"
resolve_device_identity "test" "${CONTROLLER_DEVICE_UUID:-}"

SSID="${1:-${AP_SSID:-${CONTROLLER_DEVICE_AP_SSID}}}"
PASS="${2:-}"
IFACE="${3:-wlan0}"

log() {
  printf '[pi-wifi] %s\n' "$1"
}

fail() {
  printf '[pi-wifi] %s\n' "$1" >&2
  exit 1
}

nmcli_cmd() {
  sudo nmcli "$@"
}

current_ipv4() {
  ip -4 -o addr show dev "${IFACE}" | awk '{print $4}' | head -n1
}

connect_ssid() {
  nmcli_cmd radio wifi on
  if [[ -n "${PASS}" ]]; then
    if ! nmcli_cmd --wait 20 device wifi connect "${SSID}" password "${PASS}" ifname "${IFACE}"; then
      log "retrying ${SSID} with a fresh NetworkManager profile"
      nmcli_cmd connection delete "${SSID}" >/dev/null 2>&1 || true
      nmcli_cmd --wait 20 device wifi connect "${SSID}" password "${PASS}" ifname "${IFACE}"
    fi
  else
    if ! nmcli_cmd --wait 20 device wifi connect "${SSID}" ifname "${IFACE}"; then
      log "retrying ${SSID} with a fresh NetworkManager profile"
      nmcli_cmd connection delete "${SSID}" >/dev/null 2>&1 || true
      nmcli_cmd --wait 20 device wifi connect "${SSID}" ifname "${IFACE}"
    fi
  fi
}

current_ssid="$(nmcli_cmd -t -f GENERAL.CONNECTION device show "${IFACE}" 2>/dev/null | sed 's/^GENERAL.CONNECTION://')"
if [[ "${current_ssid}" == "${SSID}" ]]; then
  current_ip="$(current_ipv4)"
  if [[ -n "${current_ip}" ]]; then
    log "already connected to ${SSID} on ${IFACE}"
  else
    log "${IFACE} is associated to ${SSID} but has no IPv4 lease; reconnecting"
    nmcli_cmd device disconnect "${IFACE}" >/dev/null 2>&1 || true
    connect_ssid
  fi
else
  found_ssid=0
  for _ in $(seq 1 10); do
    nmcli_cmd device wifi rescan ifname "${IFACE}" >/dev/null 2>&1 || true
    sleep 2
    if nmcli_cmd -t -f SSID device wifi list ifname "${IFACE}" | grep -Fxq "${SSID}"; then
      found_ssid=1
      break
    fi
  done
  if [[ "${found_ssid}" -ne 1 ]]; then
    nmcli_cmd -f SSID,SIGNAL,SECURITY device wifi list ifname "${IFACE}" >&2 || true
    fail "SSID ${SSID} not visible on ${IFACE}"
  fi
  log "connecting ${IFACE} to ${SSID}"
  connect_ssid
fi

for _ in $(seq 1 10); do
  ip_addr="$(current_ipv4)"
  if [[ -n "${ip_addr}" ]]; then
    log "${IFACE} has IPv4 ${ip_addr}"
    exit 0
  fi
  sleep 1
done

fail "no IPv4 address acquired on ${IFACE}"
