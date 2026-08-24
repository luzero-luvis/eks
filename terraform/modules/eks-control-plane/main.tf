# ── EKS control plane ────────────────────────────────────────────────────────
# Cluster only. Node groups and add-ons are deliberately NOT configured here —
# they live in ./modules/eks-managed-node-group and ./modules/eks-addons so each
# concern has exactly one home and can be changed without touching the cluster.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.25"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Public+private: operators reach the API over public; nodes use private.
  # Restrict public access to known CIDRs in prod (set via var).
  endpoint_public_access       = var.endpoint_public_access
  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # null disables Secrets envelope encryption and stops the module creating
  # its own KMS key. Pass an object with `provider_key_arn` to enable it.
  encryption_config = var.encryption_config

  enabled_log_types = var.enabled_log_types

  vpc_id = var.vpc_id

  # Nodes in private subnets; control-plane ENIs in isolated intra subnets
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  # OIDC provider — required for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Grant the Terraform caller admin access via EKS access entries (no aws-auth ConfigMap edits)
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  # Shared node security group — consumed by the node group module and
  # discovered by Karpenter through the karpenter.sh/discovery tag
  create_node_security_group           = true
  node_security_group_additional_rules = var.node_security_group_additional_rules

  tags = var.tags
}
