# VPC + EC2 web app with Terraform remote state

Terraform-provisioned AWS networking (VPC, public + private subnets across
2 AZs, an Internet Gateway, route tables) and security groups, running an
EC2 instance that serves a static page via nginx. State is stored remotely
in S3 with DynamoDB-backed locking, instead of a local `terraform.tfstate`
file.

## Why this project exists

Anyone can `git clone` a Terraform example and run `apply` without
understanding a line of it. The point of this repo is the opposite: every
resource below is one I can explain the purpose of, not just paste. That's
the difference between "I've used Terraform" and "I understand what
Terraform is doing."

## Architecture

```
                          Internet
                             │
                      ┌──────┴──────┐
                      │  Internet   │
                      │  Gateway    │
                      └──────┬──────┘
                             │
          ┌──────────────────┴──────────────────┐
          │              Public route table       │
          │              (0.0.0.0/0 -> IGW)        │
          └───────────────────┬────────────────────┘
                               │
        ┌──────────────────────┴───────────────────────┐
        │                     VPC  10.0.0.0/16           │
        │  ┌───────────────────┐   ┌───────────────────┐ │
        │  │ Public subnet AZ-a │   │ Public subnet AZ-b │ │
        │  │ 10.0.1.0/24        │   │ 10.0.2.0/24        │ │
        │  │  ┌──────────────┐  │   │                    │ │
        │  │  │ EC2 (nginx)  │  │   │      (spare)       │ │
        │  │  │ SG: 80 open, │  │   │                    │ │
        │  │  │ 22 from you  │  │   │                    │ │
        │  │  └──────────────┘  │   │                    │ │
        │  └───────────────────┘   └───────────────────┘ │
        │  ┌───────────────────┐   ┌───────────────────┐ │
        │  │ Private subnet AZ-a│   │ Private subnet AZ-b│ │
        │  │ 10.0.101.0/24 (no  │   │ 10.0.102.0/24 (no  │ │
        │  │ internet route --  │   │ internet route --  │ │
        │  │ reserved for a     │   │ reserved for a     │ │
        │  │ future DB tier)    │   │ future DB tier)    │ │
        │  └───────────────────┘   └───────────────────┘ │
        └─────────────────────────────────────────────────┘
```

Remote state (separate from the diagram above -- this lives outside the
VPC, in your AWS account's S3/DynamoDB):

```
terraform apply (bootstrap/)  --creates-->  S3 bucket (versioned, encrypted, private)
                                             DynamoDB table (lock records)

terraform apply (infra/)  --reads/writes state via-->  S3 bucket + DynamoDB lock
```

## Why these design choices

**Two-tier subnet layout (public + private) even though nothing runs in
the private subnets yet.** A real app almost always needs a
public-facing tier and a private data tier that isn't directly reachable
from the internet. Building the split now, even unused, is what shows I
understand the pattern rather than just "a VPC with one subnet and an
instance in it."

**No NAT Gateway.** A NAT Gateway is what lets instances in a *private*
subnet reach the internet (e.g. to install packages) while still being
unreachable *from* the internet. It costs ~$0.045/hour (~$32/month) plus
data processing charges, running whether you use it or not. Since
nothing in the private subnets needs outbound internet access in this
project, adding one would just be burning money to look more
"complete." I've documented it here instead so it's clear this was a
deliberate cost decision, not an oversight.

**DynamoDB for locking, not just S3 versioning.** S3 versioning protects
you from losing data if state gets overwritten. It does nothing to
*prevent* two concurrent `apply` runs from racing each other in the
first place. DynamoDB's conditional writes give Terraform an atomic
"acquire lock / release lock" primitive, so a second `apply` against
the same state waits or fails cleanly instead of corrupting things.
(Terraform 1.10+ can now do locking natively via S3 conditional writes
without DynamoDB at all -- I used the DynamoDB pattern deliberately here
because it's still the most common setup in real codebases and the one
interviewers ask about.)

**SSH restricted to one IP, HTTP open to everyone.** Principle of least
privilege: port 80 has to be open to the world because that's the
product. Port 22 has no reason to be reachable by anyone except the one
person administering the box, so it isn't.

**IMDSv2 enforced (`http_tokens = "required"`).** The EC2 instance
metadata service is how the box discovers things like its own instance
ID. The older version (IMDSv1) had no request authentication, which has
been exploited in real SSRF attacks (an attacker who can make the
server issue an arbitrary HTTP request tricks it into fetching its own
credentials from the metadata endpoint). IMDSv2 requires a
session token first, closing that hole. This is a one-line change and a
very commonly asked "how do you harden EC2" interview question.

## Prerequisites

- An AWS account (the [free tier](https://aws.amazon.com/free/) covers
  a `t3.micro`/`t2.micro` instance for 750 hours/month for the first 12
  months, and S3/DynamoDB usage here is negligible).
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  installed and configured (`aws configure`) with credentials that can
  create VPCs, EC2 instances, S3 buckets, DynamoDB tables, and IAM-free
  resources.
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
- An EC2 key pair in the region you're deploying to (EC2 console > Key
  Pairs > Create key pair, or `aws ec2 create-key-pair --key-name my-key
  --query 'KeyMaterial' --output text > my-key.pem && chmod 400 my-key.pem`).

## How to run it

### 1. Bootstrap the remote state backend (once)

```bash
cd bootstrap
terraform init
terraform apply -var="bucket_name=YOUR-UNIQUE-BUCKET-NAME"
```

Note the outputs (`state_bucket_name`, `dynamodb_table_name`,
`aws_region`) -- you need them in the next step.

### 2. Point the main infra at that backend

Edit `infra/backend.tf` and replace the three `CHANGE-ME` values with
the outputs from step 1.

### 3. Deploy the VPC + EC2 instance

```bash
cd ../infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set allowed_ssh_cidr to YOUR_IP/32 and key_name
# to the key pair you created above

terraform init      # downloads the aws provider, connects to the S3 backend
terraform plan      # review what will be created before you commit to it
terraform apply
```

After apply finishes, `terraform output web_url` gives you the address
-- open it in a browser (give nginx ~30-60 seconds to finish installing
via user_data on first boot).

### 4. SSH in (optional)

```bash
ssh -i my-key.pem ec2-user@$(terraform output -raw web_public_ip)
```

## Cost note

Everything here is designed to sit inside or very close to the AWS free
tier for a new-ish account:

| Resource | Approx. cost |
|---|---|
| EC2 `t3.micro` | Free tier: 750 hrs/month for 12 months. After that, ~$0.0104/hr (eu-west-2) |
| S3 bucket (state file, a few KB) | Effectively $0 |
| DynamoDB table (pay-per-request, a handful of ops per apply) | Effectively $0 |
| VPC, subnets, route tables, IGW, security groups | Free -- no charge for the networking constructs themselves |

The only way this project costs meaningful money is leaving the EC2
instance running long-term after the free tier expires, or adding
things like a NAT Gateway or Elastic IP (not used here).

## Tearing it down

**Destroy the infra stack first, then the bootstrap stack** (the infra
stack's *state* lives in the bootstrap stack's bucket, so tearing down
bootstrap first would strand it):

```bash
cd infra
terraform destroy

cd ../bootstrap
# the S3 bucket has `prevent_destroy = true` as a safety net -- if you
# genuinely want to remove it, comment out that lifecycle block first
terraform destroy
```

Afterwards, double check in the AWS console (EC2 > Instances, VPC >
Your VPCs, S3, DynamoDB) that nothing's left running. It's good practice
to do this after every teardown, not just trust the CLI output.

## What I'd add next (and why I didn't build it in from the start)

- **Application Load Balancer + Auto Scaling Group** instead of a single
  instance -- the natural next step for real availability, deliberately
  left out here to keep this project focused on the networking
  fundamentals rather than compute-tier HA patterns.
- **HTTPS via ACM + an ALB** -- needs a domain name to issue a cert
  against, so out of scope for a demo without one.
- **SSM Session Manager instead of SSH** -- would let you remove the
  port-22 security group rule entirely and manage the instance without
  any open inbound port or key-pair management. Left as SSH here
  because it's the more universally-understood mechanism for a first
  project, but worth mentioning live in an interview as the more modern
  alternative.

## This project on my CV

> Provisioned AWS VPC/EC2 infrastructure with Terraform, using S3/DynamoDB
> for remote state management.

Everything that line implies -- subnetting, routing, security groups,
locking-safe shared state -- is backed by an actual, explainable decision
above, not a template I ran once.
