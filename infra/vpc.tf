############################################################
# NETWORKING
#
# The mental model for a VPC:
#   - A VPC is your own private slice of AWS's network, defined by a
#     CIDR range (here 10.0.0.0/16 -- i.e. every address from
#     10.0.0.0 to 10.0.255.255, ~65k addresses).
#   - You carve that range into SUBNETS, each pinned to one
#     Availability Zone (AZ) -- a physically distinct datacenter.
#     Spreading subnets across 2+ AZs is what lets you survive one
#     datacenter having a bad day.
#   - A subnet is "public" purely by convention: it's public because
#     its ROUTE TABLE sends 0.0.0.0/0 (i.e. "anything not in the VPC")
#     to an Internet Gateway. A subnet with no such route is private.
#   - None of this makes anything internet-*accessible* by itself --
#     that's what security groups (security_groups.tf) control. A
#     public subnet just means traffic CAN reach the internet; the
#     security group decides what's actually allowed in/out.
############################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required if you ever want EC2 instances to get a resolvable public DNS name

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# --------------------------------------------------------------
# Internet Gateway -- the VPC's single door to/from the public
# internet. One per VPC, attached (not "created inside") the VPC.
# --------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# --------------------------------------------------------------
# Public subnets -- one per AZ, from var.public_subnet_cidrs.
# `count` here loops this resource block once per list element,
# so `aws_subnet.public[0]`, `aws_subnet.public[1]`, etc. get created.
# --------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # instances launched here get a public IP automatically

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# --------------------------------------------------------------
# Private subnets -- reserved for a future app/DB tier. Nothing is
# deployed into these in this project (see README for why we skip
# a NAT Gateway), but they exist so the networking story is complete
# and honestly represents "public web tier / private data tier".
# --------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# --------------------------------------------------------------
# Public route table: send all non-VPC-local traffic (0.0.0.0/0) to
# the Internet Gateway. Associated with every public subnet.
# --------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------
# Private route table: deliberately has NO route to the internet --
# only the default "local" route every VPC route table gets for
# free, which lets resources talk to other things inside the VPC.
# That absence of a 0.0.0.0/0 route is what makes this subnet
# "private". (A real private-tier-with-outbound-internet setup would
# add a NAT Gateway here -- skipped in this project to avoid its
# ~$32/month cost; see README.)
# --------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
