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

log "building web bundle"
(
  cd "${WEB_DIR}"
  npm run build
)

log "syncing web/dist into firmware/data"
mkdir -p "${FIRMWARE_DATA_DIR}"
rm -f "${FIRMWARE_DATA_DIR}/index.html" "${FIRMWARE_DATA_DIR}/app.js" "${FIRMWARE_DATA_DIR}/app.css"
cp "${WEB_DIST_DIR}/index.html" "${FIRMWARE_DATA_DIR}/index.html"
cp "${WEB_DIST_DIR}/app.js" "${FIRMWARE_DATA_DIR}/app.js"
cp "${WEB_DIST_DIR}/app.css" "${FIRMWARE_DATA_DIR}/app.css"

log "web assets synced"
