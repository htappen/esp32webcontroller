#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="${1:-}"
LOG_LABEL="${2:-UART}"
ELF_FILE="${3:-}"

if [[ -z "${LOG_FILE}" ]]; then
  printf '[boot-loop] log file is required\n' >&2
  exit 1
fi

if [[ ! -s "${LOG_FILE}" ]]; then
  exit 0
fi

fail() {
  printf '[boot-loop] %s\n' "$1" >&2
  printf '[boot-loop] %s tail:\n' "${LOG_LABEL}" >&2
  tail -n 80 "${LOG_FILE}" >&2 || true
  if [[ -x "${SCRIPT_DIR}/decode_esp32_panic_log.sh" ]]; then
    printf '[boot-loop] decoded panic summary:\n' >&2
    if [[ -n "${ELF_FILE}" ]]; then
      "${SCRIPT_DIR}/decode_esp32_panic_log.sh" "${LOG_FILE}" "${ELF_FILE}" >&2 || true
    else
      "${SCRIPT_DIR}/decode_esp32_panic_log.sh" "${LOG_FILE}" >&2 || true
    fi
  fi
  exit 1
}

crash_lines="$(
  grep -nEi \
    'Brownout detector was triggered|Guru Meditation Error|abort\\(\\) was called|assert failed|Stack smashing protect failure|panic' \
    "${LOG_FILE}" || true
)"
if [[ -n "${crash_lines}" ]]; then
  printf '%s\n' "${crash_lines}" >&2
  fail "crash signature seen in ${LOG_LABEL} log; inspect firmware/platformio.ini first"
fi

reboot_count="$(grep -cE '^rst:' "${LOG_FILE}" || true)"
if [[ "${reboot_count}" -ge 2 ]]; then
  fail "likely boot loop: saw ${reboot_count} reset banners in ${LOG_LABEL} log; inspect firmware/platformio.ini first"
fi
