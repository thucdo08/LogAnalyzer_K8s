# 🚀 LogAnalyzer K8s — Hướng dẫn triển khai từ đầu đến cuối

> **Dành cho**: Người chưa cấu hình bất kỳ thứ gì  
> **Thời gian ước tính**: 3–5 giờ (lần đầu)  
> **OS**: Ubuntu 22.04 (máy local hoặc EC2)

---

## 📁 Cấu trúc dự án

```
LogAnalyzer_K8s/
├── backend/              # Flask API (Python)
│   ├── Dockerfile        # Multi-stage build
│   └── app.py            # Có /health /ready /metrics
├── frontend/             # React/Vite UI
│   └── Dockerfile        # Multi-stage build
├── helm/loganalyzer/     # Helm Chart ứng dụng
│   ├── Chart.yaml
│   ├── values.yaml       # Cấu hình mặc định
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml          # Auto-scaling
│       ├── pdb.yaml          # Pod disruption budget
│       ├── networkpolicy.yaml # Zero-trust security
│       ├── rbac.yaml          # ServiceAccount + Role
│       ├── secret.yaml        # K8s Secrets
│       ├── servicemonitor.yaml # Prometheus scrape
│       ├── prometheusrule.yaml # Alert rules
│       └── grafana-dashboard.yaml
├── k8s/                  # Raw K8s manifests
│   ├── argocd/           # ArgoCD Applications
│   │   ├── app-infra-registry.yaml
│   │   └── appset-loganalyzer.yaml
│   ├── registry/         # Docker Registry nội bộ
│   │   ├── registry-core.yaml
│   │   ├── registry-ui.yaml
│   │   └── registry-ingress.yaml
│   └── monitoring/
│       └── prometheus-values.yaml
├── terraform/            # AWS Infrastructure
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── .github/workflows/
│   └── ci-cd.yml         # GitHub Actions CI/CD
└── Jenkinsfile           # Jenkins CI (self-hosted)
```

---

## PHẦN 1 — Cài đặt công cụ trên máy local (Windows/Ubuntu)

### 1.1 Cài AWS CLI

```bash
# Ubuntu
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Kiểm tra
aws --version
# aws-cli/2.x.x
```

### 1.2 Cài Terraform

```bash
# Ubuntu
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform -y

# Kiểm tra
terraform version
# Terraform v1.x.x
```

### 1.3 Cài kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Kiểm tra
kubectl version --client
```

### 1.4 Cài Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Kiểm tra
helm version
```

### 1.5 Cài Docker

```bash
# Ubuntu
sudo apt update
sudo apt install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Cho phép chạy Docker không cần sudo
sudo usermod -aG docker $USER
newgrp docker

# Kiểm tra
docker --version
```

---

## PHẦN 2 — Cấu hình AWS

### 2.1 Tạo IAM User (trong AWS Console)

1. Truy cập: https://console.aws.amazon.com → **IAM** → **Users** → **Create user**
2. Username: `loganalyzer-deploy`
3. **Permissions**: Chọn "Attach policies directly", thêm:
   - `AmazonEC2FullAccess`
   - `AmazonRDSFullAccess`
   - `AmazonECR_FullAccess` (hoặc `AmazonEC2ContainerRegistryFullAccess`)
   - `AmazonS3FullAccess`
   - `AmazonVPCFullAccess`
4. Sau khi tạo: **Security credentials** → **Create access key** → Download CSV

### 2.2 Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: AKIA... (từ CSV đã download)
# AWS Secret Access Key: ....
# Default region name: ap-southeast-1
# Default output format: json

# Kiểm tra
aws sts get-caller-identity
# Trả về AccountId của bạn → OK
```

### 2.3 Tạo EC2 Key Pair (SSH vào servers)

```bash
# Tạo key pair
aws ec2 create-key-pair \
  --key-name loganalyzer-key \
  --region ap-southeast-1 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/loganalyzer-key.pem

# Đặt quyền đúng
chmod 400 ~/.ssh/loganalyzer-key.pem

# Kiểm tra
aws ec2 describe-key-pairs --key-names loganalyzer-key --region ap-southeast-1
```

---

## PHẦN 3 — Deploy AWS Infrastructure với Terraform

### 3.1 Clone repository

```bash
git clone https://github.com/thucdo08/LogAnalyzer_K8s.git
cd LogAnalyzer_K8s
```

### 3.2 Tạo file biến (KHÔNG commit file này)

```bash
cat > terraform/terraform.tfvars << 'EOF'
region        = "ap-southeast-1"
project_name  = "loganalyzer"
environment   = "production"
key_pair_name = "loganalyzer-key"
db_password   = "YourStrongPassword123!"   # Replace with your actual password
my_ip_cidr    = "YOUR_PUBLIC_IP/32"    # Get your IP: curl ifconfig.me
EOF
```

> ⚠️ File `terraform.tfvars` đã được `.gitignore` — không lo bị commit lên Git.

### 3.3 Deploy Terraform

```bash
cd terraform/

# Khởi tạo (tải AWS provider)
terraform init

# Xem những gì sẽ được tạo (dry run)
terraform plan

# Tạo infrastructure (~8-12 phút, RDS mất lâu nhất)
terraform apply -auto-approve
```

Sau khi apply xong, Terraform in ra các outputs:
```
bastion_public_ip     = "54.179.23.15"
ecr_backend_url       = "573643652378.dkr.ecr.ap-southeast-1.amazonaws.com/loganalyzer-backend"
ecr_frontend_url      = "573643652378.dkr.ecr.ap-southeast-1.amazonaws.com/loganalyzer-frontend"
k8s_master_private_ip = "10.0.10.45"
k8s_worker_private_ips = ["10.0.10.50", "10.0.10.51"]
s3_log_archive_bucket = "loganalyzer-log-archive-573643652378"
```

> 📌 **Lưu ý:** Các giá trị trên chỉ in ra màn hình, **không tự lưu** vào biến. Cần chạy bước 3.4.

### 3.4 Lưu outputs vào file environment (chạy 1 lần duy nhất)

Script `terraform/scripts/save-outputs.sh` đọc toàn bộ outputs và lưu vào `~/loganalyzer.env`:

```bash
# Đứng ở thư mục gốc của project
cd ~/LogAnalyzer_K8s

# Chạy script — tự động đọc terraform outputs và lưu ra file
bash terraform/scripts/save-outputs.sh
```

Output của script:
```
✅ Saved to: /home/ubuntu/loganalyzer.env

Summary:
  Bastion IP : 54.179.23.15
  Master IP  : 10.0.10.45
  Worker IPs : 10.0.10.50 10.0.10.51
  ECR Backend: 573643652378.dkr.ecr.ap-southeast-1.amazonaws.com/loganalyzer-backend
  S3 Bucket  : loganalyzer-log-archive-573643652378
```

**Load biến vào terminal:**
```bash
# Mỗi lần mở terminal mới, chạy lệnh này:
source ~/loganalyzer.env

# Kiểm tra
echo $BASTION_IP    # → 54.179.23.15
echo $ECR_REGISTRY  # → 573643652378.dkr.ecr.ap-southeast-1.amazonaws.com

# Tự động load mỗi lần mở terminal (chỉ cần thêm 1 lần):
echo 'source ~/loganalyzer.env' >> ~/.bashrc
```

> 💡 File `~/loganalyzer.env` còn tạo sẵn các alias tiện dụng:
> - `ssh-master` → SSH thẳng vào K8s Master qua Bastion
> - `k` → shortcut cho `kubectl`
> - `kn` → shortcut cho `kubectl -n loganalyzer`

---
## PHẦN 4 — Cài đặt Kubernetes trên EC2

> 💻 **Môi trường:** Windows PowerShell. SSH dùng OpenSSH có sẵn từ Windows 10+.
> Trước tiên load biến môi trường: `. "$env:USERPROFILE\loganalyzer.env.ps1"`

### 4.1 SSH vào Master Node (từ Windows PowerShell)

```powershell
# Load biến (nếu chưa load)
. "$env:USERPROFILE\loganalyzer.env.ps1"

# Dùng alias đã tạo sẵn để SSH thẳng vào Master:
ssh-master
```

### 4.2 Kiểm tra trạng thái K8s trên Master

> 💡 **Tin vui:** Toàn bộ quá trình cài đặt Docker, kubelet, kubeadm và khởi tạo cluster (`kubeadm init`) **ĐÃ ĐƯỢC TERRAFORM TỰ ĐỘNG CHẠY** lúc tạo máy ảo. Bạn KHÔNG cần phải cài bằng tay!

> 🖥️ Các lệnh dưới chạy **bên trong SSH session trên EC2 master** (Linux bash)

```bash
# 1. Kiểm tra tiến trình cài đặt tự động (nhấn Ctrl+C để thoát)
sudo tail -f /var/log/k8s-init.log
# Chờ đến khi thấy dòng chữ: "Bootstrap finished — role: master"
```

```bash
# 2. Kiểm tra các nodes
kubectl get nodes
# NAME           STATUS   ROLES           AGE
# ip-10-0-10-83  Ready    control-plane   10m
```

*(Nếu node đang ở trạng thái `NotReady` hoặc `connection refused`, chỉ cần đợi thêm 1-2 phút để Calico và API server khởi động xong)*

```bash
# 3. Xem nội dung file join-command đã được tạo tự động
cat /home/ubuntu/join-command.sh
# Mẫu: kubeadm join 10.0.10.83:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx
# Hãy bôi đen copy dòng lệnh trên để dùng cho bước 4.3
```

### 4.3 Join Worker Nodes (từ Windows PowerShell)

```powershell
# Lấy join command từ master
ssh-master "cat /home/ubuntu/join-command.sh"
# Copy output lại (dạng: kubeadm join 10.0.10.83:6443 --token ... --discovery-token-ca-cert-hash sha256:...)
```

```powershell
# SSH vào từng worker và chạy join command
ssh -J ubuntu@$env:BASTION_IP ubuntu@10.0.10.116 -i $env:SSH_KEY
```

```bash
# Chạy bên trong SSH session trên worker (Linux bash)
# Bước 1: Load modules (tương tự master)
sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.ipv4.ip_forward=1

# Bước 2: Paste join command lấy từ master
sudo kubeadm join 10.0.10.83:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --ignore-preflight-errors=NumCPU,Mem
```

```powershell
# Sau khi join cả 2 workers, kiểm tra từ master:
ssh-master "kubectl get nodes"
# NAME     STATUS   ROLES           AGE
# master   Ready    control-plane   10m
# node-0   Ready    <none>          2m
# node-1   Ready    <none>          1m

### 4.4 Cài local-path-provisioner (cần cho PVC của Registry)

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Đặt làm default StorageClass
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 4.5 Cài NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml

# Đợi ingress controller Ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Lấy NodePort của ingress (dùng để cấu hình Cloudflare Tunnel)
kubectl get svc -n ingress-nginx
# ingress-nginx-controller   NodePort   10.x.x.x   <none>   80:3xxxx/TCP,443:3xxxx/TCP
```

---

## PHẦN 5 — Copy kubeconfig về máy Windows

```powershell
# Chạy trên Windows PowerShell (không phải bên trong SSH)
. "$env:USERPROFILE\loganalyzer.env.ps1"

# Tạo thư mục .kube nếu chưa có
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.kube"

# Copy kubeconfig từ master về Windows qua Bastion
scp -J ubuntu@$env:BASTION_IP `
    -i $env:SSH_KEY `
    ubuntu@${env:MASTER_IP}:~/.kube/config `
    "$env:USERPROFILE\.kube\loganalyzer-config"
```

```powershell
# Set KUBECONFIG để kubectl dùng file này
$env:KUBECONFIG = "$env:USERPROFILE\.kube\loganalyzer-config"

# Thêm vào env file để auto-load:
Add-Content "$env:USERPROFILE\loganalyzer.env.ps1" "`n`$env:KUBECONFIG = '$env:USERPROFILE\.kube\loganalyzer-config'"

# Kiểm tra từ máy Windows
kubectl get nodes
# NAME     STATUS   ROLES           AGE
# master   Ready    control-plane   10m
# node-0   Ready    <none>          5m
# node-1   Ready    <none>          4m
```

---

## PHẦN 6 — Cài ArgoCD

```bash
# Tạo namespace
kubectl create namespace argocd

# Cài ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Đợi ArgoCD pods ready (~3 phút)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Lấy password mặc định của admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward để truy cập UI (tạm thời)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Mở browser: https://localhost:8080
# Login: admin / <password ở trên>
```

### 6.1 Cài ArgoCD Image Updater

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

---

## PHẦN 7 — Cài Prometheus + Grafana

```bash
# Thêm Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Cài kube-prometheus-stack với custom values
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f k8s/monitoring/prometheus-values.yaml

# Đợi pods ready
kubectl get pods -n monitoring -w

# Kiểm tra
kubectl get svc -n monitoring
```

---

## PHẦN 8 — Build & Push Docker Images lên AWS ECR

```bash
# Đứng ở thư mục gốc của project
cd LogAnalyzer_K8s/

# Đăng nhập ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Lấy short SHA của commit hiện tại
IMAGE_TAG=$(git rev-parse --short HEAD)
echo "Building tag: $IMAGE_TAG"

# Build Backend
docker build \
  -t ${ECR_BACKEND}:${IMAGE_TAG} \
  -t ${ECR_BACKEND}:latest \
  ./backend

# Build Frontend
docker build \
  -t ${ECR_FRONTEND}:${IMAGE_TAG} \
  -t ${ECR_FRONTEND}:latest \
  ./frontend

# Push lên ECR
docker push ${ECR_BACKEND}:${IMAGE_TAG}
docker push ${ECR_BACKEND}:latest
docker push ${ECR_FRONTEND}:${IMAGE_TAG}
docker push ${ECR_FRONTEND}:latest

echo "✅ Images pushed:"
echo "   ${ECR_BACKEND}:${IMAGE_TAG}"
echo "   ${ECR_FRONTEND}:${IMAGE_TAG}"
```

---

## PHẦN 9 — Cập nhật Helm values với ECR URL

```bash
# Cập nhật values.yaml với ECR URL thực tế
sed -i "s|repository: jfrog.dofuta.site/loganalyzer-backend|repository: ${ECR_BACKEND}|g" \
  helm/loganalyzer/values.yaml

sed -i "s|repository: jfrog.dofuta.site/loganalyzer-frontend|repository: ${ECR_FRONTEND}|g" \
  helm/loganalyzer/values.yaml

sed -i "s|registry: jfrog.dofuta.site|registry: ${ECR_REGISTRY}|g" \
  helm/loganalyzer/values.yaml

# Cập nhật image tag
sed -i "s/tag: \"latest\"/tag: \"${IMAGE_TAG}\"/g" helm/loganalyzer/values.yaml

# Commit thay đổi
git add helm/loganalyzer/values.yaml
git commit -m "chore: update ECR registry URLs and image tag ${IMAGE_TAG}"
git push origin main

# Kiểm tra values.yaml
grep -A3 "image:" helm/loganalyzer/values.yaml
```

---

## PHẦN 10 — Deploy LogAnalyzer qua ArgoCD

### 10.1 Tạo K8s Secret để ArgoCD pull từ ECR

```bash
# Tạo IAM credentials cho K8s pull từ ECR
kubectl create secret docker-registry ecr-secret \
  --docker-server=${ECR_REGISTRY} \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-southeast-1) \
  --namespace loganalyzer

# Lặp lại tạo secret ở namespace argocd (cho ArgoCD Image Updater)
kubectl create secret docker-registry ecr-secret \
  --docker-server=${ECR_REGISTRY} \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-southeast-1) \
  --namespace argocd
```

### 10.2 Deploy ArgoCD Applications

```bash
# Deploy ArgoCD ApplicationSet (tự động tạo Application cho LogAnalyzer)
kubectl apply -f k8s/argocd/appset-loganalyzer.yaml

# Deploy infra Application (theo dõi registry)
kubectl apply -f k8s/argocd/app-infra-registry.yaml

# Kiểm tra Applications
kubectl get application -n argocd
# NAME                     SYNC STATUS   HEALTH STATUS
# loganalyzer-production   Synced        Healthy
```

### 10.3 Cài LogAnalyzer bằng Helm (manual - lần đầu)

```bash
# Cài lần đầu với secret values
helm upgrade --install loganalyzer ./helm/loganalyzer \
  --namespace loganalyzer \
  --create-namespace \
  --set secrets.openaiKey="${OPENAI_API_KEY}" \
  --set secrets.mongodbUri="${MONGODB_URI}" \
  --set backend.image.tag="${IMAGE_TAG}" \
  --set frontend.image.tag="${IMAGE_TAG}" \
  --wait

# Kiểm tra pods
kubectl get pods -n loganalyzer
# NAME                                    READY   STATUS    RESTARTS
# loganalyzer-backend-xxx                 1/1     Running   0
# loganalyzer-frontend-xxx                1/1     Running   0
```

---

## PHẦN 11 — Cấu hình GitHub Actions CI/CD

### 11.1 Tạo IAM User riêng cho CI/CD

```bash
# Tạo IAM user chỉ có quyền push ECR
aws iam create-user --user-name loganalyzer-github-actions

# Attach policy ECR
aws iam attach-user-policy \
  --user-name loganalyzer-github-actions \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# Tạo access key
aws iam create-access-key --user-name loganalyzer-github-actions
# Lưu lại AccessKeyId và SecretAccessKey
```

### 11.2 Thêm Secrets vào GitHub Repository

1. Mở: `github.com/thucdo08/LogAnalyzer_K8s` → **Settings** → **Secrets and variables** → **Actions**
2. Thêm các secrets sau (click **New repository secret**):

| Secret Name | Giá trị |
|---|---|
| `AWS_ACCESS_KEY_ID` | AccessKeyId từ bước trên |
| `AWS_SECRET_ACCESS_KEY` | SecretAccessKey từ bước trên |
| `AWS_REGION` | `ap-southeast-1` |
| `ECR_REGISTRY` | `<account_id>.dkr.ecr.ap-southeast-1.amazonaws.com` |
| `GIT_TOKEN` | GitHub Personal Access Token (Settings → Developer settings → PAT) |

### 11.3 Tạo GitHub Personal Access Token (PAT)

1. GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token** → chọn scope: `repo` (full control)
3. Copy token → dán vào secret `GIT_TOKEN`

### 11.4 Test GitHub Actions

```bash
# Push bất kỳ thay đổi nào vào main để trigger pipeline
echo "# trigger ci" >> README.md
git add README.md
git commit -m "ci: trigger first GitHub Actions run"
git push origin main

# Xem workflow tại: github.com/thucdo08/LogAnalyzer_K8s/actions
```

---

## PHẦN 12 — Kiểm tra toàn bộ hệ thống

```bash
# === Kiểm tra K8s Cluster ===
kubectl get nodes
kubectl get pods --all-namespaces

# === Kiểm tra LogAnalyzer ===
kubectl get pods -n loganalyzer
kubectl get hpa -n loganalyzer          # HPA status
kubectl get networkpolicy -n loganalyzer # NetworkPolicy
kubectl get servicemonitor -n loganalyzer # Prometheus target

# === Kiểm tra Health Endpoints ===
# Port-forward backend để test local
kubectl port-forward svc/loganalyzer-backend 8000:8000 -n loganalyzer &

curl http://localhost:8000/health
# {"status":"ok","service":"loganalyzer-backend","uptime_seconds":120.5}

curl http://localhost:8000/ready
# {"status":"ready","checks":{"rules_config":"ok","baselines_dir":"ok"}}

curl http://localhost:8000/metrics
# # HELP loganalyzer_uptime_seconds ...
# loganalyzer_uptime_seconds 120.5

# === Kiểm tra ArgoCD ===
kubectl get application -n argocd
kubectl get applicationset -n argocd

# === Kiểm tra Prometheus ===
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
# Mở: http://localhost:9090
# Vào Status → Targets → tìm loganalyzer-backend

# === Kiểm tra Grafana ===
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring &
# Mở: http://localhost:3000
# Login: admin / LogAnalyzer@SRE2025
# Dashboards → tìm "LogAnalyzer Security Platform"
```

---

## PHẦN 13 — Test GitOps Flow (Demo)

```bash
# Mô phỏng luồng GitOps hoàn chỉnh:

# 1. Sửa code (ví dụ thêm version endpoint)
echo '# version bump' >> backend/app.py
git add backend/app.py
git commit -m "feat: add version info"
git push origin main

# 2. GitHub Actions tự chạy (xem tại /actions):
#    - Test pytest
#    - Build Docker image mới (multi-stage)
#    - Push lên ECR với tag mới
#    - Cập nhật values.yaml → commit [skip ci]

# 3. ArgoCD phát hiện values.yaml thay đổi (~30 giây)
kubectl get pods -n loganalyzer -w
# Thấy pod mới được tạo → pod cũ bị xóa (RollingUpdate)

# 4. Kiểm tra ArgoCD sync
kubectl -n argocd get app loganalyzer-production
```

---

## PHẦN 14 — Test HPA (Auto-scaling Demo)

```bash
# Mô phỏng tải cao để trigger HPA scale up:
kubectl run load-test --image=busybox --restart=Never -n loganalyzer -- \
  sh -c "while true; do wget -q -O- http://loganalyzer-backend:8000/health; done"

# Theo dõi HPA scale
kubectl get hpa -n loganalyzer -w
# NAME                       MINPODS   MAXPODS   REPLICAS   CPU
# loganalyzer-backend-hpa    1         5         1          0%
# loganalyzer-backend-hpa    1         5         2          85%  ← scale up!

# Xóa load test sau khi demo
kubectl delete pod load-test -n loganalyzer
```

---

## 🔧 Troubleshooting phổ biến

### Pod không start được (ImagePullBackOff)
```bash
kubectl describe pod <pod-name> -n loganalyzer
# Nếu lỗi ECR auth:
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}
# Recreate secret:
kubectl delete secret ecr-secret -n loganalyzer
kubectl create secret docker-registry ecr-secret \
  --docker-server=${ECR_REGISTRY} --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-southeast-1) \
  --namespace loganalyzer
```

### HPA không scale (metric not available)
```bash
# Cài metrics-server (cần thiết cho HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get apiservice v1beta1.metrics.k8s.io
```

### ArgoCD không sync
```bash
kubectl -n argocd logs deployment/argocd-application-controller | tail -50
# Manual sync:
kubectl -n argocd patch app loganalyzer-production \
  -p '{"operation":{"sync":{}}}' --type merge
```

### NetworkPolicy block traffic nhầm
```bash
# Tạm disable NetworkPolicy để debug
kubectl delete networkpolicy default-deny-all -n loganalyzer
# Test xong enable lại
kubectl apply -f helm/loganalyzer/templates/networkpolicy.yaml
```

---

## 💡 Câu trả lời phỏng vấn ShopBack

> "Em đã tự xây K8s cluster trên AWS EC2 (ap-southeast-1 — gần ShopBack) bằng Terraform, sau đó deploy LogAnalyzer với đầy đủ production standards: GitOps qua ArgoCD với self-healing và auto-sync, HPA để tự scale khi lượng log tăng đột biến từ 1 lên 5 pods, NetworkPolicy theo mô hình zero-trust phù hợp với chuyên ngành ATTT của em, và Prometheus/Grafana để theo dõi error rate cùng latency real-time. CI/CD chạy trên cả Jenkins self-hosted và GitHub Actions để push images lên AWS ECR."
