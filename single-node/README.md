# Single-Node Kubernetes Host Prep

Minimal flow to prepare one Ubuntu host for `kubeadm` and verify baseline node prerequisites.

## Quick setup flow

### 1) Set up SSH access (if you do not already have it)

From this folder:

```bash
./setup-ssh.sh <hostname> <user>
```

This creates `~/.ssh/<hostname>`, installs the pubkey on the node, and adds a `Host <hostname>` entry in `~/.ssh/config` for easier ssh.

### 2) Set up the node

```bash
./remote_execution.sh <hostname> <user> setup-node.sh
```
This will install everything you need to have this host as a k8s node.

### 3) Verify installation (optional)

```bash
./remote_execution.sh <hostname> <user> verify-node-setup.sh
```
Make sure the node is setup correctly and is ready for a `kubectl join` or `kubectl init`.

## What is in this folder

- `setup-ssh.sh` - creates/uses SSH key, installs pubkey on host, adds SSH config entry
- `remote_execution.sh` - runs a local script on the remote host over SSH
- `setup-node.sh` - prepares host packages, kernel/sysctl, containerd, kube tools, and UFW
- `verify-node-setup.sh` - checks that host prep was applied correctly
- `config.yaml` - defaults consumed by `remote_execution.sh` and passed to scripts as env vars

## Important caveats

- These scripts are for setup of a machine only. There is not going to be a cluster running on the host afterworst. To do this check the single-node folder in the clusters repo - https://github.com/harizanov-angel/homelab-clusters.
- SSH key naming is fixed to host-based keys:
  - private key: `~/.ssh/<hostname>`
  - public key: `~/.ssh/<hostname>.pub`
- Scripts expect hostnames that your local machine can resolve (DNS or `/etc/hosts`).
- `setup-ssh.sh` uses `ssh-copy-id` (it must be installed on your local machine).
- `remote_execution.sh` copies the script to a temporary file on the host, executes it with `sudo`, then removes the temp file.
- `remote_execution.sh` reads `config.yaml` and passes values as env vars (currently `K8S_VERSION_SERIES`).
- `setup-node.sh` appends a small Kubernetes alias block to the SSH user's `~/.bashrc` (e.g. `k`, `kgp`, `kgs`, `kgn`).

## Prerequisites

- Target host: Ubuntu 24.04, reachable by SSH
- Local machine has: `ssh`, `scp`, `ssh-copy-id`
- On target host, SSH server is enabled:
  - `sudo apt update && sudo apt install -y openssh-server`
  - `sudo systemctl enable --now ssh`
