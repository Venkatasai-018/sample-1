# -----------------------------------------------------------------------------
# Grafana Monitoring Module - Outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.grafana.id
}

output "instance_private_ip" {
  description = "Private IP address of the Grafana instance"
  value       = aws_instance.grafana.private_ip
}

output "instance_public_ip" {
  description = "Public IP address of the Grafana instance"
  value       = aws_instance.grafana.public_ip
}

output "grafana_url" {
  description = "Grafana web interface URL"
  value       = var.associate_public_ip ? "http://${aws_instance.grafana.public_ip}:${var.grafana_port}" : "http://${aws_instance.grafana.private_ip}:${var.grafana_port}"
}

output "grafana_admin_user" {
  description = "Grafana admin username"
  value       = var.grafana_admin_user
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.grafana.id
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.grafana.arn
}

output "iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.grafana.name
}
