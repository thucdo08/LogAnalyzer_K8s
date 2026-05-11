variable "region" {
  description = "AWS Region — ap-southeast-1 (Singapore, gần ShopBack HQ)"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên project, dùng làm prefix cho tất cả resources"
  type        = string
  default     = "loganalyzer"
}

variable "environment" {
  description = "Môi trường: dev, staging, production"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment phải là: dev, staging, hoặc production."
  }
}

variable "vpc_cidr" {
  description = "CIDR block cho VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "my_ip_cidr" {
  description = "IP của bạn để giới hạn SSH access vào Bastion (format: x.x.x.x/32)"
  type        = string
  default     = "0.0.0.0/0"  # THAY bằng IP thực: "YOUR_IP/32"
}

variable "key_pair_name" {
  description = "Tên AWS Key Pair để SSH vào EC2 (phải tạo trước trong AWS Console)"
  type        = string
  default     = "loganalyzer-key"
}

variable "master_instance_type" {
  description = "EC2 instance type cho K8s Master (Control Plane)"
  type        = string
  default     = "t3.medium"  # 2 vCPU, 4GB RAM — đủ cho K8s master
}

variable "worker_instance_type" {
  description = "EC2 instance type cho K8s Workers (chạy LogAnalyzer pods)"
  type        = string
  default     = "t3.small"   # 2 vCPU, 2GB RAM — đủ cho intern demo
}

variable "worker_count" {
  description = "Số lượng K8s Worker nodes"
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"  # 2 vCPU, 1GB RAM — đủ cho demo
}

variable "db_password" {
  description = "Password cho RDS PostgreSQL admin user"
  type        = string
  sensitive   = true  # Không hiển thị trong terraform plan output

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "DB password phải có ít nhất 8 ký tự."
  }
}
