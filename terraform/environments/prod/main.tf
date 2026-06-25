# -----------------------------------------------------------------------------
# Prod Environment - Grafana Monitoring
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  # Uncomment to use S3 backend for state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "landing-page/prod/grafana/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

locals {
  vpc_id    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.public.ids[0]
}

# -----------------------------------------------------------------------------
# Grafana Monitoring Module
# -----------------------------------------------------------------------------

module "grafana_monitoring" {
  source = "../../modules/grafana-monitoring"

  environment = "prod"
  project     = var.project
  aws_region  = var.aws_region

  # EC2 Configuration - larger instance for prod
  instance_type       = var.instance_type
  key_name            = var.key_name
  subnet_id           = local.subnet_id
  vpc_id              = local.vpc_id
  associate_public_ip = var.associate_public_ip
  root_volume_size    = var.root_volume_size

  # Grafana Configuration
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password
  grafana_port           = var.grafana_port
  grafana_version        = var.grafana_version

  # Network Access - more restrictive for prod
  allowed_cidr_blocks     = var.allowed_cidr_blocks
  allowed_ssh_cidr_blocks = var.allowed_ssh_cidr_blocks

  tags = var.tags
}
