#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"
WEB_DIR="${ROOT_DIR}/web"
VGL_DIR="${ROOT_DIR}/third_party/virtual-gamepad-lib"

log() {
  printf '[setup] %s\n' "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '[setup] missing required command: %s\n' "$cmd" >&2
    return 1
  fi
}

log "root: ${ROOT_DIR}"

require_cmd python3
require_cmd npm

if [[ ! -d "${VENV_DIR}" ]]; then
  log "creating python virtual environment at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
else
  log "python virtual environment already exists"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

log "upgrading pip"
python -m pip install --upgrade pip

if ! command -v pio >/dev/null 2>&1; then
  log "installing PlatformIO into virtual environment"
  python -m pip install platformio
else
  log "PlatformIO already available on PATH"
fi

if [[ -d "${WEB_DIR}" ]]; then
  log "installing web workspace dependencies"
  (
    cd "${WEB_DIR}"
    npm install
  )
fi

if [[ -d "${VGL_DIR}" ]]; then
  log "installing virtual-gamepad-lib submodule dependencies"
  (
    cd "${VGL_DIR}"
    npm install --legacy-peer-deps
  )
fi

log "environment setup complete"
log "activate with: source ${VENV_DIR}/bin/activate"
