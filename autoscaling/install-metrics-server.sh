#!/usr/bin/env bash
# metrics-server is required for HPA (Horizontal Pod Autoscaler) to work.
# On a self-hosted cluster with kubeadm-issued certs, it needs
# --kubelet-insecure-tls unless you've set up proper kubelet serving certs.
set -euo pipefail

echo "==> Installing metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "==> Patching metrics-server to trust kubelet certs on a self-hosted cluster"
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s

echo "==> Verify with: kubectl top nodes && kubectl top pods -A"
