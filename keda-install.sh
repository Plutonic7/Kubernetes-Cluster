#!/usr/bin/env bash
# Optional: KEDA extends autoscaling to event-driven sources (queue depth,
# Prometheus metrics, cron schedules, etc.) instead of just CPU/memory.
# Useful on a homelab cluster where you might scale on a custom metric
# already collected by the Prometheus stack installed in monitoring/.
#
# Note: there is no cloud-style Cluster Autoscaler for bare-metal/kubeadm
# nodes - HPA/KEDA scale PODS, not physical nodes. To add node capacity you
# provision another machine and run scripts/00-common-setup.sh +
# scripts/02-join-worker.sh on it. (Cluster API - see PLAN.md "Recommended
# improvements" - can automate this for VM-backed nodes.)
set -euo pipefail

if ! command -v helm &>/dev/null; then
  echo "Helm is required. Run monitoring/install-monitoring.sh first or install Helm."
  exit 1
fi

helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install keda kedacore/keda --namespace keda

kubectl -n keda rollout status deployment/keda-operator --timeout=120s
echo "==> KEDA installed. Define ScaledObjects to scale on custom/event metrics."
