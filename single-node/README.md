# Single-Node Kubernetes Host Prep

Minimal flow to prepare one Ubuntu host for `kubeadm` and verify baseline node prerequisites.

## What is in this folder

- `setup-ssh-node.sh` - creates/uses SSH key, installs pubkey on host, adds SSH config entry
- `remote_execution.sh` - runs a local script on the remote host over SSH
- `bootstrap-node.sh` - prepares host packages, kernel/sysctl, containerd, kube tools, and UFW
- `verify-node-setup.sh` - checks that host prep was applied correctly
- `config.yaml` - defaults consumed by `remote_execution.sh` and passed to scripts as env vars

## Important caveats

- SSH key naming is fixed to host-based keys:
  - private key: `~/.ssh/<hostname>`
  - public key: `~/.ssh/<hostname>.pub`
- Scripts expect hostnames that your local machine can resolve (DNS or `/etc/hosts`).
- `setup-ssh-node.sh` uses `ssh-copy-id` (it must be installed on your local machine).
- `remote_execution.sh` copies the script to a temporary file on the host, executes it with `sudo`, then removes the temp file.
- `remote_execution.sh` reads `config.yaml` and passes values as env vars (currently `K8S_VERSION_SERIES`).
- `bootstrap-node.sh` appends a small Kubernetes alias block to the SSH user's `~/.bashrc` (e.g. `k`, `kgp`, `kgs`, `kgn`).

## Prerequisites

- Target host: Ubuntu 24.04, reachable by SSH
- Local machine has: `ssh`, `scp`, `ssh-copy-id`
- On target host, SSH server is enabled:
  - `sudo apt update && sudo apt install -y openssh-server`
  - `sudo systemctl enable --now ssh`

## 1) Set up SSH access

From this folder:

```bash
./setup-ssh-node.sh <hostname> <user>
```

This creates `~/.ssh/<hostname>`, installs the pubkey on the host, and adds a `Host <hostname>` entry in `~/.ssh/config`.

## 2) Run bootstrap from local machine

```bash
./remote_execution.sh <hostname> <user> bootstrap-node.sh
```

## 3) Verify node prep from local machine

```bash
./remote_execution.sh <hostname> <user> verify-node-setup.sh
```

## 4) Initialize cluster from local machine

```bash
./remote_execution.sh <hostname> <user> ../clusters/kubeadm-based/single-node/init-cluster.sh
```

## 5) Continue with cluster checks

```bash
ssh <hostname> 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
ssh <hostname> 'kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A'
```
