terraform {
  backend "s3" {
    bucket         = "zain-tfstate-vpc-ec2-webapp-2026" # bootstrap output: state_bucket_name
    key            = "github-oidc/terraform.tfstate" # path *within* the bucket -- lets one bucket hold state for many projects
    region         = "eu-west-2"                        # bootstrap output: aws_region
    dynamodb_table = "terraform-locks"                  # bootstrap output: dynamodb_table_name
    encrypt        = true
  }
}