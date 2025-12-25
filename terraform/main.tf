terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Backend config will be provided via -backend-config flag
  }
}

provider "aws" {
  region = var.aws_region
}

# DynamoDB Table
resource "aws_dynamodb_table" "counter_table" {
  name           = "${var.environment}-task-counter"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = "task-counter-cicd"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.environment}-task-counter-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = var.environment
  }
}

# IAM Policy for Lambda to access DynamoDB
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.environment}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.counter_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Package Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/task_counter"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda Function
resource "aws_lambda_function" "task_counter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.environment}-task-counter"
  role            = aws_iam_role.lambda_role.arn
  handler         = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 10

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.counter_table.name
      ENVIRONMENT         = var.environment
    }
  }

  tags = {
    Environment = var.environment
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.task_counter.function_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "task_counter_api" {
  name        = "${var.environment}-task-counter-api"
  description = "Task Counter API for ${var.environment}"

  tags = {
    Environment = var.environment
  }
}

# API Gateway Resource
resource "aws_api_gateway_resource" "counter_resource" {
  rest_api_id = aws_api_gateway_rest_api.task_counter_api.id
  parent_id   = aws_api_gateway_rest_api.task_counter_api.root_resource_id
  path_part   = "counter"
}

# API Gateway Method - GET
resource "aws_api_gateway_method" "get_counter" {
  rest_api_id   = aws_api_gateway_rest_api.task_counter_api.id
  resource_id   = aws_api_gateway_resource.counter_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Method - POST
resource "aws_api_gateway_method" "post_counter" {
  rest_api_id   = aws_api_gateway_rest_api.task_counter_api.id
  resource_id   = aws_api_gateway_resource.counter_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration - GET
resource "aws_api_gateway_integration" "get_lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.task_counter_api.id
  resource_id             = aws_api_gateway_resource.counter_resource.id
  http_method             = aws_api_gateway_method.get_counter.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.task_counter.invoke_arn
}

# API Gateway Integration - POST
resource "aws_api_gateway_integration" "post_lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.task_counter_api.id
  resource_id             = aws_api_gateway_resource.counter_resource.id
  http_method             = aws_api_gateway_method.post_counter.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.task_counter.invoke_arn
}

# Lambda permission for API Gateway - GET
resource "aws_lambda_permission" "apigw_get_lambda" {
  statement_id  = "AllowAPIGatewayInvokeGET"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.task_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.task_counter_api.execution_arn}/*/*"
}

# Lambda permission for API Gateway - POST
resource "aws_lambda_permission" "apigw_post_lambda" {
  statement_id  = "AllowAPIGatewayInvokePOST"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.task_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.task_counter_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "task_counter_deployment" {
  depends_on = [
    aws_api_gateway_integration.get_lambda_integration,
    aws_api_gateway_integration.post_lambda_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.task_counter_api.id
  stage_name  = var.environment
}

# S3 Bucket for Frontend
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.environment}-task-counter-frontend-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "frontend_bucket_pab" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Website Configuration
resource "aws_s3_bucket_website_configuration" "frontend_bucket_website" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# S3 Bucket Policy for Public Read
resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend_bucket_pab]
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}