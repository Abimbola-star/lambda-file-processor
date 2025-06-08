output "s3_bucket_name" {
  value = aws_s3_bucket.upload_bucket.bucket
}

output "api_url" {
  value = aws_apigatewayv2_api.lambda_api.api_endpoint
}
