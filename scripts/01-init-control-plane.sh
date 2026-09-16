#!/usr/bin/env bash
# Run on the FIRST control-plane node only, after 00-common-setup.sh.
set -euo pipefail

# EDIT ME: the IP or DNS name workers/other control-plane nodes will use to
# reach the API server. For a single control-plane node this can just be
# that node's own IP. For HA (3 control-plane nodes) point it at your
# load balancer VIP/DNS name instead.
CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-192.168.1.10}"
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"   # matches Calico's default

echo "==> Running kubeadm init"
kubeadm init \
  --control-plane-endpoint "${CONTROL_PLANE_ENDPOINT}:6443" \
  --upload-certs \
  --pod-network-cidr "${POD_CIDR}"

echo "==> Configuring kubectl for the current user"
mkdir -p "$HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo ""
echo "=================================================================="
echo " Save the 'kubeadm join' commands kubeadm printed above:"
echo "   - one for joining ADDITIONAL CONTROL-PLANE nodes (has --certificate-key)"
echo "   - one for joining WORKER nodes"
echo " If you lose them, regenerate with:"
echo "   kubeadm token create --print-join-command"
echo "   kubeadm init phase upload-certs --upload-certs   (for a new cert key)"
echo "=================================================================="
echo ""
echo "==> Next: install the CNI with scripts/03-install-calico.sh"
