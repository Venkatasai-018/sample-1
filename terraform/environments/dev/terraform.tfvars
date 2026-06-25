# -----------------------------------------------------------------------------
# Dev Environment - terraform.tfvars
# -----------------------------------------------------------------------------

aws_region = "us-east-1"
project    = "landing-page"

# -----------------------------------------------------------------------------
# Network (leave empty to use default VPC)
# -----------------------------------------------------------------------------
# vpc_id    = "vpc-xxxxxxxxx"
# subnet_id = "subnet-xxxxxxxxx"

# -----------------------------------------------------------------------------
# EC2 Configuration
# -----------------------------------------------------------------------------
instance_type       = "t3.small"
key_name            = ""  # Set your SSH key name if needed
associate_public_ip = true
root_volume_size    = 20

# -----------------------------------------------------------------------------
# Grafana Configuration
# -----------------------------------------------------------------------------
grafana_admin_user     = "admin"
grafana_admin_password = "DevGrafana@2024!"  # CHANGE THIS!
grafana_port           = 3000
grafana_version        = "latest"

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------
# Restrict to your IP in production!
allowed_cidr_blocks = ["0.0.0.0/0"]

# SSH access (add your IP if needed)
# allowed_ssh_cidr_blocks = ["YOUR_IP/32"]

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
tags = {
  Team = "DevOps"
}
