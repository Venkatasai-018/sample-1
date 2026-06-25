# Terraform Grafana Monitoring

This Terraform configuration provisions a Grafana monitoring server on EC2 with Docker.

## Structure

```
terraform/
├── modules/
│   └── grafana-monitoring/     # Reusable module
│       ├── main.tf             # EC2, SG, IAM resources
│       ├── variables.tf        # Input variables
│       ├── outputs.tf          # Outputs
│       ├── versions.tf         # Provider requirements
│       └── user_data.sh.tpl    # EC2 bootstrap script
│
└── environments/
    ├── dev/                    # Dev environment
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars    # Dev-specific values
    │
    ├── qa/                     # QA environment
    │   └── ...
    │
    └── prod/                   # Production environment
        └── ...
```

## Quick Start

### 1. Configure AWS credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
# Or use AWS CLI profile
export AWS_PROFILE="your-profile"
```

### 2. Deploy Dev Environment

```bash
cd terraform/environments/dev

# Edit terraform.tfvars with your password
# grafana_admin_password = "YourSecurePassword!"

terraform init
terraform plan
terraform apply
```

### 3. Access Grafana

After `terraform apply`, you'll see output like:

```
grafana_url = "http://54.xxx.xxx.xxx:3000"
```

Wait 2-3 minutes for Docker to initialize, then access the URL.

- **Username:** admin (or as configured)
- **Password:** (from terraform.tfvars)

## Configuration

### terraform.tfvars Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | us-east-1 |
| `grafana_admin_password` | Admin password | **Required** |
| `grafana_admin_user` | Admin username | admin |
| `grafana_port` | Grafana port | 3000 |
| `grafana_version` | Docker image version | latest |
| `instance_type` | EC2 instance type | t3.small |
| `allowed_cidr_blocks` | IPs allowed to access | ["0.0.0.0/0"] |

### Environment Differences

| Setting | Dev | QA | Prod |
|---------|-----|-----|------|
| Instance Type | t3.small | t3.small | t3.medium |
| Volume Size | 20 GB | 20 GB | 50 GB |
| Grafana Version | latest | latest | 10.4.1 (pinned) |
| Access | Open | Open | Restricted |

## Features

- **Auto-configured CloudWatch datasource** - Ready to query AWS metrics
- **Pre-built ASG dashboard** - Monitor Auto Scaling Groups immediately
- **IAM role with CloudWatch access** - No manual credential setup needed
- **SSM enabled** - Connect without SSH keys via Session Manager
- **Persistent storage** - Grafana data persists across container restarts

## Cleanup

```bash
cd terraform/environments/dev
terraform destroy
```

## Security Notes

1. **Change default passwords** in terraform.tfvars before deploying
2. **Restrict `allowed_cidr_blocks`** to your IP/VPN in production
3. **Use VPC endpoints** for CloudWatch in private subnets
4. **Enable HTTPS** via ALB/CloudFront for production use
