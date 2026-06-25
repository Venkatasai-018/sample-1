# -----------------------------------------------------------------------------
# QA Environment - Outputs
# -----------------------------------------------------------------------------

output "grafana_url" {
  description = "Grafana web interface URL"
  value       = module.grafana_monitoring.grafana_url
}

output "grafana_admin_user" {
  description = "Grafana admin username"
  value       = module.grafana_monitoring.grafana_admin_user
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.grafana_monitoring.instance_id
}

output "instance_public_ip" {
  description = "Public IP of Grafana instance"
  value       = module.grafana_monitoring.instance_public_ip
}

output "instance_private_ip" {
  description = "Private IP of Grafana instance"
  value       = module.grafana_monitoring.instance_private_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = module.grafana_monitoring.security_group_id
}

output "connection_instructions" {
  description = "How to connect to Grafana"
  value       = <<-EOT
    
    ============================================
    Grafana QA Environment Ready!
    ============================================
    
    URL:      ${module.grafana_monitoring.grafana_url}
    Username: ${module.grafana_monitoring.grafana_admin_user}
    Password: (as configured in terraform.tfvars)
    
    Wait 2-3 minutes after instance launch for
    Docker and Grafana to initialize.
    
    ============================================
  EOT
}
