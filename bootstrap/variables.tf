variable "aws_region" {
  description = "AWS region to create the state bucket + lock table in."
  type        = string
  default     = "eu-west-2" # London -- change if you want a different region
}

variable "bucket_name" {
  description = <<-EOT
    Globally-unique S3 bucket name for Terraform remote state.
    S3 bucket names are unique across ALL AWS accounts worldwide, not just
    yours -- "my-terraform-state" is almost certainly already taken by
    someone else. Include your name/handle and a random-ish suffix, e.g.
    "sajit-tfstate-vpc-ec2-2026".
  EOT
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string
  default     = "terraform-locks"
}

variable "project_name" {
  description = "Tag value used to identify resources belonging to this project."
  type        = string
  default     = "vpc-ec2-webapp"
}
