#!/usr/bin/env bash
# Run on each WORKER node, after 00-common-setup.sh.
# Paste the exact 'kubeadm join ...' command that 01-init-control-plane.sh
# printed for WORKERS (not the control-plane one). Example shape:
#
#   kubeadm join 192.168.1.10:6443 --token abcdef.0123456789abcdef \
#     --discovery-token-ca-cert-hash sha256:<hash>
#
# If you lost it, run this on a control-plane node to print a fresh one:
#   kubeadm token create --print-join-command
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 '<full kubeadm join command copied from control-plane output>'"
  exit 1
fi

eval "$1"

echo "==> Joined. Verify from a control-plane node with: kubectl get nodes"
