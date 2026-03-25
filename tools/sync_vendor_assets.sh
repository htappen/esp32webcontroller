#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="${ROOT_DIR}/third_party/virtual-gamepad-lib"
VENDOR_DIR="${ROOT_DIR}/firmware/data/vendor"
BUILD=0

usage() {
  cat <<'EOF'
Usage: ./tools/sync_vendor_assets.sh [--build]

Copies browser-ready assets from the virtual-gamepad-lib submodule into
firmware/data/vendor for LittleFS upload.

Options:
  --build    Run npm install + npm run build inside the submodule before syncing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "${SUBMODULE_DIR}" || ! -f "${ROOT_DIR}/.gitmodules" ]]; then
  echo "missing submodule checkout: ${SUBMODULE_DIR}" >&2
  echo "run: git submodule update --init --recursive" >&2
  exit 1
fi

DIST_DIR="${SUBMODULE_DIR}/dist"
ASSET_DIR="${SUBMODULE_DIR}/gamepad_assets"

if [[ "${BUILD}" -eq 1 ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required when --build is used" >&2
    exit 1
  fi

  pushd "${SUBMODULE_DIR}" >/dev/null
  npm install
  npm run build
  popd >/dev/null
fi

if [[ ! -d "${DIST_DIR}" ]]; then
  echo "missing ${DIST_DIR}" >&2
  echo "initialize submodules, or rerun with --build if the submodule has not been built yet" >&2
  exit 1
fi

if [[ ! -d "${ASSET_DIR}" ]]; then
  echo "missing ${ASSET_DIR}" >&2
  exit 1
fi

mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/virtual-gamepad-lib"
mkdir -p "${VENDOR_DIR}/virtual-gamepad-lib"
cp -R "${DIST_DIR}/"* "${VENDOR_DIR}/virtual-gamepad-lib/"
cp -R "${ASSET_DIR}" "${VENDOR_DIR}/virtual-gamepad-lib/"

echo "Synced virtual-gamepad-lib modules and assets into ${VENDOR_DIR}/virtual-gamepad-lib"
