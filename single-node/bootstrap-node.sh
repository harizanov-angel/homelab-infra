#!/usr/bin/env bash
set -euo pipefail

# Run this script directly on the target Ubuntu host.
# Optional overrides:
#   K8S_VERSION_SERIES=v1.32 sudo ./bootstrap-node.sh

K8S_VERSION_SERIES="${K8S_VERSION_SERIES:-v1.32}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

disable_swap() {
  swapoff -a || true
  sed -ri 's@^([^#].*\s+swap\s+.*)$@# \1@g' /etc/fstab
}

configure_kernel_modules() {
  cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
  modprobe overlay
  modprobe br_netfilter

  cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
  sysctl --system >/dev/null
}

install_base_packages() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https ca-certificates curl gpg ufw
}

install_containerd() {
  apt-get install -y containerd
  mkdir -p /etc/containerd
  containerd config default >/etc/containerd/config.toml
  sed -ri 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl daemon-reload
  systemctl enable --now containerd
}

install_kubernetes_packages() {
  mkdir -p -m 0755 /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION_SERIES}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION_SERIES}/deb/ /
EOF

  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
  systemctl enable --now kubelet
}

configure_ufw() {
  ufw --force default deny incoming
  ufw --force default allow outgoing
  ufw allow OpenSSH
  ufw allow 6443/tcp
  ufw allow 2379:2380/tcp
  ufw allow 10250/tcp
  ufw allow 10259/tcp
  ufw allow 10257/tcp
  ufw allow 30000:32767/tcp
  ufw --force enable
}

configure_shell_aliases() {
  local target_user target_home rc_file
  target_user="${SUDO_USER:-}"
  if [[ -z "${target_user}" ]]; then
    return
  fi

  target_home="$(getent passwd "${target_user}" | cut -d: -f6 || true)"
  if [[ -z "${target_home}" ]]; then
    return
  fi

  rc_file="${target_home}/.bashrc"
  touch "${rc_file}"
  if grep -q "### homelab kubernetes aliases ###" "${rc_file}"; then
    return
  fi

  cat >> "${rc_file}" <<'EOF'

### homelab kubernetes aliases ###
alias k='kubectl'
alias kgp='kubectl get pods -A'
alias kgs='kubectl get svc -A'
alias kgn='kubectl get nodes -o wide'
### /homelab kubernetes aliases ###
EOF
  chown "${target_user}:${target_user}" "${rc_file}"
}

print_next_steps() {
  cat <<EOF
  Next - verify that the node are setup correctly:
   ./remote_execution.sh <hostname> <user> verify-node-setup.sh
EOF
}

main() {
  require_root
  disable_swap
  configure_kernel_modules
  install_base_packages
  install_containerd
  install_kubernetes_packages
  configure_ufw
  configure_shell_aliases
  print_next_steps
}

main "$@"
