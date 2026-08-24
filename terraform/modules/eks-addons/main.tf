# ── EKS managed add-ons ──────────────────────────────────────────────────────
# One aws_eks_addon per map entry. Add-ons are split out of the control-plane
# module because ordering matters: the CNI must exist before the first node
# joins, everything else must be installed after nodes are schedulable.
#
# Resolve the version to install. `most_recent = true` picks the newest version
# compatible with the cluster's Kubernetes version instead of the EKS default.
data "aws_eks_addon_version" "this" {
  for_each = var.addons

  addon_name         = coalesce(each.value.name, each.key)
  kubernetes_version = var.kubernetes_version
  most_recent        = each.value.most_recent
}

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name = var.cluster_name
  addon_name   = coalesce(each.value.name, each.key)

  addon_version        = coalesce(each.value.addon_version, data.aws_eks_addon_version.this[each.key].version)
  configuration_values = each.value.configuration_values

  service_account_role_arn = each.value.service_account_role_arn

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_association != null ? each.value.pod_identity_association : []

    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  # OVERWRITE on create takes ownership of the self-managed copy EKS may have
  # bootstrapped; PRESERVE on update keeps any field patched in-cluster.
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  # Keep the add-on's Kubernetes resources when the add-on itself is removed
  preserve = each.value.preserve

  timeouts {
    create = each.value.timeouts.create
    update = each.value.timeouts.update
    delete = each.value.timeouts.delete
  }

  tags = merge(var.tags, each.value.tags)
}
