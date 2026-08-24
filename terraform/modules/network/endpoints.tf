# ── VPC endpoints ────────────────────────────────────────────────────────────
# Keeps AWS API traffic on the AWS network instead of routing it out through the
# NAT gateway. Two very different cost profiles:
#
#   Gateway endpoints (S3)  — free. Always worth enabling: ECR image layers are
#                             stored in S3, so this removes the largest single
#                             source of NAT data-processing charges.
#   Interface endpoints     — $0.01/hr per AZ each (~$7.30/month/AZ, so ~$22/month
#                             per service across 3 AZs) plus $0.01/GB. Worth it
#                             when NAT data-processing ($0.045/GB) on that service
#                             exceeds the hourly cost, or when you want image
#                             pulls and IRSA to survive the loss of the NAT's AZ.
locals {
  create_endpoints = var.enable_s3_endpoint || length(var.interface_endpoints) > 0

  s3_endpoint = var.enable_s3_endpoint ? {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${var.name}-s3" }
    }
  } : {}

  interface_endpoints = {
    for service in var.interface_endpoints : service => {
      service             = service
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "${var.name}-${service}" }
    }
  }
}

# Interface endpoints terminate as ENIs in the private subnets and only ever
# receive HTTPS from inside the VPC.
resource "aws_security_group" "vpc_endpoints" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from within the VPC to interface VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpc-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from the VPC"

  cidr_ipv4   = module.vpc.vpc_cidr_block
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  create = local.create_endpoints

  vpc_id             = module.vpc.vpc_id
  security_group_ids = length(var.interface_endpoints) > 0 ? [aws_security_group.vpc_endpoints[0].id] : []

  endpoints = merge(local.s3_endpoint, local.interface_endpoints)

  tags = var.tags
}
