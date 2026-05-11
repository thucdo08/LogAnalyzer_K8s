output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion host"
  value       = aws_instance.bastion.public_ip
}

output "k8s_master_private_ip" {
  description = "Private IP of the K8s master node"
  value       = aws_instance.k8s_master.private_ip
}

output "k8s_worker_private_ips" {
  description = "Private IPs of K8s worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "rds_connection_string" {
  description = "PostgreSQL connection string template (replace <PASSWORD>)"
  value       = "postgresql://loganalyzer_admin:<PASSWORD>@${aws_db_instance.postgres.endpoint}/loganalyzer"
  sensitive   = true
}

output "ecr_backend_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for the frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}

output "s3_log_archive_bucket" {
  description = "S3 bucket name for log archiving"
  value       = aws_s3_bucket.log_archive.id
}

output "ssh_command_to_master" {
  description = "SSH command to reach the K8s master via Bastion"
  value       = "ssh -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.k8s_master.private_ip} -i ~/.ssh/loganalyzer-key.pem"
}

output "next_steps" {
  description = "Post-apply steps to bootstrap the K8s cluster"
  value       = <<-EOT
    === NEXT STEPS ===
    1. SSH to master: ssh -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.k8s_master.private_ip} -i ~/.ssh/loganalyzer-key.pem
    2. Wait for user-data to finish: sudo tail -f /var/log/k8s-init.log
    3. Copy kubeconfig locally: scp -J ubuntu@${aws_instance.bastion.public_ip} ubuntu@${aws_instance.k8s_master.private_ip}:~/.kube/config ~/.kube/loganalyzer-config
    4. Join workers: cat /home/ubuntu/join-command.sh  (run on each worker)
    5. Install ArgoCD: kubectl create ns argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    6. Apply GitOps config: kubectl apply -f k8s/argocd/appset-loganalyzer.yaml
    7. Update values.yaml:
       backend:  ${aws_ecr_repository.backend.repository_url}
       frontend: ${aws_ecr_repository.frontend.repository_url}
    EOT
}
