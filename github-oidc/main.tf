############################################################
# GITHUB ACTIONS OIDC
#
# Lets GitHub Actions authenticate to AWS without ever storing a
# long-lived AWS access key as a GitHub secret.
#
# How it works: GitHub's Actions runner can mint a short-lived,
# cryptographically signed identity token for the specific workflow
# run in progress (which repo, which event triggered it, who kicked
# it off). AWS can be told to trust tokens signed by GitHub (the OIDC
# provider below), and to hand out temporary AWS credentials to any
# token matching a specific pattern (the IAM role's trust policy
# below) -- in this case, "only requests coming from a pull_request
# run on this exact repo." No secret is ever generated, copied into
# GitHub, or sitting around waiting to leak.
#
# Run this ONCE PER AWS ACCOUNT, not once per project. AWS only
# allows a single OIDC provider per unique provider URL -- if you've
# already created one (e.g. setting up CI for a different repo later),
# creating a second aws_iam_openid_connect_provider for the same URL
# will fail with "EntityAlreadyExists". In that case, delete the
# provider resource block below and reference the existing one with a
# data source instead:
#   data "aws_iam_openid_connect_provider" "github_actions" {
#     url = "https://token.actions.githubusercontent.com"
#   }
# and add a new aws_iam_role (with its own trust policy for the new
# repo) underneath it.
############################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.27.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # No thumbprint_list: as of AWS provider v5.47+, AWS validates
  # GitHub's certificate against its own trusted CA store instead of a
  # thumbprint you supply, and the argument became fully optional.
  # Omitting it avoids hardcoding a value that can go stale (or, as
  # happened while building this, be transcribed one character short).
}

# Trust policy: WHO is allowed to assume this role, and under what
# conditions. This is the actual security boundary -- get this wrong
# and either nobody can use it, or (much worse) more than you intended
# can.
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect = "Allow"
    # sts:TagSession is required alongside sts:AssumeRoleWithWebIdentity
    # because aws-actions/configure-aws-credentials attaches several
    # pieces of GitHub context (repo, workflow, actor, ref, etc.) as
    # IAM role session tags by default. Without this, AWS rejects the
    # whole combined call with a vague "not authorized to perform
    # sts:AssumeRoleWithWebIdentity" error.
    actions = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    # "aud" (audience) must always be sts.amazonaws.com for AWS OIDC.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope to THIS repo, pull_request events only, via the `sub`
    # claim. AWS REQUIRES a GitHub-OIDC trust policy to condition on
    # `sub` (or `job_workflow_ref`) -- it rejects a policy scoped only
    # on other claims like `repository`. So `sub` it is.
    #
    # Two patterns, because as of 15 July 2026 GitHub embeds immutable
    # numeric IDs in `sub` for newly-created repos:
    #   classic:  repo:owner/repo:pull_request
    #   new:      repo:owner@<orgid>/repo@<repoid>:pull_request
    # StringLike (not StringEquals) so the "*" wildcards match whatever
    # those numeric IDs are. This is the ONLY condition on `sub` --
    # do not also add a StringEquals on the same key, or AWS will
    # require both to match at once (impossible) and every assume-role
    # call fails with a misleading "not authorized" error.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:pull_request",
        "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_terraform_plan" {
  name               = "github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = {
    Purpose = "github-actions-oidc"
  }
}

# WHAT the role can actually do, once assumed. AWS's managed
# ReadOnlyAccess policy covers every `Describe`/`Get`/`List` call
# `terraform plan` needs to compare your code against real
# infrastructure -- but deliberately nothing that could change
# anything. This is intentionally much narrower than the
# AdministratorAccess your own local IAM user has: your laptop gets
# broad access for convenience while you're learning; CI only ever
# gets enough to show you a diff. That asymmetry -- humans apply,
# automation only plans -- is worth being able to explain unprompted.
resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.github_actions_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess alone isn't quite enough: reading and locking
# Terraform's OWN state file needs a couple of write-shaped calls
# (writing a lock record is, mechanically, a DynamoDB write) --
# scoped to only the specific state object and lock table, nothing
# else.
data "aws_iam_policy_document" "state_access" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.state_bucket_name}/${var.state_key}",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }

  statement {
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}",
    ]
  }
}

resource "aws_iam_role_policy" "state_access" {
  name   = "terraform-state-access"
  role   = aws_iam_role.github_actions_terraform_plan.id
  policy = data.aws_iam_policy_document.state_access.json
}
