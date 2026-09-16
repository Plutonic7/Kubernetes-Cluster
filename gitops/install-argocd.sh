#!/usr/bin/env bash
# Installs Argo CD for GitOps-style auto-deployment: push to your Git repo,
# Argo CD detects the change and reconciles the cluster to match.
set -euo pipefail

NAMESPACE="${NAMESPACE:-argocd}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${NAMESPACE}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for argocd-server to be ready"
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-server --timeout=180s

echo "==> Initial admin password:"
kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "==> Access UI with: kubectl -n ${NAMESPACE} port-forward svc/argocd-server 8080:443"
echo "    Then log in and change the admin password immediately."
echo "==> Next: point an Application manifest (see gitops/app-example.yaml) at your repo."
