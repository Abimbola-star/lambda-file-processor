# Create a Random Suffix for Uniqueness in S3 Bucket Name
resource "random_id" "suffix" {
  byte_length = 4
  # Keep the same random ID even when other attributes change
  keepers = {
    # This value should remain the same across all environments
    app_name = "file-processor"
  }
}


# Create an S3 Bucket for Uploading Files

resource "aws_s3_bucket" "upload_bucket" {
  bucket = "file-upload-dev-bucket-${random_id.suffix.hex}"  
  force_destroy = true 

  lifecycle {
    prevent_destroy = false           # Allows terraform destroy to delete bucket
    ignore_changes  = [tags, versioning, website, acceleration_status]  # Ignores various configuration changes
  }
}

resource "aws_s3_bucket_public_access_block" "upload_bucket_public_access" {
  bucket = aws_s3_bucket.upload_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.upload_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.upload_bucket.arn}/*"
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.upload_bucket_public_access]
}

# Allow S3 to Invoke the Lambda Function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload_bucket.arn
}

# Setup S3 Event Notification to Trigger Lambda on File Upload
resource "aws_s3_bucket_notification" "s3_lambda_trigger" {
  bucket = aws_s3_bucket.upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_processor.arn  # Lambda to trigger
    events              = ["s3:ObjectCreated:*"]  # Trigger on any file upload
  }

  depends_on = [aws_lambda_permission.allow_s3]  # Ensure Lambda permission is set first
}

# IAM Role for Lambda with Trust Relationship Policy

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role_${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"  # Allows Lambda to assume this role
      }
    }]
  })
  
  # Force IAM role creation to complete before use
  provisioner "local-exec" {
    command = "sleep 10"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}


# Attach Basic Execution Policy to Lambda Role

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  depends_on = [aws_iam_role.lambda_exec_role]
}


# Attach CloudWatch Logging Permissions to Lambda Execution Role

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logging" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  depends_on = [aws_iam_role.lambda_exec_role]
}


# Package Python Lambda Function into a .zip Archive

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.root}/lambda_function.py"  # Your uploaded function
  output_path = "${path.module}/lambda_function.zip"
}

# Define the Lambda Function

resource "aws_lambda_function" "file_processor" {
  function_name = "file-upload-handler-${random_id.suffix.hex}"
  handler       = "lambda_function.lambda_handler"  # Entry point
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256  # Triggers update on code change
  publish       = false  # Don't publish versions
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to versions
      version, last_modified, qualified_arn
    ]
  }
}


# Create API Gateway HTTP API (v2)

resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "lambda-api"
  protocol_type = "HTTP"
}


# Allow API Gateway to Invoke the Lambda Function

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"  # Allow all routes/stages
}


# Define API Gateway → Lambda Integration

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                    = aws_apigatewayv2_api.lambda_api.id
  integration_type          = "AWS_PROXY"  # Lambda proxy integration
  integration_uri           = aws_lambda_function.file_processor.invoke_arn
  integration_method        = "POST"
  payload_format_version    = "2.0"
}


# Define the HTTP Route (POST /upload)

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id = aws_apigatewayv2_api.lambda_api.id
  route_key = "ANY /process"  # HTTP POST to /upload
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}


# Enable and Auto-Deploy the Default Stage for API Gateway

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.lambda_api.id
  name        = "$default"  # Use default stage
  auto_deploy = true        # Automatically deploy new changes
}

