# Hướng dẫn thực thi Lab GitOps - Các bước còn lại
# Chạy trên k8s-master-1

# =======================================================
# BƯỚC 6: Build & Push Docker image lên Private Registry
# =======================================================

# 6.1. Config Docker daemon trên TẤT CẢ K8s nodes để accept HTTP registry
# (Chạy trên cả 3 master nodes)
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["jfrog.dofuta.site"]
}
EOF
sudo systemctl restart docker

# 6.2. Build & push image từ máy có source code
# (Nếu không có Jenkins, dùng script thủ công)
REGISTRY="jfrog.dofuta.site"
TAG=$(git rev-parse --short HEAD)

docker build -t ${REGISTRY}/loganalyzer-backend:${TAG} ./backend
docker build -t ${REGISTRY}/loganalyzer-frontend:${TAG} ./frontend

docker push ${REGISTRY}/loganalyzer-backend:${TAG}
docker push ${REGISTRY}/loganalyzer-frontend:${TAG}

# Kiểm tra image đã lên registry chưa
curl http://jfrog.dofuta.site/v2/_catalog

# =======================================================
# BƯỚC 7: Config ArgoCD ApplicationSet (GitOps trigger)
# =======================================================

# 7.1. Cài ArgoCD Image Updater (trigger từ Container Registry)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# 7.2. Cấu hình Image Updater biết registry nội bộ (HTTP, insecure)
kubectl -n argocd edit configmap argocd-image-updater-config
# Thêm vào data:
# registries: |
#   - name: private
#     api_url: http://jfrog.dofuta.site
#     prefix: jfrog.dofuta.site
#     insecure: yes

# 7.3. Apply infra Application (theo dõi k8s/registry/)
kubectl apply -f argocd/app-infra-registry.yaml

# 7.4. Apply ApplicationSet cho LogAnalyzer
kubectl apply -f argocd/appset-loganalyzer.yaml

# Kiểm tra
kubectl get applicationset -n argocd
kubectl get application -n argocd

# =======================================================
# BƯỚC 8: Demo luồng GitOps
# =======================================================

# Demo thay đổi code → CI build → image mới → ArgoCD auto-sync
# 1. Sửa code (ví dụ: đổi version trong frontend)
# 2. git commit & push
# 3. Xem Jenkins build tự chạy (hoặc chạy build-push.sh thủ công)
# 4. Xem ArgoCD tự detect và sync deployment mới
#    kubectl get pods -n loganalyzer -w
#    kubectl -n argocd app get loganalyzer-production

# Xem log ArgoCD Image Updater (nếu dùng)
kubectl logs -n argocd deployment/argocd-image-updater -f
