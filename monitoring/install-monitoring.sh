#!/usr/bin/env bash
# Installs kube-prometheus-stack (Prometheus + Grafana + Alertmanager +
# prometheus-node-exporter) via Helm. Run with kubectl configured for the
# target cluster.
set -euo pipefail

NAMESPACE="${NAMESPACE:-monitoring}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD before running}"

if ! command -v helm &>/dev/null; then
  echo "==> Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "==> Adding prometheus-community Helm repo"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing/upgrading kube-prometheus-stack"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  -f "$(dirname "$0")/kube-prometheus-stack-values.yaml" \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}"

echo "==> Waiting for node-exporter DaemonSet to be ready on all nodes"
kubectl -n "${NAMESPACE}" rollout status daemonset/kube-prometheus-stack-prometheus-node-exporter --timeout=180s

echo "==> Done. Access Grafana with:"
echo "    kubectl -n ${NAMESPACE} port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "    then open http://localhost:3000 (user: admin)"
