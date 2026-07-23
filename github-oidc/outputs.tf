output "role_arn" {
  description = <<-EOT
    Copy this into GitHub: repo Settings -> Secrets and variables ->
    Actions -> Variables tab -> New repository variable, named
    AWS_ROLE_ARN. (A "variable," not a "secret" -- a role ARN isn't
    sensitive on its own; the whole point of OIDC is that nothing
    secret needs storing at all.)
  EOT
  value = aws_iam_role.github_actions_terraform_plan.arn
}
