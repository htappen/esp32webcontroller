#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PI_HOST="${PI_HOST:-controller-pi}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/home/controller/controller-pi-e2e}"

log() {
  printf '[pi-sync] %s\n' "$1"
}

sync_repo_snapshot() {
  log "staging ${ROOT_DIR} -> ${PI_HOST}:${REMOTE_BASE_DIR}"
  tar -C "${ROOT_DIR}" \
    --exclude=".git" \
    --exclude=".venv" \
    --exclude=".platformio" \
    --exclude="web/node_modules" \
    --exclude="third_party/virtual-gamepad-lib/node_modules" \
    -cf - . \
    | ssh "${PI_HOST}" "mkdir -p '${REMOTE_BASE_DIR}' && tar -C '${REMOTE_BASE_DIR}' -xf -"
}

sync_repo_snapshot
