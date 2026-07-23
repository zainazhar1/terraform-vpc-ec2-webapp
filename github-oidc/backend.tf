terraform {
  backend "s3" {
    bucket         = "CHANGE-ME-state-bucket-name"    # same bucket as bootstrap/infra
    key            = "github-oidc/terraform.tfstate"  # different key -- no clash
    region         = "CHANGE-ME-region"
    dynamodb_table = "CHANGE-ME-lock-table-name"
    encrypt        = true
  }
}
