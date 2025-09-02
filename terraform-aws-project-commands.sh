#!/bin/bash

# Set project directory
PROJECT_DIR=terraform-ubuntu-project
MODULE_DIR=$PROJECT_DIR/modules/ec2

# Create directories
mkdir -p $MODULE_DIR
echo "Created project directories."

# ---------- Root Files ----------

# providers.tf
cat > $PROJECT_DIR/providers.tf << 'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}
EOF

# variables.tf
cat > $PROJECT_DIR/variables.tf << 'EOF'
variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH key name"
  type        = string
  default     = "terraform-generated-key"
}
EOF

# terraform.tfvars
cat > $PROJECT_DIR/terraform.tfvars << 'EOF'
region = "us-east-1"
instance_type = "t3.micro"
key_name = "terraform-generated-key"
EOF

# versions.tf
cat > $PROJECT_DIR/versions.tf << 'EOF'
terraform {
  required_version = ">= 1.5.0"
}
EOF

# main.tf
cat > $PROJECT_DIR/main.tf << 'EOF'
module "ubuntu_ec2" {
  source        = "./modules/ec2"
  instance_type = var.instance_type
  key_name      = var.key_name
}
EOF

# outputs.tf
cat > $PROJECT_DIR/outputs.tf << 'EOF'
output "instance_ip" {
  value = module.ubuntu_ec2.instance_ip
}

output "ssh_command" {
  value = module.ubuntu_ec2.ssh_command
}
EOF

# ---------- Module Files ----------

# modules/ec2/main.tf
cat > $MODULE_DIR/main.tf << 'EOF'
# Generate SSH key
resource "tls_private_key" "my_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.my_key.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.my_key.private_key_pem
  filename        = "${path.module}/terraform-key.pem"
  file_permission = "0400"
}

# Security group for SSH
resource "aws_security_group" "ssh_access" {
  name        = "ssh_access"
  description = "Allow SSH inbound"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Get latest Ubuntu 22.04 LTS AMI for the region
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# EC2 instance
resource "aws_instance" "ubuntu_vm" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.ssh_access.id]

  tags = {
    Name = "TerraformUbuntuVM"
  }
}
EOF

# modules/ec2/variables.tf
cat > $MODULE_DIR/variables.tf << 'EOF'
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH key name"
  type        = string
  default     = "terraform-generated-key"
}
EOF

# modules/ec2/outputs.tf
cat > $MODULE_DIR/outputs.tf << 'EOF'
output "instance_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.ubuntu_vm.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i ${path.module}/terraform-key.pem ubuntu@${aws_instance.ubuntu_vm.public_ip}"
}
EOF

echo "Terraform project created at $PROJECT_DIR"
echo "Next steps:"
echo "1. cd $PROJECT_DIR"
echo "2. terraform init"
echo "3. terraform apply -auto-approve"
echo "4. terraform output ssh_command to get SSH command"
