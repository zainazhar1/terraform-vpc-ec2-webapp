############################################################
# SECURITY GROUPS
#
# A security group is a stateful virtual firewall attached to an
# instance (well, technically its network interface). "Stateful"
# means: if you allow inbound traffic on a port, the RESPONSE traffic
# is automatically allowed back out -- you don't need a matching
# egress rule for replies.
#
# Principle applied here: only open what's actually needed.
#   - Port 80 (HTTP) open to the whole internet, because that's the
#     entire point of a public web app.
#   - Port 22 (SSH) open ONLY to your own IP (var.allowed_ssh_cidr),
#     because there's no reason anyone else on the internet should
#     even be able to attempt an SSH connection to this box.
############################################################

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP from anywhere and SSH only from the operator IP"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.web.id
  description       = "SSH restricted to the operator IP only"
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Egress: allow all outbound. The instance needs this to reach the
# internet for OS package updates (yum/dnf) during the user_data
# bootstrap script that installs nginx.
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.web.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # -1 = all protocols
}
