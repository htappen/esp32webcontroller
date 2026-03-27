#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="${ROOT_DIR}/web"
HOST="0.0.0.0"
PORT="8080"
DEVICE_HOST=""

usage() {
  cat <<'EOF'
Usage: ./tools/serve_web_preview.sh [--device-host HOST] [--host HOST] [--port PORT]

Builds the web UI from web/src and serves the built bundle locally.

Options:
  --device-host HOST   Proxy ESP32 traffic to this host, e.g. game.local or 192.168.4.1
  --host HOST          Local bind host. Default: 0.0.0.0
  --port PORT          Local bind port. Default: 8080
  -h, --help           Show this help

Examples:
  ./tools/serve_web_preview.sh
  ./tools/serve_web_preview.sh --device-host game.local
  ./tools/serve_web_preview.sh --device-host 192.168.4.1 --port 9090
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-host)
      DEVICE_HOST="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
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

cd "${WEB_DIR}"
npm run build

SERVER_ARGS=(
  --root "${WEB_DIR}/dist"
  --host "${HOST}"
  --port "${PORT}"
)

if [[ -n "${DEVICE_HOST}" ]]; then
  SERVER_ARGS+=(
    --api-target "http://${DEVICE_HOST}"
    --ws-target "ws://${DEVICE_HOST}:81"
  )
fi

echo "Serving preview on http://${HOST}:${PORT}"
if [[ -n "${DEVICE_HOST}" ]]; then
  echo "Proxy target: http://${DEVICE_HOST} and ws://${DEVICE_HOST}:81"
else
  echo "No ESP32 proxy configured. UI will render, but /api and WebSocket calls will stay local."
fi

exec node "${ROOT_DIR}/tools/web_preview_server.mjs" "${SERVER_ARGS[@]}"
