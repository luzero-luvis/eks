# ─────────────────────────────────────────────────────────────────────────────
# Cluster composition. Every AWS-level concern lives in ./modules/<name>;
# this file only wires them together and owns the ordering between them.
#
#   network            VPC, subnets, NAT, flow logs
#   eks-control-plane  the cluster itself
#   eks-addons         EKS managed add-ons (twice — see the ordering note below)
#   eks-managed-node-group  fixed system nodes
#   irsa               one IAM role per workload identity
#   karpenter          IAM/SQS + controller + EC2NodeClass/NodePool
# ─────────────────────────────────────────────────────────────────────────────

module "network" {
  source = "./modules/network"

  name         = "${local.name}-vpc"
  cluster_name = local.name
  cidr         = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_s3_endpoint  = var.enable_s3_endpoint
  interface_endpoints = var.interface_endpoints

  tags = local.common_tags
}

module "eks_control_plane" {
  source = "./modules/eks-control-plane"

  cluster_name       = local.name
  kubernetes_version = var.cluster_version

  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.private_subnets
  control_plane_subnet_ids = module.network.intra_subnets

  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  node_security_group_additional_rules = {
    # Nodes need to talk to each other for pod-to-pod traffic
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  tags = merge(local.common_tags, {
    # Karpenter uses this tag to discover the cluster's security groups
    "karpenter.sh/discovery" = local.name
  })
}

# ── Workload identities ──────────────────────────────────────────────────────

module "ebs_csi_irsa" {
  source = "./modules/irsa"

  name                       = "${local.name}-ebs-csi"
  oidc_provider_arn          = module.eks_control_plane.oidc_provider_arn
  namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
  attach_ebs_csi_policy      = true

  tags = local.common_tags
}

module "alb_controller_irsa" {
  source = "./modules/irsa"

  name                                   = "${local.name}-alb-controller"
  oidc_provider_arn                      = module.eks_control_plane.oidc_provider_arn
  namespace_service_accounts             = ["kube-system:aws-load-balancer-controller"]
  attach_load_balancer_controller_policy = true

  tags = local.common_tags
}

# ── Add-ons, part 1: before compute ──────────────────────────────────────────
# The VPC CNI must be installed before the first node joins, otherwise nodes
# come up without pod networking and the node group never reaches ACTIVE.
module "eks_addons_bootstrap" {
  source = "./modules/eks-addons"

  cluster_name       = module.eks_control_plane.cluster_name
  kubernetes_version = module.eks_control_plane.cluster_version

  addons = {
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          # Prefix delegation: each ENI prefix gives 16 IPs instead of 1 —
          # critical for high-density clusters (many pods per node)
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          # Required to enable Kubernetes NetworkPolicy enforcement via VPC CNI
          ENABLE_NETWORK_POLICY = "true"
        }
      })
    }
  }

  tags = local.common_tags
}

# ── System node group ────────────────────────────────────────────────────────
# Dedicated ON_DEMAND nodes for Karpenter, CoreDNS, ALB controller, and other
# cluster-critical add-ons. Karpenter manages all application nodes.
module "eks_system_node_group" {
  source = "./modules/eks-managed-node-group"

  name         = "${local.name}-system"
  cluster_name = module.eks_control_plane.cluster_name

  subnet_ids                        = module.network.private_subnets
  cluster_primary_security_group_id = module.eks_control_plane.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks_control_plane.node_security_group_id]
  cluster_service_cidr              = module.eks_control_plane.cluster_service_cidr
  cluster_ip_family                 = module.eks_control_plane.cluster_ip_family

  instance_types = var.system_node_instance_types
  capacity_type  = "ON_DEMAND"

  min_size     = var.system_node_min_size
  max_size     = var.system_node_max_size
  desired_size = var.system_node_desired_size

  labels = {
    "node-role"               = "system"
    "karpenter.sh/controller" = "true"
  }

  # Taint keeps application pods off system nodes; Karpenter/CoreDNS tolerate it
  taints = {
    CriticalAddonsOnly = {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  tags = merge(local.common_tags, {
    "karpenter.sh/discovery" = local.name
  })

  depends_on = [module.eks_addons_bootstrap]
}

# ── Add-ons, part 2: after compute ───────────────────────────────────────────
# These need schedulable nodes to reach ACTIVE, so they are created once the
# system node group exists.
module "eks_addons" {
  source = "./modules/eks-addons"

  cluster_name       = module.eks_control_plane.cluster_name
  kubernetes_version = module.eks_control_plane.cluster_version

  addons = {
    coredns = {
      # Lameduck + readiness probe: critical with Karpenter since nodes are
      # created/terminated rapidly. Without these, DNS queries hit terminating
      # CoreDNS pods and fail.
      configuration_values = jsonencode({
        corefile = <<-COREFILE
          .:53 {
              errors
              health {
                lameduck 5s
              }
              ready
              kubernetes cluster.local in-addr.arpa ip6.arpa {
                pods insecure
                fallthrough in-addr.arpa ip6.arpa
                ttl 30
              }
              prometheus :9153
              forward . /etc/resolv.conf {
                max_concurrent 1000
              }
              cache 30
              loop
              reload
              loadbalance
          }
        COREFILE
      })
    }

    kube-proxy = {}

    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.arn
    }

    # Node Monitoring Agent: detects and reports fatal node conditions so
    # Karpenter and managed node groups can auto-repair affected nodes
    eks-node-monitoring-agent = {}
  }

  tags = local.common_tags

  depends_on = [module.eks_system_node_group]
}

# ── Karpenter ────────────────────────────────────────────────────────────────

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name        = module.eks_control_plane.cluster_name
  cluster_endpoint    = module.eks_control_plane.cluster_endpoint
  discovery_tag_value = local.name

  chart_version      = var.karpenter_version
  availability_zones = local.azs

  tags = local.common_tags

  depends_on = [module.eks_system_node_group]
}

# ── API Gateway ──────────────────────────────────────────────────────────────
# Off by default: it provisions an NLB that costs money and serves nothing until
# a workload is bound to its target group. Enable it, apply, then apply the
# TargetGroupBinding from the `api_gateway_target_group_binding` output.
module "api_gateway" {
  source = "./modules/api-gateway"

  count = var.enable_api_gateway ? 1 : 0

  name     = "${local.name}-api"
  vpc_id   = module.network.vpc_id
  vpc_cidr = module.network.vpc_cidr_block

  # Private subnets for both the NLB and the VPC Link ENIs
  subnet_ids = module.network.private_subnets

  target_port           = var.api_gateway_target_port
  health_check_path     = var.api_gateway_health_check_path
  throttling_rate_limit = var.api_gateway_throttling_rate_limit

  tags = local.common_tags
}
