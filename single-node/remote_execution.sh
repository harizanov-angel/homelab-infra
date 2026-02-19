#!/usr/bin/env bash
set -euo pipefail

# Run a local script on a remote host via SSH.
# Usage: ./remote_execution.sh <hostname> <user> <local_script>

HOSTNAME_ARG="${1:-}"
USER_ARG="${2:-}"
LOCAL_SCRIPT_ARG="${3:-}"
TARGET="${USER_ARG}@${HOSTNAME_ARG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
LOCAL_SCRIPT=""
REMOTE_SCRIPT=""
K8S_VERSION_SERIES=""
POD_CIDR=""
SERVICE_CIDR=""
NODE_NAME=""

usage() {
  echo "Usage: $0 <hostname> <user> <local_script>"
}

require_args() {
  if [[ -z "${HOSTNAME_ARG}" || -z "${USER_ARG}" || -z "${LOCAL_SCRIPT_ARG}" ]]; then
    usage
    exit 1
  fi
}

resolve_script_path() {
  if [[ "${LOCAL_SCRIPT_ARG}" == */* ]]; then
    LOCAL_SCRIPT="${LOCAL_SCRIPT_ARG}"
  else
    LOCAL_SCRIPT="${SCRIPT_DIR}/${LOCAL_SCRIPT_ARG}"
  fi

  if [[ ! -f "${LOCAL_SCRIPT}" ]]; then
    echo "Local script not found: ${LOCAL_SCRIPT}" >&2
    exit 1
  fi

  REMOTE_SCRIPT="/tmp/remote_execution_$(basename "${LOCAL_SCRIPT}").$$.sh"
}

yaml_get_top_level() {
  local key="$1"
  awk -F': *' -v requested_key="${key}" '
    $0 ~ /^[[:space:]]*#/ {next}
    $1 == requested_key {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "${CONFIG_FILE}" || true
}

load_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    return
  fi
  K8S_VERSION_SERIES="$(yaml_get_top_level "k8s_version_series")"
  POD_CIDR="$(yaml_get_top_level "pod_cidr")"
  SERVICE_CIDR="$(yaml_get_top_level "service_cidr")"
  NODE_NAME="$(yaml_get_top_level "node_name")"
}

build_remote_env_prefix() {
  local env_parts=()
  [[ -n "${K8S_VERSION_SERIES}" ]] && env_parts+=("K8S_VERSION_SERIES=$(printf '%q' "${K8S_VERSION_SERIES}")")
  [[ -n "${POD_CIDR}" ]] && env_parts+=("POD_CIDR=$(printf '%q' "${POD_CIDR}")")
  [[ -n "${SERVICE_CIDR}" ]] && env_parts+=("SERVICE_CIDR=$(printf '%q' "${SERVICE_CIDR}")")
  [[ -n "${NODE_NAME}" ]] && env_parts+=("NODE_NAME=$(printf '%q' "${NODE_NAME}")")
  if [[ ${#env_parts[@]} -eq 0 ]]; then
    echo ""
  else
    printf "%s " "${env_parts[@]}"
  fi
}

main() {
  require_args
  resolve_script_path
  load_config
  local env_prefix
  env_prefix="$(build_remote_env_prefix)"
  scp "${LOCAL_SCRIPT}" "${TARGET}:${REMOTE_SCRIPT}"
  ssh -tt "${TARGET}" "chmod 700 '${REMOTE_SCRIPT}' && sudo ${env_prefix}bash '${REMOTE_SCRIPT}'; RC=\$?; rm -f '${REMOTE_SCRIPT}'; exit \$RC"
}

main "$@"
