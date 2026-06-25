# -----------------------------------------------------------------------------
# Monitoring Module - Main
# CloudWatch Alarms, Dashboard, SNS for Landing Page ASG/ALB/CloudFront
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"
  
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "monitoring"
  })

  # Only create ALB alarms if ALB ARN suffix is provided
  create_alb_alarms = var.alb_arn_suffix != "" && var.target_group_arn_suffix != ""
  
  # Only create CloudFront alarms if distribution ID is provided
  create_cloudfront_alarms = var.cloudfront_distribution_id != ""
}

# -----------------------------------------------------------------------------
# SNS Topic for Alerts
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-monitoring-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.sns_email_endpoints)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Application
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/${local.name_prefix}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "ssm" {
  name              = "/ssm/deploy/${local.name_prefix}"
  retention_in_days = var.environment == "prod" ? 90 : 14
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# ASG Alarms
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${local.name_prefix}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "ASG CPU utilization above ${var.cpu_utilization_threshold}%"
  
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "asg_instances_low" {
  alarm_name          = "${local.name_prefix}-asg-instances-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Minimum"
  threshold           = var.asg_min_healthy_instances
  alarm_description   = "ASG has fewer than ${var.asg_min_healthy_instances} healthy instance(s)"
  
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "asg_status_check_failed" {
  alarm_name          = "${local.name_prefix}-asg-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "One or more ASG instances failed status check"
  
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# ALB Alarms (conditional)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count = local.create_alb_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "ALB 5xx errors exceeded ${var.alb_5xx_threshold}"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx_errors" {
  count = local.create_alb_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-target-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "Target 5xx errors exceeded ${var.alb_5xx_threshold}"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_latency_high" {
  count = local.create_alb_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.alb_latency_threshold
  alarm_description   = "ALB target response time exceeded ${var.alb_latency_threshold}s"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = local.create_alb_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.unhealthy_host_threshold
  alarm_description   = "Unhealthy hosts >= ${var.unhealthy_host_threshold}"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_healthy_hosts_low" {
  count = local.create_alb_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-healthy-hosts-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.asg_min_healthy_instances
  alarm_description   = "Healthy hosts below ${var.asg_min_healthy_instances}"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# CloudFront Alarms (conditional)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_error_rate" {
  count    = local.create_cloudfront_alarms ? 1 : 0
  provider = aws.us_east_1  # CloudFront metrics are in us-east-1

  alarm_name          = "${local.name_prefix}-cloudfront-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = var.cloudfront_error_rate_threshold
  alarm_description   = "CloudFront 5xx error rate exceeded ${var.cloudfront_error_rate_threshold}%"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    DistributionId = var.cloudfront_distribution_id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx_error_rate" {
  count    = local.create_cloudfront_alarms ? 1 : 0
  provider = aws.us_east_1

  alarm_name          = "${local.name_prefix}-cloudfront-4xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "CloudFront 4xx error rate exceeded 10%"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    DistributionId = var.cloudfront_distribution_id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
