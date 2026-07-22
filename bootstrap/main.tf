############################################################
# BOOTSTRAP MODULE
#
# This is a separate, tiny Terraform root module whose only job is to
# create the S3 bucket + DynamoDB table that the REAL infrastructure
# (in ../infra) will use as its "remote backend" for state storage
# and locking.
#
# WHY THIS HAS TO BE SEPARATE:
# Terraform can't use an S3 bucket as its backend until that bucket
# exists. If you tried to define the bucket AND tell Terraform to
# store its state in that same bucket in one go, you'd have a
# chicken-and-egg problem on the very first `terraform init`.
#
# So the pattern (used in almost every real Terraform codebase) is:
#   1. Run this bootstrap module first, with its state kept LOCALLY
#      (a terraform.tfstate file on your own disk, just this once).
#   2. Once the bucket + table exist, point the main `infra` module's
#      backend config at them, and every future `terraform apply`
#      for the real infrastructure stores its state remotely.
#
# You only ever run `terraform apply` in THIS folder once (or when
# you deliberately change something about the state backend itself).
############################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Deliberately NO backend block here -> state for this module stays
  # local, in bootstrap/terraform.tfstate. That file is small and
  # only matters to you personally, so it's fine (even good practice)
  # for it to live on your own machine rather than shared remotely.
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------------------------------------------
# S3 bucket to hold *.tfstate files for every other project/module.
# ----------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  # Belt-and-braces: even if someone runs `terraform destroy` against
  # this bootstrap stack by mistake, refuse to delete a bucket that
  # might be holding the only copy of your infrastructure's state.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project     = var.project_name
    Purpose     = "terraform-remote-state"
    ManagedBy   = "terraform"
  }
}

# Versioning means every write to the state file keeps its previous
# version. If a bad `apply` corrupts your state, you can roll back to
# the last good version from the S3 console instead of losing it.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State files can contain sensitive values (e.g. DB passwords set via
# a resource argument). Encrypt them at rest by default.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nobody should ever need this bucket to be public. Block every
# public-access mechanism S3 supports, explicitly, rather than relying
# on the account-level default.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------------------
# DynamoDB table used purely for state LOCKING (not to store state
# itself -- that's the S3 bucket's job).
#
# Locking matters because Terraform state is a single shared file.
# If two people (or two CI jobs) ran `terraform apply` on the same
# state at the same moment with no locking, they could both read the
# old state, both compute a plan, and both write conflicting results
# back -- silently corrupting the state file. DynamoDB gives
# Terraform a "who's currently holding the lock" record, backed by
# DynamoDB's strongly-consistent conditional writes, so the second
# apply just waits / errors instead of racing the first.
# ----------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # no fixed hourly cost -- you only
                                    # pay for the handful of reads/writes
                                    # that happen during each apply
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = var.project_name
    Purpose   = "terraform-state-locking"
    ManagedBy = "terraform"
  }
}
