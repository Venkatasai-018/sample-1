# -----------------------------------------------------------------------------
# Monitoring Module - Outputs
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "log_group_app_name" {
  description = "Name of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.name
}

output "log_group_app_arn" {
  description = "ARN of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.arn
}

output "log_group_ssm_name" {
  description = "Name of the SSM deploy CloudWatch log group"
  value       = aws_cloudwatch_log_group.ssm.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_arn : null
}

# Alarm ARNs
output "alarm_arns" {
  description = "Map of alarm names to ARNs"
  value = merge(
    {
      asg_cpu_high          = aws_cloudwatch_metric_alarm.asg_cpu_high.arn
      asg_instances_low     = aws_cloudwatch_metric_alarm.asg_instances_low.arn
      asg_status_check_failed = aws_cloudwatch_metric_alarm.asg_status_check_failed.arn
    },
    local.create_alb_alarms ? {
      alb_5xx_errors        = aws_cloudwatch_metric_alarm.alb_5xx_errors[0].arn
      alb_target_5xx_errors = aws_cloudwatch_metric_alarm.alb_target_5xx_errors[0].arn
      alb_latency_high      = aws_cloudwatch_metric_alarm.alb_latency_high[0].arn
      alb_unhealthy_hosts   = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts[0].arn
      alb_healthy_hosts_low = aws_cloudwatch_metric_alarm.alb_healthy_hosts_low[0].arn
    } : {},
    local.create_cloudfront_alarms ? {
      cloudfront_5xx_error_rate = aws_cloudwatch_metric_alarm.cloudfront_5xx_error_rate[0].arn
      cloudfront_4xx_error_rate = aws_cloudwatch_metric_alarm.cloudfront_4xx_error_rate[0].arn
    } : {}
  )
}
