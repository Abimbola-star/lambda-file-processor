# Create a Random Suffix for Uniqueness in S3 Bucket Name
resource "random_id" "suffix" {
  byte_length = 4
}


# Create an S3 Bucket for Uploading Files

resource "aws_s3_bucket" "upload_bucket" {
  bucket = "file-upload-dev-bucket-${random_id.suffix.hex}"  
  force_destroy = true 

  lifecycle {
    prevent_destroy = false           # Allows terraform destroy to delete bucket
    ignore_changes  = [tags]          # Ignores tag changes to prevent recreation
  }
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
  name = "lambda_exec_role"

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
}


# Attach Basic Execution Policy to Lambda Role

resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "lambda_basic_execution"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Attach CloudWatch Logging Permissions to Lambda Execution Role

resource "aws_iam_policy_attachment" "lambda_cloudwatch_logging" {
  name       = "lambda_cloudwatch_logging"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}


# Package Python Lambda Function into a .zip Archive

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.root}/lambda_function.py"  # Your uploaded function
  output_path = "${path.module}/lambda_function.zip"
}

# Define the Lambda Function

resource "aws_lambda_function" "file_processor" {
  function_name = "file-upload-handler"
  handler       = "lambda_function.lambda_handler"  # Entry point
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256  # Triggers update on code change
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

