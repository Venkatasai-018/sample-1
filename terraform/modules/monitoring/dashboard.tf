# -----------------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-monitoring"
  dashboard_body = jsonencode({
    widgets = concat(
      # Header
      [
        {
          type   = "text"
          x      = 0
          y      = 0
          width  = 24
          height = 1
          properties = {
            markdown = "# ${var.project} - ${upper(var.environment)} Environment Monitoring"
          }
        }
      ],
      
      # ASG Widgets
      [
        {
          type   = "metric"
          x      = 0
          y      = 1
          width  = 8
          height = 6
          properties = {
            title  = "ASG Instance Count"
            region = var.aws_region
            metrics = [
              ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name, { label = "InService" }],
              [".", "GroupDesiredCapacity", ".", ".", { label = "Desired" }],
              [".", "GroupMinSize", ".", ".", { label = "Min" }],
              [".", "GroupMaxSize", ".", ".", { label = "Max" }]
            ]
            stat   = "Average"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = 1
          width  = 8
          height = 6
          properties = {
            title  = "ASG CPU Utilization"
            region = var.aws_region
            metrics = [
              ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]
            ]
            stat   = "Average"
            period = 60
            annotations = {
              horizontal = [
                {
                  label = "Alarm Threshold"
                  value = var.cpu_utilization_threshold
                  color = "#ff0000"
                }
              ]
            }
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = 1
          width  = 8
          height = 6
          properties = {
            title  = "ASG Network I/O"
            region = var.aws_region
            metrics = [
              ["AWS/EC2", "NetworkIn", "AutoScalingGroupName", var.asg_name, { label = "Network In" }],
              [".", "NetworkOut", ".", ".", { label = "Network Out" }]
            ]
            stat   = "Sum"
            period = 60
          }
        }
      ],
      
      # ALB Widgets (if ALB configured)
      local.create_alb_alarms ? [
        {
          type   = "metric"
          x      = 0
          y      = 7
          width  = 8
          height = 6
          properties = {
            title  = "ALB Request Count"
            region = var.aws_region
            metrics = [
              ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]
            ]
            stat   = "Sum"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = 7
          width  = 8
          height = 6
          properties = {
            title  = "ALB Target Response Time"
            region = var.aws_region
            metrics = [
              ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p50", label = "p50" }],
              ["...", { stat = "p90", label = "p90" }],
              ["...", { stat = "p99", label = "p99" }]
            ]
            period = 60
            annotations = {
              horizontal = [
                {
                  label = "Threshold"
                  value = var.alb_latency_threshold
                  color = "#ff0000"
                }
              ]
            }
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = 7
          width  = 8
          height = 6
          properties = {
            title  = "ALB HTTP Responses"
            region = var.aws_region
            metrics = [
              ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { label = "2xx", color = "#2ca02c" }],
              [".", "HTTPCode_Target_4XX_Count", ".", ".", ".", ".", { label = "4xx", color = "#ff7f0e" }],
              [".", "HTTPCode_Target_5XX_Count", ".", ".", ".", ".", { label = "5xx", color = "#d62728" }],
              [".", "HTTPCode_ELB_5XX_Count", ".", ".", { label = "ELB 5xx", color = "#9467bd" }]
            ]
            stat   = "Sum"
            period = 60
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 13
          width  = 8
          height = 6
          properties = {
            title  = "ALB Healthy/Unhealthy Hosts"
            region = var.aws_region
            metrics = [
              ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { label = "Healthy", color = "#2ca02c" }],
              [".", "UnHealthyHostCount", ".", ".", ".", ".", { label = "Unhealthy", color = "#d62728" }]
            ]
            stat   = "Average"
            period = 60
          }
        }
      ] : [],
      
      # CloudFront Widgets (if CloudFront configured)
      local.create_cloudfront_alarms ? [
        {
          type   = "metric"
          x      = 8
          y      = 13
          width  = 8
          height = 6
          properties = {
            title  = "CloudFront Requests"
            region = "us-east-1"
            metrics = [
              ["AWS/CloudFront", "Requests", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]
            ]
            stat   = "Sum"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = 13
          width  = 8
          height = 6
          properties = {
            title  = "CloudFront Error Rates"
            region = "us-east-1"
            metrics = [
              ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global", { label = "4xx %", color = "#ff7f0e" }],
              [".", "5xxErrorRate", ".", ".", ".", ".", { label = "5xx %", color = "#d62728" }]
            ]
            stat   = "Average"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 19
          width  = 12
          height = 6
          properties = {
            title  = "CloudFront Cache Hit Rate"
            region = "us-east-1"
            metrics = [
              ["AWS/CloudFront", "CacheHitRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]
            ]
            stat   = "Average"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 19
          width  = 12
          height = 6
          properties = {
            title  = "CloudFront Bytes Downloaded"
            region = "us-east-1"
            metrics = [
              ["AWS/CloudFront", "BytesDownloaded", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]
            ]
            stat   = "Sum"
            period = 300
          }
        }
      ] : [],
      
      # Alarm Status Widget
      [
        {
          type   = "alarm"
          x      = 0
          y      = 25
          width  = 24
          height = 4
          properties = {
            title  = "Alarm Status"
            alarms = compact([
              aws_cloudwatch_metric_alarm.asg_cpu_high.arn,
              aws_cloudwatch_metric_alarm.asg_instances_low.arn,
              aws_cloudwatch_metric_alarm.asg_status_check_failed.arn,
              local.create_alb_alarms ? aws_cloudwatch_metric_alarm.alb_5xx_errors[0].arn : "",
              local.create_alb_alarms ? aws_cloudwatch_metric_alarm.alb_unhealthy_hosts[0].arn : "",
              local.create_cloudfront_alarms ? aws_cloudwatch_metric_alarm.cloudfront_5xx_error_rate[0].arn : ""
            ])
          }
        }
      ]
    )
  })
}
