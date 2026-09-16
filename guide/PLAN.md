# Self-Hosted Kubernetes Cluster with kubeadm — Beginner's Step-by-Step Plan

This walks you from "nothing installed" to a working local Kubernetes cluster
with etcd backups, Prometheus metrics, autoscaling, GitOps auto-deployment,
and CIS-style hardening. Every command referenced here lives in this folder —
see [README.md](README.md) for the file map.

**Time estimate:** 2-4 hours for the core cluster, another hour or two for
the add-ons, spread over a day is fine.

---

## 0. Decide your topology

Pick based on what hardware you have:

| Setup | Machines needed | Good for |
|---|---|---|
| Minimal | 1 control-plane + 1 worker | Learning, low resource use |
| Recommended | 1 control-plane + 2 workers | Realistic homelab, room to schedule real workloads |
| HA | 3 control-plane + 2+ workers | Surviving a control-plane node dying (advanced — see Appendix A) |

This plan assumes the **Recommended** setup. Each machine can be:
- A physical box on your network, or
- A VM (VirtualBox, Multipass, Proxmox, or Hyper-V)

**Minimum specs per node:** 2 CPUs, 2GB RAM (4GB+ recommended for the
control-plane once you add monitoring), 20GB disk, Ubuntu 22.04 or 24.04
Server LTS installed, all nodes on the same network and able to reach each
other by IP.

Write down your IPs now, you'll need them repeatedly:

```
control-plane: 192.168.1.10   (hostname: k8s-cp1)
worker-1:      192.168.1.11   (hostname: k8s-worker1)
worker-2:      192.168.1.12   (hostname: k8s-worker2)
```

Set each machine's hostname to something matching (`hostnamectl set-hostname k8s-cp1`)
and add all three to `/etc/hosts` on every node:

```
192.168.1.10 k8s-cp1
192.168.1.11 k8s-worker1
192.168.1.12 k8s-worker2
```

---

## 1. Prepare every node

On **all three machines**, copy this repo over (`scp` or clone it) and run
as root:

```bash
sudo KUBE_VERSION=1.30 bash scripts/00-common-setup.sh
```

This installs containerd, kubeadm, kubelet, kubectl, disables swap, and sets
the kernel/network settings Kubernetes requires. Takes 3-5 minutes per node.

**Checkpoint:** `kubelet --version` and `containerd --version` both return
output with no errors on every node.

---

## 2. Initialize the control plane

On **k8s-cp1 only**:

```bash
export CONTROL_PLANE_ENDPOINT=192.168.1.10
sudo -E bash scripts/01-init-control-plane.sh
```

**This will print two `kubeadm join ...` commands near the bottom of the
output — copy both into a text file now.** One is for joining more
control-plane nodes, one is for workers. They contain a secret token; treat
them like a password (they're only valid for 24h anyway).

**Checkpoint:** `kubectl get nodes` shows `k8s-cp1` in `NotReady` state
(expected — it becomes `Ready` after the next step installs networking).

---

## 3. Install the pod network (Calico)

Still on **k8s-cp1**:

```bash
bash scripts/03-install-calico.sh
```

Wait for it to report all pods `Running` (can take 2-5 minutes on first
pull). Then:

```bash
kubectl get nodes
```

**Checkpoint:** `k8s-cp1` now shows `Ready`.

---

## 4. Join the worker nodes

On **k8s-worker1** and **k8s-worker2**, paste the *worker* join command you
saved in step 2:

```bash
sudo bash scripts/02-join-worker.sh 'kubeadm join 192.168.1.10:6443 --token ... --discovery-token-ca-cert-hash sha256:...'
```

Back on **k8s-cp1**, confirm:

```bash
kubectl get nodes
```

**Checkpoint:** all three nodes show `Ready`. If a worker doesn't turn
`Ready` within a minute or two, check `journalctl -u kubelet -f` on that
node.

🎉 **You now have a working Kubernetes cluster.** Everything below is
add-ons, in the order the original requirements listed them.

---

## 5. Etcd backup and restore

Automated daily snapshots, on **each control-plane node** (just k8s-cp1 in
this topology):

```bash
sudo cp etcd/etcd-backup.sh /usr/local/bin/etcd-backup.sh
sudo chmod +x /usr/local/bin/etcd-backup.sh
sudo cp etcd/etcd-backup.service etcd/etcd-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now etcd-backup.timer
```

Run one manually right now to confirm it works, and check the result:

```bash
sudo systemctl start etcd-backup.service
sudo journalctl -u etcd-backup.service -n 30
ls -lh /var/backups/etcd
```

**Copy `/var/backups/etcd` off the node regularly** (cron + `rsync` to
another machine, or `rclone` to cloud storage). A backup that only exists on
the machine it's protecting doesn't survive that machine dying.

**To restore** (only if disaster strikes — this is destructive):

```bash
sudo bash etcd/etcd-restore.sh /var/backups/etcd/etcd-snapshot-<timestamp>.db
```

Read the script's comments before running it for real; test it once on a
throwaway cluster so you're not learning the procedure during an actual
outage.

**Checkpoint:** you have a snapshot file in `/var/backups/etcd`, a copy of it
somewhere off that node, and you've read (ideally dry-run tested) the
restore procedure.

---

## 6. Prometheus + node-exporter for metrics

Needs Helm and about 1GB RAM headroom on the control-plane or a worker. On
**k8s-cp1** (or wherever your kubectl is configured):

```bash
export GRAFANA_ADMIN_PASSWORD='pick-a-real-password'
bash monitoring/install-monitoring.sh
```

This installs Prometheus, Grafana, Alertmanager, and
`prometheus-node-exporter` as a DaemonSet — meaning one exporter pod per
node, so every machine's CPU/memory/disk/network metrics get scraped.

```bash
kubectl -n monitoring get pods -o wide
```

**Checkpoint:** you see a `node-exporter` pod on each of the 3 nodes, all
`Running`. View dashboards:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000`, log in as `admin`, open the "Node Exporter /
Nodes" dashboard (bundled by default).

---

## 7. Auto deployment and autoscaling

Two separate things live under this heading:

**(a) Auto-scaling pods** (add/remove pod replicas based on load):

```bash
bash autoscaling/install-metrics-server.sh
kubectl top nodes   # should print real numbers, confirms metrics-server works
kubectl apply -f autoscaling/hpa-example.yaml
kubectl get hpa -w
```

**Checkpoint:** `kubectl get hpa` shows a `TARGETS` column with a real
percentage (not `<unknown>`) within a minute or two.

> Note: on bare-metal/kubeadm there's no cloud-style autoscaler that adds
> **physical nodes** for you — HPA scales pods within the capacity you have.
> To add capacity, provision another machine and repeat steps 1 + 4. See
> Appendix B for automating that with Cluster API if you're VM-based.

Optional — event-driven scaling (scale on a queue depth, cron schedule, or
a custom Prometheus metric, not just CPU/memory):

```bash
bash autoscaling/keda-install.sh
```

**(b) Auto-deployment** (push to Git, cluster updates itself — GitOps):

```bash
bash gitops/install-argocd.sh
```

Follow the printed instructions to log in, then edit
`gitops/app-example.yaml` to point `repoURL`/`path` at your own manifests
repo and apply it:

```bash
kubectl apply -f gitops/app-example.yaml
```

**Checkpoint:** pushing a change to that repo path results in Argo CD
syncing it onto the cluster automatically within its poll interval (default
~3 min), visible in the Argo CD UI as `Synced`/`Healthy`.

---

## 8. Cluster hardening

```bash
sudo bash hardening/apply-hardening.sh
```

Read the script's output carefully — it edits the API server's static pod
manifest (backed up automatically first) to turn on audit logging and
secrets encryption at rest. Watch the API server come back up:

```bash
watch kubectl -n kube-system get pods -l component=kube-apiserver
```

If it doesn't recover within a minute, restore the printed backup path and
investigate before retrying.

Then apply the remaining hardening manifests:

```bash
kubectl apply -f hardening/pod-security-namespace-labels.yaml
kubectl apply -f hardening/network-policy-default-deny.yaml
```

Run a CIS benchmark scan to see where you stand:

```bash
kubectl apply -f hardening/kube-bench-job.yaml
kubectl logs job/kube-bench | less
```

Work through any `[FAIL]` lines it reports. Most kubeadm clusters start
around 70-80% pass rate; the flags this plan already applied close a good
chunk of the gap.

**Checkpoint:** kube-bench log has no `[FAIL]` on critical items (API server
anonymous auth, etcd client cert auth, kubelet anonymous auth), Secrets
created after this point are encrypted at rest (spot-check: read the raw
value straight out of etcd — it should look like ciphertext, not plaintext
JSON).

Other hardening worth doing manually (not scripted here, environment-specific):
- Rotate the kubeadm bootstrap tokens / join tokens if they've been sitting around
- Set resource `requests`/`limits` on every workload so one bad pod can't starve a node
- Restrict `kubectl` access via RBAC per user/team instead of sharing `admin.conf`
- Keep kubelet's `--anonymous-auth=false` and `--read-only-port=0` (default in
  recent versions, worth double-checking)
- Patch the OS and re-run `kubeadm upgrade` on a regular cadence — see Appendix C

---

## 9. Recommended improvements (not in the original ask, worth adding)

Roughly in priority order for a homelab that's meant to actually host things:

1. **Ingress + TLS** — `ingress-nginx` for routing HTTP(S) into the cluster,
   plus `cert-manager` for free automatic TLS certs (Let's Encrypt, or a
   self-signed internal CA if this never leaves your LAN).
2. **Persistent storage** — kubeadm gives you no default `StorageClass`.
   For a homelab, `Longhorn` (simple, replicated block storage across
   nodes) or `Rook-Ceph` (more powerful, more overhead) are the common
   picks. Without this, anything needing a `PersistentVolumeClaim` will
   just hang `Pending`.
3. **Full backup beyond etcd** — etcd snapshots protect cluster *state*
   (what should be running), not application *data* (a database's actual
   rows) or PVC contents. Add `Velero` with a storage backend (MinIO
   works great self-hosted) to back up both manifests and volume data.
4. **Centralized logging** — `Loki` + `Promtail` (pairs naturally with the
   Grafana you already have from step 6) so pod logs survive pod
   restarts/deletions.
5. **Secrets management** — plain Kubernetes Secrets are only
   base64-encoded (you already added at-rest encryption in step 8, which
   helps, but consider `sealed-secrets` or `external-secrets` if you want
   to safely commit secret *references* to Git for the GitOps flow in
   step 7).
6. **Alerting to somewhere you'll see it** — configure Alertmanager
   (already installed in step 6) to send to Discord/Slack/ntfy/email
   instead of sitting unread in-cluster.
7. **Image scanning** — `Trivy` (as a kubectl plugin or admission
   controller) to catch known CVEs in images before/as they deploy,
   especially relevant once GitOps is auto-deploying whatever lands in
   Git.
8. **Regular `kubeadm` and OS upgrades** — subscribe to the Kubernetes
   release notes; don't let the cluster drift more than 2-3 minor
   versions behind, upgrades get riskier the further behind you are.
9. **If you outgrow single-control-plane** — move to the 3-node HA layout
   (Appendix A) before you have workloads you can't afford to lose during
   a control-plane reboot.

---

## Appendix A: Going HA (3 control-plane nodes)

Same steps 1-4, with two changes:
- Point `CONTROL_PLANE_ENDPOINT` at a load balancer VIP (HAProxy +
  keepalived, or any reverse proxy in front of all three API servers on
  6443) instead of a single node's IP, *before* running `kubeadm init`.
- After step 2, run the **control-plane join command** (the one with
  `--certificate-key`, not the worker one) on the other two control-plane
  nodes, then continue to step 3/4 as normal.

## Appendix B: Automating node provisioning

If your nodes are VMs, look at **Cluster API (CAPI)** with a provider
matching your hypervisor (e.g. `cluster-api-provider-vsphere`, or
`CAPMOX` for Proxmox) to turn "provision a new worker" into a single
`kubectl apply` instead of manual OS installs. Out of scope for this plan
but worth it once you're doing this more than a couple of times.

## Appendix C: Upgrading the cluster

```bash
# On the control-plane node, one minor version at a time:
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.31.x-*
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.31.x
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.31.x-* kubectl=1.31.x-*
sudo systemctl restart kubelet
sudo apt-mark hold kubeadm kubelet kubectl
```

Then repeat `apt-get install kubeadm=... && kubeadm upgrade node` on each
worker. Always re-run an etcd backup (step 5) immediately before upgrading.
