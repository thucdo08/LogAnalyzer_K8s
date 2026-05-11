#!/bin/bash
# =============================================================
# K8s Node Init Script — chạy khi EC2 khởi động lần đầu
# Tham số: role = "master" | "worker"
# =============================================================
set -euo pipefail
ROLE="${role}"    # Injected bởi Terraform templatefile()

LOG="/var/log/k8s-init.log"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date)] Starting K8s init for role: $ROLE"

# =============================================================
# Phần 1: Cài đặt chung (chạy trên cả master và worker)
# =============================================================

# Tắt swap (bắt buộc với K8s)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Kernel modules cần thiết
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Sysctl settings
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Cài Docker
apt-get update -qq
apt-get install -y -qq docker.io curl apt-transport-https ca-certificates gnupg
systemctl enable --now docker

# Cài kubeadm, kubelet, kubectl v1.29
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "[$(date)] Base packages installed. Role: $ROLE"

# =============================================================
# Phần 2: Master-only setup
# =============================================================
if [ "$ROLE" = "master" ]; then
  # Lấy private IP của instance này
  PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

  # Init cluster
  kubeadm init \
    --pod-network-cidr=192.168.0.0/16 \
    --apiserver-advertise-address="$PRIVATE_IP" \
    --ignore-preflight-errors=NumCPU \
    >> "$LOG" 2>&1

  # Setup kubectl cho root
  mkdir -p /root/.kube
  cp /etc/kubernetes/admin.conf /root/.kube/config

  # Setup kubectl cho user ubuntu
  mkdir -p /home/ubuntu/.kube
  cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
  chown ubuntu:ubuntu /home/ubuntu/.kube/config

  # Cài Calico CNI
  kubectl --kubeconfig=/root/.kube/config apply \
    -f https://docs.projectcalico.org/manifests/calico.yaml

  # Lưu join command để worker dùng sau
  kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
  chmod 600 /home/ubuntu/join-command.sh
  chown ubuntu:ubuntu /home/ubuntu/join-command.sh

  echo "[$(date)] Master init DONE. Join command saved to /home/ubuntu/join-command.sh"
fi

echo "[$(date)] K8s init script completed for role: $ROLE"
