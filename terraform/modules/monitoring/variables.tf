# -----------------------------------------------------------------------------
# Monitoring Module - Variables
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (dev, qa, prod)"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "landing-page"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Auto Scaling Group Monitoring
# -----------------------------------------------------------------------------

variable "asg_name" {
  description = "Name of the Auto Scaling Group to monitor"
  type        = string
}

variable "asg_min_healthy_instances" {
  description = "Minimum number of healthy instances in ASG"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# ALB Monitoring
# -----------------------------------------------------------------------------

variable "alb_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer (e.g., app/my-alb/1234567890)"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the Target Group (e.g., targetgroup/my-tg/1234567890)"
  type        = string
  default     = ""
}

variable "alb_5xx_threshold" {
  description = "Threshold for ALB 5xx errors"
  type        = number
  default     = 10
}

variable "alb_latency_threshold" {
  description = "Threshold for ALB target response time in seconds"
  type        = number
  default     = 2
}

variable "unhealthy_host_threshold" {
  description = "Threshold for unhealthy host count"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# CloudFront Monitoring (optional)
# -----------------------------------------------------------------------------

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (optional)"
  type        = string
  default     = ""
}

variable "cloudfront_error_rate_threshold" {
  description = "CloudFront error rate threshold percentage"
  type        = number
  default     = 5
}

# -----------------------------------------------------------------------------
# Application Monitoring
# -----------------------------------------------------------------------------

variable "app_port" {
  description = "Application port"
  type        = number
  default     = 3000
}

variable "health_path" {
  description = "Health check path"
  type        = string
  default     = "/api/health"
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold percentage"
  type        = number
  default     = 80
}

variable "memory_utilization_threshold" {
  description = "Memory utilization threshold percentage (requires CloudWatch agent)"
  type        = number
  default     = 80
}

# -----------------------------------------------------------------------------
# Alerting
# -----------------------------------------------------------------------------

variable "sns_email_endpoints" {
  description = "List of email addresses to receive alerts"
  type        = list(string)
  default     = []
}

variable "enable_slack_notifications" {
  description = "Enable Slack notifications via Lambda"
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Dashboard
# -----------------------------------------------------------------------------

variable "create_dashboard" {
  description = "Create CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "dashboard_refresh_interval" {
  description = "Dashboard auto-refresh interval in seconds"
  type        = number
  default     = 60
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
