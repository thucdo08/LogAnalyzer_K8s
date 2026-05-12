## 🏗️ Lab: Production-grade LogAnalyzer trên Kubernetes HA Cluster

### Mô tả
Triển khai hệ thống phân tích log bảo mật (LogAnalyzer) lên Kubernetes, áp dụng đầy đủ các tiêu chuẩn SRE: GitOps, Auto-scaling, Zero-trust Security, Monitoring, và CI/CD với AWS.

### Kiến trúc tổng thể
```
Internet
    │
[Cloudflare Tunnel Zero Trust]
    │
[HAProxy Load Balancer]  ←── AWS EC2 (t3.small, Public Subnet)
    │
[NGINX Ingress Controller]  ←── K8s NodePort
    │
    ├──→ [Frontend Pod] (React/Vite + Nginx Alpine)
    │           │
    │     [NetworkPolicy: allow-frontend-to-backend]
    │           │
    └──→ [Backend Pod] (Flask + Python 3.10)
                │
        ┌───────┼────────────┐
        │       │            │
   [MongoDB  [OpenAI    [RDS Postgres]
    Atlas]    API]      (AWS, metadata)
```

### Hạ tầng AWS (Terraform IaC)
| Resource | Spec | Purpose |
|---|---|---|
| VPC | 10.0.0.0/16, ap-southeast-1 | Isolated network |
| EC2 Master | t3.medium | K8s Control Plane |
| EC2 Workers | t3.small × 2 | Run LogAnalyzer pods |
| RDS Postgres | db.t3.micro, encrypted | Metadata storage |
| ECR | 2 repos, scan-on-push | Container registry |
| S3 | Lifecycle: 30d→IA→90d→Glacier | Log archive cold storage |

### Công nghệ sử dụng
| Thành phần | Công nghệ |
|---|---|
| Container Build | Docker Multi-stage (non-root user) |
| Container Registry | AWS ECR (private, scan-on-push) |
| GitOps Controller | ArgoCD (ApplicationSet, self-heal, prune) |
| CI/CD | Jenkins (self-hosted) + GitHub Actions (cloud) |
| Package Manager | Helm v3 |
| Ingress | NGINX Ingress Controller |
| DNS/Access | Cloudflare Tunnel Zero Trust |
| IaC | Terraform (AWS ap-southeast-1) |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) |
| Alerting | PrometheusRule (5 alert rules) |
| Security | NetworkPolicy (zero-trust) + RBAC + K8s Secrets |

### Luồng CI/CD GitOps
```
Developer push code
        │
   [GitHub Actions]
        │
   ├── Job: pytest (backend tests)
   ├── Job: docker build (multi-stage) → push AWS ECR
   ├── Job: Trivy scan (CVE detection)
   └── Job: update values.yaml (image tag) → git commit
                │
           [ArgoCD]  ←── Detect values.yaml changed
                │
        Rolling Update K8s pods (zero-downtime)
```

### SRE Features đã triển khai
- ✅ **Reliability**: Liveness + Readiness + Startup Probes
- ✅ **Scalability**: HPA (backend 1→5 pods, frontend 1→3 pods) theo CPU/RAM
- ✅ **High Availability**: PodDisruptionBudget (minAvailable=1), podAntiAffinity
- ✅ **Zero-downtime**: RollingUpdate (maxUnavailable=0, maxSurge=1)
- ✅ **Security**: NetworkPolicy (default-deny-all, 4 allow rules), RBAC, non-root containers
- ✅ **Observability**: /health /ready /metrics endpoints, ServiceMonitor, Grafana dashboard (8 panels)
- ✅ **GitOps**: ArgoCD auto-sync, self-heal, prune — Git là source of truth duy nhất
- ✅ **IaC**: Terraform AWS (VPC, EC2, RDS, ECR, S3) — toàn bộ infra dạng code

### Kết quả & Demo
- 🌐 ArgoCD UI: https://argocd.dofuta.site
- 🌐 Docker Registry UI: https://jfrog.dofuta.site
- 🌐 App: https://loganalyzer.dofuta.site
- ✅ Auto-deploy khi push code lên GitHub (ArgoCD detect trong ~30s)
- ✅ Self-healing: ArgoCD tự khôi phục resource bị xóa tay
- ✅ Scale test: backend tự scale 1→3 pods khi simulate log spike

### Nói trong phỏng vấn ShopBack
> "Em đã triển khai LogAnalyzer — hệ thống phân tích log bảo mật — lên K8s cluster tự xây trên AWS EC2, dùng Terraform để provision hạ tầng. Em áp dụng GitOps với ArgoCD để tự động hóa deployment, cấu hình HPA để hệ thống tự scale khi lượng log tăng đột biến, và thiết lập NetworkPolicy theo mô hình zero-trust — phù hợp với chuyên ngành An toàn thông tin của em. Prometheus + Grafana dashboard cho phép team vận hành theo dõi error rate và latency real-time."
