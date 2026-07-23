############################################################
# REMOTE BACKEND CONFIG
#
# This tells Terraform "don't store state as a local terraform.tfstate
# file -- store it in this S3 object instead, and use this DynamoDB
# table to lock it while an apply is in progress."
#
# IMPORTANT / A COMMON GOTCHA:
# Backend blocks can NOT reference variables, locals, or data sources.
# They are read before Terraform has evaluated any of that -- they're
# needed just to figure out *where the state itself lives*. So the
# values below have to be literal strings.
#
# Fill in the three values marked CHANGE-ME using the outputs from
# `terraform output` in the ../bootstrap folder, after you've applied
# that module once. See the root README for the full step-by-step.
############################################################

terraform {
  backend "s3" {
    bucket         = "zain-tfstate-vpc-ec2-webapp-2026" # bootstrap output: state_bucket_name
    key            = "vpc-ec2-webapp/terraform.tfstate" # path *within* the bucket -- lets one bucket hold state for many projects
    region         = "eu-west-2"                        # bootstrap output: aws_region
    dynamodb_table = "terraform-locks"                  # bootstrap output: dynamodb_table_name
    encrypt        = true
  }
}
