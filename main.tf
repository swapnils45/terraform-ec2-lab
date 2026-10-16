terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

provider "http" {}

# Find your current public IP for SSH access.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

# Retrieve the latest Ubuntu 24.04 LTS AMI.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Use the default VPC in Oregon.
resource "aws_default_vpc" "default" {}

# Import the public key derived from your existing Passkey.pem.
resource "aws_key_pair" "passkey" {
  key_name   = "Passkey"
  public_key = file(pathexpand("~/Passkey.pub"))
}

# Allow SSH only from your current public IP.
resource "aws_security_group" "terraform_lab" {
  name        = "terraform-lab-sg"
  description = "SSH access for Terraform lab"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description = "SSH from my current public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      "${chomp(data.http.my_ip.response_body)}/32"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "terraform-lab-sg"
    Environment = "dev"
  }
}

# Create the Ubuntu EC2 instance.
resource "aws_instance" "terraform_lab" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.passkey.key_name
  vpc_security_group_ids      = [aws_security_group.terraform_lab.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name        = "terraform-lab"
    Environment = "dev"
  }
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.terraform_lab.id
}

output "public_ip" {
  description = "Public IPv4 address"
  value       = aws_instance.terraform_lab.public_ip
}

output "ssh_command" {
  description = "Command to connect from MobaXterm local terminal"
  value       = "ssh -i /drives/d/aws/Passkey.pem ubuntu@${aws_instance.terraform_lab.public_ip}"
}

