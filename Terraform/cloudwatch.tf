
# Optional SNS Topic for Alerts

resource "aws_sns_topic" "lambda_alerts" {
  name = "lambda-error-alerts-topic"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.lambda_alerts.arn
  protocol  = "email"
  endpoint  = "your_email@example.com" # <-- Change to your real email
}


# CloudWatch Alarm: Lambda Error Threshold

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "LambdaErrorAlarm"
  alarm_description   = "Triggers if there are any Lambda function errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  dimensions = {
    FunctionName = aws_lambda_function.file_processor.function_name
  }

  alarm_actions = [aws_sns_topic.lambda_alerts.arn] # Send notification via SNS
}


# CloudWatch Alarm: Lambda Duration > 3 sec

resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  alarm_name          = "LambdaDurationAlarm"
  alarm_description   = "Triggers if average Lambda duration exceeds 3s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Average"
  threshold           = 3000 # milliseconds
  dimensions = {
    FunctionName = aws_lambda_function.file_processor.function_name
  }

  alarm_actions = [aws_sns_topic.lambda_alerts.arn]
}
