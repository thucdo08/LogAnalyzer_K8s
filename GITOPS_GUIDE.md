# GitOps Guide – LogAnalyzer trên K8s HA Cluster

## Môi trường thực hiện
| Ký hiệu | Máy | Mô tả |
|---------|-----|-------|
| 🖥️ **[WIN]** | Windows (máy cá nhân) | Máy dev, có VS Code, Docker Desktop |
| 🟢 **[MASTER-1]** | `devops@k8s-master-1` | K8s master node (có kubectl, helm) |
| 🔵 **[MASTER-2/3]** | `devops@k8s-master-2/3` | K8s worker/master node |
| 🌐 **[BROWSER]** | Trình duyệt | Truy cập ArgoCD UI, Registry UI |

---

## Kiến trúc tổng quan
```
[WIN] push code
      │
      ▼
GitHub Repo ←── ArgoCD watches ──→ K8s Cluster [MASTER-1]
      │                                   │
      ▼                                   ▼
[WIN] build-push.sh             Rolling update pods
      │
      ▼
jfrog.dofuta.site (Private Registry chạy trong K8s)
```

---

## ⚙️ SETUP LẦN ĐẦU

### 1. Config insecure registry (chạy trên CẢ 3 K8s nodes)

🔵 **[MASTER-1]**, **[MASTER-2]**, **[MASTER-3]** – SSH vào từng máy và chạy:
```bash
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{"insecure-registries": ["jfrog.dofuta.site"]}
EOF
sudo systemctl restart docker

# Kiểm tra
docker info | grep -A2 "Insecure"
```

### 2. Apply ArgoCD Application (chỉ cần 1 lần)

🟢 **[MASTER-1]** – Pull repo và apply:
```bash
git clone https://github.com/thucdo08/LogAnalyzer_K8s.git
cd LogAnalyzer_K8s

kubectl apply -f argocd/app-infra-registry.yaml   # quản lý Docker Registry
kubectl apply -f argocd/appset-loganalyzer.yaml   # deploy LogAnalyzer app
```

---

## 🔄 QUY TRÌNH GITOPS HÀNG NGÀY

### Bước 1 – Build & Push image

🖥️ **[WIN]** – Mở PowerShell trong thư mục dự án:
```powershell
# Cách 1: Dùng script
bash scripts/build-push.sh          # tự lấy git short SHA làm tag

# Cách 2: Thủ công
$REGISTRY = "jfrog.dofuta.site"
$TAG = git rev-parse --short HEAD
docker build -t "$REGISTRY/loganalyzer-backend:$TAG" ./backend
docker build -t "$REGISTRY/loganalyzer-frontend:$TAG" ./frontend
docker push "$REGISTRY/loganalyzer-backend:$TAG"
docker push "$REGISTRY/loganalyzer-frontend:$TAG"
```
> ⚠️ Yêu cầu Docker Desktop đã thêm `"insecure-registries": ["jfrog.dofuta.site"]` trong Settings → Docker Engine

### Bước 2 – Cập nhật image tag trong Helm values

🖥️ **[WIN]** – Tiếp tục trong PowerShell:
```powershell
$TAG = git rev-parse --short HEAD

# Sửa tag trong values.yaml (dùng VSCode hoặc)
(Get-Content helm\loganalyzer\values.yaml) -replace 'tag: .*', "tag: `"$TAG`"" `
    | Set-Content helm\loganalyzer\values.yaml

git add helm/loganalyzer/values.yaml
git commit -m "ci: update image tag to $TAG"
git push origin main
```

### Bước 3 – ArgoCD tự động sync (~1-3 phút)

🌐 **[BROWSER]** – Vào https://argocd.dofuta.site để theo dõi trực quan

Hoặc sync ngay lập tức:

🟢 **[MASTER-1]**:
```bash
kubectl -n argocd app sync loganalyzer-production
```

---

## 🔍 KIỂM TRA SAU KHI GITOPS CHẠY

### Kiểm tra ArgoCD sync status

🟢 **[MASTER-1]**:
```bash
# Xem tổng quan
kubectl get application -n argocd

# Xem chi tiết
kubectl -n argocd app get loganalyzer-production

# Xem history sync
kubectl -n argocd app history loganalyzer-production
```
Kết quả mong đợi:
```
NAME                     SYNC STATUS   HEALTH STATUS
loganalyzer-production   Synced        Healthy
infra-registry           Synced        Healthy
```

### Kiểm tra pods đang chạy đúng image tag

🟢 **[MASTER-1]**:
```bash
kubectl get pods -n loganalyzer

# Verify image tag đúng không
kubectl get pods -n loganalyzer \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'
```

### Kiểm tra images trên Registry

🖥️ **[WIN]** – PowerShell hoặc trình duyệt:
```powershell
# Xem danh sách images
Invoke-RestMethod http://jfrog.dofuta.site/v2/_catalog

# Xem tags của image backend
Invoke-RestMethod http://jfrog.dofuta.site/v2/loganalyzer-backend/tags/list
```
Hoặc vào 🌐 **[BROWSER]**: **http://jfrog.dofuta.site**

### Kiểm tra app hoạt động

🌐 **[BROWSER]**: Truy cập **https://loganalyzer.dofuta.site**

🖥️ **[WIN]** hoặc 🟢 **[MASTER-1]**:
```bash
curl https://loganalyzer.dofuta.site
```

### Kiểm tra self-healing (tự phục hồi)

🟢 **[MASTER-1]**:
```bash
# Xóa pod thủ công → ArgoCD sẽ tự tạo lại
kubectl delete pod -n loganalyzer -l app=loganalyzer-backend

# Quan sát pod tự tạo lại
kubectl get pods -n loganalyzer -w
```

---

## 🛠️ DEBUG KHI CÓ LỖI

🟢 **[MASTER-1]**:
```bash
# Xem log ArgoCD controller
kubectl logs -n argocd deployment/argocd-application-controller --tail=50

# Xem events trong namespace app
kubectl get events -n loganalyzer --sort-by='.lastTimestamp'

# Xem log pod lỗi
kubectl logs -n loganalyzer <pod-name>
kubectl logs -n loganalyzer <pod-name> --previous   # log lần chạy trước

# Mô tả pod (xem lỗi ImagePullBackOff, OOMKilled...)
kubectl describe pod -n loganalyzer <pod-name>

# Rollback về version trước
kubectl -n argocd app rollback loganalyzer-production
```

---

## 🧪 DEMO LUỒNG GITOPS (cho phỏng vấn)

**Mở 2 terminal song song:**

🟢 **[MASTER-1]** – Terminal A (quan sát):
```bash
kubectl get pods -n loganalyzer -w
```

🖥️ **[WIN]** – Terminal B (trigger deploy):
```powershell
# 1. Sửa code nhỏ
Add-Content backend\app.py "`n# v1.1 demo"

# 2. Commit
git add .; git commit -m "demo: trigger gitops"

# 3. Build & push image mới
bash scripts/build-push.sh

# 4. Cập nhật tag và push
$TAG = git rev-parse --short HEAD
(Get-Content helm\loganalyzer\values.yaml) -replace 'tag: .*', "tag: `"$TAG`"" `
    | Set-Content helm\loganalyzer\values.yaml
git add helm/loganalyzer/values.yaml
git commit -m "ci: update tag $TAG"
git push origin main
```

🌐 **[BROWSER]**: Mở https://argocd.dofuta.site  
→ Trong ~2 phút sẽ thấy ArgoCD chuyển sang **Syncing** → **Healthy**  
→ Terminal A sẽ thấy pod cũ đang **Terminating**, pod mới đang **Running**
