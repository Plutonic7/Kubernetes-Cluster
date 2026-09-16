#!/usr/bin/env bash
# Snapshots etcd on a control-plane node and prunes old snapshots.
# Run this ON a control-plane node (etcd runs as a static pod there).
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/etcd}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
ENDPOINT="${ENDPOINT:-https://127.0.0.1:2379}"
CERT_DIR="/etc/kubernetes/pki/etcd"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

mkdir -p "${BACKUP_DIR}"

echo "==> Taking etcd snapshot -> ${SNAPSHOT_FILE}"
ETCDCTL_API=3 etcdctl \
  --endpoints="${ENDPOINT}" \
  --cacert="${CERT_DIR}/ca.crt" \
  --cert="${CERT_DIR}/server.crt" \
  --key="${CERT_DIR}/server.key" \
  snapshot save "${SNAPSHOT_FILE}"

echo "==> Verifying snapshot integrity"
ETCDCTL_API=3 etcdctl --write-out=table snapshot status "${SNAPSHOT_FILE}"

echo "==> Also backing up cluster PKI + kubeadm config (needed for a full restore)"
tar -czf "${BACKUP_DIR}/cluster-pki-${TIMESTAMP}.tar.gz" \
  /etc/kubernetes/pki \
  /etc/kubernetes/manifests \
  /etc/kubernetes/admin.conf

echo "==> Pruning snapshots older than ${RETENTION_DAYS} days"
find "${BACKUP_DIR}" -name 'etcd-snapshot-*.db' -mtime "+${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -name 'cluster-pki-*.tar.gz' -mtime "+${RETENTION_DAYS}" -delete

echo "==> Done. Latest snapshot: ${SNAPSHOT_FILE}"
echo "    STRONGLY RECOMMENDED: copy ${BACKUP_DIR} off this node (rsync/rclone/S3)."
echo "    A backup that only lives on the node it protects is not a backup."
