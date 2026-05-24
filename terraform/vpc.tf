module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  # One NAT GW per AZ — eliminates cross-AZ traffic charges for egress
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs to CloudWatch — required for security auditing
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_max_aggregation_interval    = 60

  public_subnet_tags = {
    # Required so the ALB controller can auto-discover subnets for internet-facing ALBs
    "kubernetes.io/role/elb"             = 1
    "karpenter.sh/discovery"             = local.name
  }

  private_subnet_tags = {
    # Required so the ALB controller can auto-discover subnets for internal ALBs
    "kubernetes.io/role/internal-elb"    = 1
    "karpenter.sh/discovery"             = local.name
  }

  tags = {
    Name = "${local.name}-vpc"
  }
}
