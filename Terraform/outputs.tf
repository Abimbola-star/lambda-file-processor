# Output the API Gateway endpoint URL
output "api_endpoint" {
  description = "The HTTP API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.api_stage.invoke_url
}

# Output the Lambda function name
output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.file_processor.function_name
}