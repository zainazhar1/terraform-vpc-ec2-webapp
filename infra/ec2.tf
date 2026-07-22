############################################################
# EC2 INSTANCE
############################################################

# Rather than hardcoding an AMI ID (which is region-specific and goes
# stale), look up the latest Amazon Linux 2023 AMI at apply-time.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id # lands in the first public subnet/AZ
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = var.key_name

  # Runs once on first boot -- see user_data.sh for what it does.
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true # if you edit user_data.sh, `terraform apply` will replace the instance so the new script actually runs

  metadata_options {
    http_tokens = "required" # force IMDSv2 -- refuse the older, unauthenticated IMDSv1 metadata requests
  }

  tags = {
    Name = "${var.project_name}-web"
  }
}
