#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="${1:-$HOME/.ssh/controller_pi_ed25519}"
KEY_DIR="$(dirname "${KEY_PATH}")"
SSH_CONFIG_PATH="${HOME}/.ssh/config"
SSH_CONFIG_DIR="$(dirname "${SSH_CONFIG_PATH}")"
MANAGED_BLOCK_BEGIN="# BEGIN controller-pi managed block"
MANAGED_BLOCK_END="# END controller-pi managed block"

log() {
  printf '[pi-ssh] %s\n' "$1"
}

render_ssh_config_block() {
  cat <<EOF
${MANAGED_BLOCK_BEGIN}
Host controller-pi
  HostName controller-pi
  User controller
  IdentityFile ${KEY_PATH}
${MANAGED_BLOCK_END}
EOF
}

upsert_ssh_config() {
  local config_path="$1"
  local temp_path

  temp_path="$(mktemp)"

  if [[ -f "${config_path}" ]]; then
    awk -v begin="${MANAGED_BLOCK_BEGIN}" -v end="${MANAGED_BLOCK_END}" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip != 1 { print }
    ' "${config_path}" > "${temp_path}"
  fi

  if [[ -s "${temp_path}" ]]; then
    printf '\n' >> "${temp_path}"
  fi

  render_ssh_config_block >> "${temp_path}"
  mv "${temp_path}" "${config_path}"
}

mkdir -p "${KEY_DIR}"
mkdir -p "${SSH_CONFIG_DIR}"

if [[ -e "${KEY_PATH}" && -e "${KEY_PATH}.pub" ]]; then
  log "using existing key material at ${KEY_PATH}"
elif [[ -e "${KEY_PATH}" || -e "${KEY_PATH}.pub" ]]; then
  log "refusing to continue with partial key material at ${KEY_PATH}"
  exit 1
else
  ssh-keygen -t ed25519 -f "${KEY_PATH}" -N "" -C "controller-pi-test"
  log "generated new key material at ${KEY_PATH}"
fi

upsert_ssh_config "${SSH_CONFIG_PATH}"

log "private key: ${KEY_PATH}"
log "public key: ${KEY_PATH}.pub"
log "ssh config: ${SSH_CONFIG_PATH}"
log "install with:"
printf '  ssh-copy-id -i %s.pub controller@controller-pi\n' "${KEY_PATH}"
log "configured Host controller-pi for user controller with IdentityFile ${KEY_PATH}"
