# Terraform — AWS Infrastructure for LogAnalyzer K8s

Provision toàn bộ hạ tầng AWS cần thiết để chạy LogAnalyzer trên Kubernetes, theo tiêu chuẩn SRE thực tế.

## Kiến trúc được tạo

```
ap-southeast-1 (Singapore)
└── VPC (10.0.0.0/16)
    ├── Public Subnet (10.0.1.0/24)
    │   ├── Bastion Host (t3.micro) — SSH jump server
    │   └── Internet Gateway → Route Table
    ├── Private Subnet 1 (10.0.10.0/24)
    │   ├── K8s Master (t3.medium)
    │   ├── K8s Worker 1 (t3.small)
    │   └── K8s Worker 2 (t3.small)
    └── Private Subnet 2 (10.0.11.0/24)
        └── RDS PostgreSQL (db.t3.micro, encrypted)

ECR: loganalyzer-backend + loganalyzer-frontend
S3: log-archive (lifecycle: 30d→IA, 90d→Glacier, 365d→delete)
```

## Prerequisites

```bash
# Cài Terraform >= 1.5.0
terraform -v

# Cấu hình AWS credentials
aws configure
# Region: ap-southeast-1
# Access Key: (IAM user của bạn)

# Tạo EC2 Key Pair trong AWS Console trước
# EC2 → Key Pairs → Create key pair → loganalyzer-key
```

## Deploy

```bash
cd terraform/

# 1. Initialize (tải AWS provider)
terraform init

# 2. Xem plan (không thay đổi gì)
terraform plan -var="db_password=YourPass123!"

# 3. Apply (tạo resources — ~5 phút)
terraform apply -var="db_password=YourPass123!" -auto-approve

# 4. Lấy outputs
terraform output
terraform output -raw rds_endpoint    # Connection string
terraform output -raw ecr_backend_url # ECR URL để update values.yaml
```

## Chi phí ước tính (On-demand, ap-southeast-1)

| Resource | Type | Cost/month |
|---|---|---|
| EC2 Master | t3.medium | ~$30 |
| EC2 Worker × 2 | t3.small × 2 | ~$30 |
| EC2 Bastion | t3.micro | ~$8 |
| RDS Postgres | db.t3.micro | ~$15 |
| ECR | Storage | ~$1 |
| S3 | Minimal | ~$1 |
| **Tổng** | | **~$85/tháng** |

> **Tip**: Stop EC2 instances khi không dùng để tiết kiệm. RDS cũng có thể stop tạm.

## Sau khi `terraform apply`

```bash
# SSH vào master qua bastion
ssh -J ubuntu@<BASTION_IP> ubuntu@<MASTER_PRIVATE_IP>

# Trên master: init K8s cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Cài Calico CNI
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Cài ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply LogAnalyzer GitOps config
kubectl apply -f argocd/appset-loganalyzer.yaml
```

## Cleanup

```bash
# Xóa toàn bộ resources (tránh tốn tiền)
terraform destroy -var="db_password=YourPass123!" -auto-approve
```
