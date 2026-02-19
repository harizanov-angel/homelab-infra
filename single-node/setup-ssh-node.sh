#!/usr/bin/env bash
set -euo pipefail

# Configure SSH key access to a node.
# Usage: ./setup-ssh-node.sh <node_host> <node_user>

NODE_HOST="${1:-}"
NODE_USER="${2:-}"
KEY_PATH="${HOME}/.ssh/${NODE_HOST}"

usage() {
  echo "Usage: $0 <node_host> <node_user>"
}

require_args() {
  if [[ -z "${NODE_HOST}" || -z "${NODE_USER}" ]]; then
    usage
    exit 1
  fi
}

ensure_key() {
  mkdir -p "$(dirname "${KEY_PATH}")"
  if [[ ! -f "${KEY_PATH}" ]]; then
    echo "Creating SSH key at ${KEY_PATH}"
    ssh-keygen -t ed25519 -a 100 -N "" -f "${KEY_PATH}" -C "homelab-${NODE_HOST}"
  else
    echo "Using existing SSH key at ${KEY_PATH}"
  fi
}

seed_known_hosts() {
  mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
  touch "${HOME}/.ssh/known_hosts" && chmod 600 "${HOME}/.ssh/known_hosts"
  ssh-keyscan -H "${NODE_HOST}" >>"${HOME}/.ssh/known_hosts" 2>/dev/null || true
}

copy_pubkey() {
  echo "Copying public key with ssh-copy-id (password prompt is expected)"
  ssh-copy-id -i "${KEY_PATH}.pub" "${NODE_USER}@${NODE_HOST}"
}

verify_login() {
  ssh -i "${KEY_PATH}" \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    "${NODE_USER}@${NODE_HOST}" "echo 'SSH key auth is working'"
}

ensure_ssh_config_entry() {
  local ssh_config
  ssh_config="${HOME}/.ssh/config"

  mkdir -p "${HOME}/.ssh"
  touch "${ssh_config}" && chmod 600 "${ssh_config}"

  if grep -q "^Host ${NODE_HOST}$" "${ssh_config}"; then
    return
  fi

  cat >> "${ssh_config}" <<EOF
Host ${NODE_HOST}
  HostName ${NODE_HOST}
  User ${NODE_USER}
  IdentityFile ${KEY_PATH}
  IdentitiesOnly yes
EOF
}

main() {
  require_args
  ensure_key
  seed_known_hosts
  copy_pubkey
  ensure_ssh_config_entry
  verify_login
  echo "SSH setup complete. Use: ssh ${NODE_HOST}"
}

main "$@"
