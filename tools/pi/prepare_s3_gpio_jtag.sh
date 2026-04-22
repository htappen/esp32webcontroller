#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bash "${ROOT_DIR}/tools/pi/set_gpio3_low.sh"
bash "${ROOT_DIR}/tools/pi/set_gpio4_low.sh"

