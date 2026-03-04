#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="${ROOT_DIR}/web"
FW_DATA_DIR="${ROOT_DIR}/firmware/data"

if [[ ! -d "${WEB_DIR}" ]]; then
  echo "web workspace not found: ${WEB_DIR}" >&2
  exit 1
fi

pushd "${WEB_DIR}" >/dev/null
npm run build
popd >/dev/null

rm -rf "${FW_DATA_DIR}/assets"
mkdir -p "${FW_DATA_DIR}/assets"
cp -R "${WEB_DIR}/dist"/* "${FW_DATA_DIR}/assets/"

echo "Packed web assets into ${FW_DATA_DIR}/assets"
