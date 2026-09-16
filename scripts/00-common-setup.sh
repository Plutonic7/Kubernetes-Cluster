#!/usr/bin/env bash
# Run this on EVERY node (control-plane and worker) before anything else.
# Target OS: Ubuntu 22.04 / 24.04 LTS. Run as root (sudo -i) or with sudo.
set -euo pipefail

KUBE_VERSION="${KUBE_VERSION:-1.30}"   # kubeadm/kubelet/kubectl minor version to pin

echo "==> Disabling swap"
swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

echo "==> Loading required kernel modules"
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "==> Setting required sysctls"
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "==> Installing containerd"
apt-get update
apt-get install -y ca-certificates curl gnupg apt-transport-https

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y containerd.io

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
# Required so kubelet's cgroup driver matches containerd's
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "==> Installing kubeadm, kubelet, kubectl (v${KUBE_VERSION})"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key" | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "==> Enabling kubelet"
systemctl enable --now kubelet

echo "==> Basic firewall notes (adjust for your setup):"
echo "    Control-plane: 6443/tcp 2379-2380/tcp 10250-10252/tcp"
echo "    Workers:       10250/tcp 30000-32767/tcp"

echo "==> Done. Node is ready for kubeadm init/join."
