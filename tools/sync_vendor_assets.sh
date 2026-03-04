#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="${ROOT_DIR}/third_party/virtual-gamepad-lib"
VENDOR_DIR="${ROOT_DIR}/firmware/data/vendor"

if [[ ! -d "${SUBMODULE_DIR}" ]]; then
  echo "missing submodule: ${SUBMODULE_DIR}" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to build virtual-gamepad-lib assets" >&2
  exit 1
fi

pushd "${SUBMODULE_DIR}" >/dev/null
npm install
npm run build
popd >/dev/null

mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/virtual-gamepad-lib"
cp -R "${SUBMODULE_DIR}/dist" "${VENDOR_DIR}/virtual-gamepad-lib"

echo "Synced virtual-gamepad-lib dist into ${VENDOR_DIR}/virtual-gamepad-lib"
