#!/usr/bin/env bash

if [[ -n "${DEVICE_IDENTITY_SH_LOADED:-}" ]]; then
  return 0
fi
DEVICE_IDENTITY_SH_LOADED=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_TEST_DEVICE_UUID="019cba78-45f9-7003-ad59-451b095628be"
DEFAULT_DEVICE_IDENTITY_ARTIFACT="${ROOT_DIR}/build/device_identity.env"
DEFAULT_DEVICE_IDENTITY_HEADER="${ROOT_DIR}/firmware/src/generated/device_identity.h"

# Curated from the python-petname English word lists, trimmed to short ASCII words
# so the friendly BLE/Wi-Fi names stay compact and the hostname remains readable.
readonly DEVICE_IDENTITY_ADJECTIVES=(
  agile amber beryl brisk calm cedar civil clever coral dapper eager faint
  fond gentle golden grand happy humble jaunty jovial kind lucid mellow merry
  noble peppy placid proud quaint quick quiet rapid regal serene spry sunny
  swift tidy warm witty zesty
)

readonly DEVICE_IDENTITY_NOUNS=(
  antler badger beaver bunny cedar comet corgi daisy falcon fern finch fox
  gecko heron iris lizard maple marmot mink otter panda parrot pebble pine
  pixel puffin rabbit raven robin salmon shadow smoke star stone tiger tulip
  weasel willow wolf wren
)

device_identity_artifact_path() {
  printf '%s\n' "${CONTROLLER_DEVICE_IDENTITY_ARTIFACT:-${DEFAULT_DEVICE_IDENTITY_ARTIFACT}}"
}

device_identity_title_case() {
  local value="${1:-}"
  if [[ -z "${value}" ]]; then
    printf '\n'
    return 0
  fi
  printf '%s\n' "${value^}"
}

normalize_device_uuid() {
  local raw="${1:-}"
  raw="${raw,,}"
  if [[ ! "${raw}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    printf '[identity] invalid UUID "%s"\n' "${1:-}" >&2
    return 1
  fi
  printf '%s\n' "${raw}"
}

generate_device_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid
    return 0
  fi
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  printf '[identity] unable to generate UUID\n' >&2
  return 1
}

device_identity_hash() {
  local uuid="$1"
  printf '%s' "${uuid}" | sha256sum | awk '{print $1}'
}

device_identity_pick_word() {
  local hash="$1"
  local start="$2"
  local array_name="$3"
  local slice="${hash:${start}:8}"
  local -n words_ref="${array_name}"
  local count="${#words_ref[@]}"
  local index=$(( 16#${slice} % count ))
  printf '%s\n' "${words_ref[${index}]}"
}

device_identity_build_from_uuid() {
  local uuid
  uuid="$(normalize_device_uuid "${1}")" || return 1

  local hash adjective noun
  hash="$(device_identity_hash "${uuid}")"
  adjective="$(device_identity_pick_word "${hash}" 0 DEVICE_IDENTITY_ADJECTIVES)"
  noun="$(device_identity_pick_word "${hash}" 8 DEVICE_IDENTITY_NOUNS)"

  CONTROLLER_DEVICE_UUID="${uuid}"
  CONTROLLER_DEVICE_ADJECTIVE="${adjective}"
  CONTROLLER_DEVICE_NOUN="${noun}"
  CONTROLLER_DEVICE_HOSTNAME="${adjective}-${noun}"
  CONTROLLER_DEVICE_FRIENDLY_NAME="$(device_identity_title_case "${adjective}") $(device_identity_title_case "${noun}")"
  CONTROLLER_DEVICE_AP_SSID="${CONTROLLER_DEVICE_FRIENDLY_NAME} Pad"
  CONTROLLER_DEVICE_BLE_NAME="${CONTROLLER_DEVICE_FRIENDLY_NAME} Pad"
  CONTROLLER_DEVICE_MDNS_INSTANCE_NAME="${CONTROLLER_DEVICE_FRIENDLY_NAME} Pad"
  CONTROLLER_DEVICE_LOCAL_URL="http://${CONTROLLER_DEVICE_HOSTNAME}.local"
}

write_device_identity_artifact() {
  local artifact_path="${1:-$(device_identity_artifact_path)}"
  mkdir -p "$(dirname "${artifact_path}")"
  cat > "${artifact_path}" <<EOF
CONTROLLER_DEVICE_UUID='${CONTROLLER_DEVICE_UUID}'
CONTROLLER_DEVICE_ADJECTIVE='${CONTROLLER_DEVICE_ADJECTIVE}'
CONTROLLER_DEVICE_NOUN='${CONTROLLER_DEVICE_NOUN}'
CONTROLLER_DEVICE_FRIENDLY_NAME='${CONTROLLER_DEVICE_FRIENDLY_NAME}'
CONTROLLER_DEVICE_AP_SSID='${CONTROLLER_DEVICE_AP_SSID}'
CONTROLLER_DEVICE_BLE_NAME='${CONTROLLER_DEVICE_BLE_NAME}'
CONTROLLER_DEVICE_HOSTNAME='${CONTROLLER_DEVICE_HOSTNAME}'
CONTROLLER_DEVICE_MDNS_INSTANCE_NAME='${CONTROLLER_DEVICE_MDNS_INSTANCE_NAME}'
CONTROLLER_DEVICE_LOCAL_URL='${CONTROLLER_DEVICE_LOCAL_URL}'
EOF
}

load_device_identity_artifact() {
  local artifact_path="${1:-$(device_identity_artifact_path)}"
  if [[ ! -f "${artifact_path}" ]]; then
    return 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "${artifact_path}"
  set +a
}

device_identity_header_path() {
  printf '%s\n' "${CONTROLLER_DEVICE_IDENTITY_HEADER:-${DEFAULT_DEVICE_IDENTITY_HEADER}}"
}

write_device_identity_header() {
  local header_path="${1:-$(device_identity_header_path)}"
  local default_sta_ssid="${CONTROLLER_DEFAULT_STA_SSID:-}"
  local default_sta_pass="${CONTROLLER_DEFAULT_STA_PASS:-}"
  default_sta_ssid="${default_sta_ssid//\\/\\\\}"
  default_sta_ssid="${default_sta_ssid//\"/\\\"}"
  default_sta_pass="${default_sta_pass//\\/\\\\}"
  default_sta_pass="${default_sta_pass//\"/\\\"}"
  mkdir -p "$(dirname "${header_path}")"
  cat > "${header_path}" <<EOF
#pragma once

#define CONTROLLER_DEVICE_UUID "${CONTROLLER_DEVICE_UUID}"
#define CONTROLLER_AP_SSID "${CONTROLLER_DEVICE_AP_SSID}"
#define CONTROLLER_BLE_NAME "${CONTROLLER_DEVICE_BLE_NAME}"
#define CONTROLLER_HOSTNAME "${CONTROLLER_DEVICE_HOSTNAME}"
#define CONTROLLER_MDNS_INSTANCE_NAME "${CONTROLLER_DEVICE_MDNS_INSTANCE_NAME}"
#define CONTROLLER_FRIENDLY_NAME "${CONTROLLER_DEVICE_FRIENDLY_NAME}"
#define CONTROLLER_LOCAL_URL "${CONTROLLER_DEVICE_LOCAL_URL}"
#define CONTROLLER_DEFAULT_STA_SSID "${default_sta_ssid}"
#define CONTROLLER_DEFAULT_STA_PASS "${default_sta_pass}"
EOF
}

resolve_device_identity() {
  local mode="${1:-test}"
  local explicit_uuid="${2:-${CONTROLLER_DEVICE_UUID:-}}"
  local artifact_path
  artifact_path="$(device_identity_artifact_path)"

  if [[ -n "${explicit_uuid}" ]]; then
    device_identity_build_from_uuid "${explicit_uuid}" || return 1
    write_device_identity_artifact "${artifact_path}"
    return 0
  fi

  if [[ "${mode}" == "build" ]] && load_device_identity_artifact "${artifact_path}"; then
    device_identity_build_from_uuid "${CONTROLLER_DEVICE_UUID}" || return 1
    return 0
  fi

  if [[ "${mode}" == "build" ]]; then
    explicit_uuid="$(generate_device_uuid)" || return 1
  else
    explicit_uuid="${DEFAULT_TEST_DEVICE_UUID}"
  fi

  device_identity_build_from_uuid "${explicit_uuid}" || return 1
  write_device_identity_artifact "${artifact_path}"
}

clear_device_identity_artifact() {
  local artifact_path="${1:-$(device_identity_artifact_path)}"
  rm -f "${artifact_path}"
}
