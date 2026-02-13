#!/usr/bin/env bash
set -euo pipefail

# Configure SSH key-based access from this machine to a node.
#
# Usage:
#   ./scripts/setup-ssh-node.sh <node_host> <node_user> [ssh_port] [key_name]
#
# Example:
#   ./scripts/setup-ssh-node.sh yoga-node angel 22 yoga-node

NODE_HOST="${1:-}"
NODE_USER="${2:-}"
SSH_PORT="${3:-22}"
KEY_NAME_ARG="${4:-}"
KEY_NAME="${KEY_NAME:-${KEY_NAME_ARG:-${NODE_HOST}}}"
KEY_DIR="${KEY_DIR:-$HOME/.ssh}"
KEY_PATH="${KEY_PATH:-${KEY_DIR}/${KEY_NAME}}"
ADD_SSH_CONFIG="${ADD_SSH_CONFIG:-true}"

usage() {
  echo "Usage: $0 <node_host> <node_user> [ssh_port] [key_name]"
}

require_arg() {
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
  mkdir -p "${HOME}/.ssh"
  touch "${HOME}/.ssh/known_hosts"
  chmod 700 "${HOME}/.ssh"
  chmod 600 "${HOME}/.ssh/known_hosts"
  ssh-keyscan -p "${SSH_PORT}" -H "${NODE_HOST}" >>"${HOME}/.ssh/known_hosts" 2>/dev/null || true
}

copy_pubkey() {
  if command -v ssh-copy-id >/dev/null 2>&1; then
    echo "Copying public key with ssh-copy-id (password prompt is expected)"
    ssh-copy-id -i "${KEY_PATH}.pub" -p "${SSH_PORT}" "${NODE_USER}@${NODE_HOST}"
  else
    echo "ssh-copy-id not found; appending key manually (password prompt is expected)"
    cat "${KEY_PATH}.pub" | ssh -p "${SSH_PORT}" "${NODE_USER}@${NODE_HOST}" \
      "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; cat >> ~/.ssh/authorized_keys"
  fi
}

verify_login() {
  echo "Verifying key-based SSH login"
  ssh -i "${KEY_PATH}" \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -p "${SSH_PORT}" \
    "${NODE_USER}@${NODE_HOST}" "echo 'SSH key auth is working'"
}

ensure_ssh_config_entry() {
  if [[ "${ADD_SSH_CONFIG}" != "true" ]]; then
    echo "Skipping ~/.ssh/config update (ADD_SSH_CONFIG=${ADD_SSH_CONFIG})"
    return
  fi

  local ssh_config begin_mark end_mark
  ssh_config="${HOME}/.ssh/config"
  begin_mark="# >>> homelab ${NODE_HOST} >>>"
  end_mark="# <<< homelab ${NODE_HOST} <<<"

  mkdir -p "${HOME}/.ssh"
  touch "${ssh_config}"
  chmod 600 "${ssh_config}"

  if grep -Fq "${begin_mark}" "${ssh_config}"; then
    echo "SSH config entry for ${NODE_HOST} already exists in ${ssh_config}"
    return
  fi

  cat >>"${ssh_config}" <<EOF
${begin_mark}
Host ${NODE_HOST}
  HostName ${NODE_HOST}
  User ${NODE_USER}
  Port ${SSH_PORT}
  IdentityFile ${KEY_PATH}
  IdentitiesOnly yes
${end_mark}
EOF

  echo "Added SSH config entry for ${NODE_HOST} in ${ssh_config}"
}

print_next_steps() {
  cat <<EOF

SSH setup complete.
Next:
1) Test interactive shell:
   ssh "${NODE_HOST}"

   Or explicitly:
   ssh -i "${KEY_PATH}" -p "${SSH_PORT}" "${NODE_USER}@${NODE_HOST}"

2) Run remote bootstrap:
   KEY_PATH="${KEY_PATH}" ./scripts/run-remote-bootstrap.sh "${NODE_HOST}" "${NODE_USER}" "${SSH_PORT}"
EOF
}

main() {
  require_arg
  ensure_key
  seed_known_hosts
  copy_pubkey
  verify_login
  ensure_ssh_config_entry
  print_next_steps
}

main "$@"
