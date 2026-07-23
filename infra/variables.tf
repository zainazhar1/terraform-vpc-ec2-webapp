variable "aws_region" {
  description = "AWS region to deploy into. Must match the region used for the backend."
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Short name used in resource names and tags."
  type        = string
  default     = "vpc-ec2-webapp"
}

# --------------------------------------------------------------
# Networking
# --------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the whole VPC."
  type        = string
  default     = "10.0.0.0/16" # ~65,536 addresses -- far more than we need, but it's the conventional default and leaves room to grow
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ). Instances here get a route to the internet via the Internet Gateway."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for the private subnets (one per AZ). Nothing runs here
    yet in this project -- they exist to demonstrate the public/private
    split you'd use for a real app (e.g. a database tier with no direct
    route to the internet). See the README for why we don't add a NAT
    Gateway here.
  EOT
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Must have at least as many entries as public/private_subnet_cidrs."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

# --------------------------------------------------------------
# Security
# --------------------------------------------------------------

variable "allowed_ssh_cidr" {
  description = <<-EOT
    CIDR allowed to SSH into the web instance, e.g. "203.0.113.7/32"
    (your own public IP -- check https://checkip.amazonaws.com).
    Deliberately has NO default: you must set this explicitly so you
    don't accidentally leave port 22 open to the entire internet.
  EOT
  type        = string
}

# --------------------------------------------------------------
# Compute
# --------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the web server."
  type        = string
  default     = "t3.micro" # eligible for the AWS free tier (t2.micro/t3.micro, 750 hrs/month for 12 months on a new account)
}

variable "key_name" {
  description = <<-EOT
    Name of an existing EC2 key pair (create one in the AWS console under
    EC2 > Key Pairs, or `aws ec2 create-key-pair`) used for SSH access.
  EOT
  type        = string
}
