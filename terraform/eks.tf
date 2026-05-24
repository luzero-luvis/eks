module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  # Public+private: operators reach the API over public; nodes use private.
  # Restrict public access to known CIDRs in prod (set via var).
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Envelope-encrypt all Kubernetes Secrets with a customer-managed KMS key
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # Full control-plane log retention for audit/compliance
  cluster_enabled_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  vpc_id = module.vpc.vpc_id

  # Nodes in private subnets; control-plane ENIs in isolated intra subnets
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # OIDC provider — required for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Grant the Terraform caller admin access via EKS access entries (no aws-auth ConfigMap edits)
  enable_cluster_creator_admin_permissions = true

  # ── EKS Managed Add-ons ─────────────────────────────────────────────────────
  cluster_addons = {
    # VPC CNI must be installed before nodes to avoid IP exhaustion race
    vpc-cni = {
      before_compute              = true
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
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

    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
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

    # Node Monitoring Agent: detects and reports fatal node conditions so
    # Karpenter and managed node groups can auto-repair affected nodes
    eks-node-monitoring-agent = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }

    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }

    aws-ebs-csi-driver = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
      service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # ── System Node Group ────────────────────────────────────────────────────────
  # Dedicated ON_DEMAND nodes for Karpenter, CoreDNS, ALB controller, and other
  # cluster-critical add-ons. Karpenter manages all application nodes.
  eks_managed_node_groups = {
    system = {
      name           = "${local.name}-system"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.system_node_min_size
      max_size     = var.system_node_max_size
      desired_size = var.system_node_desired_size

      # AL2023 — replaces AL2 with SELinux, minimal footprint, rpm-ostree updates
      ami_type = "AL2023_x86_64_STANDARD"

      # IMDSv2 required — prevents SSRF-based metadata credential theft
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = aws_kms_key.ebs.arn
            delete_on_termination = true
          }
        }
      }

      labels = {
        "node-role"                = "system"
        "karpenter.sh/controller"  = "true"
      }

      # Taint keeps application pods off system nodes; Karpenter/CoreDNS tolerate it
      taints = [
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = {
        "karpenter.sh/discovery" = local.name
      }
    }
  }

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
    # Karpenter uses this tag to discover the cluster
    "karpenter.sh/discovery" = local.name
  })
}
