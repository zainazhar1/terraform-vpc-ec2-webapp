#!/bin/bash
# This runs once, automatically, the first time the instance boots
# (EC2 calls this "user data"). It's how we get from "a blank Amazon
# Linux box" to "a box serving a web page" with no manual SSH step.
set -euxo pipefail

dnf update -y
dnf install -y nginx

# Fetch a couple of facts about the instance itself from the AWS
# metadata service, purely to prove (when you load the page) that
# you're hitting a real EC2 instance and not a cached/static file.
# This uses IMDSv2 (token-based) rather than the older IMDSv1, which
# AWS now recommends against because IMDSv1 has no request
# authentication and has been used in real-world SSRF attacks to
# steal instance credentials.
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Terraform VPC + EC2 demo</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 4rem auto; line-height: 1.5; }
    code { background: #f0f0f0; padding: 0.15rem 0.4rem; border-radius: 4px; }
  </style>
</head>
<body>
  <h1>It works.</h1>
  <p>This nginx server was provisioned entirely by Terraform: VPC, subnets,
     route tables, security groups, and this EC2 instance.</p>
  <p>Instance ID: <code>${INSTANCE_ID}</code></p>
  <p>Availability zone: <code>${AVAILABILITY_ZONE}</code></p>
</body>
</html>
HTML

systemctl enable nginx
systemctl start nginx
