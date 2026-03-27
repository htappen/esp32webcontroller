#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${PI_PYTHON_VENV_DIR:-${SCRIPT_DIR}/.venv-pi}"
REQ_FILE="${SCRIPT_DIR}/python-requirements.txt"

log() {
  printf '[pi-python-setup] %s\n' "$1"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[pi-python-setup] missing required command: %s\n' "${cmd}" >&2
    exit 1
  fi
}

require_cmd python3

if [[ ! -d "${VENV_DIR}" ]]; then
  log "creating Pi Python harness venv at ${VENV_DIR}"
  python3 -m venv --system-site-packages "${VENV_DIR}"
else
  log "reusing Pi Python harness venv at ${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

log "upgrading pip in Pi Python harness venv"
python -m pip install --upgrade pip

if [[ -s "${REQ_FILE}" ]]; then
  log "installing Pi Python harness requirements from ${REQ_FILE}"
  python -m pip install -r "${REQ_FILE}"
else
  log "no extra Pi Python harness requirements declared"
fi

log "verifying Pi Python harness imports"
python -c "import dbus, gi"

log "Pi Python harness venv ready"
