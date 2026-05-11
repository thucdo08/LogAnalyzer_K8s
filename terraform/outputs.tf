output "vpc_id" {
  description = "ID của VPC vừa tạo"
  value       = aws_vpc.main.id
}

output "bastion_public_ip" {
  description = "Public IP của Bastion host (dùng để SSH vào cluster)"
  value       = aws_instance.bastion.public_ip
}

output "k8s_master_private_ip" {
  description = "Private IP của K8s Master node"
  value       = aws_instance.k8s_master.private_ip
}

output "k8s_worker_private_ips" {
  description = "Private IPs của K8s Worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

output "rds_endpoint" {
  description = "Endpoint của RDS PostgreSQL (dùng trong K8s Secret)"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true  # Không hiển thị trong output mặc định
}

output "rds_connection_string" {
  description = "Connection string template cho LogAnalyzer backend"
  value       = "postgresql://loganalyzer_admin:<PASSWORD>@${aws_db_instance.postgres.endpoint}/loganalyzer"
  sensitive   = true
}

output "ecr_backend_url" {
  description = "ECR URL cho backend image — dùng trong values.yaml và GitHub Actions"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR URL cho frontend image — dùng trong values.yaml và GitHub Actions"
  value       = aws_ecr_repository.frontend.repository_url
}

output "s3_log_archive_bucket" {
  description = "S3 bucket name để archive log files cũ"
  value       = aws_s3_bucket.log_archive.id
}

output "ssh_command_to_master" {
  description = "Command để SSH vào K8s Master qua Bastion"
  value       = "ssh -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.k8s_master.private_ip}"
}

output "next_steps" {
  description = "Các bước tiếp theo sau terraform apply"
  value       = <<-EOT
    ===== NEXT STEPS =====
    1. SSH vào master: ${join("", ["ssh -J ubuntu@", aws_instance.bastion.public_ip, " ubuntu@", aws_instance.k8s_master.private_ip])}
    2. Cài K8s: sudo kubeadm init --pod-network-cidr=192.168.0.0/16
    3. Cài Calico CNI: kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    4. Join workers vào cluster (lấy token từ kubeadm init output)
    5. Cài ArgoCD: kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    6. Apply ArgoCD ApplicationSet: kubectl apply -f argocd/appset-loganalyzer.yaml
    7. Cập nhật values.yaml với ECR URLs:
       - backend: ${aws_ecr_repository.backend.repository_url}
       - frontend: ${aws_ecr_repository.frontend.repository_url}
    EOT
}
