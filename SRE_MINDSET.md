# SRE Mindset — From Problem to Production

> Tài liệu này mô phỏng cách một SRE thực thụ **tư duy và ra quyết định**  
> khi nhận một ứng dụng và đưa nó lên production.  
> Đọc xong bạn sẽ hiểu **tại sao** chọn từng công cụ, không chỉ **cách dùng**.

---

## 1. SRE Là Gì? (Góc Nhìn Thực Tế)

SRE (Site Reliability Engineering) là ngành kỹ thuật đảm bảo hệ thống:
- **Luôn chạy** (Reliability) — uptime 99.9%+ không phải may rủi
- **Tự phục hồi** (Self-healing) — khi có lỗi, hệ thống tự xử lý trước khi người dùng nhận ra
- **Tự mở rộng** (Auto-scaling) — tải tăng gấp 10 lần không cần can thiệp thủ công
- **Minh bạch** (Observability) — mọi thứ xảy ra bên trong đều được ghi lại và theo dõi

SRE **không phải** sysadmin restart server. SRE là người **thiết kế hệ thống** sao cho ít phải restart nhất có thể.

---

## 2. Bài Toán Ban Đầu

### Ứng dụng LogAnalyzer làm gì?

LogAnalyzer là hệ thống phân tích log bảo mật:
1. User upload file log (Apache, Nginx, SSH, Syslog...)
2. Backend (Flask/Python) parse và phân tích bằng ML + GenAI (OpenAI)
3. Trả về báo cáo: IP đáng ngờ, pattern tấn công, mức độ nghiêm trọng
4. Frontend (React) hiển thị kết quả dưới dạng dashboard

### Vấn đề khi chạy bình thường (trước SRE)

```
Developer laptop
      │
   python app.py
      │
   Chạy tốt!
   ... cho đến khi:
   - Tắt máy → app chết
   - RAM đầy → app treo
   - Nhiều người dùng cùng lúc → app lag
   - Deploy version mới → downtime
   - Ai biết lỗi xảy ra lúc 3am?
```

### Câu hỏi SRE đặt ra

| Câu hỏi | Tầm quan trọng |
|---|---|
| App chết thì tự restart không? | Critical |
| Tải tăng đột ngột thì làm gì? | High |
| Deploy version mới có downtime không? | High |
| Lỗi xảy ra lúc 3am ai biết? | High |
| Ai thay đổi gì trên server lúc nào? | Medium |
| Infra tạo bằng tay hay bằng code? | Medium |

---

## 3. Lên Ý Tưởng Giải Pháp

### Bước 1: Xác định "Pain Points"

```
Pain Point              → Giải pháp SRE
─────────────────────────────────────────────────────
App chết không tự restart → Container + K8s restart policy
Deploy thủ công           → CI/CD Pipeline tự động
Config lẫn lộn giữa dev/prod → Helm values per environment
Không biết app đang làm gì → Prometheus metrics + Grafana
Alert lúc 3am             → PrometheusRule → AlertManager
Infra tạo tay dễ sai       → Terraform (Infrastructure as Code)
"Tôi sửa gì đó trên server" → GitOps: Git là source of truth duy nhất
```

### Bước 2: Chọn Kiến Trúc

Một SRE luôn nghĩ theo **tầng (layers)**:

```
┌─────────────────────────────────────────────────────┐
│  LAYER 5: OBSERVABILITY                             │
│  Prometheus scrape metrics → Grafana dashboard      │
│  AlertManager → Slack/Email khi có vấn đề           │
├─────────────────────────────────────────────────────┤
│  LAYER 4: CI/CD & GITOPS                            │
│  GitHub push → Actions build image → ArgoCD deploy  │
│  Git commit = deployment trigger                    │
├─────────────────────────────────────────────────────┤
│  LAYER 3: APPLICATION RUNTIME                       │
│  Kubernetes: scheduling, scaling, self-healing      │
│  Helm: package manager cho K8s manifests            │
├─────────────────────────────────────────────────────┤
│  LAYER 2: CONTAINER                                 │
│  Docker: đóng gói app + dependencies thành 1 unit   │
│  ECR: lưu trữ images an toàn                        │
├─────────────────────────────────────────────────────┤
│  LAYER 1: INFRASTRUCTURE                            │
│  Terraform: VPC, EC2, RDS, ECR trên AWS             │
│  Mọi thứ là code, reproducible 100%                 │
└─────────────────────────────────────────────────────┘
```

---

## 4. Lựa Chọn Công Cụ — Tại Sao?

### 4.1 Docker — Tại sao containerize?

**Vấn đề trước Docker:**
```bash
# Developer A
pip install flask==2.0
python app.py  # Works!

# Server production
pip install flask==2.3  # Version khác!
python app.py  # ImportError!
```

**Sau Docker:**
```
Image = app + Python 3.10 + flask==2.0 + mọi dependency
     = chạy giống nhau ở MỌI NƠI
     = "Works on my machine" không còn là vấn đề
```

**Tại sao multi-stage build?**
```dockerfile
# Stage 1: Builder (có pip, gcc, build tools — ~500MB)
FROM python:3.10 AS builder
RUN pip install -r requirements.txt

# Stage 2: Runtime (chỉ có app + libs — ~120MB)
FROM python:3.10-slim
COPY --from=builder /usr/local/lib/python3.10/site-packages ./
```
→ Image nhỏ hơn 4x = pull nhanh hơn = deploy nhanh hơn

### 4.2 Kubernetes — Tại sao không dùng Docker Compose?

Docker Compose tốt cho development. Nhưng production cần:

| Tính năng | Docker Compose | Kubernetes |
|---|---|---|
| Container chết tự restart | ❌ Phải cấu hình thêm | ✅ Tự động |
| Scale lên 5 instances | ❌ Thủ công | ✅ `kubectl scale` hoặc HPA |
| Rolling update không downtime | ❌ Không hỗ trợ | ✅ Built-in |
| Health check thông minh | ❌ Cơ bản | ✅ liveness/readiness/startup probes |
| Resource limits | ❌ Không có | ✅ CPU/Memory limits |
| Secrets management | ❌ `.env` file | ✅ K8s Secrets encrypted |
| Network isolation | ❌ Không có | ✅ NetworkPolicy |

### 4.3 Helm — Tại sao không dùng raw YAML?

Raw K8s YAML có vấn đề:
```yaml
# deployment-dev.yaml
image: loganalyzer-backend:dev
replicas: 1
memory: "256Mi"

# deployment-prod.yaml  (copy paste, dễ sai)
image: loganalyzer-backend:prod
replicas: 3
memory: "512Mi"
```

Với Helm:
```yaml
# values.yaml — thay đổi theo environment
replicaCount: {{ .Values.replicaCount }}
image:
  tag: {{ .Values.backend.image.tag }}
```
```bash
# Deploy dev
helm upgrade loganalyzer . -f values-dev.yaml

# Deploy prod
helm upgrade loganalyzer . -f values-prod.yaml
```
→ **1 template, nhiều environment** — không bao giờ copy-paste YAML

### 4.4 ArgoCD — Tại sao GitOps?

**Vấn đề của CI/CD truyền thống:**
```
Developer push code
→ Jenkins build image
→ Jenkins SSH vào server
→ Jenkins chạy kubectl apply
→ ??? Ai biết server đang ở trạng thái gì?
→ "Hôm qua tôi sửa gì đó trực tiếp trên cluster..."
```

**GitOps với ArgoCD:**
```
Git repository = Source of truth duy nhất
Không ai được sửa cluster trực tiếp
ArgoCD liên tục so sánh Git ↔ Cluster
Nếu khác nhau → ArgoCD tự sync về Git state
```

```
Hệ quả:
✅ Muốn rollback → git revert → ArgoCD tự làm
✅ Ai sửa gì lúc nào → xem git log
✅ Cluster bị xóa → apply lại từ Git trong 5 phút
✅ Self-healing: ai sửa tay trên cluster → ArgoCD reset lại
```

### 4.5 Prometheus + Grafana — Tại sao cần monitoring?

**Không có monitoring:**
```
User: "App của anh hỏng rồi!"
SRE:  "Ủa hỏng từ lúc nào?"
User: "Từ tối qua"
SRE:  "..."  ← Không có dữ liệu để debug
```

**Có Prometheus + Grafana:**
```
22:34 — Error rate tăng từ 0.1% lên 15%
22:35 — CPU của backend pod tăng lên 95%
22:35 — Alert "HighErrorRate" gửi vào Slack
22:36 — SRE nhận alert, xem Grafana, thấy memory leak
22:40 — Rolling restart → vấn đề giải quyết
Total downtime: 6 phút, user hầu như không biết
```

### 4.6 Terraform — Tại sao IaC?

Bạn đã hiểu phần này. Tóm lại:
- **Reproducible**: tạo lại infra giống hệt từ code
- **Reviewable**: infra changes qua Pull Request
- **Auditable**: git log biết ai thay đổi gì
- **Destroyable**: `terraform destroy` xóa sạch, không tốn tiền

---

## 5. Kiến Trúc Tổng Quan

```
                        INTERNET
                            │
                    [Cloudflare Tunnel]
                    (Zero-trust, no open ports)
                            │
                   [NGINX Ingress Controller]
                   (K8s, routes traffic to pods)
                      │           │
              [Frontend Pod]  [Backend Pod]
              (React/Nginx)   (Flask/Python)
                                  │
                    ┌─────────────┼────────────┐
                    │             │            │
              [MongoDB Atlas] [OpenAI API] [RDS Postgres]
              (log storage)  (AI analysis) (metadata)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INFRASTRUCTURE LAYER (AWS ap-southeast-1)
┌─────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)                              │
│  ├── Public Subnet: Bastion EC2 (t3.micro)      │
│  └── Private Subnet:                            │
│       ├── K8s Master (t3.medium)                │
│       ├── K8s Worker × 2 (t3.small)            │
│       └── RDS PostgreSQL (db.t3.micro)          │
└─────────────────────────────────────────────────┘
  Managed by: Terraform

CONTAINER REGISTRY
  AWS ECR: loganalyzer-backend, loganalyzer-frontend
  Scan on push, lifecycle policy (keep 10 images)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CI/CD FLOW
  Developer push to main
       │
  [GitHub Actions]
  ├── Run pytest
  ├── Docker build (multi-stage)
  ├── Push to AWS ECR
  ├── Trivy vulnerability scan
  └── Update helm/values.yaml (new image tag)
              │
         [ArgoCD]  ← detects values.yaml change
              │
    Rolling update pods (zero-downtime)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OBSERVABILITY STACK
  Backend /metrics endpoint
       │
  [Prometheus] ← ServiceMonitor scrapes every 30s
       │
  [Grafana] ← 8-panel dashboard (auto-provisioned)
       │
  [AlertManager] ← PrometheusRule triggers alerts
```

---

## 6. SLO / SLI — Cách Đo Độ Tin Cậy

SRE không nói "app chạy tốt". SRE nói:

```
SLI (Service Level Indicator) — Thước đo thực tế:
  "99.2% requests trong 30 ngày qua trả về HTTP 200 trong < 500ms"

SLO (Service Level Objective) — Mục tiêu:
  "LogAnalyzer phải có error rate < 5% và p99 latency < 3 giây"

SLA (Service Level Agreement) — Cam kết với user:
  "Nếu uptime dưới 99%, user được hoàn tiền"
```

Với LogAnalyzer, SLO của chúng ta:

| Metric | Target | Alert threshold |
|---|---|---|
| Availability | > 99% | < 99% trong 5 phút |
| Error rate | < 5% | > 5% trong 5 phút |
| P99 latency /analyze | < 3s | > 3s trong 5 phút |
| Pod restart count | < 3/15min | > 3 restarts |

→ Đây chính xác là những gì `prometheusrule.yaml` implement.

---

## 7. Ngày Làm Việc Của Một SRE

```
09:00 — Xem Grafana dashboard, check overnight alerts
09:15 — Review PR từ developer: "Add new log parser"
        → Check: có test không? Resource limits OK không?
        → Approve → GitHub Actions tự build & deploy
10:30 — Alert: "HighErrorRate 8% on backend"
        → Xem Grafana: error bắt đầu lúc 10:15
        → Xem logs: OpenAI API rate limit exceeded
        → Fix: tăng retry timeout trong code
        → Deploy qua PR → ArgoCD sync
11:00 — Error rate về 0.3% → resolve alert
14:00 — Capacity planning: traffic tháng tới tăng 3x?
        → Xem HPA history → workers đang ổn
        → Terraform plan: thêm 1 worker node
16:00 — Incident review: ghi lại bài học từ sự cố sáng
        → Update runbook
```

Đây là nghề SRE: **không phải chờ cháy rồi chữa, mà thiết kế để không bao giờ cháy.**
