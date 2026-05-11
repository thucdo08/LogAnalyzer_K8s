#!/bin/bash
# K8s node bootstrap script — runs on first EC2 boot via user-data
# Installs Docker + kubeadm v1.29. Masters also run kubeadm init.
# Role is injected by Terraform templatefile(): "master" | "worker"

set -euo pipefail
ROLE="${role}"

LOG="/var/log/k8s-init.log"
exec > >(tee -a "$LOG") 2>&1
echo "[$(date)] Starting K8s bootstrap — role: $ROLE"

# Disable swap (required by K8s)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Sysctl settings for K8s networking
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Install Docker
apt-get update -qq
apt-get install -y -qq docker.io curl apt-transport-https ca-certificates gnupg
systemctl enable --now docker

# Install kubeadm, kubelet, kubectl v1.29
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "[$(date)] Base packages installed."

# Master-only: initialise cluster
if [ "$ROLE" = "master" ]; then
  PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

  kubeadm init \
    --pod-network-cidr=192.168.0.0/16 \
    --apiserver-advertise-address="$PRIVATE_IP" \
    --ignore-preflight-errors=NumCPU >> "$LOG" 2>&1

  # Configure kubectl for root and ubuntu users
  mkdir -p /root/.kube
  cp /etc/kubernetes/admin.conf /root/.kube/config

  mkdir -p /home/ubuntu/.kube
  cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
  chown ubuntu:ubuntu /home/ubuntu/.kube/config

  # Install Calico CNI
  kubectl --kubeconfig=/root/.kube/config apply \
    -f https://docs.projectcalico.org/manifests/calico.yaml

  # Save join command for workers
  kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
  chmod 600 /home/ubuntu/join-command.sh
  chown ubuntu:ubuntu /home/ubuntu/join-command.sh

  echo "[$(date)] Master init complete. Join command: /home/ubuntu/join-command.sh"
fi

echo "[$(date)] Bootstrap finished — role: $ROLE"
