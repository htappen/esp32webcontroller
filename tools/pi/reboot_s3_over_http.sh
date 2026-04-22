#!/usr/bin/env bash
set -euo pipefail

HTTP_BASE_URL="${1:-${PI_S3_RECOVERY_HTTP_BASE_URL:-${CONTROLLER_DEVICE_LOCAL_URL:-}}}"

if [[ -z "${HTTP_BASE_URL}" ]]; then
  printf '[pi-http-reboot] no HTTP base URL provided\n' >&2
  exit 1
fi

printf '[pi-http-reboot] requesting firmware reboot at %s\n' "${HTTP_BASE_URL}"
curl -m 3 -fsS -X POST "${HTTP_BASE_URL%/}/api/device/reboot" >/dev/null
printf '[pi-http-reboot] reboot request accepted\n'
