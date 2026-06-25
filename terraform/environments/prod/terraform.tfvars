# -----------------------------------------------------------------------------
# Prod Environment - terraform.tfvars
# -----------------------------------------------------------------------------

aws_region = "us-east-1"
project    = "landing-page"

# -----------------------------------------------------------------------------
# Network - CONFIGURE FOR YOUR PROD VPC
# -----------------------------------------------------------------------------
# vpc_id    = "vpc-xxxxxxxxx"
# subnet_id = "subnet-xxxxxxxxx"

# -----------------------------------------------------------------------------
# EC2 Configuration - Larger instance for production
# -----------------------------------------------------------------------------
instance_type       = "t3.medium"
key_name            = ""  # Set your SSH key name
associate_public_ip = true
root_volume_size    = 50

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------
grafana_admin_user     = "admin"
grafana_admin_password = "ProdGrafana@Secure2024!"  # CHANGE THIS - use strong password!
grafana_port           = 3000
grafana_version        = "10.4.1"  # Pin specific version for prod stability

# -----------------------------------------------------------------------------
# Access Control - RESTRICT FOR PRODUCTION!
# -----------------------------------------------------------------------------
# IMPORTANT: Replace with your actual allowed CIDRs
allowed_cidr_blocks = [
  "10.0.0.0/8",       # Internal network
  # "YOUR_OFFICE_IP/32"  # Add your office IP
]

# SSH access - restrict to bastion/admin IPs only
# allowed_ssh_cidr_blocks = ["10.0.0.0/8"]

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
tags = {
  Team        = "DevOps"
  CostCenter  = "Infrastructure"
  Criticality = "High"
}
