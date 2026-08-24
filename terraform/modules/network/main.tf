module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  intra_subnets   = var.intra_subnets

  # One NAT GW per AZ — eliminates cross-AZ traffic charges for egress
  enable_nat_gateway     = true
  single_nat_gateway     = !var.one_nat_gateway_per_az
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs to CloudWatch — required for security auditing
  enable_flow_log                      = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_log
  create_flow_log_cloudwatch_log_group = var.enable_flow_log
  flow_log_max_aggregation_interval    = var.flow_log_max_aggregation_interval

  public_subnet_tags = {
    # Required so the ALB controller can auto-discover subnets for internet-facing ALBs
    "kubernetes.io/role/elb" = 1
    "karpenter.sh/discovery" = var.cluster_name
  }

  private_subnet_tags = {
    # Required so the ALB controller can auto-discover subnets for internal ALBs
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}
