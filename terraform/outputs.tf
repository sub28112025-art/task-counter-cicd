output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_deployment.task_counter_deployment.invoke_url}/counter"
}

output "s3_bucket_name" {
  description = "S3 bucket name for frontend"
  value       = aws_s3_bucket.frontend_bucket.id
}

output "s3_website_url" {
  description = "S3 website endpoint"
  value       = aws_s3_bucket_website_configuration.frontend_bucket_website.website_endpoint
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.counter_table.name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.task_counter.function_name
}