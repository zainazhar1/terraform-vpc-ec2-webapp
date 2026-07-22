output "state_bucket_name" {
  description = "Plug this into infra/backend.tf as `bucket`."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "Plug this into infra/backend.tf as `dynamodb_table`."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_region" {
  description = "Plug this into infra/backend.tf as `region`."
  value       = var.aws_region
}
