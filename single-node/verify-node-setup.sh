#!/usr/bin/env bash
set -euo pipefail

# Verify baseline host prerequisites prepared by setup-node.sh.

FAIL_COUNT=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

check_command() {
  local cmd="$1"
  local label="$2"
  if command -v "${cmd}" >/dev/null 2>&1; then
    pass "${label}"
  else
    fail "${label}"
  fi
}

check_file_contains_line() {
  local file="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -f "${file}" ]]; then
    fail "${label} (missing file: ${file})"
    return
  fi

  if grep -Fxq "${expected}" "${file}" >/dev/null 2>&1; then
    pass "${label}"
  else
    fail "${label} (missing line: ${expected})"
  fi
}

check_service_active_enabled() {
  local unit="$1"
  local label="$2"
  local active enabled

  active="$(systemctl is-active "${unit}" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "${unit}" 2>/dev/null || true)"

  if [[ "${active}" == "active" && "${enabled}" == "enabled" ]]; then
    pass "${label}"
  else
    fail "${label} (active=${active:-unknown}, enabled=${enabled:-unknown})"
  fi
}

check_swap_disabled() {
  if swapon --noheadings | grep -q . >/dev/null 2>&1; then
    fail "Swap is disabled"
  else
    pass "Swap is disabled"
  fi
}

check_required_modules_loaded() {
  # overlay can be a loadable module or built into the kernel.
  if lsmod | grep -q "^overlay\\s" >/dev/null 2>&1 || grep -Eq "^nodev[[:space:]]+overlay$" /proc/filesystems; then
    pass "Kernel support present: overlay"
  else
    fail "Kernel support present: overlay"
  fi

  # br_netfilter can be built in; /proc/sys/net/bridge indicates availability.
  if lsmod | grep -q "^br_netfilter\\s" >/dev/null 2>&1 || [[ -e /proc/sys/net/bridge/bridge-nf-call-iptables ]]; then
    pass "Kernel support present: br_netfilter"
  else
    fail "Kernel support present: br_netfilter"
  fi
}

check_sysctl_runtime() {
  local iptables ipforward
  iptables="$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || true)"
  ipforward="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || true)"

  [[ "${iptables}" == "1" ]] && pass "sysctl runtime net.bridge.bridge-nf-call-iptables=1" \
    || fail "sysctl runtime net.bridge.bridge-nf-call-iptables=1 (actual=${iptables:-unset})"
  [[ "${ipforward}" == "1" ]] && pass "sysctl runtime net.ipv4.ip_forward=1" \
    || fail "sysctl runtime net.ipv4.ip_forward=1 (actual=${ipforward:-unset})"
}

check_containerd_cgroup_driver() {
  local cfg="/etc/containerd/config.toml"
  if [[ ! -f "${cfg}" ]]; then
    fail "containerd config exists at ${cfg}"
    return
  fi

  if grep -q "SystemdCgroup = true" "${cfg}" >/dev/null 2>&1; then
    pass "containerd uses systemd cgroup driver"
  else
    fail "containerd uses systemd cgroup driver"
  fi
}

check_k8s_repo_and_hold() {
  if [[ -f /etc/apt/sources.list.d/kubernetes.list ]]; then
    pass "Kubernetes apt repo file exists"
  else
    fail "Kubernetes apt repo file exists"
  fi

  local held
  held="$(apt-mark showhold 2>/dev/null || true)"

  if printf "%s\n" "${held}" | grep -q "^kubelet$" >/dev/null 2>&1; then
    pass "Package hold set: kubelet"
  else
    fail "Package hold set: kubelet"
  fi
  if printf "%s\n" "${held}" | grep -q "^kubeadm$" >/dev/null 2>&1; then
    pass "Package hold set: kubeadm"
  else
    fail "Package hold set: kubeadm"
  fi
  if printf "%s\n" "${held}" | grep -q "^kubectl$" >/dev/null 2>&1; then
    pass "Package hold set: kubectl"
  else
    fail "Package hold set: kubectl"
  fi
}

check_ufw_active() {
  local ufw_status
  ufw_status="$(ufw status | awk 'NR==1 {print $2}')"
  if [[ "${ufw_status}" == "active" ]]; then
    pass "UFW is active"
  else
    fail "UFW is active"
  fi
}

main() {
  echo "Verifying node bootstrap prerequisites..."
  check_command "containerd" "containerd binary installed"
  check_command "kubelet" "kubelet binary installed"
  check_command "kubeadm" "kubeadm binary installed"
  check_command "kubectl" "kubectl binary installed"

  check_swap_disabled
  check_required_modules_loaded
  check_file_contains_line "/etc/modules-load.d/k8s.conf" "overlay" "Persistent module config includes overlay"
  check_file_contains_line "/etc/modules-load.d/k8s.conf" "br_netfilter" "Persistent module config includes br_netfilter"
  check_file_contains_line "/etc/sysctl.d/99-kubernetes-cri.conf" "net.bridge.bridge-nf-call-iptables = 1" "Persistent sysctl includes bridge iptables"
  check_file_contains_line "/etc/sysctl.d/99-kubernetes-cri.conf" "net.ipv4.ip_forward = 1" "Persistent sysctl includes IPv4 forwarding"
  check_sysctl_runtime

  check_service_active_enabled "containerd" "containerd service active and enabled"
  check_containerd_cgroup_driver
  check_k8s_repo_and_hold
  check_ufw_active

  if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    pass "Verification completed with no failures"
    exit 0
  fi

  fail "Verification completed with failures=${FAIL_COUNT}"
  exit 1
}

main "$@"
