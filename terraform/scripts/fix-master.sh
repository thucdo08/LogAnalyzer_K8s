#!/bin/bash
set -e

echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

echo "Resetting K8s..."
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d

echo "Initalizing K8s..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address="$PRIVATE_IP" --ignore-preflight-errors=NumCPU,Mem

echo "Configuring kubectl..."
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Applying Calico..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

echo "Creating join command..."
sudo kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
sudo chown ubuntu:ubuntu /home/ubuntu/join-command.sh

echo "Done!"
