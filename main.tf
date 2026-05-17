terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}


provider "aws" {
  region = "us-east-1"
  # If you configured a named profile above, add: profile = "cs312"
  profile = "cs312"
}

# Use the default VPC instead of creating a new one
data "aws_vpc" "default" {
  default = true
}

# Security Group for the control node: SSH access from your laptop
resource "aws_security_group" "control" {
  name        = "cs312-tf-control-sg"
  description = "Control node: SSH only"
  vpc_id      = data.aws_vpc.default.id

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

  tags = {
    Name = "cs312-tf-control-sg"
  }
}

# Security Group for the managed node: SSH from control node only, HTTP from anywhere
resource "aws_security_group" "managed" {
  name        = "cs312-tf-managed-sg"
  description = "Managed node: SSH from control node, TCP from 25565 from anywhere"
  vpc_id      = data.aws_vpc.default.id

    ingress {
    description = "SSH from laptop"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

  ingress {
    description = "minecraft player"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cs312-tf-managed-sg"
  }
}

# Control node: you SSH into this instance from your laptop
resource "aws_instance" "control" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.control.id]
  iam_instance_profile   = "LabInstanceProfile"

  tags = {
    Name = "cs312-tf-control"
  }
}

# Managed node: the server that will run the application
resource "aws_instance" "managed" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.managed.id]
  iam_instance_profile   = "LabInstanceProfile"

  tags = {
    Name = "cs312-tf-managed"
  }
}

# ECR repository for the CI/CD pipeline in Lab 6
resource "aws_ecr_repository" "minecraft" {
  name                 = "cs312-minecraft"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}


resource "null_resource" "ansible_provision" {

  depends_on = [
    aws_instance.control,
    aws_instance.managed,
    local_file.inventory
  ]

  provisioner "local-exec" {
    command = "sleep 60 && chmod 400 newkey.pem && ansible-playbook -i inventory.ini playbook.yml --private-key ./newkey.pem"
  }
}

resource "local_file" "inventory" {
  filename = "${path.module}/inventory.ini"

  content = <<EOT
[minecraft]
${aws_instance.managed.public_ip} ansible_user=ubuntu

[control]
${aws_instance.control.public_ip} ansible_user=ubuntu
EOT
}