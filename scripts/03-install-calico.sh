#!/usr/bin/env bash
# Run on a control-plane node (with kubectl configured) after the cluster is
# initialized. Installs Calico as the CNI - chosen because it supports
# Kubernetes NetworkPolicy, which the hardening step relies on.
set -euo pipefail

CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"

echo "==> Installing Calico ${CALICO_VERSION}"
kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

cat <<'EOF' > /tmp/calico-custom-resources.yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

echo "==> Waiting for the Tigera operator CRDs to register"
sleep 15
kubectl apply -f /tmp/calico-custom-resources.yaml

echo "==> Waiting for Calico pods to become ready (this can take a few minutes)"
kubectl -n calico-system wait --for=condition=Ready pods --all --timeout=300s || true

kubectl get pods -n calico-system
echo "==> If all pods are Running, join your worker nodes next."
