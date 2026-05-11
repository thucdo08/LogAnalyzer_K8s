# =============================================================
# Terraform — AWS Infrastructure as Code
# Region: ap-southeast-1 (Singapore) — gần ShopBack HQ
#
# Kiến trúc triển khai:
#   VPC → Public Subnet (HAProxy/Jump) + Private Subnet (K8s Nodes)
#   EC2: 1 Master (t3.medium) + 2 Workers (t3.small) + 1 Bastion
#   RDS: PostgreSQL t3.micro (LogAnalyzer metadata)
#   ECR: Repository cho backend + frontend images
#
# Để deploy:
#   terraform init
#   terraform plan -var="db_password=YourSecurePass123"
#   terraform apply -var="db_password=YourSecurePass123"
# =============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment để lưu state trên S3 (production best practice)
  # backend "s3" {
  #   bucket  = "loganalyzer-terraform-state"
  #   key     = "k8s/terraform.tfstate"
  #   region  = "ap-southeast-1"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "thucdo08"
    }
  }
}

# =============================================================
# Data Sources
# =============================================================
data "aws_availability_zones" "available" {
  state = "available"
}

# Lấy AWS Account ID (dùng cho S3 bucket name unique)
data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================
# VPC & Networking
# =============================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# Public Subnet — cho Bastion/HAProxy (expose ra internet)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)   # 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

# Private Subnet — cho K8s nodes + RDS (không expose ra internet)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10)  # 10.0.10.0/24
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.project_name}-private-subnet" }
}

# Private Subnet 2 — RDS yêu cầu ít nhất 2 AZ
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11)  # 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "${var.project_name}-private-subnet-2" }
}

# Route Table cho Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =============================================================
# Security Groups
# =============================================================

# SG cho Bastion/Jump Host
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Bastion host - SSH jump server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from your IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG cho K8s Master + Workers
resource "aws_security_group" "k8s" {
  name        = "${var.project_name}-k8s-sg"
  description = "Kubernetes cluster nodes"
  vpc_id      = aws_vpc.main.id

  # SSH từ Bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # K8s API Server (kubectl access)
  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # NodePort range (Ingress Controller)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Public access cho Ingress
  }

  # Calico CNI + K8s internal communication
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true  # Cho phép nodes nói chuyện với nhau
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG cho RDS PostgreSQL
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS PostgreSQL — chỉ K8s nodes được kết nối"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL chỉ từ K8s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s.id]
  }

  # Không có egress rule → mặc định allow all (RDS chỉ cần receive)
}

# =============================================================
# EC2 Instances — Kubernetes Cluster
# =============================================================

# Bastion Host (jump server để SSH vào K8s nodes)
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = { Name = "${var.project_name}-bastion", Role = "bastion" }
}

# K8s Master Node
resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.k8s.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # User data: cài Docker + kubeadm khi EC2 khởi động
  user_data = base64encode(templatefile("${path.module}/scripts/k8s-init.sh", {
    role = "master"
  }))

  tags = { Name = "${var.project_name}-k8s-master", Role = "k8s-master" }
}

# K8s Worker Nodes
resource "aws_instance" "k8s_workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.k8s.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # User data: cài Docker + kubeadm (không init cluster, chỳ lệnh join từ master)
  user_data = base64encode(templatefile("${path.module}/scripts/k8s-init.sh", {
    role = "worker"
  }))

  tags = {
    Name = "${var.project_name}-k8s-worker-${count.index + 1}"
    Role = "k8s-worker"
  }
}

# =============================================================
# RDS PostgreSQL — LogAnalyzer Metadata Storage
# =============================================================
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_2.id]

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100  # Auto-scaling storage
  storage_type          = "gp3"
  storage_encrypted     = true  # Encrypt data at rest

  db_name  = "loganalyzer"
  username = "loganalyzer_admin"
  password = var.db_password  # Từ variables (sensitive)

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Security settings
  publicly_accessible    = false  # Không expose ra internet
  deletion_protection    = false  # Set true trong production
  skip_final_snapshot    = true   # Set false trong production

  # Backup (production: 7 ngày)
  backup_retention_period = 1
  backup_window           = "03:00-04:00"  # 3AM Singapore time

  tags = { Name = "${var.project_name}-postgres" }
}

# =============================================================
# AWS ECR — Container Registry cho Docker Images
# =============================================================
resource "aws_ecr_repository" "backend" {
  name                 = "loganalyzer-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true  # Tự động scan CVE khi push image
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Component = "backend" }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "loganalyzer-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Component = "frontend" }
}

# ECR Lifecycle Policy: Giữ tối đa 10 images, xóa cũ tự động
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# =============================================================
# S3 Bucket — Cold Storage cho log files cũ (archive)
# =============================================================
resource "aws_s3_bucket" "log_archive" {
  # Bucket name phải globally unique — dùng account ID để đảm bảo không trùng
  bucket = "${var.project_name}-log-archive-${data.aws_caller_identity.current.account_id}"

  tags = { Purpose = "Cold storage for archived security logs" }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter { prefix = "logs/" }

    # Sau 30 ngày → chuyển sang S3 Standard-IA (rẻ hơn)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Sau 90 ngày → chuyển sang Glacier (rất rẻ, archive dài hạn)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Sau 365 ngày → xóa (compliance: 1 năm)
    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
