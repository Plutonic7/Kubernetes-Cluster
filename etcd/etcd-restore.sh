#!/usr/bin/env bash
# Restores etcd from a snapshot taken by etcd-backup.sh.
# DESTRUCTIVE: this replaces the cluster's entire state. Use for disaster
# recovery only (e.g. etcd corrupted, all control-plane data lost).
#
# Run on EACH control-plane node, one at a time, with the SAME snapshot file.
# For a single control-plane node, just run it once.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/etcd-snapshot-YYYYmmdd-HHMMSS.db"
  exit 1
fi

SNAPSHOT_FILE="$1"
CERT_DIR="/etc/kubernetes/pki/etcd"
RESTORE_DIR="/var/lib/etcd-restore"
NODE_NAME="$(hostname)"

# EDIT ME to match your cluster before running on more than one node.
INITIAL_CLUSTER="${INITIAL_CLUSTER:-${NODE_NAME}=https://127.0.0.1:2380}"
INITIAL_ADVERTISE_PEER_URLS="${INITIAL_ADVERTISE_PEER_URLS:-https://127.0.0.1:2380}"

echo "==> Step 1: stop the kubelet and move the static pod manifests aside"
echo "    so etcd/apiserver stop while we restore."
systemctl stop kubelet
mkdir -p /etc/kubernetes/manifests-paused
mv /etc/kubernetes/manifests/*.yaml /etc/kubernetes/manifests-paused/ 2>/dev/null || true

echo "==> Step 2: restoring snapshot to ${RESTORE_DIR}"
rm -rf "${RESTORE_DIR}"
ETCDCTL_API=3 etcdctl snapshot restore "${SNAPSHOT_FILE}" \
  --name "${NODE_NAME}" \
  --initial-cluster "${INITIAL_CLUSTER}" \
  --initial-advertise-peer-urls "${INITIAL_ADVERTISE_PEER_URLS}" \
  --data-dir "${RESTORE_DIR}"

echo "==> Step 3: point etcd's static pod manifest at the restored data dir"
echo "    Edit /etc/kubernetes/manifests-paused/etcd.yaml: change the"
echo "    hostPath for /var/lib/etcd to point at ${RESTORE_DIR} instead,"
echo "    (or move ${RESTORE_DIR} to replace the original /var/lib/etcd)."
read -rp "Press Enter once you've confirmed/edited the etcd manifest... "

echo "==> Step 4: restoring PKI/config backup if you're rebuilding from scratch"
echo "    (skip if PKI is already intact on this node):"
echo "    tar -xzf cluster-pki-<timestamp>.tar.gz -C /"

echo "==> Step 5: bring the static pods back and restart kubelet"
mv /etc/kubernetes/manifests-paused/*.yaml /etc/kubernetes/manifests/ 2>/dev/null || true
systemctl start kubelet

echo "==> Verify: kubectl get nodes && kubectl get pods -A"
echo "==> If you have multiple control-plane nodes, repeat on each one using"
echo "    the SAME snapshot file before rejoining them."
