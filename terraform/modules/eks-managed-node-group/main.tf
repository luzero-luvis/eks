# ── EKS managed node group ───────────────────────────────────────────────────
# Wraps the official standalone sub-module. Used outside the parent EKS module,
# so the cluster primary SG and node SG must be passed in explicitly — without
# them the nodes come up with no security groups and never join the cluster.
module "node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 21.25"

  name         = var.name
  cluster_name = var.cluster_name

  # Left null, the sub-module reads the version from the cluster itself
  kubernetes_version = var.kubernetes_version

  subnet_ids = var.subnet_ids

  cluster_primary_security_group_id = var.cluster_primary_security_group_id
  vpc_security_group_ids            = var.vpc_security_group_ids
  cluster_service_cidr              = var.cluster_service_cidr
  cluster_ip_family                 = var.cluster_ip_family

  min_size     = var.min_size
  max_size     = var.max_size
  desired_size = var.desired_size

  instance_types = var.instance_types
  capacity_type  = var.capacity_type

  # AL2023 — replaces AL2 with SELinux, minimal footprint, rpm-ostree updates
  ami_type = var.ami_type

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
        volume_size           = var.root_volume_size
        volume_type           = var.root_volume_type
        encrypted             = var.root_volume_encrypted
        delete_on_termination = true
      }
    }
  }

  labels = var.labels
  taints = var.taints

  # Node repair: EKS replaces nodes the node monitoring agent reports as unhealthy
  node_repair_config = var.enable_node_repair ? { enabled = true } : null

  iam_role_additional_policies = var.iam_role_additional_policies

  tags = var.tags
}
