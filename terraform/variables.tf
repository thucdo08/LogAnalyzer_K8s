variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
  default     = "loganalyzer"
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation to restrict SSH access (e.g. 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_pair_name" {
  description = "Name of the AWS EC2 Key Pair for SSH access (must exist before apply)"
  type        = string
  default     = "loganalyzer-key"
}

variable "master_instance_type" {
  description = "EC2 instance type for the K8s control plane node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for K8s worker nodes"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of K8s worker nodes"
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_password" {
  description = "Master password for the RDS PostgreSQL instance"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters."
  }
}
