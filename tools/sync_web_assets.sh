#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="${ROOT_DIR}/web"
WEB_DIST_DIR="${WEB_DIR}/dist"
FIRMWARE_DATA_DIR="${ROOT_DIR}/firmware/data"

log() {
  printf '[sync-web] %s\n' "$1"
}

if [[ ! -d "${WEB_DIR}/node_modules" ]]; then
  log "missing web/node_modules; run npm install in web/ first"
  exit 1
fi

log "clearing generated web assets from firmware/data"
mkdir -p "${FIRMWARE_DATA_DIR}"
find "${FIRMWARE_DATA_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

log "linting web sources"
(
  cd "${WEB_DIR}"
  npm run lint
)

log "building web bundle"
(
  cd "${WEB_DIR}"
  npm run build
)

log "syncing web/dist into firmware/data"
cp -R "${WEB_DIST_DIR}/." "${FIRMWARE_DATA_DIR}/"

log "web assets synced"
