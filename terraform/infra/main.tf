terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = ">= 5.0" }
    random = { source = "hashicorp/random", version = ">= 3.5" }
  }

  backend "s3" {
    bucket         = "tf-backend-tfstate-0f719b6b"
    key            = "infra/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tf-backend-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# -------------------------
# Data S3 bucket (random files)
# -------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  data_bucket = "${var.project}-data-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "data" {
  bucket = local.data_bucket
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration { status = "Enabled" }
}

# auto-delete objects after 7 days
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "expire-after-7-days"
    status = "Enabled"

    expiration { days = 7 }
  }
}

# -------------------------
# Default VPC + default subnet (no custom VPC)
# -------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# take first subnet
locals {
  subnet_id = tolist(data.aws_subnets.default.ids)[0]
}

# -------------------------
# Security Group (SSH + 6443 from your IP only)
# -------------------------
resource "aws_security_group" "node" {
  name        = "${var.project}-node-sg"
  description = "SSH and k3s API only from my IP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "k3s API 6443 from my IP"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # outbound open (needed for apt, pulling images, reaching S3, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-node-sg" }
}

# -------------------------
# IAM role for EC2 -> write to S3 data bucket
# -------------------------
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${var.project}-s3-access"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.s3_access.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project}-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# -------------------------
# EC2 (Ubuntu 22.04)
# -------------------------
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

resource "aws_instance" "node" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.node.id]
  associate_public_ip_address = true

  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.this.name

  tags = { Name = "${var.project}-node" }
}
