#!/usr/bin/env bash
set -euo pipefail

SSID="${1:-ESP32-Controller}"
PASS="${2:-controller123}"
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

current_ssid="$(nmcli_cmd -t -f GENERAL.CONNECTION device show "${IFACE}" 2>/dev/null | sed 's/^GENERAL.CONNECTION://')"
if [[ "${current_ssid}" == "${SSID}" ]]; then
  log "already connected to ${SSID} on ${IFACE}"
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
  nmcli_cmd radio wifi on
  if ! nmcli_cmd --wait 20 device wifi connect "${SSID}" password "${PASS}" ifname "${IFACE}"; then
    log "retrying ${SSID} with a fresh NetworkManager profile"
    nmcli_cmd connection delete "${SSID}" >/dev/null 2>&1 || true
    nmcli_cmd --wait 20 device wifi connect "${SSID}" password "${PASS}" ifname "${IFACE}"
  fi
fi

for _ in $(seq 1 10); do
  ip_addr="$(ip -4 -o addr show dev "${IFACE}" | awk '{print $4}' | head -n1)"
  if [[ -n "${ip_addr}" ]]; then
    log "${IFACE} has IPv4 ${ip_addr}"
    exit 0
  fi
  sleep 1
done

fail "no IPv4 address acquired on ${IFACE}"
