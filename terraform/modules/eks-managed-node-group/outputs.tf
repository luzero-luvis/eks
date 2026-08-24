output "node_group_id" {
  description = "EKS managed node group ID"
  value       = module.node_group.node_group_id
}

output "node_group_arn" {
  description = "EKS managed node group ARN"
  value       = module.node_group.node_group_arn
}

output "node_group_status" {
  description = "Status of the node group"
  value       = module.node_group.node_group_status
}

output "iam_role_name" {
  description = "IAM role name assigned to the nodes"
  value       = module.node_group.iam_role_name
}

output "iam_role_arn" {
  description = "IAM role ARN assigned to the nodes"
  value       = module.node_group.iam_role_arn
}

output "launch_template_id" {
  description = "Launch template backing the node group"
  value       = module.node_group.launch_template_id
}
