# kubeadm Homelab Cluster

Scripts and manifests for a self-hosted Kubernetes cluster built with
`kubeadm`, with etcd backup/restore, Prometheus metrics (node-exporter),
GitOps auto-deployment + pod autoscaling, and CIS-style hardening baked in.

**Start here:** [PLAN.md](PLAN.md) — a full step-by-step walkthrough,
beginner-friendly, with a checkpoint after every step.

## Layout

```
scripts/          Cluster bring-up: node prep, kubeadm init/join, CNI
etcd/             Etcd snapshot backup (systemd timer) + restore procedure
monitoring/       kube-prometheus-stack (Prometheus, Grafana, node-exporter)
autoscaling/      metrics-server, HPA example, optional KEDA
gitops/           Argo CD install + example auto-sync Application
hardening/        Audit logging, secrets encryption, NetworkPolicy, PSA, kube-bench
```

## Requirements

- 3 Linux machines (physical or VM), Ubuntu 22.04/24.04 LTS, 2 CPU / 2GB RAM
  minimum each, same network, static IPs
- Root/sudo access on each
- `kubectl`/`helm` run from the control-plane node (or your workstation once
  `~/.kube/config` is copied over)

## Quick start

```bash
# On every node:
sudo bash scripts/00-common-setup.sh

# On the control-plane node:
export CONTROL_PLANE_ENDPOINT=<control-plane-ip>
sudo -E bash scripts/01-init-control-plane.sh
bash scripts/03-install-calico.sh

# On each worker, using the join command printed above:
sudo bash scripts/02-join-worker.sh '<kubeadm join ...>'
```

Then continue through [PLAN.md](PLAN.md) sections 5-8 for backups,
monitoring, autoscaling/GitOps, and hardening.

## Notes

- All scripts are meant to be read before running — several ask you to
  confirm values (IPs, join tokens, passwords) rather than guessing them.
- `hardening/apply-hardening.sh` edits the live API server manifest; it
  backs up the original first, but read it before running on anything you
  care about.
- No cloud account or public DNS is required — this is designed to run
  entirely on your local network.
