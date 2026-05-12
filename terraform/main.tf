# Terraform — AWS Infrastructure as Code
# Region: ap-southeast-1 (Singapore)
#
# Architecture:
#   VPC -> Public Subnet (Bastion) + Private Subnets (K8s + RDS)
#   EC2: 1 Master (t3.medium) + 2 Workers (t3.small) + 1 Bastion (t3.micro)
#   RDS: PostgreSQL t3.micro
#   ECR: backend + frontend image repositories
#   S3:  cold storage for archived log files
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to store state in S3 (recommended for production)
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

# -------------------------------------------------------------
# Data Sources
# -------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# Used for globally unique S3 bucket naming
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

# -------------------------------------------------------------
# VPC & Networking
# -------------------------------------------------------------
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

# Public subnet — hosts Bastion (internet-facing)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1) # 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

# Private subnet — K8s nodes (no direct internet access)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10) # 10.0.10.0/24
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.project_name}-private-subnet" }
}

# Second private subnet — required by RDS (multi-AZ subnet group)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11) # 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "${var.project_name}-private-subnet-2" }
}

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

# -------------------------------------------------------------
# Security Groups
# -------------------------------------------------------------

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

resource "aws_security_group" "k8s" {
  name        = "${var.project_name}-k8s-sg"
  description = "Kubernetes cluster nodes"
  vpc_id      = aws_vpc.main.id

  # SSH via Bastion only
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # K8s API server
  ingress {
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # NodePort range for Ingress Controller
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inter-node traffic (Calico CNI)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS PostgreSQL - accessible from K8s nodes only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from K8s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s.id]
  }
}

# -------------------------------------------------------------
# EC2 Instances — Kubernetes Cluster
# -------------------------------------------------------------

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = { Name = "${var.project_name}-bastion", Role = "bastion" }
}

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

  user_data = base64encode(templatefile("${path.module}/scripts/k8s-init.sh", {
    role = "master"
  }))

  tags = { Name = "${var.project_name}-k8s-master", Role = "k8s-master" }
}

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

  user_data = base64encode(templatefile("${path.module}/scripts/k8s-init.sh", {
    role = "worker"
  }))

  tags = {
    Name = "${var.project_name}-k8s-worker-${count.index + 1}"
    Role = "k8s-worker"
  }
}

# -------------------------------------------------------------
# RDS PostgreSQL
# -------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_2.id]

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "16.6"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "loganalyzer"
  username = "loganalyzer_admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  deletion_protection = false # set true in production
  skip_final_snapshot = true  # set false in production

  backup_retention_period = 1
  backup_window           = "03:00-04:00" # SGT

  tags = { Name = "${var.project_name}-postgres" }
}

# -------------------------------------------------------------
# AWS ECR — Container Registries
# -------------------------------------------------------------
resource "aws_ecr_repository" "backend" {
  name                 = "loganalyzer-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
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

# Retain only the 10 most recent images
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

# -------------------------------------------------------------
# S3 — Cold Storage for Archived Log Files
# -------------------------------------------------------------
resource "aws_s3_bucket" "log_archive" {
  # Account ID ensures globally unique bucket name
  bucket = "${var.project_name}-log-archive-${data.aws_caller_identity.current.account_id}"

  tags = { Purpose = "Cold storage for archived security logs" }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter { prefix = "logs/" }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

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
