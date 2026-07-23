variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "github_repo" {
  description = <<-EOT
    GitHub "owner/repo" this role trusts, e.g.
    "zainazhar1/terraform-vpc-ec2-webapp". Must match exactly (case
    sensitive) -- this is the actual security boundary: only workflow
    runs from this exact repo can ever assume this role.
  EOT
  type = string
}

variable "state_bucket_name" {
  description = "Same S3 bucket used in infra/backend.tf."
  type        = string
}

variable "state_key" {
  description = "Same `key` used in infra/backend.tf."
  type        = string
  default     = "vpc-ec2-webapp/terraform.tfstate"
}

variable "dynamodb_table_name" {
  description = "Same DynamoDB table used in infra/backend.tf."
  type        = string
  default     = "terraform-locks"
}
