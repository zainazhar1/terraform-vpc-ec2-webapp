terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.27 because security_groups.tf uses the separate
      # aws_vpc_security_group_ingress_rule/egress_rule resources,
      # which weren't added until that version.
      version = ">= 5.27.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      TestTag   = "test123"
    }
  }
}
