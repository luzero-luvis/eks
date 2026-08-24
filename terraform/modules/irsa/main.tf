# ── IAM Role for Service Account (IRSA) ──────────────────────────────────────
# One role per workload, trusted by the cluster's OIDC provider and scoped to a
# single namespace/service-account pair. No node-role permissions, no static keys.
module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name = var.name

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = var.namespace_service_accounts
    }
  }

  # AWS-maintained policy sets shipped with the upstream module
  attach_ebs_csi_policy                  = var.attach_ebs_csi_policy
  attach_load_balancer_controller_policy = var.attach_load_balancer_controller_policy

  # Any additional managed policies, keyed by a stable name
  policies = var.policies

  tags = var.tags
}
