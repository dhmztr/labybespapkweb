# Alert kosztow
resource "aws_budgets_budget" "monthly_cost" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "2"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Filtr logow dla nieudanych prob logowania
resource "aws_cloudwatch_log_metric_filter" "failed_logins" {
  name           = "${var.project_name}-failed-logins"
  pattern        = "AUTH_FAILED"
  log_group_name = aws_cloudwatch_log_group.app.name

  metric_transformation {
    name      = "FailedLoginCount"
    namespace = "UnterApp/Security"
    value     = "1"
  }
}

# Alarm na serie nieudanych logowan
resource "aws_cloudwatch_metric_alarm" "brute_force_alarm" {
  alarm_name          = "${var.project_name}-failed-logins-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedLoginCount"
  namespace           = "UnterApp/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_description   = "Wykryto co najmniej 5 nieudanych prob logowania w ciagu 5 minut"
}

# Dashboard ze wszystkimi wymaganymi metrykami
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-monitoring"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "ECS Fargate - CPU i RAM (%)",
          region = var.aws_region,
          period = 60,
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "RDS PostgreSQL - CPU i wolne miejsce (Storage)",
          region = var.aws_region,
          period = 60,
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier],
            [".", "FreeStorageSpace", ".", ".", { yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "ALB - Liczba zadan i czas odpowiedzi",
          region = var.aws_region,
          period = 60,
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum" }],
            [".", "TargetResponseTime", ".", ".", { stat = "Average", yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "Bledy HTTP (4xx/5xx) i nieudane logowania",
          region = var.aws_region,
          period = 60,
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { stat = "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", ".", ".", { stat = "Sum" }],
            ["UnterApp/Security", "FailedLoginCount", { stat = "Sum" }]
          ]
        }
      }
    ]
  })
}
