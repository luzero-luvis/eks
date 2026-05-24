locals {
  name   = var.cluster_name
  region = var.aws_region

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # /20 private subnets (~4k IPs each) — generous for node + pod IPs with prefix delegation
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  # /24 public subnets — only for NAT GW and internet-facing ALBs
  public_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  # /28 intra subnets — EKS control-plane ENIs, no route to internet
  intra_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 52)]

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}
